package core

import (
	"context"
	"net/http"
	"strconv"
	"strings"
	"testing"
	"time"
)

func hongguoOverseaFixture(t *testing.T, mainlandStatus int, mainlandBody string) (*Downloader, *[]string) {
	var requests []string
	registered := 0
	d := sourceFixtureDownloader(t, func(request *http.Request) (*http.Response, error) {
		if strings.Contains(request.URL.Path, "device_register") {
			registered++
			requests = append(requests, "register")
			id := strconv.Itoa(1000 + registered)
			return sourceFixtureResponse(request, http.StatusOK, `{"device_id_str":"`+id+`","install_id_str":"`+id+`9"}`), nil
		}
		host := request.URL.Host
		requests = append(requests, "model@"+host)
		if host == "api5-normal-sinfonlinea.fqnovel.com" {
			return sourceFixtureResponse(request, http.StatusOK, hongguoRotationModelOK), nil
		}
		return sourceFixtureResponse(request, mainlandStatus, mainlandBody), nil
	})
	d.cfg.Retries = 1
	client := d.hongguoClient()
	client.state.DeviceID, client.state.InstallID, client.state.Registered = "7", "8", true
	return d, &requests
}

func TestHongguoAppMediaFallsBackToOverseaLine(t *testing.T) {
	d, requests := hongguoOverseaFixture(t, http.StatusOK, "")
	media, err := d.resolveHongguoAppMedia(context.Background(), "12345")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasSuffix(media.URL, "high.mp4") {
		t.Fatal("oversea line did not return media", media)
	}
	if d.hongguoPlayerSuspended() {
		t.Fatal("oversea fallback success must not suspend the player")
	}
	mainland, oversea := 0, 0
	for _, r := range *requests {
		if r == "model@api5-normal-sinfonlineb.fqnovel.com" {
			mainland++
		}
		if r == "model@api5-normal-sinfonlinea.fqnovel.com" {
			oversea++
		}
	}
	if mainland != 1+hongguoDeviceRotations || oversea != 1 {
		t.Fatal("unexpected line fallback counts", *requests)
	}
}

func TestHongguoAppMediaMainlandSuccessSkipsOverseaLine(t *testing.T) {
	d, requests := hongguoOverseaFixture(t, http.StatusOK, hongguoRotationModelOK)
	if _, err := d.resolveHongguoAppMedia(context.Background(), "12345"); err != nil {
		t.Fatal(err)
	}
	for _, r := range *requests {
		if strings.Contains(r, "sinfonlinea") {
			t.Fatal("mainland success must not touch the oversea line", *requests)
		}
	}
}

func TestHongguoAppMediaNonEmptyErrorSkipsOverseaLine(t *testing.T) {
	d, requests := hongguoOverseaFixture(t, http.StatusInternalServerError, "boom")
	_, err := d.resolveHongguoAppMedia(context.Background(), "12345")
	if err == nil || !strings.Contains(err.Error(), "HTTP 500") {
		t.Fatal("expected mainland HTTP 500 error", err)
	}
	for _, r := range *requests {
		if strings.Contains(r, "sinfonlinea") {
			t.Fatal("non-empty mainland error must not fall back to the oversea line", *requests)
		}
	}
}

func TestHongguoOverseaSourceIdentity(t *testing.T) {
	if got := canonicalProviderSource("hongguo-oversea"); got != sourceHongguoOversea {
		t.Fatalf("canonical overseas = %q, want %q", got, sourceHongguoOversea)
	}
	if got := canonicalProviderSource("hongguo"); got != sourceHongguo {
		t.Fatalf("canonical domestic = %q, want %q", got, sourceHongguo)
	}
	if !isHuangguoProviderSource(sourceHongguoOversea) {
		t.Fatalf("overseas source must be a known provider source")
	}
	source, id, ok := splitProviderDramaID("hongguo-oversea:123456")
	if !ok || source != sourceHongguoOversea || id != "123456" {
		t.Fatalf("split overseas = (%q, %q, %v), want (%q, %q, true)", source, id, ok, sourceHongguoOversea, "123456")
	}
	if _, _, ok := splitProviderDramaID("hongguo-oversea:"); ok {
		t.Fatalf("empty overseas source id must be rejected")
	}
	if _, _, ok := splitProviderDramaID("hongguo-oversea"); ok {
		t.Fatalf("bare overseas source must be rejected")
	}
	if source, _, ok := splitProviderDramaID("hongguo:123456"); !ok || source != sourceHongguo {
		t.Fatalf("domestic split regressed: (%q, %v)", source, ok)
	}
}

