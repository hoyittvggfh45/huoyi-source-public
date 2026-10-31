package core

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestLegadoTocJSBaseURLDingGuoShape(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/novel/1/index_1.html":
			fmt.Fprint(w, `<div class="c"><a href="/ch1">C1</a></div><a href="/novel/1/index_2.html">next</a>`)
		case "/novel/1/index_2.html":
			fmt.Fprint(w, `<div class="c"><a href="/ch2">C2</a></div>`)
		default:
			http.NotFound(w, r)
		}
	}))
	defer srv.Close()
	srcJSON, _ := json.Marshal(map[string]interface{}{
		"bookSourceName": "Ding",
		"bookSourceUrl":  srv.URL,
		"ruleToc": map[string]string{
			"tocList":     "class.c",
			"chapterName": "a@text",
			"chapterUrl":  "a@href",
			"nextTocUrl": "@js:\nvar html = String(result);\nvar matched = baseUrl.match(/index_(\\d+)\\.html$/);\nvar page = matched ? parseInt(matched[1]) : 1;\nvar next = page + 1;\nif (html.indexOf(\"/index_\" + next + \".html\") < 0) return \"\";\nvar prefix = baseUrl.replace(/index_\\d+\\.html$/, \"\").replace(/\\/$/, \"\");\nreturn prefix + \"/index_\" + next + \".html\";",
		},
	})
	out, err := LegadoRunJSON(string(srcJSON), "toc", srv.URL+"/novel/1/index_1.html")
	if err != nil {
		t.Fatalf("toc failed: %v", err)
	}
	var chapters []map[string]string
	if err := json.Unmarshal([]byte(out), &chapters); err != nil || len(chapters) != 2 || chapters[1]["title"] != "C2" {
		t.Fatalf("want C1,C2 got %q err %v", out, err)
	}
}

func TestLegadoTocJSBaseURLHaiTangShape(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.HasSuffix(r.URL.Path, "_2/"):
			fmt.Fprint(w, `<ul class="lb"><li><a href="/c2">H2</a></li></ul>`)
		case strings.HasSuffix(r.URL.Path, "/"):
			fmt.Fprint(w, `<ul class="lb"><li><a href="/c1">H1</a></li></ul><a href="/book/12/34_2/">_2/</a>`)
		default:
			http.NotFound(w, r)
		}
	}))
	defer srv.Close()
	srcJSON, _ := json.Marshal(map[string]interface{}{
		"bookSourceName": "Tang",
		"bookSourceUrl":  srv.URL,
		"ruleToc": map[string]string{
			"tocList":     "class.lb",
			"chapterName": "a@text",
			"chapterUrl":  "a@href",
			"nextTocUrl": "@js:\nvar matched = baseUrl.match(/\\/(\\d+)\\/(\\d+)(?:_(\\d+))?\\/?$/);\nif (!matched) return \"\";\nvar current = matched[3] ? parseInt(matched[3]) : 1;\nvar next = current + 1;\nif (result.indexOf(\"_\" + next + \"/\") < 0) return \"\";\nvar prefix = baseUrl.replace(/_\\d+\\/$/, \"\").replace(/\\/$/, \"\");\nreturn prefix + \"_\" + next + \"/\";",
		},
	})
	out, err := LegadoRunJSON(string(srcJSON), "toc", srv.URL+"/book/12/34/")
	if err != nil {
		t.Fatalf("toc failed: %v", err)
	}
	var chapters []map[string]string
	if err := json.Unmarshal([]byte(out), &chapters); err != nil || len(chapters) != 2 || chapters[1]["title"] != "H2" {
		t.Fatalf("want H1,H2 got %q err %v", out, err)
	}
}

func TestLegadoTocMaxTocPages(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		page := 1
		fmt.Sscanf(strings.TrimPrefix(r.URL.Path, "/p"), "%d", &page)
		if page < 1 || page > 10 {
			http.NotFound(w, r)
			return
		}
		next := ""
		if page < 10 {
			next = fmt.Sprintf(`<a class="next" href="/p%d">next</a>`, page+1)
		}
		fmt.Fprintf(w, `<div class="c"><a href="/ch%d">C%d</a></div>%s`, page, page, next)
	}))
	defer srv.Close()
	srcJSON, _ := json.Marshal(map[string]interface{}{
		"bookSourceName": "Max",
		"bookSourceUrl":  srv.URL,
		"ruleToc": map[string]string{
			"tocList":     "class.c",
			"chapterName": "a@text",
			"chapterUrl":  "a@href",
			"nextTocUrl":  "a.next@href",
			"maxTocPages": "3",
		},
	})
	out, err := LegadoRunJSON(string(srcJSON), "toc", srv.URL+"/p1")
	if err != nil {
		t.Fatalf("toc failed: %v", err)
	}
	var chapters []map[string]string
	if err := json.Unmarshal([]byte(out), &chapters); err != nil || len(chapters) != 3 {
		t.Fatalf("want 3 chapters with maxTocPages=3, got %q err %v", out, err)
	}
}

