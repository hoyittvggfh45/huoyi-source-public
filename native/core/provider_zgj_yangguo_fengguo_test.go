package core

import (
	"context"
	"testing"
)

func TestZgjYangguoFengguoRetag(t *testing.T) {
	drama := Drama{ID: "redtube:294430461", Source: "redtube", SourceID: "294430461", Title: "Sample"}
	chapters := []Chapter{{ID: "redtube:294430461:main", Source: "redtube", Title: "正片", PageURL: "https://www.redtube.net/294430461", Referer: "https://www.redtube.net/"}}
	retagged, retaggedChapters := retagZgjFamilyDrama(drama, chapters, sourceYangguo)
	if retagged.ID != "yangguo:294430461" || retagged.Source != sourceYangguo {
		t.Fatalf("retagged drama = %+v", retagged)
	}
	if len(retaggedChapters) != 1 || retaggedChapters[0].ID != "yangguo:294430461:main" || retaggedChapters[0].Source != sourceYangguo {
		t.Fatalf("retagged chapters = %+v", retaggedChapters)
	}
	if retaggedChapters[0].PageURL != "https://www.redtube.net/294430461" {
		t.Fatalf("retag must keep page URL, got %+v", retaggedChapters[0])
	}
	items := retagZgjFamilyDramas([]Drama{{ID: "pornhub:abc", Source: "pornhub", SourceID: "abc"}}, sourceFengguo)
	if items[0].ID != "fengguo:abc" || items[0].Source != sourceFengguo {
		t.Fatalf("retagged items = %+v", items)
	}
}

func TestZgjRedtubeMediaJSON(t *testing.T) {
	body := `[{"defaultQuality":false,"format":"mp4","quality":"1080","videoUrl":"https://ev-ph.rdtcdn.com/v1080.mp4"},{"defaultQuality":true,"format":"mp4","quality":"720","videoUrl":"https://ev-ph.rdtcdn.com/v720.mp4"},{"defaultQuality":false,"format":"mp4","quality":"480","videoUrl":"https://ev-ph.rdtcdn.com/v480.mp4"}]`
	address, quality := redtubeMediaURLFromJSON(body)
	if address != "https://ev-ph.rdtcdn.com/v720.mp4" || quality != 720 {
		t.Fatalf("default pick = %q %d", address, quality)
	}
	noDefault := `[{"defaultQuality":false,"format":"mp4","quality":"240","videoUrl":"https://ev-ph.rdtcdn.com/v240.mp4"},{"defaultQuality":false,"format":"mp4","quality":"1080","videoUrl":"https://ev-ph.rdtcdn.com/v1080.mp4"}]`
	address, quality = redtubeMediaURLFromJSON(noDefault)
	if address != "https://ev-ph.rdtcdn.com/v1080.mp4" || quality != 1080 {
		t.Fatalf("max quality pick = %q %d", address, quality)
	}
	if address, _ := redtubeMediaURLFromJSON(`not json`); address != "" {
		t.Fatalf("invalid json must yield empty, got %q", address)
	}
}

func TestZgjRedtubeDirectMp4(t *testing.T) {
	body := `<a href="https://pix-cdn77.rdtcdn.com/x.mp4/plain/rs:fit:1280:720">poster</a><a href="https://ev-ph.rdtcdn.com/y.mp4">video</a>`
	if got := redtubeDirectMp4FromHTML(body); got != "https://ev-ph.rdtcdn.com/y.mp4" {
		t.Fatalf("direct mp4 = %q", got)
	}
	plainOnly := `<a href="https://pix-cdn77.rdtcdn.com/x.mp4/plain/rs:fit:1280:720">poster</a>`
	if got := redtubeDirectMp4FromHTML(plainOnly); got != "" {
		t.Fatalf("plain transform must be skipped, got %q", got)
	}
}

