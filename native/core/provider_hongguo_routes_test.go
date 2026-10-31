package core

import (
	"context"
	"fmt"
	"reflect"
	"strings"
	"testing"
)

func TestHongguoPlaybackTransportFailed(t *testing.T) {
	if !hongguoPlaybackTransportFailed(fmt.Errorf("Get \"https://example.test\": EOF")) {
		t.Fatal("EOF must count as transport failure")
	}
	if !hongguoPlaybackTransportFailed(fmt.Errorf("read: connection reset by peer")) {
		t.Fatal("connection reset must count as transport failure")
	}
	if hongguoPlaybackTransportFailed(nil) {
		t.Fatal("nil must not count as transport failure")
	}
	if hongguoPlaybackTransportFailed(fmt.Errorf("unexpected status 429")) {
		t.Fatal("status errors must not trigger the http retry")
	}
}

func TestHongguoRouteOrder(t *testing.T) {
	if got := hongguoRouteOrder(false); !reflect.DeepEqual(got, []int{0, 1, 2, 3, 4, 5}) {
		t.Fatalf("mainland order = %v", got)
	}
	if got := hongguoRouteOrder(true); !reflect.DeepEqual(got, []int{1, 0, 2, 3, 4, 5}) {
		t.Fatalf("oversea order = %v", got)
	}
	if hongguoRouteCount != 6 {
		t.Fatalf("route count = %d, want 6", hongguoRouteCount)
	}
}

func TestHongguoRouteDispatchRejectsOutOfRangeWithoutNetwork(t *testing.T) {
	downloader := &Downloader{}
	if _, err := downloader.resolveHongguoMediaRoute(context.Background(), sourceHongguo, "123", "456", 6); err == nil {
		t.Fatal("route 6 must be rejected")
	}
	if _, err := downloader.resolveHongguoMediaRoute(context.Background(), sourceHongguo, "123", "456", -1); err == nil {
		t.Fatal("route -1 must be rejected")
	}
	if _, err := downloader.resolveHongguoMediaRoute(context.Background(), "other", "123", "456", 0); err == nil {
		t.Fatal("non-hongguo source must be rejected")
	}
}

func TestValidateHongguoRouteMedia(t *testing.T) {
	good := providerMedia{URL: "https://media.test/play.mp4"}
	if err := validateHongguoRouteMedia(good, "123", "456"); err != nil {
		t.Fatalf("request-bound media must pass: %v", err)
	}
	if err := validateHongguoRouteMedia(providerMedia{URL: "https://media.test/play.mp4", VideoID: "999"}, "123", "456"); err == nil || !strings.Contains(err.Error(), "集数") {
		t.Fatalf("wrong video id must fail, got %v", err)
	}
	if err := validateHongguoRouteMedia(providerMedia{URL: "https://media.test/play.mp4", SeriesID: "999"}, "123", "456"); err == nil || !strings.Contains(err.Error(), "剧集") {
		t.Fatalf("wrong series id must fail, got %v", err)
	}
	if err := validateHongguoRouteMedia(providerMedia{URL: ""}, "123", "456"); err == nil {
		t.Fatal("empty url must fail")
	}
}

func TestHongguoBatchMediaFromResultRequiresExactVideoKey(t *testing.T) {
	model := map[string]any{"video_list": []any{
		map[string]any{"main_url": "https://media.test/batch.mp4", "video_meta": map[string]any{"codec_type": "h264", "definition": "720p"}},
	}}
	result := map[string]any{"data": map[string]any{"456": map[string]any{"video_model": model}}}
	media, err := hongguoBatchMediaFromResult(result, "456")
	if err != nil || media.URL != "https://media.test/batch.mp4" || media.VideoID != "456" {
		t.Fatalf("exact key must play: media=%+v err=%v", media, err)
	}
	otherOnly := map[string]any{"data": map[string]any{"999": map[string]any{"video_model": model}}}
	if _, err := hongguoBatchMediaFromResult(otherOnly, "456"); err == nil {
		t.Fatal("another episode entry must never stand in for the requested episode")
	}
}

func TestHongguoBatchPayload(t *testing.T) {
	payload := hongguoBatchPayload("456")
	mixed, _ := payload["mixed_video_id_map"].(map[string]any)
	ids, _ := mixed["1004"].([]string)
	if len(ids) != 1 || ids[0] != "456" {
		t.Fatalf("batch payload ids = %v", ids)
	}
}

func TestHongguoResolveIDs(t *testing.T) {
	task := Task{DramaID: "hongguo:123", Chapter: Chapter{VideoURL: "hongguo-cenc://456"}}
	source, series, video, ok := hongguoResolveIDs(task)
	if !ok || source != "hongguo" || series != "123" || video != "456" {
		t.Fatalf("ids = %q %q %q %v", source, series, video, ok)
	}
	task = Task{DramaID: "hongguo-oversea:123", Chapter: Chapter{ID: "hongguo:123:456"}}
	source, _, video, ok = hongguoResolveIDs(task)
	if !ok || source != "hongguo-oversea" || video != "456" {
		t.Fatalf("chapter id fallback = %q %q %v", source, video, ok)
	}
	task = Task{DramaID: "other:123", Chapter: Chapter{VideoURL: "hongguo-cenc://456"}}
	if _, _, _, ok := hongguoResolveIDs(task); ok {
		t.Fatal("other source must not resolve as hongguo")
	}
}

func TestHongguoPlaybackChoiceCarriesRouteNotVariant(t *testing.T) {
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	variant := providerMedia{URL: "https://media.test/route.mp4", Referer: "https://media.test/", Quality: 720}
	choice := nativePlaybackChoice{
		hongguo: true, hongguoSource: sourceHongguo, hongguoSeries: "123", hongguoVideo: "456",
		hongguoRoute: 2, hongguoQuality: 0, hongguoResolved: true,
		media: []providerMedia{variant}, index: 0, qualities: []int{720}, adBlock: true,
	}
	plan, err := engine.nativeOpenPlayback(context.Background(), choice)
	if err != nil {
		t.Fatal(err)
	}
	if plan.RouteIndex != 2 || plan.RouteCount != 6 || plan.OriginalURL != variant.URL {
		t.Fatalf("plan route = %d/%d original url = %q", plan.RouteIndex, plan.RouteCount, plan.OriginalURL)
	}
	if _, err := engine.nativeSelectRoute(context.Background(), plan.Session, 6); err == nil {
		t.Fatal("selecting route 6 must fail before any network attempt")
	}
	last := choice
	last.hongguoRoute = 5
	lastPlan, err := engine.nativeOpenPlayback(context.Background(), last)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := engine.nativeNextPlayback(context.Background(), lastPlan.Session); err == nil {
		t.Fatal("next after the last route must fail")
	}
}
