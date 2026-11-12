package core

import (
	"context"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"
)

func TestFeedProbePopularLive(t *testing.T) {
	if os.Getenv("HG_FEED_PROBE2") != "1" {
		t.Skip("probe requires HG_FEED_PROBE2=1")
	}
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(engine.downloads.close)
	ctx, cancel := context.WithTimeout(context.Background(), 6*time.Minute)
	defer cancel()

	series := "7698294694886788121"
	entry, err := engine.downloader.hongguoAppDetail(ctx, series)
	t.Logf("detail: chapters=%d err=%v title=%q", len(entry.Chapters), err, entry.Drama.Title)
	if err != nil || len(entry.Chapters) == 0 {
		t.Fatal("no chapters")
	}
	ch0 := entry.Chapters[0]
	video := strings.TrimPrefix(ch0.VideoURL, "hongguo-cenc://")
	plan, err := engine.nativeResolve(ctx, nativeInput{Drama: nativeNormalize(entry.Drama), Chapter: ch0, Index: 0})
	t.Logf("resolve: sessionEmpty=%v danmakuId=%q err=%v", plan.Session == "", plan.DanmakuID, err)
	if err == nil {
		page, err := engine.nativeComments(ctx, nativeInput{PlaybackSession: plan.Session})
		t.Logf("comments(plan): total=%d collectors=%d items=%d err=%v", page.Total, page.CollectorsCount, len(page.Items), err)
	}
	direct, err := engine.downloader.hongguoComments(ctx, series, "")
	t.Logf("commentsBySeries: total=%d collectors=%d items=%d score=%v scoreCount=%d err=%v", direct.Total, direct.CollectorsCount, len(direct.Items), direct.Score, direct.ScoreCount, err)
	dm, err := engine.downloader.hongguoDanmaku(ctx, series, video, 0, 30000)
	t.Logf("danmakuById 0-30s: items=%d total=%d err=%v", len(dm.Items), dm.Total, err)
	dm2, err := engine.downloader.hongguoDanmaku(ctx, series, video, 0, 120000)
	t.Logf("danmakuById 0-120s: items=%d total=%d err=%v", len(dm2.Items), dm2.Total, err)

	cctx := context.WithValue(ctx, backgroundCatalogKey{}, true)
	cctx = context.WithValue(cctx, hongguoCommentKey{}, true)
	body := map[string]any{
		"comment_source": 1, "server_channel": 34, "group_id": series, "group_type": 1,
		"comment_type": 2, "sort": 1, "count": 20, "cursor": "", "aid": 8662, "compliance_status": 0,
		"business_param": map[string]any{"book_id": series, "need_count": true},
	}
	raw, err := engine.downloader.hongguoAppRequest(cctx, http.MethodPost, "/novel/commentapi/comment/list/"+series+"/v1/", nil, body)
	if err != nil {
		t.Logf("raw comment api err=%v", err)
		return
	}
	data := hongguoAnyMap(raw["data"])
	if data == nil {
		t.Logf("raw comment api: no data, topKeys=%v", keysOf(raw))
		return
	}
	t.Logf("raw comment api: dataKeys=%v", keysOf(data))
	info := hongguoAnyMap(data["common_list_info"])
	t.Logf("raw common_list_info=%v", info)
	t.Logf("raw extra=%v", hongguoAnyMap(data["extra"]))
	if rows, ok := data["data_list"].([]any); ok {
		t.Logf("raw data_list len=%d", len(rows))
	}
}

func keysOf(m map[string]any) []string {
	out := []string{}
	for k := range m {
		out = append(out, k)
	}
	return out
}
