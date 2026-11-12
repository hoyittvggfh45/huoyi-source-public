package core

import (
	"context"
	"os"
	"strings"
	"testing"
	"time"
)

func TestFeedProbeLive(t *testing.T) {
	if os.Getenv("HG_FEED_PROBE") != "1" {
		t.Skip("probe requires HG_FEED_PROBE=1")
	}
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(engine.downloads.close)
	ctx, cancel := context.WithTimeout(context.Background(), 6*time.Minute)
	defer cancel()

	dramas, err := engine.downloader.fetchHongguoAppCatalogCategory(ctx, "comic_series")
	t.Logf("comic catalog: n=%d err=%v", len(dramas), err)
	if len(dramas) == 0 {
		t.Fatal("no comic dramas")
	}
	first := dramas[0]
	t.Logf("first drama: id=%q categoryName=%q categoryField=%q normalizedCategory=%q tags=%v heat=%q", first.ID, first.CategoryName, first.Category, nativeDramaCategory(first), first.Tags, first.Heat)

	_, seriesID, valid := splitProviderDramaID(first.ID)
	if !valid {
		t.Fatalf("bad drama id %q", first.ID)
	}
	entry, err := engine.downloader.hongguoAppDetail(ctx, seriesID)
	t.Logf("detail: chapters=%d err=%v", len(entry.Chapters), err)
	if err != nil || len(entry.Chapters) == 0 {
		t.Fatal("no chapters")
	}
	ch0 := entry.Chapters[0]
	t.Logf("chapter0: id=%q videoURL=%q source=%q", ch0.ID, ch0.VideoURL, ch0.Source)

	plan, err := engine.nativeResolve(ctx, nativeInput{Drama: nativeNormalize(first), Chapter: ch0, Index: 0})
	t.Logf("resolve: sessionEmpty=%v danmakuId=%q urlLen=%d err=%v", plan.Session == "", plan.DanmakuID, len(plan.URL), err)
	if err == nil {
		page, err := engine.nativeComments(ctx, nativeInput{PlaybackSession: plan.Session})
		t.Logf("comments(plan): total=%d collectors=%d items=%d err=%v", page.Total, page.CollectorsCount, len(page.Items), err)
	}
	direct, err := engine.downloader.hongguoComments(ctx, seriesID, "")
	t.Logf("commentsBySeries: total=%d collectors=%d items=%d err=%v", direct.Total, direct.CollectorsCount, len(direct.Items), err)
	video := strings.TrimPrefix(ch0.VideoURL, "hongguo-cenc://")
	dm, err := engine.downloader.hongguoDanmaku(ctx, seriesID, video, 0, 30000)
	t.Logf("danmakuById: items=%d total=%d err=%v", len(dm.Items), dm.Total, err)

	board, ok := findRankingBoard("hongguo-comic")
	if !ok {
		t.Fatal("no comic board")
	}
	rank, err := engine.downloader.fetchHongguoRankingPage(ctx, board, 1)
	t.Logf("ranking comic p1: items=%d err=%v", len(rank.Items), err)
	ids := map[string]bool{}
	for _, d := range dramas {
		ids[d.ID] = true
	}
	matched := 0
	for i, item := range rank.Items {
		if i < 3 {
			t.Logf("rank item %d: rank=%d id=%q title=%q heat=%q metric=%q", i, item.Rank, item.Drama.ID, item.Drama.Title, item.Drama.Heat, item.Metric)
		}
		if ids[item.Drama.ID] {
			matched++
		}
	}
	t.Logf("ranking/catalog id matches: %d of %d ranking items", matched, len(rank.Items))
}
