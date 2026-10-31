package seku

import "testing"

func TestYoutubeCatsShape(t *testing.T) {
	want := []struct{ id, name string }{
		{"home", "首页"},
		{"shorts", "Shorts"},
		{"channel:UC-9-kyTW8ZkZNDHQJ6FgpwQ", "音乐"},
		{"browse:FEstorefront", "影视"},
		{"channel:UC4R8DWoMoI7CAwX8_LjQHig", "直播"},
		{"channel:UCOpNcN46UbXVtpKMrmU4Abg", "游戏"},
		{"browse:FEpodcasts_destination|qgcCCAE%3D", "播客"},
		{"preset:新闻", "新闻"},
		{"preset:体育", "体育"},
		{"preset:时尚", "时尚"},
		{"preset:学习", "学习"},
	}
	if len(ytCats) != len(want) {
		t.Fatalf("ytCats = %d, want %d", len(ytCats), len(want))
	}
	for i, c := range want {
		if ytCats[i].id != c.id || ytCats[i].name != c.name {
			t.Fatalf("ytCats[%d] = %+v, want %+v", i, ytCats[i], c)
		}
	}
	if got := ytCatName("home"); got != "首页" {
		t.Fatalf("ytCatName(home) = %q", got)
	}
}

func TestYoutubeItemFromVideoRenderer(t *testing.T) {
	sub := map[string]interface{}{
		"videoId": "dQw4w9WgXcQ",
		"title":   map[string]interface{}{"simpleText": "Fixture Video"},
		"thumbnail": map[string]interface{}{"thumbnails": []interface{}{
			map[string]interface{}{"url": "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg", "width": float64(480)},
		}},
		"lengthText": map[string]interface{}{"simpleText": "3:32"},
	}
	it, ok := ytItemFrom("videoRenderer", sub)
	if !ok {
		t.Fatal("videoRenderer fixture must parse")
	}
	if it.id != "dQw4w9WgXcQ" || it.title != "Fixture Video" || it.pic != "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg" || it.remarks != "3:32" {
		t.Fatalf("ytItem = %+v", it)
	}
	if _, ok := ytItemFrom("videoRenderer", map[string]interface{}{"videoId": "short"}); ok {
		t.Fatal("short videoId must be rejected")
	}
}

func TestYoutubeHarvestDedupes(t *testing.T) {
	renderer := map[string]interface{}{
		"videoId": "dQw4w9WgXcQ",
		"title":   map[string]interface{}{"simpleText": "Fixture Video"},
	}
	data := map[string]interface{}{
		"a": map[string]interface{}{"videoRenderer": renderer},
		"b": map[string]interface{}{"videoRenderer": renderer},
	}
	items := ytHarvest(data, ytVideoKinds)
	if len(items) != 1 || items[0].id != "dQw4w9WgXcQ" {
		t.Fatalf("ytHarvest = %+v", items)
	}
}

func TestYoutubeItemsToDramasShape(t *testing.T) {
	items := ytItemsToDramas("youtube", []ytItem{{id: "dQw4w9WgXcQ", title: "Fixture Video", pic: "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg", remarks: "3:32"}}, "首页")
	if len(items) != 1 {
		t.Fatalf("items = %d, want 1", len(items))
	}
	m, ok := items[0].(map[string]interface{})
	if !ok {
		t.Fatalf("item type = %T", items[0])
	}
	if m["id"] != "youtube:dQw4w9WgXcQ" || m["vod_id"] != "dQw4w9WgXcQ" || m["cover"] != "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg" {
		t.Fatalf("drama map = %+v", m)
	}
	chapters, _ := m["chapters"].([]interface{})
	if len(chapters) != 1 {
		t.Fatalf("chapters = %d, want 1", len(chapters))
	}
	ep, _ := chapters[0].(map[string]interface{})
	if ep["title"] != "正片" || ep["episodeId"] != "dQw4w9WgXcQ" {
		t.Fatalf("chapter = %+v", ep)
	}
}
