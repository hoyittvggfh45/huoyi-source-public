package core

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
)

const hongguoRouteCount = 6

const (
	hongguoRouteAppMainland = 0
	hongguoRouteAppOversea  = 1
	hongguoRouteAppBatch    = 2
	hongguoRouteWebFallback = 3
	hongguoRouteWebPlayer   = 4
	hongguoRoutePlaybackAPI = 5
)

func hongguoResolveIDs(task Task) (string, string, string, bool) {
	source, seriesID, ok := splitProviderDramaID(task.DramaID)
	if !ok || (source != sourceHongguo && source != sourceHongguoOversea) {
		return "", "", "", false
	}
	videoID := strings.TrimPrefix(task.Chapter.VideoURL, "hongguo-cenc://")
	if !hongguoNumericID.MatchString(videoID) {
		if idx := strings.LastIndex(task.Chapter.ID, ":"); idx >= 0 {
			videoID = task.Chapter.ID[idx+1:]
		}
	}
	if !hongguoNumericID.MatchString(seriesID) || !hongguoNumericID.MatchString(videoID) {
		return "", "", "", false
	}
	return source, seriesID, videoID, true
}

func hongguoRouteName(route int) string {
	switch route {
	case hongguoRouteAppMainland:
		return "App大陆线"
	case hongguoRouteAppOversea:
		return "App海外线"
	case hongguoRouteAppBatch:
		return "App批量线"
	case hongguoRouteWebFallback:
		return "网页兜底线"
	case hongguoRouteWebPlayer:
		return "网页取流线"
	case hongguoRoutePlaybackAPI:
		return "备用接口线"
	}
	return "未知线路"
}

func hongguoRouteOrder(oversea bool) []int {
	if oversea {
		return []int{hongguoRouteAppOversea, hongguoRouteAppMainland, hongguoRouteAppBatch, hongguoRouteWebFallback, hongguoRouteWebPlayer, hongguoRoutePlaybackAPI}
	}
	return []int{hongguoRouteAppMainland, hongguoRouteAppOversea, hongguoRouteAppBatch, hongguoRouteWebFallback, hongguoRouteWebPlayer, hongguoRoutePlaybackAPI}
}

func validateHongguoRouteMedia(media providerMedia, seriesID, videoID string) error {
	if !isProviderHTTPMediaURL(media.URL) {
		return errors.New("该线路未返回有效的播放地址")
	}
	if media.SeriesID != "" && media.SeriesID != seriesID {
		return fmt.Errorf("该线路返回的剧集与当前剧集不符")
	}
	if media.VideoID != "" && media.VideoID != videoID {
		return fmt.Errorf("该线路返回的集数与当前集数不符")
	}
	return nil
}

func (downloader *Downloader) resolveHongguoMediaRoute(ctx context.Context, source, seriesID, videoID string, route int) (providerMedia, error) {
	if source != sourceHongguo && source != sourceHongguoOversea {
		return providerMedia{}, errors.New("红果章节缺少剧 ID，请刷新剧库后重新加入队列")
	}
	if !hongguoNumericID.MatchString(seriesID) || !hongguoNumericID.MatchString(videoID) {
		return providerMedia{}, errors.New("红果章节 ID 无效，请重新获取章节")
	}
	if route < 0 || route >= hongguoRouteCount {
		return providerMedia{}, errors.New("该播放线路不可用")
	}
	var media providerMedia
	var err error
	switch route {
	case hongguoRouteAppMainland:
		media, err = downloader.resolveHongguoAppRouteLine(ctx, false, videoID)
	case hongguoRouteAppOversea:
		media, err = downloader.resolveHongguoAppRouteLine(ctx, true, videoID)
	case hongguoRouteAppBatch:
		media, err = downloader.resolveHongguoAppBatchMedia(ctx, videoID)
	case hongguoRouteWebFallback:
		media, err = downloader.resolveHongguoWebFallback(ctx, seriesID, videoID)
	case hongguoRouteWebPlayer:
		media, err = downloader.resolveHongguoWebMedia(ctx, seriesID, videoID)
	case hongguoRoutePlaybackAPI:
		media, err = downloader.resolveHongguoPlaybackAPI(ctx, seriesID, videoID)
	}
	if err != nil {
		return providerMedia{}, err
	}
	if err := validateHongguoRouteMedia(media, seriesID, videoID); err != nil {
		return providerMedia{}, err
	}
	return media, nil
}