func TestLegadoTocJSStringifiedArray(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, `<html><body>dummy</body></html>`)
	}))
	defer srv.Close()
	srcJSON, _ := json.Marshal(map[string]interface{}{
		"bookSourceName": "MaoShape",
		"bookSourceUrl":  srv.URL,
		"ruleToc": map[string]string{
			"chapterList": "@js:\nvar list = [{title: 'C1', url: 'https://x.example/c1'}, {title: 'C2', url: 'https://x.example/c2'}];\nvar out = [];\nfor (var i = 0; i < list.length; i++) { out.push({title: list[i].title, url: list[i].url}); }\nreturn JSON.stringify(out);",
			"chapterName": "$.title",
			"chapterUrl":  "$.url",
			"nextTocUrl":  "",
		},
	})
	out, err := LegadoRunJSON(string(srcJSON), "toc", srv.URL+"/shuku/123/")
	if err != nil {
		t.Fatalf("toc failed: %v", err)
	}
	var chapters []map[string]string
	if err := json.Unmarshal([]byte(out), &chapters); err != nil || len(chapters) != 2 || chapters[0]["title"] != "C1" || chapters[1]["url"] != "https://x.example/c2" {
		t.Fatalf("want C1,C2 got %q err %v", out, err)
	}
}

func TestLegadoContentReplaceAndReplaceRegex(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, `<div id="content"><p>First　　Second www.aishangba.org tail</p></div>`)
	}))
	defer srv.Close()
	srcJSON, _ := json.Marshal(map[string]interface{}{
		"bookSourceName": "Rep",
		"bookSourceUrl":  srv.URL,
		"ruleContent": map[string]string{
			"content":      "#content@textNodes##　{2,}##\n##",
			"replaceRegex": "##www\\.aishangba\\.org##\n##",
		},
	})
	out, err := LegadoRunJSON(string(srcJSON), "content", srv.URL+"/c1")
	if err != nil {
		t.Fatalf("content failed: %v", err)
	}
	var res map[string]string
	if err := json.Unmarshal([]byte(out), &res); err != nil {
		t.Fatalf("bad json %q %v", out, err)
	}
	content := res["content"]
	if !strings.Contains(content, "First\nSecond") || strings.Contains(content, "aishangba") {
		t.Fatalf("replace failed, got %q", content)
	}
}

func TestLegadoContentKeepsFirstPageOnNextFailure(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.Contains(r.URL.Path, "p2") {
			http.Error(w, "boom", 500)
			return
		}
		fmt.Fprint(w, `<div id="c">PageOne</div><a id="next1" href="/p2">next</a>`)
	}))
	defer srv.Close()
	srcJSON, _ := json.Marshal(map[string]interface{}{
		"bookSourceName": "Keep",
		"bookSourceUrl":  srv.URL,
		"ruleContent": map[string]string{
			"content":        "div#c@text",
			"nextContentUrl": "a#next1@href",
		},
	})
	out, err := LegadoRunJSON(string(srcJSON), "content", srv.URL+"/p1")
	if err != nil {
		t.Fatalf("content should keep first page, got err %v", err)
	}
	if !strings.Contains(out, "PageOne") {
		t.Fatalf("want PageOne kept, got %q", out)
	}
}

func TestLegadoSourceHeaderPassed(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-Test-Source") != "yes" {
			http.Error(w, "missing header", 403)
			return
		}
		fmt.Fprint(w, `<div class="item"><a class="title" href="/b/1">BookA</a></div>`)
	}))
	defer srv.Close()
	srcJSON, _ := json.Marshal(map[string]interface{}{
		"bookSourceName": "Hdr",
		"bookSourceUrl":  srv.URL,
		"header":         `{"X-Test-Source":"yes"}`,
		"searchUrl":      "/s?q={{key}}",
		"ruleSearch": map[string]string{
			"bookList": "class.item",
			"name":     "a.title@text",
			"bookUrl":  "a.title@href",
		},
	})
	out, err := LegadoRunJSON(string(srcJSON), "search", "x")
	if err != nil || !strings.Contains(out, "BookA") {
		t.Fatalf("header search failed, out %q err %v", out, err)
	}
}

func TestLegadoCheckWebJSUnsupported(t *testing.T) {
	out, err := LegadoRunJSON(`{"bookSourceName":"W","bookSourceUrl":"https://x.example","searchUrl":"/s","ruleSearch":{"bookList":"div.item","name":"a@text"},"ruleContent":{"content":"div#c@text","webJs":"@js:1"}}`, "check", "")
	if err != nil {
		t.Fatalf("check failed: %v", err)
	}
	if !strings.Contains(out, `"supported":false`) || !strings.Contains(out, `"field":"webJs"`) {
		t.Fatalf("want webJs unsupported, got %s", out)
	}
}
