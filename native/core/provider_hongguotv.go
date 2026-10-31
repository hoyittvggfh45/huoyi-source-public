package core

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"
)

const sourceHongguotv = "hongguotv"

type hongguotvCategory struct {
	id    string
	name  string
	route string
	rank  string
}

var hongguotvCategories = []hongguotvCategory{
	{id: "short", name: "真人剧", route: "real-drama"},
	{id: "comic", name: "漫剧", route: "comic-drama"},
	{id: "ai", name: "AI剧", route: "ai-drama"},
	{id: "rank-hot", name: "热门榜", rank: "hot-drama"},
	{id: "rank-real", name: "真人榜", rank: "hot-real-drama"},
	{id: "rank-comic", name: "漫剧榜", rank: "hot-comic-drama"},
	{id: "rank-ai", name: "AI榜", rank: "hot-ai-drama"},
}

func hongguotvCategoryFor(id string) (hongguotvCategory, bool) {
	for _, entry := range hongguotvCategories {
		if entry.id == id {
			return entry, true
		}
	}
	return hongguotvCategory{}, false
}

func hongguotvRetag(drama Drama) Drama {
	_, sourceID, valid := splitProviderDramaID(drama.ID)
	if !valid {
		sourceID = drama.SourceID
	}
	if sourceID == "" {
		return drama
	}
	drama.ID = providerDramaID(sourceHongguotv, sourceID)
	drama.Source = sourceHongguotv
	drama.SourceID = sourceID
	drama.ChannelName = "红果TV"
	return drama
}

func hongguotvDramaFromAny(v any, category string) Drama {
	m, ok := v.(map[string]any)
	if !ok {
		return Drama{}
	}
	vd, _ := m["video_data"].(map[string]any)
	if len(vd) == 0 {
		vd = m
	}
	sourceID := firstNonEmpty(mapString(vd, "series_id_str", "series_id"), mapString(m, "series_id_str", "series_id"), mapString(vd, "keyword"), mapString(m, "keyword"))
	if !hongguoNumericID.MatchString(sourceID) {
		return Drama{}
	}
	title := firstNonEmpty(mapString(vd, "series_title", "series_name", "title"), mapString(m, "series_name", "name"), sourceID)
	cover := firstNonEmpty(mapString(vd, "series_cover", "cover"), mapString(m, "series_cover"))
	intro := firstNonEmpty(mapString(vd, "series_intro", "video_desc"), mapString(m, "series_intro"))
	count := firstNonEmpty(mapString(vd, "episode_cnt"), mapString(m, "episode_cnt"))
	remark := firstNonEmpty(mapString(vd, "episode_right_text"), mapString(m, "episode_right_text"))
	releaseStatus := releaseStatusFromRemark(remark)
	if mapString(vd, "series_status") == "1" {
		releaseStatus = "finished"
	} else if mapString(vd, "series_status") == "0" {
		releaseStatus = "ongoing"
	}
	if remark == "" && count != "" {
		remark = "共" + count + "集"
	}
	tags := mapStringSlice(vd, "tags")
	for _, value := range anyList(vd["category_list"]) {
		item, _ := value.(map[string]any)
		if name := mapString(item, "name"); name != "" {
			found := false
			for _, tag := range tags {
				if tag == name {
					found = true
					break
				}
			}
			if !found {
				tags = append(tags, name)
			}
		}
	}
	genre := mapString(vd, "category_name", "categoryName", "category")
	if genre == "" && len(tags) > 0 {
		genre = tags[0]
	}
	return Drama{ID: providerDramaID(sourceHongguotv, sourceID), Source: sourceHongguotv, SourceID: sourceID, Title: title, Name: title, Desc: intro, Intro: intro, Cover: cover, CoverURL: cover, CategoryName: firstNonEmpty(genre, category), ChannelName: "红果TV", Remark: remark, TotalEpisode: count, EpisodeCount: count, Tags: tags, ReleaseStatus: releaseStatus, Score: mapString(vd, "score"), Views: mapString(vd, "series_play_cnt", "play_cnt"), Heat: hongguoHeat(vd), OnlineDate: hongguoOnlineDate(vd, time.Now())}
}

