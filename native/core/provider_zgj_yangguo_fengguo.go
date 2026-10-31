package core

import (
	"context"
	"encoding/json"
	"errors"
	"net/url"
	"regexp"
	"strconv"
	"strings"
)

func retagZgjFamilyDrama(drama Drama, chapters []Chapter, source string) (Drama, []Chapter) {
	drama.ID = providerDramaID(source, drama.SourceID)
	drama.Source = source
	for i := range chapters {
		key := chapters[i].ID
		if idx := strings.LastIndex(key, ":"); idx >= 0 {
			key = key[idx+1:]
		}
		chapters[i].ID = providerChapterID(source, drama.SourceID, key)
		chapters[i].Source = source
	}
	return drama, chapters
}

func retagZgjFamilyDramas(items []Drama, source string) []Drama {
	for i := range items {
		items[i].ID = providerDramaID(source, items[i].SourceID)
		items[i].Source = source
	}
	return items
}

func (d *Downloader) fetchYangguoCatalogPage(ctx context.Context, page int, category string) ([]Drama, bool, error) {
	items, more, err := d.fetchRedtubeCatalogPage(ctx, page, category)
	if err != nil {
		return nil, false, err
	}
	return retagZgjFamilyDramas(items, sourceYangguo), more, nil
}

func (d *Downloader) fetchYangguoDetail(ctx context.Context, id string) (Drama, []Chapter, error) {
	drama, chapters, err := d.fetchRedtubeDetail(ctx, id)
	if err != nil {
		return Drama{}, nil, err
	}
	drama, chapters = retagZgjFamilyDrama(drama, chapters, sourceYangguo)
	return drama, chapters, nil
}

func (d *Downloader) searchYangguo(ctx context.Context, query string) ([]Drama, error) {
	address := redtubeBaseURL + "/search/?query=" + url.QueryEscape(query)
	body, err := d.fetchProviderText(ctx, address, redtubeBaseURL+"/")
	if err != nil {
		return nil, err
	}
	return retagZgjFamilyDramas(redtubeDramasFromHTML(body, redtubeBaseURL), sourceYangguo), nil
}

func (d *Downloader) fetchFengguoCatalogPage(ctx context.Context, page int, category string) ([]Drama, bool, error) {
	items, more, err := d.fetchPornhubCatalogPage(ctx, page, category)
	if err != nil {
		return nil, false, err
	}
	return retagZgjFamilyDramas(items, sourceFengguo), more, nil
}

func (d *Downloader) fetchFengguoDetail(ctx context.Context, viewkey string) (Drama, []Chapter, error) {
	drama, chapters, err := d.fetchPornhubDetail(ctx, viewkey)
	if err != nil {
		return Drama{}, nil, err
	}
	drama, chapters = retagZgjFamilyDrama(drama, chapters, sourceFengguo)
	return drama, chapters, nil
}

func (d *Downloader) searchFengguo(ctx context.Context, query string) ([]Drama, error) {
	address := pornhubBaseURL + "/video/search?search=" + url.QueryEscape(query)
	body, err := d.fetchProviderText(ctx, address, pornhubBaseURL+"/")
	if err != nil {
		return nil, err
	}
	return retagZgjFamilyDramas(pornhubDramasFromHTML(body, pornhubBaseURL), sourceFengguo), nil
}

var redtubeMediaPathRe = regexp.MustCompile(`"/media/mp4\?s=[^"]*"`)
var redtubeDirectMp4Re = regexp.MustCompile(`https?://[^"'\s\\]+\.mp4[^"'\s\\]*`)

type redtubeMediaEntry struct {
	DefaultQuality bool   `json:"defaultQuality"`
	Format         string `json:"format"`
	Quality        string `json:"quality"`
	VideoURL       string `json:"videoUrl"`
}

func redtubeMediaURLFromJSON(body string) (string, int) {
	var entries []redtubeMediaEntry
	if err := json.Unmarshal([]byte(body), &entries); err != nil {
		return "", 0
	}
	best := ""
	bestQuality := -1
	def := ""
	defQuality := 0
	for _, entry := range entries {
		if entry.Format != "mp4" || !isProviderHTTPMediaURL(entry.VideoURL) {
			continue
		}
		quality, _ := strconv.Atoi(entry.Quality)
		if entry.DefaultQuality {
			def = entry.VideoURL
			defQuality = quality
		}
		if quality > bestQuality {
			bestQuality = quality
			best = entry.VideoURL
		}
	}
	if def != "" {
		return def, defQuality
	}
	return best, bestQuality
}

