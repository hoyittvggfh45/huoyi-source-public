package core

import (
	"context"
	"errors"
	"strings"

	"duanjuapp/native/core/seku"
)

const youtubeBaseURL = "https://www.youtube.com"

func (d *Downloader) fetchYoutubeCatalogPage(ctx context.Context, page int, category string) ([]Drama, bool, error) {
	items, _, hasMore, err := seku.YoutubeCatalog(sourceYouTube, category, page)
	if err != nil {
		return nil, false, err
	}
	out := []Drama{}
	for _, item := range items {
		if m, ok := item.(map[string]interface{}); ok {
			if drama := sekuDramaFromMap(sourceYouTube, m); drama.ID != "" {
				out = append(out, drama)
			}
		}
	}
	return out, hasMore, nil
}

func (d *Downloader) searchYoutube(ctx context.Context, query string) ([]Drama, error) {
	items, err := seku.YoutubeSearch(sourceYouTube, query)
	if err != nil {
		return nil, err
	}
	out := []Drama{}
	for _, item := range items {
		if m, ok := item.(map[string]interface{}); ok {
			if drama := sekuDramaFromMap(sourceYouTube, m); drama.ID != "" {
				out = append(out, drama)
			}
		}
	}
	return out, nil
}

func (d *Downloader) fetchYoutubeDetail(ctx context.Context, videoID string) (Drama, []Chapter, error) {
	m, err := seku.YoutubeDetail(sourceYouTube, videoID)
	if err != nil {
		return Drama{}, nil, err
	}
	drama := sekuDramaFromMap(sourceYouTube, m)
	if drama.ID == "" {
		drama = Drama{ID: providerDramaID(sourceYouTube, videoID), Source: sourceYouTube, SourceID: videoID}
	}
	return drama, sekuChaptersFromMap(sourceYouTube, videoID, m), nil
}

func (d *Downloader) resolveYoutubeMedia(ctx context.Context, task Task) (providerMedia, error) {
	source, videoID, valid := splitProviderDramaID(task.DramaID)
	if !valid || source != sourceYouTube {
		return providerMedia{}, errors.New("剧集信息无效")
	}
	epRaw := videoID
	if prefix := task.DramaID + ":"; strings.HasPrefix(task.Chapter.ID, prefix) {
		if rest := strings.TrimPrefix(task.Chapter.ID, prefix); rest != "" {
			epRaw = rest
		}
	}
	result, err := seku.YoutubeResolve(sourceYouTube, epRaw)
	if err != nil {
		return providerMedia{}, err
	}
	address := sekuMapText(result, "url", "videoUrl", "playUrl")
	if !isProviderHTTPMediaURL(address) {
		return providerMedia{}, errors.New("YouTube 未返回有效播放地址")
	}
	referer := sekuMapText(result, "referer")
	if referer == "" {
		if headers, ok := result["headers"].(map[string]interface{}); ok {
			referer = sekuMapText(headers, "Referer", "referer")
		}
	}
	return providerMedia{URL: address, Referer: referer, NeedsParse: parseFlagFromMap(result)}, nil
}