func (d *Downloader) fetchHongguotvCategoryPage(ctx context.Context, route, category string, page int) ([]Drama, int, error) {
	if page < 1 {
		page = 1
	}
	body, err := d.fetchProviderText(ctx, hongguoBaseURL+"/category/"+route+"?page="+strconv.Itoa(page), hongguoBaseURL+"/")
	if err != nil {
		return nil, 0, err
	}
	data := parseRouterData(body)
	loaded := routerLoaderMap(data, "category_page", "category_$")
	if len(loaded) == 0 || loaded["isSuccess"] == false {
		return nil, 0, errors.New("红果TV 分类数据不可用，可能是页面结构或访问权限变化")
	}
	items := anyList(loaded["recommendList"])
	out := make([]Drama, 0, len(items))
	for _, item := range items {
		if drama := hongguotvDramaFromAny(item, category); drama.ID != "" {
			out = append(out, drama)
		}
	}
	pages, _ := strconv.Atoi(mapString(nestedMap(loaded, "pagination"), "totalPages"))
	return out, pages, nil
}

var reHongguotvMergeLoader = regexp.MustCompile(`(?s)data-fn-name="mergeLoaderData"[^>]*?data-fn-args="([^"]*)"`)

func hongguotvRankList(body string) []Drama {
	for _, match := range reHongguotvMergeLoader.FindAllStringSubmatch(body, -1) {
		if len(match) < 2 {
			continue
		}
		decoded := html.UnescapeString(match[1])
		var args []any
		decoder := json.NewDecoder(strings.NewReader(decoded))
		decoder.UseNumber()
		if err := decoder.Decode(&args); err != nil || len(args) < 2 {
			continue
		}
		key, _ := args[0].(string)
		if !strings.HasPrefix(key, "rank_") {
			continue
		}
		sections := anyList(args[1])
		for _, section := range sections {
			sectionMap, _ := section.(map[string]any)
			if sectionMap == nil || mapString(sectionMap, "key") != "content" {
				continue
			}
			payloads := anyList(sectionMap["routerDataFnArgs"])
			if len(payloads) == 0 {
				continue
			}
			payload, _ := payloads[0].(string)
			if payload == "" {
				continue
			}
			var content map[string]any
			contentDecoder := json.NewDecoder(strings.NewReader(payload))
			contentDecoder.UseNumber()
			if err := contentDecoder.Decode(&content); err != nil {
				continue
			}
			rows := anyList(content["rankList"])
			out := make([]Drama, 0, len(rows))
			for _, row := range rows {
				item, _ := row.(map[string]any)
				if item == nil {
					continue
				}
				sourceID := firstNonEmpty(mapString(item, "seriesId", "series_id", "id"))
				if !hongguoNumericID.MatchString(sourceID) {
					continue
				}
				rank := mapString(item, "rank")
				remark := ""
				if rank != "" {
					remark = "第" + rank + "名"
				}
				out = append(out, Drama{
					ID: providerDramaID(sourceHongguotv, sourceID), Source: sourceHongguotv, SourceID: sourceID,
					Title: firstNonEmpty(mapString(item, "title", "series_name"), sourceID),
					Name:  firstNonEmpty(mapString(item, "title", "series_name"), sourceID),
					Cover: mapString(item, "cover", "series_cover"), CoverURL: mapString(item, "cover", "series_cover"),
					ChannelName: "红果TV", Remark: remark,
				})
			}
			if len(out) > 0 {
				return out
			}
		}
	}
	return nil
}

func (d *Downloader) fetchHongguotvRankPage(ctx context.Context, rank, category string) ([]Drama, error) {
	body, err := d.fetchProviderText(ctx, hongguoBaseURL+"/rank/"+rank, hongguoBaseURL+"/")
	if err != nil {
		return nil, err
	}
	items := hongguotvRankList(body)
	if len(items) == 0 {
		return nil, errors.New("红果TV 榜单数据不可用，可能是页面结构或访问权限变化")
	}
	for i := range items {
		if items[i].CategoryName == "" {
			items[i].CategoryName = category
		}
	}
	return items, nil
}