func redtubeDirectMp4FromHTML(body string) string {
	for _, raw := range redtubeDirectMp4Re.FindAllString(body, -1) {
		cleaned := strings.ReplaceAll(strings.ReplaceAll(raw, `\/`, `/`), "&amp;", "&")
		if strings.Contains(cleaned, "/plain/") {
			continue
		}
		if strings.Contains(cleaned, "rdtcdn.com") && isProviderHTTPMediaURL(cleaned) {
			return cleaned
		}
	}
	return ""
}

func (d *Downloader) resolveYangguoMedia(ctx context.Context, task Task) (providerMedia, error) {
	source, sourceID, valid := splitProviderDramaID(task.DramaID)
	if !valid || source != sourceYangguo {
		return providerMedia{}, errors.New("艳果播放分集信息无效，请刷新详情")
	}
	pageURL := strings.TrimSpace(task.Chapter.PageURL)
	if pageURL == "" {
		pageURL = redtubeBaseURL + "/" + sourceID
	}
	body, err := d.fetchProviderText(ctx, pageURL, redtubeBaseURL+"/")
	if err != nil {
		return providerMedia{}, err
	}
	flat := strings.ReplaceAll(body, `\/`, `/`)
	if match := redtubeMediaPathRe.FindString(flat); match != "" {
		path := strings.Trim(match, `"`)
		if mediaBody, err := d.fetchProviderText(ctx, redtubeBaseURL+path, pageURL); err == nil {
			if address, quality := redtubeMediaURLFromJSON(mediaBody); address != "" {
				return providerMedia{URL: address, Referer: pageURL, Quality: quality}, nil
			}
		}
	}
	if address := redtubeDirectMp4FromHTML(body); address != "" {
		return providerMedia{URL: address, Referer: pageURL}, nil
	}
	return providerMedia{}, errors.New("艳果未返回可播地址，请刷新详情")
}

type pornhubMediaDefinition struct {
	Format   string          `json:"format"`
	VideoURL string          `json:"videoUrl"`
	Quality  json.RawMessage `json:"quality"`
}

func pornhubMediaURLFromDefinitions(body string) (string, int, bool) {
	idx := strings.Index(body, `"mediaDefinitions":`)
	if idx < 0 {
		return "", 0, false
	}
	rest := strings.TrimSpace(body[idx+len(`"mediaDefinitions":`):])
	decoder := json.NewDecoder(strings.NewReader(rest))
	var definitions []pornhubMediaDefinition
	if err := decoder.Decode(&definitions); err != nil {
		return "", 0, false
	}
	mp4 := ""
	bestHLS := ""
	bestQuality := -1
	for _, definition := range definitions {
		if !isProviderHTTPMediaURL(definition.VideoURL) {
			continue
		}
		switch definition.Format {
		case "mp4":
			if strings.Contains(definition.VideoURL, "/video/get_media") {
				continue
			}
			if mp4 == "" {
				mp4 = definition.VideoURL
			}
		case "hls":
			var qualityText string
			if err := json.Unmarshal(definition.Quality, &qualityText); err != nil {
				continue
			}
			if quality, err := strconv.Atoi(qualityText); err == nil && quality > bestQuality {
				bestQuality = quality
				bestHLS = definition.VideoURL
			}
		}
	}
	if mp4 != "" {
		return mp4, 0, true
	}
	if bestHLS != "" {
		return bestHLS, bestQuality, true
	}
	return "", 0, false
}

func (d *Downloader) resolveFengguoMedia(ctx context.Context, task Task) (providerMedia, error) {
	source, sourceID, valid := splitProviderDramaID(task.DramaID)
	if !valid || source != sourceFengguo {
		return providerMedia{}, errors.New("Fengguo播放分集信息无效，请刷新详情")
	}
	pageURL := strings.TrimSpace(task.Chapter.PageURL)
	if pageURL == "" {
		pageURL = pornhubBaseURL + "/view_video.php?viewkey=" + sourceID
	}
	body, err := d.fetchProviderText(ctx, pageURL, pornhubBaseURL+"/")
	if err != nil {
		return providerMedia{}, err
	}
	if address, quality, ok := pornhubMediaURLFromDefinitions(body); ok {
		return providerMedia{URL: address, Referer: pageURL, Quality: quality}, nil
	}
	return providerMedia{}, errors.New("Fengguo未返回可播地址，请刷新详情")
}
