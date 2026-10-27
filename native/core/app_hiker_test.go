package core

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func newTestServer(t *testing.T) *httptest.Server {
	t.Helper()
	htmlText := `<html><body><div class="row-item-title">TabOne</div><div class="row-item-content"><div class="item"><a href="/play/1">ItemOne</a></div></div></body></html>`
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(htmlText))
	}))
	t.Cleanup(srv.Close)
	return srv
}

func TestHikerParseArray(t *testing.T) {
	htmlText := `<html><body><ul class="list"><li><a title="A" href="/a">A</a></li><li><a title="B" href="/b">B</a></li></ul></body></html>`
	out := hikerParseArray(htmlText, "body&&.list&&li")
	if len(out) != 2 {
		t.Fatalf("want 2, got %d: %v", len(out), out)
	}
	if !strings.Contains(out[0], "A") {
		t.Fatalf("first item missing A: %s", out[0])
	}
	title := hikerParseSingle(out[0], "a&&title")
	if title != "A" {
		t.Fatalf("want title A, got %q", title)
	}
}

func TestHikerJSSetResult(t *testing.T) {
	e := NewHikerEngine("")
	rule := HikerRule{FindRule: "js:\nvar d=[]; d.push({title:'T1', url:'http://x/1'}); setResult(d);"}
	res, err := e.Run(rule, "find", "")
	if err != nil {
		t.Fatal(err)
	}
	b, _ := json.Marshal(res)
	if !strings.Contains(string(b), "T1") {
		t.Fatalf("result missing T1: %s", b)
	}
}

func TestHikerConfigPreRule(t *testing.T) {
	e := NewHikerEngine("")
	rule := HikerRule{
		PreRule:  "initConfig({host: 'https://example.test/'});",
		FindRule: "js:\nvar host = config.host; var d=[]; d.push({title: host, url: host}); setResult(d);",
	}
	res, err := e.Run(rule, "find", "")
	if err != nil {
		t.Fatal(err)
	}
	b, _ := json.Marshal(res)
	if !strings.Contains(string(b), "https://example.test/") {
		t.Fatalf("result missing config host: %s", b)
	}
}

func TestHikerPdfFunctions(t *testing.T) {
	e := NewHikerEngine("")
	e.lastHTML = `<html><body><div class="row-item-content"><div class="item"><a href="/x">X</a></div></div></body></html>`
	rule := HikerRule{FindRule: "js:\nvar list = pdfa(getResCode(), 'body&&.row-item-content&&.item'); var d=[]; d.push({title: pdfh(list[0], 'a&&Text'), url: pd(list[0], 'a&&href')}); setHomeResult({data: d});"}
	res, err := e.Run(rule, "find", "")
	if err != nil {
		t.Fatal(err)
	}
	b, _ := json.Marshal(res)
	if !strings.Contains(string(b), "/x") {
		t.Fatalf("result missing /x: %s", b)
	}
}

func TestHikerNanrenStyleFind(t *testing.T) {
	srv := newTestServer(t)
	rule := HikerRule{
		URL:     "hiker://empty##",
		PreRule: "initConfig({host: '" + srv.URL + "/'});",
		FindRule: "js:\nvar res = {};\nvar d = [];\nvar host = config.host;\nvar MY_URL = MY_URL.replace(\"hiker://empty##\", host);\nvar html = fetch(MY_URL);\nvar tabs = pdfa(html, 'body&&.row-item-title');\nvar conts = pdfa(html, 'body&&.row-item-content');\nfor (var i = 0; i < conts.length; i++) {\n    var list = pdfa(conts[i], '.row-item-content&&.item');\n    var title = pdfh(tabs[i], '.row-item-title&&Text');\n    d.push({title: title, url: 'hiker://empty', col_type: 'flex_button'});\n    for (var j = 0; j < list.length; j++) {\n        d.push({title: pdfh(list[j], 'a&&Text'), url: pd(list[j], 'a&&href'), col_type: 'flex_button'});\n    }\n}\nres.data = d;\nsetHomeResult(res);",
	}
	e := NewHikerEngine("")
	res, err := e.Run(rule, "find", "")
	if err != nil {
		t.Fatal(err)
	}
	b, _ := json.Marshal(res)
	if !strings.Contains(string(b), "TabOne") || !strings.Contains(string(b), "/play/1") {
		t.Fatalf("result missing tab or item: %s", b)
	}
}

func TestHikerCleanListURL(t *testing.T) {
	got := hikerCleanListURL("https://example.test/list/fypage[firstPage=https://example.test/list.html]")
	if got != "https://example.test/list/1" {
		t.Fatalf("want https://example.test/list/1, got %q", got)
	}
}

func TestHikerListRule(t *testing.T) {
	e := NewHikerEngine("")
	e.lastHTML = `<html><body><ul class="list"><li><a title="A" href="/a">A</a></li></ul></body></html>`
	rule := HikerRule{FindRule: ".list&&li;a&&title;a&&href"}
	res, err := e.Run(rule, "find", "")
	if err != nil {
		t.Fatal(err)
	}
	b, _ := json.Marshal(res)
	if !strings.Contains(string(b), "A") {
		t.Fatalf("list result missing A: %s", b)
	}
}