func (d *Downloader) fetchHongguotvCatalog(ctx context.Context, category string, page int) ([]Drama, bool, error) {
	if page < 1 {
		page = 1
	}
	if category == "" {
		category = "short"
	}
	entry, ok := hongguotvCategoryFor(category)
	if !ok {
		return nil, false, errors.New("红果TV 分类无效")
	}
	if entry.rank != "" {
		if page > 1 {
			return []Drama{}, false, nil
		}
		items, err := d.fetchHongguotvRankPage(ctx, entry.rank, entry.name)
		return items, false, err
	}
	items, totalPages, err := d.fetchHongguotvCategoryPage(ctx, entry.route, entry.name, page)
	if err != nil {
		return nil, false, err
	}
	return items, page < totalPages, nil
}

func (d *Downloader) fetchHongguotvChapters(ctx context.Context, sourceID string) (string, []Chapter, error) {
	body, err := d.fetchProviderText(ctx, hongguoBaseURL+"/detail?series_id="+strings.TrimSpace(sourceID), hongguoBaseURL+"/")
	if err != nil {
		return "", nil, err
	}
	data := parseRouterData(body)
	loaded := routerLoaderMap(data, "detail_page", "detail_")
	detail, _ := loaded["seriesDetail"].(map[string]any)
	if len(detail) == 0 {
		return "", nil, fmt.Errorf("红果TV 详情为空")
	}
	title := firstNonEmpty(mapString(detail, "series_name", "series_title", "name"), sourceID)
	vids := anyList(detail["vid_list"])
	chapters := make([]Chapter, 0, len(vids))
	for i, v := range vids {
		vid := strings.TrimSpace(fmt.Sprint(v))
		if vid == "" || vid == "<nil>" {
			continue
		}
		idx := i + 1
		chapters = append(chapters, Chapter{ID: providerChapterID(sourceHongguotv, sourceID, vid), Source: sourceHongguotv, Title: fmt.Sprintf("第%d集", idx), VideoURL: "hongguotv-cenc://" + vid, CurrentEpisode: rawEpisode(idx)})
	}
	if len(chapters) == 0 {
		return title, nil, errors.New("红果TV 详情没有返回剧集 ID")
	}
	return title, chapters, nil
}

func (d *Downloader) searchHongguotvDramas(ctx context.Context, keyword string) (hongguoSearchEntry, error) {
	entry, err := d.searchHongguoDramas(ctx, keyword)
	if err != nil {
		return entry, err
	}
	retagged := make([]Drama, 0, len(entry.Dramas))
	for _, drama := range entry.Dramas {
		if tagged := hongguotvRetag(drama); tagged.ID != "" {
			retagged = append(retagged, tagged)
		}
	}
	entry.Dramas = retagged
	entry.Warning = strings.ReplaceAll(entry.Warning, "红果", "红果TV")
	return entry, nil
}

func hongguotvBatchPayload(videoID string) map[string]any {
	return map[string]any{
		"biz_param": map[string]any{
			"detail_page_version": 0, "device_level": 3, "disable_digg_stat": false,
			"need_all_video_definition": true, "need_mp4_align": false, "use_os_player": false,
			"use_server_dns": false, "video_platform": 1024,
		},
		"mixed_video_id_map": map[string]any{"1004": []string{videoID}},
	}
}

func hongguotvBatchModel(result map[string]any, videoID string) (map[string]any, error) {
	data := nestedMap(result, "data")
	if len(data) == 0 {
		return nil, errors.New("红果TV 批量取流未返回数据")
	}
	entry, _ := data[videoID].(map[string]any)
	if len(entry) == 0 {
		for _, value := range data {
			if candidate, ok := value.(map[string]any); ok && len(candidate) > 0 {
				entry = candidate
				break
			}
		}
	}
	if len(entry) == 0 {
		return nil, errors.New("红果TV 批量取流没有对应视频")
	}
	model, _ := entry["video_model"].(map[string]any)
	if encoded, ok := entry["video_model"].(string); ok && encoded != "" {
		if decoded, err := decodeHongguoBase64(encoded); err == nil && len(decoded) > 0 {
			encoded = string(decoded)
		}
		decoder := json.NewDecoder(strings.NewReader(encoded))
		decoder.UseNumber()
		if err := decoder.Decode(&model); err != nil {
			return nil, errors.New("红果TV 批量播放信息格式异常")
		}
	}
	if len(model) == 0 {
		if rows := anyList(entry["video_list"]); len(rows) > 0 {
			model = map[string]any{"video_list": entry["video_list"], "video_duration": entry["video_duration"], "duration": entry["duration"]}
		}
	}
	if len(model) == 0 {
		return nil, errors.New("红果TV 批量取流内容为空")
	}
	return model, nil
}

