//go:build live

package core

import (
	"context"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"
)

func zgjLiveCover(cover any) string {
	text, _ := cover.(string)
	return text
}

func verifyZgjLiveMedia(t *testing.T, client *http.Client, address, referer string) {
	t.Helper()
	if client == nil {
		client = &http.Client{Timeout: 60 * time.Second}
	}
	if strings.HasSuffix(strings.Split(address, "?")[0], ".m3u8") {
		req, err := http.NewRequestWithContext(context.Background(), http.MethodGet, address, nil)
		if err != nil {
			t.Fatal(err)
		}
		if referer != "" {
			req.Header.Set("Referer", referer)
		}
		resp, err := client.Do(req)
		if err != nil {
			t.Fatalf("playlist fetch %s: %v", address, err)
		}
		defer resp.Body.Close()
		body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
		if err != nil {
			t.Fatal(err)
		}
		if resp.StatusCode != http.StatusOK || !strings.Contains(string(body), "#EXTM3U") {
			t.Fatalf("playlist %s status %d, body %.200s", address, resp.StatusCode, body)
		}
		return
	}
	req, err := http.NewRequestWithContext(context.Background(), http.MethodGet, address, nil)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Range", "bytes=0-1023")
	if referer != "" {
		req.Header.Set("Referer", referer)
	}
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("range fetch %s: %v", address, err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 4096))
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != http.StatusPartialContent {
		t.Fatalf("range %s status %d, body %.200s", address, resp.StatusCode, body)
	}
	contentType := resp.Header.Get("Content-Type")
	if !strings.HasPrefix(contentType, "video/") {
		t.Fatalf("range %s content-type %q, body %.64s", address, contentType, body)
	}
}

func TestZgjYangguoLive(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 180*time.Second)
	defer cancel()
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	downloader := engine.downloader
	items, _, err := downloader.fetchYangguoCatalogPage(ctx, 1, "amateur")
	if err != nil {
		t.Fatalf("yangguo catalog: %v", err)
	}
	if len(items) == 0 {
		if body, err := downloader.fetchProviderText(ctx, redtubeBaseURL+"/redtube/amateur", redtubeBaseURL+"/"); err == nil && strings.Contains(strings.ToLower(body), "verify your age") {
			t.Skip("redtube served the Texas age-verification interstitial on this egress")
		}
		t.Fatalf("yangguo catalog items = %+v", items)
	}
	if !strings.HasPrefix(zgjLiveCover(items[0].Cover), "http") {
		t.Fatalf("yangguo catalog items = %+v", items)
	}
	drama, chapters, err := downloader.fetchYangguoDetail(ctx, "294430461")
	if err != nil {
		t.Fatalf("yangguo detail: %v", err)
	}
	if drama.Title == "" || zgjLiveCover(drama.Cover) == "" || len(chapters) != 1 || chapters[0].PageURL == "" {
		t.Fatalf("yangguo detail = %+v %+v", drama, chapters)
	}
	results, err := downloader.searchYangguo(ctx, "test")
	if err != nil {
		t.Fatalf("yangguo search: %v", err)
	}
	if len(results) == 0 {
		t.Fatal("yangguo search must return results")
	}
	media, err := downloader.resolveYangguoMedia(ctx, Task{DramaID: "yangguo:294430461", Chapter: chapters[0]})
	if err != nil {
		t.Fatalf("yangguo resolve: %v", err)
	}
	if media.URL == "" {
		t.Fatal("yangguo resolve returned empty URL")
	}
	verifyZgjLiveMedia(t, downloader.client, media.URL, media.Referer)
}

func TestZgjFengguoLive(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 180*time.Second)
	defer cancel()
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	downloader := engine.downloader
	items, _, err := downloader.fetchFengguoCatalogPage(ctx, 1, "")
	if err != nil {
		t.Fatalf("fengguo catalog: %v", err)
	}
	if len(items) == 0 || !strings.HasPrefix(zgjLiveCover(items[0].Cover), "http") {
		t.Fatalf("fengguo catalog items = %+v", items)
	}
	drama, chapters, err := downloader.fetchFengguoDetail(ctx, "6a21bdeb05d8b")
	if err != nil {
		t.Fatalf("fengguo detail: %v", err)
	}
	if drama.Title == "" || zgjLiveCover(drama.Cover) == "" || len(chapters) != 1 || chapters[0].PageURL == "" {
		t.Fatalf("fengguo detail = %+v %+v", drama, chapters)
	}
	results, err := downloader.searchFengguo(ctx, "test")
	if err != nil {
		t.Fatalf("fengguo search: %v", err)
	}
	if len(results) == 0 {
		t.Fatal("fengguo search must return results")
	}
	media, err := downloader.resolveFengguoMedia(ctx, Task{DramaID: "fengguo:6a21bdeb05d8b", Chapter: chapters[0]})
	if err != nil {
		t.Fatalf("fengguo resolve: %v", err)
	}
	if media.URL == "" {
		t.Fatal("fengguo resolve returned empty URL")
	}
	verifyZgjLiveMedia(t, downloader.client, media.URL, media.Referer)
}
