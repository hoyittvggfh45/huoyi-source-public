package core

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"time"
)

const hongguoModelCacheTTL = 60 * time.Second

const hongguoModelHandoverTTL = 15 * time.Second

const hongguoModelHandoverMax = 6

const hongguoModelMaxBytes = 256 << 10

type hongguoCachedModel struct {
	entry   map[string]any
	savedAt time.Time
}

func hongguoModelSize(entry map[string]any) int {
	encoded, err := json.Marshal(entry)
	if err != nil {
		return hongguoModelMaxBytes + 1
	}
	return len(encoded)
}

func (downloader *Downloader) hongguoTakeUpcomingModel(videoID string) (map[string]any, bool) {
	client := downloader.hongguoClient()
	client.mu.Lock()
	defer client.mu.Unlock()
	entry, found := client.models[videoID]
	if !found {
		return nil, false
	}
	delete(client.models, videoID)
	if time.Since(entry.savedAt) < 0 || time.Since(entry.savedAt) > hongguoModelCacheTTL {
		return nil, false
	}
	return entry.entry, true
}

func (downloader *Downloader) hongguoOfferUpcomingModel(videoID string, entry map[string]any) {
	if videoID == "" || len(entry) == 0 || hongguoModelSize(entry) > hongguoModelMaxBytes {
		return
	}
	client := downloader.hongguoClient()
	client.mu.Lock()
	defer client.mu.Unlock()
	if len(client.models) >= 64 {
		for key := range client.models {
			delete(client.models, key)
			break
		}
	}
	client.models[videoID] = hongguoCachedModel{entry: entry, savedAt: time.Now()}
}

func (downloader *Downloader) hongguoOfferModel(videoID string, entry map[string]any) {
	if videoID == "" || len(entry) == 0 || hongguoModelSize(entry) > hongguoModelMaxBytes {
		return
	}
	client := downloader.hongguoClient()
	client.mu.Lock()
	defer client.mu.Unlock()
	now := time.Now()
	for key, cached := range client.handover {
		if now.Sub(cached.savedAt) > hongguoModelHandoverTTL {
			delete(client.handover, key)
		}
	}
	for len(client.handover) >= hongguoModelHandoverMax {
		oldest := ""
		var oldestAt time.Time
		for key, cached := range client.handover {
			if oldest == "" || cached.savedAt.Before(oldestAt) {
				oldest, oldestAt = key, cached.savedAt
			}
		}
		delete(client.handover, oldest)
	}
	client.handover[videoID] = hongguoCachedModel{entry: entry, savedAt: now}
}

func (downloader *Downloader) hongguoTakeModel(videoID string) (map[string]any, bool) {
	client := downloader.hongguoClient()
	client.mu.Lock()
	defer client.mu.Unlock()
	entry, found := client.handover[videoID]
	if !found {
		return nil, false
	}
	delete(client.handover, videoID)
	if time.Since(entry.savedAt) < 0 || time.Since(entry.savedAt) > hongguoModelHandoverTTL {
		return nil, false
	}
	return entry.entry, true
}

func (downloader *Downloader) hongguoMediaFromModelEntry(ctx context.Context, entry map[string]any, sources ...map[string]any) (providerMedia, error) {
	model, err := hongguoVideoModelValue(entry["video_model"])
	if err != nil {
		return providerMedia{}, errors.New("红果 App 播放信息格式异常")
	}
	if model == nil {
		model = map[string]any{}
	}
	if len(model) == 0 {
		if rows := anyList(entry["video_list"]); len(rows) > 0 {
			model["video_list"] = entry["video_list"]
			model["video_duration"] = entry["video_duration"]
			model["duration"] = entry["duration"]
		}
	}
	if len(model) == 0 {
		return providerMedia{}, errHongguoAppEmptyBody
	}
	hongguoAttachKeySeed(model, append([]map[string]any{entry}, sources...)...)
	downloader.hongguoMergeFallbackAPI(ctx, model)
	return selectHongguoAppMedia(model)
}

func (downloader *Downloader) hongguoPrefetchModels(ctx context.Context, videoIDs []string) {
	if len(videoIDs) == 0 {
		return
	}
	seen := map[string]bool{}
	ids := make([]any, 0, len(videoIDs))
	for _, id := range videoIDs {
		if !hongguoNumericID.MatchString(id) || seen[id] {
			continue
		}
		seen[id] = true
		ids = append(ids, id)
	}
	if len(ids) == 0 {
		return
	}
	payload := map[string]any{
		"mixed_video_id_map": map[string]any{"1004": ids},
		"biz_param":          map[string]any{"need_all_video_definition": true, "video_platform": 3},
	}
	result, err := downloader.hongguoAppRequestInternal(ctx, http.MethodPost, "/novel/player/multi_video_model/v1/", nil, payload, true)
	if err != nil {
		return
	}
	data := nestedMap(result, "data")
	for _, id := range ids {
		videoID, _ := id.(string)
		entry, _ := data[videoID].(map[string]any)
		if entry == nil {
			continue
		}
		downloader.hongguoOfferUpcomingModel(videoID, entry)
	}
}