func (downloader *Downloader) resolveHongguoAppRouteLine(ctx context.Context, oversea bool, videoID string) (providerMedia, error) {
	if err := downloader.ensureHongguoDevice(ctx, ""); err != nil {
		return providerMedia{}, err
	}
	if downloader.hongguoDeviceLimited() {
		downloader.ensureHongguoDevice(ctx, downloader.hongguoDeviceID())
	}
	if oversea {
		return downloader.resolveHongguoAppMediaLine(hongguoOverseaCtx(ctx), videoID)
	}
	return downloader.resolveHongguoAppMediaLine(ctx, videoID)
}

func hongguoBatchPayload(videoID string) map[string]any {
	return map[string]any{
		"biz_param": map[string]any{
			"detail_page_version": 0, "device_level": 3, "disable_digg_stat": false,
			"need_all_video_definition": true, "need_mp4_align": false, "use_os_player": false,
			"use_server_dns": false, "video_platform": 1024,
		},
		"mixed_video_id_map": map[string]any{"1004": []string{videoID}},
	}
}

func hongguoBatchMediaFromResult(result map[string]any, videoID string) (providerMedia, error) {
	data := nestedMap(result, "data")
	entry, _ := data[videoID].(map[string]any)
	if len(entry) == 0 {
		return providerMedia{}, errors.New("红果批量接口未返回本集播放信息")
	}
	model, _ := entry["video_model"].(map[string]any)
	if encoded, ok := entry["video_model"].(string); ok && encoded != "" {
		if decoded, err := decodeHongguoBase64(encoded); err == nil && len(decoded) > 0 {
			encoded = string(decoded)
		}
		decoder := json.NewDecoder(strings.NewReader(encoded))
		decoder.UseNumber()
		if err := decoder.Decode(&model); err != nil {
			return providerMedia{}, errors.New("红果批量播放信息格式异常")
		}
	}
	if len(model) == 0 {
		return providerMedia{}, errors.New("红果批量接口未返回本集播放信息")
	}
	media, err := selectHongguoAppMedia(model)
	if err != nil {
		return providerMedia{}, err
	}
	media.VideoID = videoID
	return media, nil
}

func (downloader *Downloader) hongguoBatchEndpoint(ctx context.Context, path string, payload map[string]any, videoID string) (providerMedia, error, bool) {
	for attempt := 0; attempt <= hongguoDeviceRotations; attempt++ {
		if attempt > 0 {
			if err := downloader.ensureHongguoDevice(ctx, downloader.hongguoDeviceID()); err != nil {
				return providerMedia{}, err, false
			}
		}
		result, err := downloader.hongguoAppRequestInternal(ctx, http.MethodPost, path, nil, payload, true)
		if err != nil {
			if strings.Contains(err.Error(), "110001") {
				return providerMedia{}, err, true
			}
			if errors.Is(err, errHongguoAppEmptyBody) {
				downloader.markHongguoDeviceLimited()
				continue
			}
			return providerMedia{}, err, false
		}
		media, err := hongguoBatchMediaFromResult(result, videoID)
		if err != nil {
			return providerMedia{}, err, false
		}
		downloader.clearHongguoDeviceLimited()
		return media, nil, false
	}
	return providerMedia{}, errHongguoAppEmptyBody, false
}

func (downloader *Downloader) resolveHongguoAppBatchMedia(ctx context.Context, videoID string) (providerMedia, error) {
	if !hongguoNumericID.MatchString(videoID) {
		return providerMedia{}, errors.New("红果视频 ID 无效")
	}
	if err := downloader.ensureHongguoDevice(ctx, ""); err != nil {
		return providerMedia{}, err
	}
	if downloader.hongguoDeviceLimited() {
		downloader.ensureHongguoDevice(ctx, downloader.hongguoDeviceID())
	}
	payload := hongguoBatchPayload(videoID)
	media, err, is110001 := downloader.hongguoBatchEndpoint(ctx, "/novel/player/multi_video_model/v1/", payload, videoID)
	if err == nil {
		return media, nil
	}
	if !is110001 {
		return providerMedia{}, err
	}
	media, preloadErr, _ := downloader.hongguoBatchEndpoint(ctx, "/novel/player/multi_video_model/preload/v1/", payload, videoID)
	if preloadErr != nil {
		return providerMedia{}, preloadErr
	}
	return media, nil
}