func TestRelabelHongguoDrama(t *testing.T) {
	domestic := Drama{ID: "hongguo:123", Source: sourceHongguo, SourceID: "123", Title: "T"}
	relabeled := relabelHongguoDrama(domestic, sourceHongguoOversea)
	if relabeled.ID != "hongguo-oversea:123" || relabeled.Source != sourceHongguoOversea || relabeled.SourceID != "123" || relabeled.Title != "T" {
		t.Fatalf("relabel = %+v", relabeled)
	}
	derived := relabelHongguoDrama(Drama{ID: "hongguo:456", Source: sourceHongguo}, sourceHongguoOversea)
	if derived.ID != "hongguo-oversea:456" || derived.Source != sourceHongguoOversea {
		t.Fatalf("derived relabel = %+v", derived)
	}
	stable := relabelHongguoDrama(relabeled, sourceHongguoOversea)
	if stable.ID != "hongguo-oversea:123" || stable.Source != sourceHongguoOversea {
		t.Fatalf("relabel must be idempotent, got %+v", stable)
	}
}

func TestRelabelHongguoChapters(t *testing.T) {
	chapters := []Chapter{
		{ID: "hongguo:123:789", Source: sourceHongguo, Title: "第1集", VideoURL: "hongguo-cenc://789"},
		{ID: "hgtv:1:2", Source: sourceHGTV, Title: "其他源", VideoURL: "https://example.com/x.m3u8"},
	}
	out := relabelHongguoChapters(chapters, sourceHongguoOversea)
	if out[0].ID != "hongguo-oversea:123:789" || out[0].Source != sourceHongguoOversea {
		t.Fatalf("hongguo chapter not relabeled: %+v", out[0])
	}
	if out[0].VideoURL != "hongguo-cenc://789" {
		t.Fatalf("video url must stay untouched: %q", out[0].VideoURL)
	}
	if out[1].ID != "hgtv:1:2" || out[1].Source != sourceHGTV {
		t.Fatalf("foreign chapter must stay untouched: %+v", out[1])
	}
}

func TestHongguoOverseaCtx(t *testing.T) {
	if hongguoCtxIsOversea(context.Background()) {
		t.Fatalf("plain ctx must not be overseas")
	}
	if !hongguoCtxIsOversea(hongguoOverseaCtx(context.Background())) {
		t.Fatalf("overseas ctx must be detected")
	}
	if hongguoFeedPrefix(true) != "oversea:" || hongguoFeedPrefix(false) != "" {
		t.Fatalf("feed prefix mismatch")
	}
}

func TestHongguoCatalogHasMoreFor(t *testing.T) {
	state := &hongguoCatalogState{Version: 1, Feeds: map[string]hongguoCatalogCursor{
		"short_play":         {Initialized: true, Exhausted: true},
		"comic_series":       {Initialized: true, Exhausted: true},
		"ai_series":          {Initialized: true, Exhausted: true},
		"oversea:short_play": {Initialized: true, Exhausted: false},
	}}
	if hongguoCatalogHasMoreFor(state, false) {
		t.Fatalf("domestic feeds exhausted, want no more")
	}
	if !hongguoCatalogHasMoreFor(state, true) {
		t.Fatalf("overseas feed open, want more")
	}
	if hongguoCatalogHasMore(state) != hongguoCatalogHasMoreFor(state, false) {
		t.Fatalf("legacy helper must match domestic check")
	}
}

func TestRestoreHongguoCatalogKeepsOverseaFeeds(t *testing.T) {
	device := newHongguoDeviceID()
	state := &hongguoCatalogState{
		Version: 1, DeviceID: device, InstallID: device,
		Feeds: map[string]hongguoCatalogCursor{
			"oversea:short_play": {Initialized: true, Offset: 54, UpdatedAt: time.Now()},
			"bogus-feed":         {Initialized: true, Offset: 0},
		},
	}
	downloader := &Downloader{}
	downloader.restoreHongguoCatalog(state)
	snapshot := downloader.hongguoCatalogSnapshot()
	if _, ok := snapshot.Feeds["oversea:short_play"]; !ok {
		t.Fatalf("overseas feed must survive restore, got %+v", snapshot.Feeds)
	}
	if _, ok := snapshot.Feeds["bogus-feed"]; ok {
		t.Fatalf("unknown feed must be dropped")
	}
}
