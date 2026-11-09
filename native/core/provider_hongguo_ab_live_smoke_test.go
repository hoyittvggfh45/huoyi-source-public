package core

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strings"
	"testing"
	"time"
)

type hongguoLiveRecorder struct {
	base     http.RoundTripper
	requests []hongguoLiveRequest
}

type hongguoLiveRequest struct {
	host        string
	path        string
	contentType string
	versionCode string
	userAgent   string
}

func (recorder *hongguoLiveRecorder) RoundTrip(request *http.Request) (*http.Response, error) {
	entry := hongguoLiveRequest{host: request.URL.Host, path: request.URL.Path, versionCode: request.URL.Query().Get("version_code"), userAgent: request.Header.Get("User-Agent")}
	if request.Body != nil {
		content, err := io.ReadAll(request.Body)
		request.Body.Close()
		if err == nil {
			request.Body = io.NopCloser(bytes.NewReader(content))
			var parsed map[string]any
			if json.Unmarshal(content, &parsed) == nil {
				if value, ok := parsed["content_type"]; ok {
					encoded, _ := json.Marshal(value)
					entry.contentType = string(encoded)
				}
			}
		}
	}
	recorder.requests = append(recorder.requests, entry)
	return recorder.base.RoundTrip(request)
}

func hongguoLiveFindSeriesID(value any, depth int) string {
	if depth > 8 {
		return ""
	}
	switch item := value.(type) {
	case map[string]any:
		for _, key := range []string{"series_id_str", "series_id"} {
			if text := mapString(item, key); hongguoNumericID.MatchString(text) {
				return text
			}
		}
		for _, child := range item {
			if found := hongguoLiveFindSeriesID(child, depth+1); found != "" {
				return found
			}
		}
	case []any:
		for _, child := range item {
			if found := hongguoLiveFindSeriesID(child, depth+1); found != "" {
				return found
			}
		}
	}
	return ""
}

