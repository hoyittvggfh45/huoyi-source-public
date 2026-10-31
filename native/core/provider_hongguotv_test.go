package core

import (
	"strings"
	"testing"
)

const hongguotvRankFixture = `<script async="" data-script-src="modern-run-window-fn" data-fn-name="mergeLoaderData" data-fn-args="[&quot;rank_hot-drama/page&quot;,[{&quot;key&quot;:&quot;content&quot;,&quot;routerDataFnName&quot;:&quot;p&quot;,&quot;routerDataFnArgs&quot;:[&quot;{\&quot;isSuccess\&quot;:true,\&quot;rankList\&quot;:[{\&quot;id\&quot;:\&quot;111\&quot;,\&quot;seriesId\&quot;:\&quot;111\&quot;,\&quot;rank\&quot;:1,\&quot;title\&quot;:\&quot;第一名剧\&quot;,\&quot;cover\&quot;:\&quot;https://example.test/a.jpg\&quot;},{\&quot;id\&quot;:\&quot;222\&quot;,\&quot;seriesId\&quot;:\&quot;222\&quot;,\&quot;rank\&quot;:2,\&quot;title\&quot;:\&quot;第二名剧\&quot;,\&quot;cover\&quot;:\&quot;https://example.test/b.jpg\&quot;}]}&quot;]}]]"></script>`

func TestHongguotvCategories(t *testing.T) {
	if len(hongguotvCategories) != 7 {
		t.Fatalf("categories = %d, want 7", len(hongguotvCategories))
	}
	entry, ok := hongguotvCategoryFor("rank-hot")
	if !ok || entry.rank != "hot-drama" {
		t.Fatalf("rank-hot = %+v %v, want rank hot-drama", entry, ok)
	}
	if _, ok := hongguotvCategoryFor("nope"); ok {
		t.Fatalf("unknown category should not resolve")
	}
	if !validNativeCategory(sourceHongguotv, "comic") || validNativeCategory(sourceHongguotv, "nope") {
		t.Fatalf("validNativeCategory hongguotv mismatch")
	}
}

func TestHongguotvRankList(t *testing.T) {
	items := hongguotvRankList(hongguotvRankFixture)
	if len(items) != 2 {
		t.Fatalf("rank items = %d, want 2", len(items))
	}
	if items[0].ID != "hongguotv:111" || items[0].Source != sourceHongguotv || items[0].ChannelName != "红果TV" || items[0].Remark != "第1名" {
		t.Fatalf("first rank item = %+v", items[0])
	}
	if items[1].Title != "第二名剧" || items[1].Cover != "https://example.test/b.jpg" {
		t.Fatalf("second rank item = %+v", items[1])
	}
	if got := hongguotvRankList("<html></html>"); len(got) != 0 {
		t.Fatalf("empty page should yield no rank items, got %d", len(got))
	}
}

func TestHongguotvDramaFromAny(t *testing.T) {
	drama := hongguotvDramaFromAny(map[string]any{
		"series_id": "7699683909419666457", "series_name": "归路",
		"series_cover": "https://example.test/cover.jpg", "episode_cnt": "78",
		"episode_right_text": "全78集", "tags": []any{"现代", "重生"},
	}, "真人剧")
	if drama.ID != "hongguotv:7699683909419666457" || drama.Source != sourceHongguotv {
		t.Fatalf("drama id/source = %s %s", drama.ID, drama.Source)
	}
	if drama.ChannelName != "红果TV" || drama.Title != "归路" || drama.Remark != "全78集" {
		t.Fatalf("drama = %+v", drama)
	}
	if len(drama.Tags) != 2 {
		t.Fatalf("tags = %v", drama.Tags)
	}
}

func TestHongguotvRetag(t *testing.T) {
	drama := Drama{ID: "hongguo:123", Source: sourceHongguo, SourceID: "123", Title: "剧", ChannelName: "红果"}
	tagged := hongguotvRetag(drama)
	if tagged.ID != "hongguotv:123" || tagged.Source != sourceHongguotv || tagged.ChannelName != "红果TV" {
		t.Fatalf("retagged = %+v", tagged)
	}
}

func TestHongguotvBatchModel(t *testing.T) {
	model, err := hongguotvBatchModel(map[string]any{
		"data": map[string]any{
			"999": map[string]any{
				"video_model": map[string]any{
					"video_list": []any{map[string]any{"main_url": "https://example.test/v.mp4"}},
				},
			},
		},
	}, "999")
	if err != nil || len(model) == 0 {
		t.Fatalf("object model err = %v model = %v", err, model)
	}
	encoded, err := hongguotvBatchModel(map[string]any{
		"data": map[string]any{
			"999": map[string]any{
				"video_model": `{"video_list":[{"main_url":"https://example.test/w.mp4"}],"video_duration":"30"}`,
			},
		},
	}, "999")
	if err != nil || len(encoded) == 0 {
		t.Fatalf("string model err = %v model = %v", err, encoded)
	}
	payload := hongguotvBatchPayload("999")
	ids, _ := payload["mixed_video_id_map"].(map[string]any)["1004"].([]string)
	if len(ids) != 1 || ids[0] != "999" {
		t.Fatalf("payload ids = %v", ids)
	}
	if _, err := hongguotvBatchModel(map[string]any{"data": map[string]any{}}, "999"); err == nil {
		t.Fatalf("empty data should error")
	}
	if !strings.Contains(canonicalProviderSource("hongguotv"), sourceHongguotv) {
		t.Fatalf("canonical hongguotv mismatch")
	}
	if !isHuangguoProviderSource(sourceHongguotv) || !nativeSourceAvailable(sourceHongguotv) {
		t.Fatalf("hongguotv should be an available provider source")
	}
}
