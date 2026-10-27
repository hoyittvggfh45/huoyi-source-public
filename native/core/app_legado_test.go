package core

import (
	"strings"
	"testing"
)

func TestLegadoSplitAttr(t *testing.T) {
	sel, attr := legadoSplitAttr("div.item a.title@href")
	if sel != "div.item a.title" || attr != "href" {
		t.Fatalf("want div.item a.title/href, got %s/%s", sel, attr)
	}
	sel, attr = legadoSplitAttr("div#content@text")
	if sel != "div#content" || attr != "text" {
		t.Fatalf("want div#content/text, got %s/%s", sel, attr)
	}
	if _, _ = legadoSplitAttr("//div"); true {
		sel, _ = legadoSplitAttr("//div")
		if sel != "" {
			t.Fatalf("xpath should be unsupported, got %s", sel)
		}
	}
}

func TestLegadoFieldAndText(t *testing.T) {
	block := `<div class="item"><a class="title" href="/b/1">BookA</a><span class="author">AuthA</span></div>`
	if got := legadoField(block, "a.title@text"); got != "BookA" {
		t.Fatalf("want BookA, got %q", got)
	}
	if got := legadoField(block, "a.title@href"); got != "/b/1" {
		t.Fatalf("want /b/1, got %q", got)
	}
	if got := legadoField(block, "span.author@text"); got != "AuthA" {
		t.Fatalf("want AuthA, got %q", got)
	}
	text := legadoHTMLToText(`<div id="c"><p>第一段</p><p>第二段<br>续行</p></div>`)
	if !strings.Contains(text, "第一段\n第二段\n续行") {
		t.Fatalf("want paragraph breaks, got %q", text)
	}
	src, err := legadoParseSource([]byte(`{"bookSourceName":"T","bookSourceUrl":"https://x.example","searchUrl":"https://x.example/s?k={{key}}&p={{page}}","ruleSearch":{"bookList":"div.item","name":"a.title@text","bookUrl":"a.title@href"},"ruleToc":{"tocList":"dd a","chapterName":"@text","chapterUrl":"@href"},"ruleContent":{"content":"div#content@text"}}`))
	if err != nil {
		t.Fatal(err)
	}
	if src.Name != "T" || src.BookList != "div.item" || src.TocList != "dd a" || src.ContentRule != "div#content@text" {
		t.Fatalf("bad parse: %+v", src)
	}
}
