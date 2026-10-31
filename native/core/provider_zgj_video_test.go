package core

import (
	"context"
	"testing"
)

const zgjVideoChengguoCatalogFixture = `<html><body>
<div class="card"><a href="/drama/dj-abcdef01"><img src="https://cdn.example.com/c1.jpg" alt="Drama One"></a><span>真人短剧</span><span>更新至12集</span></div>
<div class="card"><a href="/drama/dj-12345678"><img src="https://cdn.example.com/c2.jpg" alt="Drama Two"></a><span>连载中</span></div>
<a href="/browse/page-2">next</a>
</body></html>`

const zgjVideoChengguoDetailFixture = `<html><body>
<h1>Chengguo Drama</h1><p class="desc">A short drama synopsis.</p>
<button><a href="/play/dj-abcdef01/1">1</a></button><button><a href="/play/dj-abcdef01/2">2</a></button>
</body></html>`

const zgjVideoPornhubCatalogFixture = `<html><body>
<div class="video"><a href="/view_video.php?viewkey=ph123"><img src="https://cdn.example.com/p1.jpg" title="PH One"></a></div>
<div class="video"><a href="/view_video.php?viewkey=ph456"><img src="https://cdn.example.com/p2.jpg" alt="PH Two"></a></div>
<a href="/video?page=2">next</a>
</body></html>`

const zgjVideoPornhubDetailFixture = `<html><head><meta property="og:image" content="https://cdn.example.com/poster.jpg"></head><body>
<h1>PH Detail</h1><div id="player"></div>
</body></html>`

const zgjVideoRedtubeCatalogFixture = `<html><body>
<div class="video"><a href="/294430461"><img src="https://cdn.example.com/r1.jpg" title="RT One"></a></div>
<div class="video"><a href="/294430462"><img src="https://cdn.example.com/r2.jpg" alt="RT Two"></a></div>
<a href="/redtube/amateur?page=2">next</a>
</body></html>`

const zgjVideoRedtubeDetailFixture = `<html><head><meta property="og:image" content="https://cdn.example.com/rt.jpg"></head><body>
<h1>RT Detail</h1><div id="player"></div>
</body></html>`

func TestZgjVideoChengguoCatalogAndDetail(t *testing.T) {
	items := chengguoDramasFromHTML(zgjVideoChengguoCatalogFixture, chengguoBaseURL)
	if len(items) != 2 {
		t.Fatalf("chengguo items = %d, want 2", len(items))
	}
	if items[0].ID != "chengguodj:dj-abcdef01" || items[0].TotalEpisode != 12 {
		t.Fatalf("chengguo item 0 = %+v", items[0])
	}
	drama, chapters, err := chengguoDetailFromHTML(zgjVideoChengguoDetailFixture, chengguoBaseURL, "dj-abcdef01")
	if err != nil {
		t.Fatal(err)
	}
	if drama.Title != "Chengguo Drama" || len(chapters) != 2 {
		t.Fatalf("chengguo detail = %+v %+v", drama, chapters)
	}
	if chapters[0].Title != "第1集" || chapters[0].PageURL != chengguoBaseURL+"/play/dj-abcdef01/1" || chapters[0].VideoURL != "" {
		t.Fatalf("chengguo chapter 0 = %+v", chapters[0])
	}
}

func TestZgjVideoPornhubCatalogAndDetail(t *testing.T) {
	items := pornhubDramasFromHTML(zgjVideoPornhubCatalogFixture, pornhubBaseURL)
	if len(items) != 2 || items[0].ID != "pornhub:ph123" || items[1].Title != "PH Two" {
		t.Fatalf("pornhub items = %+v", items)
	}
	drama, chapters, err := pornhubDetailFromHTML(zgjVideoPornhubDetailFixture, pornhubBaseURL, "ph123")
	if err != nil {
		t.Fatal(err)
	}
	if drama.Title != "PH Detail" || drama.Cover != "https://cdn.example.com/poster.jpg" {
		t.Fatalf("pornhub detail = %+v", drama)
	}
	if len(chapters) != 1 || chapters[0].Title != "正片" || chapters[0].VideoURL != "" {
		t.Fatalf("pornhub chapters = %+v", chapters)
	}
}

func TestZgjVideoRedtubeCatalogAndDetail(t *testing.T) {
	items := redtubeDramasFromHTML(zgjVideoRedtubeCatalogFixture, redtubeBaseURL)
	if len(items) != 2 || items[0].ID != "redtube:294430461" || items[1].Title != "RT Two" {
		t.Fatalf("redtube items = %+v", items)
	}
	drama, chapters, err := redtubeDetailFromHTML(zgjVideoRedtubeDetailFixture, redtubeBaseURL, "294430461")
	if err != nil {
		t.Fatal(err)
	}
	if drama.Title != "RT Detail" || drama.Cover != "https://cdn.example.com/rt.jpg" {
		t.Fatalf("redtube detail = %+v", drama)
	}
	if len(chapters) != 1 || chapters[0].Title != "正片" || chapters[0].VideoURL != "" {
		t.Fatalf("redtube chapters = %+v", chapters)
	}
}