func TestHongguoABContentLiveSmoke(t *testing.T) {
	if os.Getenv("HG_HONGGUO_AB_LIVE_SMOKE") != "1" {
		t.Skip("live smoke requires HG_HONGGUO_AB_LIVE_SMOKE=1")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Minute)
	defer cancel()
	recorder := &hongguoLiveRecorder{base: http.DefaultTransport}
	d := &Downloader{cfg: Config{dataDir: t.TempDir(), Retries: 2}, client: &http.Client{Transport: recorder}, limiter: newRequestLimiter(3, 0), providerHosts: map[string]string{}}
	if err := d.ensureHongguoDevice(ctx, ""); err != nil {
		t.Fatalf("device register: %v", err)
	}
	mark := func() int { return len(recorder.requests) }
	checkHosts := func(from int, want string, what string) {
		for _, entry := range recorder.requests[from:] {
			if !strings.Contains(entry.host, "fqnovel.com") {
				continue
			}
			if entry.host != want {
				t.Fatalf("%s hit %s, want %s (%+v)", what, entry.host, want, entry)
			}
			uaVersion := regexp.MustCompile(`com\.phoenix\.read/(\d+)`).FindStringSubmatch(entry.userAgent)
			if len(uaVersion) != 2 || uaVersion[1] != entry.versionCode {
				t.Fatalf("%s version mismatch: query=%s ua=%s", what, entry.versionCode, entry.userAgent)
			}
		}
	}
	from := mark()
	if _, err := d.hongguoAppRequest(ctx, http.MethodGet, hongguoBookmallTabPath, url.Values{"tab_type": {"8"}}, nil); err != nil {
		t.Fatalf("bookmall tab: %v", err)
	}
	checkHosts(from, "api5-normal-sinfonlinea.fqnovel.com", "bookmall tab")
	t.Logf("bookmall tab ok on A")
	from = mark()
	landpage, err := d.hongguoAppRequest(ctx, http.MethodPost, "/reading/distribution/category/landpage/v/", nil, map[string]any{
		"filter_ids": "", "req_scene": "short_play", "offset": 0, "need_selector_panel": false, "limit": 18,
		"select_items": map[string]any{"genre": []string{"short_play"}, "category_dim_theme": []string{}, "category_dim_role": []string{}, "category_dim_epoch": []string{}, "sort": []string{}, "gender": []string{}, "online_time": []string{}},
		"session_id":   "", "req_type": "only_content", "client_req_type": 3,
	})
	if err != nil {
		t.Fatalf("landpage: %v", err)
	}
	checkHosts(from, "api5-normal-sinfonlinea.fqnovel.com", "landpage")
	seriesID := hongguoLiveFindSeriesID(landpage["data"], 0)
	if seriesID == "" {
		seriesID = "6975711477277655048"
	}
	t.Logf("landpage ok on A, series=%s", seriesID)
	from = mark()
	if _, err := d.hongguoAppRequest(ctx, http.MethodGet, "/reading/bookapi/search/tab/v1/", url.Values{"query": {"重生"}, "search_source": {"2"}, "offset": {"0"}, "count": {"24"}, "bookstore_tab": {"-1"}}, nil); err != nil {
		t.Fatalf("search tab: %v", err)
	}
	checkHosts(from, "api5-normal-sinfonlinea.fqnovel.com", "search tab")
	t.Logf("search tab ok on A")
	from = mark()
	entry, err := d.hongguoAppDetail(ctx, seriesID)
	if err != nil {
		t.Fatalf("video_detail %s: %v", seriesID, err)
	}
	checkHosts(from, "api5-normal-sinfonlinea.fqnovel.com", "video_detail")
	if len(entry.Chapters) == 0 {
		t.Fatalf("video_detail %s returned no chapters", seriesID)
	}
	videoID := strings.TrimPrefix(entry.Chapters[0].VideoURL, "hongguo-cenc://")
	if !hongguoNumericID.MatchString(videoID) {
		t.Fatalf("video_detail %s first chapter has no video id", seriesID)
	}
	t.Logf("video_detail ok on A, series=%s first video=%s", seriesID, videoID)
	from = mark()
	media, err := d.resolveHongguoVideoModel(ctx, videoID)
	if err != nil {
		t.Fatalf("video_model %s: %v", videoID, err)
	}
	if media.URL == "" {
		t.Fatalf("video_model %s returned no URL", videoID)
	}
	var modelTypes []string
	for _, entry := range recorder.requests[from:] {
		if strings.HasSuffix(entry.path, "/video_model/v1/") {
			if entry.host != "api5-normal-sinfonlineb.fqnovel.com" {
				t.Fatalf("video_model hit %s, want B", entry.host)
			}
			modelTypes = append(modelTypes, entry.contentType)
		}
	}
	if len(modelTypes) == 0 || modelTypes[0] != "1" {
		t.Fatalf("video_model must try content_type 1 first, got %v", modelTypes)
	}
	t.Logf("video_model ok on B, content_types=%v url=%s", modelTypes, media.URL)
	from = mark()
	probe, err := d.hongguoAppRequest(ctx, http.MethodPost, "/novel/player/video_model/v1/", nil, map[string]any{
		"video_id": videoID, "content_type": 1001,
		"biz_param": map[string]any{"need_all_video_definition": true, "video_platform": 3},
	})
	if err != nil {
		t.Fatalf("video_model content_type 1001 probe %s: %v", videoID, err)
	}
	probeModel, _ := hongguoVideoModelValue(nestedMap(probe, "data")["video_model"])
	t.Logf("video_model content_type 1001 accepted by server, model rows=%d", len(anyList(probeModel["video_list"])))
	for _, entry := range recorder.requests[from:] {
		if strings.HasSuffix(entry.path, "/video_model/v1/") && entry.host != "api5-normal-sinfonlineb.fqnovel.com" {
			t.Fatalf("video_model 1001 probe hit %s, want B", entry.host)
		}
	}
	from = mark()
	full, err := d.resolveHongguoAppMedia(ctx, videoID)
	if err != nil {
		t.Fatalf("full media chain %s: %v", videoID, err)
	}
	if full.URL == "" {
		t.Fatalf("full media chain %s returned no URL", videoID)
	}
	for _, entry := range recorder.requests[from:] {
		if strings.Contains(entry.path, "video_model") && entry.host != "api5-normal-sinfonlineb.fqnovel.com" {
			t.Fatalf("media chain hit %s, want B", entry.host)
		}
	}
	t.Logf("full media chain ok, url=%s", full.URL)
}