func TestZgjPornhubDefinitions(t *testing.T) {
	body := `<script>var x = {"mediaDefinitions":[{"format":"hls","quality":"720","videoUrl":"https://em-h.phncdn.com/h720.m3u8"},{"format":"hls","quality":"1080","videoUrl":"https://em-h.phncdn.com/h1080.m3u8"},{"format":"mp4","quality":[],"videoUrl":"https://cn.pornhub.com/video/get_media?s=abc&v=ph123","remote":true},{"format":"mp4","quality":[],"videoUrl":"https://kw.phncdn.com/v.mp4","remote":true}],"other":1};</script>`
	address, _, ok := pornhubMediaURLFromDefinitions(body)
	if !ok || address != "https://kw.phncdn.com/v.mp4" {
		t.Fatalf("direct mp4 entry must win over get_media proxy, got %q %v", address, ok)
	}
	proxyOnly := `{"mediaDefinitions":[{"format":"hls","quality":"720","videoUrl":"https://em-h.phncdn.com/h720.m3u8"},{"format":"mp4","quality":[],"videoUrl":"https://cn.pornhub.com/video/get_media?s=abc&v=ph123","remote":true}]}`
	address, quality, ok := pornhubMediaURLFromDefinitions(proxyOnly)
	if !ok || address != "https://em-h.phncdn.com/h720.m3u8" || quality != 720 {
		t.Fatalf("get_media-only mp4 must fall back to hls, got %q %d %v", address, quality, ok)
	}
	hlsOnly := `{"mediaDefinitions":[{"format":"hls","quality":"240","videoUrl":"https://em-h.phncdn.com/h240.m3u8"},{"format":"hls","quality":"720","videoUrl":"https://em-h.phncdn.com/h720.m3u8"}]}`
	address, quality, ok = pornhubMediaURLFromDefinitions(hlsOnly)
	if !ok || address != "https://em-h.phncdn.com/h720.m3u8" || quality != 720 {
		t.Fatalf("hls pick = %q %d %v", address, quality, ok)
	}
	if _, _, ok := pornhubMediaURLFromDefinitions(`no definitions here`); ok {
		t.Fatal("missing definitions must fail")
	}
}

func TestZgjYangguoFengguoDispatch(t *testing.T) {
	if got := canonicalProviderSource("yangguo"); got != sourceYangguo {
		t.Fatalf("canonical yangguo = %q", got)
	}
	if got := canonicalProviderSource("fengguo"); got != sourceFengguo {
		t.Fatalf("canonical fengguo = %q", got)
	}
	if !isHuangguoProviderSource(sourceYangguo) || !isHuangguoProviderSource(sourceFengguo) {
		t.Fatal("yangguo and fengguo must be provider sources")
	}
	if !validNativeCategory(sourceYangguo, "amateur") || validNativeCategory(sourceYangguo, "teen") {
		t.Fatal("yangguo categories must mirror redtube")
	}
	if !validNativeCategory(sourceFengguo, "111") || validNativeCategory(sourceFengguo, "999") {
		t.Fatal("fengguo categories must mirror pornhub")
	}
	if !nativeSourceSupportsSearch(sourceYangguo) || !nativeSourceSupportsSearch(sourceFengguo) {
		t.Fatal("yangguo and fengguo must support search")
	}
	downloader := &Downloader{}
	if got := downloader.providerBaseURL(sourceYangguo); got != redtubeBaseURL {
		t.Fatalf("yangguo base = %q", got)
	}
	if got := downloader.providerBaseURL(sourceFengguo); got != pornhubBaseURL {
		t.Fatalf("fengguo base = %q", got)
	}
	engine := &nativeEngine{}
	categories, err := engine.nativeCategories(context.Background(), sourceYangguo, false)
	if err != nil || len(categories) != 2 || categories[1].ID != "amateur" {
		t.Fatalf("yangguo categories = %+v err %v", categories, err)
	}
	categories, err = engine.nativeCategories(context.Background(), sourceFengguo, false)
	if err != nil || len(categories) != 4 || categories[1].ID != "111" {
		t.Fatalf("fengguo categories = %+v err %v", categories, err)
	}
}