func TestZgjVideoDispatchAndResolve(t *testing.T) {
	if got := canonicalProviderSource("www.redtube.net"); got != sourceRedtube {
		t.Fatalf("canonical redtube.net = %q", got)
	}
	if !isHuangguoProviderSource(sourceChengguo) || !isHuangguoProviderSource(sourcePornhub) {
		t.Fatal("new sources must be provider sources")
	}
	if !validNativeCategory(sourcePornhub, "111") || !validNativeCategory(sourcePornhub, "65") || !validNativeCategory(sourcePornhub, "15") {
		t.Fatal("verified pornhub categories must be valid")
	}
	if validNativeCategory(sourcePornhub, "999") || validNativeCategory(sourceRedtube, "teen") {
		t.Fatal("unverified categories must be rejected")
	}
	if !nativeSourceSupportsSearch(sourceChengguo) {
		t.Fatal("chengguo must support search")
	}
	if nativeSourceSupportsSearch(sourcePornhub) || nativeSourceSupportsSearch(sourceRedtube) {
		t.Fatal("pornhub and redtube search is unverified and must stay unsupported")
	}
	downloader := &Downloader{}
	for name, fn := range map[string]func(context.Context, Task) (providerMedia, error){
		"chengguo": downloader.resolveChengguoMedia,
		"pornhub":  downloader.resolvePornhubMedia,
		"redtube":  downloader.resolveRedtubeMedia,
	} {
		if _, err := fn(context.Background(), Task{}); err == nil {
			t.Fatalf("%s resolve must fail until page-source verification", name)
		}
	}
}

func TestZgjVideoYoutubeRouting(t *testing.T) {
	if got := canonicalProviderSource("www.youtube.com"); got != sourceYouTube {
		t.Fatalf("canonical www.youtube.com = %q", got)
	}
	if got := canonicalProviderSource("youtube"); got != sourceYouTube {
		t.Fatalf("canonical youtube = %q", got)
	}
	if !isHuangguoProviderSource(sourceYouTube) {
		t.Fatal("youtube must be a provider source")
	}
	if !validNativeCategory(sourceYouTube, "home") || !validNativeCategory(sourceYouTube, "shorts") || !validNativeCategory(sourceYouTube, "channel:UC-9-kyTW8ZkZNDHQJ6FgpwQ") || !validNativeCategory(sourceYouTube, "browse:FEpodcasts_destination|qgcCCAE%3D") {
		t.Fatal("verified youtube categories must be valid")
	}
	if validNativeCategory(sourceYouTube, "bogus") {
		t.Fatal("unverified youtube categories must be rejected")
	}
	if !nativeSourceSupportsSearch(sourceYouTube) {
		t.Fatal("youtube must support search")
	}
	downloader := &Downloader{}
	if got := downloader.providerBaseURL(sourceYouTube); got != "https://www.youtube.com" {
		t.Fatalf("youtube base URL = %q", got)
	}
	if slot, ok := zgjVideoSlotFor("youtube"); !ok || slot.Tier != zgjTierComplete || slot.Group != zgjGroupGreen || !slot.HasCatalog || !slot.HasDetail || !slot.HasSearch || !slot.HasResolve {
		t.Fatalf("youtube slot = %+v ok=%v, want complete/green with all routes", slot, ok)
	}
	item := map[string]interface{}{
		"vod_id": "dQw4w9WgXcQ", "id": "youtube:dQw4w9WgXcQ", "title": "Fixture Title",
		"cover":        "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg",
		"categoryName": "首页", "episodeCount": 1,
		"chapters": []interface{}{map[string]interface{}{"episodeId": "dQw4w9WgXcQ", "title": "正片", "index": 1, "episode": 1}},
	}
	drama := sekuDramaFromMap(sourceYouTube, item)
	if drama.ID != "youtube:dQw4w9WgXcQ" || drama.Source != sourceYouTube || drama.SourceID != "dQw4w9WgXcQ" || drama.Cover != "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg" {
		t.Fatalf("youtube drama conversion = %+v", drama)
	}
	chapters := sekuChaptersFromMap(sourceYouTube, "dQw4w9WgXcQ", item)
	if len(chapters) != 1 || chapters[0].Title != "正片" || chapters[0].ID != "youtube:dQw4w9WgXcQ:dQw4w9WgXcQ" {
		t.Fatalf("youtube chapters = %+v", chapters)
	}
}