func (d *Downloader) resolveHongguotvBatchMedia(ctx context.Context, videoID string) (providerMedia, error) {
	if err := d.ensureHongguoDevice(ctx, ""); err != nil {
		return providerMedia{}, err
	}
	if d.hongguoDeviceLimited() {
		if err := d.ensureHongguoDevice(ctx, d.hongguoDeviceID()); err != nil {
			return providerMedia{}, err
		}
	}
	result, err := d.hongguoAppRequestInternal(ctx, http.MethodPost, "/novel/player/multi_video_model/v1/", nil, hongguotvBatchPayload(videoID), true)
	if err != nil && !strings.Contains(err.Error(), "110001") {
		return providerMedia{}, err
	}
	if err != nil {
		result, err = d.hongguoAppRequestInternal(ctx, http.MethodPost, "/novel/player/multi_video_model/preload/v1/", nil, hongguotvBatchPayload(videoID), true)
		if err != nil {
			return providerMedia{}, err
		}
	}
	model, err := hongguotvBatchModel(result, videoID)
	if err != nil {
		return providerMedia{}, err
	}
	d.clearHongguoDeviceLimited()
	return selectHongguoAppMedia(model)
}

func (d *Downloader) resolveHongguotvWebMedia(ctx context.Context, seriesID, videoID string) (providerMedia, error) {
	body, err := d.fetchProviderText(ctx, hongguoBaseURL+"/player/"+seriesID+"/"+videoID, hongguoBaseURL+"/")
	if err != nil {
		return providerMedia{}, err
	}
	loaded := routerLoaderMap(parseRouterData(body), "player_", "player_page")
	if mapString(loaded, "vid") != videoID || mapString(loaded, "series_id") != seriesID {
		return providerMedia{}, fmt.Errorf("红果TV 未返回所请求的剧集，可能仅允许网页试看")
	}
	info, _ := loaded["video_player_info"].(map[string]any)
	addresses := hongguoMediaAddresses(info)
	if len(addresses) == 0 {
		return providerMedia{}, fmt.Errorf("红果TV 该集未提供公开播放地址，可能需要登录或 App 授权")
	}
	return providerMedia{URL: addresses[0], Referer: hongguoBaseURL + "/"}, nil
}

func (d *Downloader) resolveHongguotvMedia(ctx context.Context, task Task) (providerMedia, error) {
	source, seriesID, valid := splitProviderDramaID(task.DramaID)
	if !valid || source != sourceHongguotv {
		return providerMedia{}, fmt.Errorf("红果TV 剧集信息无效")
	}
	videoID := strings.TrimPrefix(task.Chapter.VideoURL, "hongguotv-cenc://")
	if !hongguoNumericID.MatchString(videoID) || !hongguoNumericID.MatchString(seriesID) {
		return providerMedia{}, fmt.Errorf("红果TV 章节 ID 无效，请重新获取章节")
	}
	if media, err := d.resolveHongguoAppMedia(ctx, videoID); err == nil {
		return media, nil
	} else if ctx.Err() != nil {
		return providerMedia{}, ctx.Err()
	}
	if media, err := d.resolveHongguotvBatchMedia(ctx, videoID); err == nil {
		return media, nil
	} else if ctx.Err() != nil {
		return providerMedia{}, ctx.Err()
	}
	if media, err := d.resolveHongguotvWebMedia(ctx, seriesID, videoID); err == nil {
		return media, nil
	} else {
		return providerMedia{}, fmt.Errorf("红果TV 取流失败：单集与批量 App 取流未返回可用地址，网页取流失败：%v", err)
	}
}
