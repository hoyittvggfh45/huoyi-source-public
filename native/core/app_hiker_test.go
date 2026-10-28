package core

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"io"
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
		URL:      "hiker://empty##",
		PreRule:  "initConfig({host: '" + srv.URL + "/'});",
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

func TestHikerAttrSelectors(t *testing.T) {
	htmlText := `<html><body><div class="list"><a href="/play/1" data-id="7">One</a><a href="/read/2.mp4" data-id="8">Two</a><a href="/play/3">Three</a></div></body></html>`
	if got := hikerParseArray(htmlText, "div.list&&a[href]"); len(got) != 3 {
		t.Fatalf("want 3 for [href], got %d", len(got))
	}
	if got := hikerParseArray(htmlText, `div.list&&a[href="/play/1"]`); len(got) != 1 {
		t.Fatalf("want 1 for exact attr, got %d", len(got))
	}
	if got := hikerParseArray(htmlText, `div.list&&a[href*="play"]`); len(got) != 2 {
		t.Fatalf("want 2 for *= attr, got %d", len(got))
	}
	if got := hikerParseArray(htmlText, `div.list&&a[href^="/read"]`); len(got) != 1 {
		t.Fatalf("want 1 for ^= attr, got %d", len(got))
	}
	if got := hikerParseArray(htmlText, `div.list&&a[href$=".mp4"]`); len(got) != 1 {
		t.Fatalf("want 1 for $= attr, got %d", len(got))
	}
	if got := hikerParseArray(htmlText, `div.list&&a[data-id="8"]`); len(got) != 1 || !strings.Contains(got[0], "Two") {
		t.Fatalf("want Two for data-id attr, got %v", got)
	}
	if got := hikerParseArray(htmlText, `div.list&&[data-id="7"]`); len(got) != 1 || !strings.Contains(got[0], "One") {
		t.Fatalf("want One for tag-less attr, got %v", got)
	}
	if got := hikerParseSingle(htmlText, `div.list&&a[href*="play"]&&Text`); got != "One" {
		t.Fatalf("want One for attr single text, got %q", got)
	}
}

func TestHikerPositionalSelectors(t *testing.T) {
	htmlText := `<html><body><ul><li>A</li><li>B</li><li>C</li></ul></body></html>`
	if got := hikerParseArray(htmlText, "ul&&li:eq(1)"); len(got) != 1 || !strings.Contains(got[0], "B") {
		t.Fatalf("want B for :eq(1), got %v", got)
	}
	if got := hikerParseArray(htmlText, "ul&&li:first"); len(got) != 1 || !strings.Contains(got[0], "A") {
		t.Fatalf("want A for :first, got %v", got)
	}
	if got := hikerParseArray(htmlText, "ul&&li:last"); len(got) != 1 || !strings.Contains(got[0], "C") {
		t.Fatalf("want C for :last, got %v", got)
	}
	if got := hikerParseArray(htmlText, "ul&&li:eq(9)"); len(got) != 0 {
		t.Fatalf("want 0 for out of range :eq, got %d", len(got))
	}
	if got := hikerParseSingle(htmlText, "ul&&li:eq(2)&&Text"); got != "C" {
		t.Fatalf("want C for :eq single text, got %q", got)
	}
	attrHtml := `<html><body><div class="list"><a href="/play/1">One</a><a href="/read/2">Two</a><a href="/play/3">Three</a></div></body></html>`
	if got := hikerParseSingle(attrHtml, `div.list&&a[href*="play"]:eq(1)&&Text`); got != "Three" {
		t.Fatalf("want Three for attr plus :eq, got %q", got)
	}
}

func TestHikerResolveURL(t *testing.T) {
	if got := hikerResolveURL("https://example.test/a/b", "/x/y"); got != "https://example.test/x/y" {
		t.Fatalf("want absolute root ref, got %q", got)
	}
	if got := hikerResolveURL("https://example.test/a", "//cdn.test/x.jpg"); got != "https://cdn.test/x.jpg" {
		t.Fatalf("want scheme from base, got %q", got)
	}
	if got := hikerResolveURL("https://example.test", "real"); got != "real" {
		t.Fatalf("want bare key untouched, got %q", got)
	}
	if got := hikerResolveURL("https://example.test", "hiker://empty"); got != "hiker://empty" {
		t.Fatalf("want hiker link untouched, got %q", got)
	}
	if got := hikerResolveURL("hiker://empty##", "/x"); got != "/x" {
		t.Fatalf("want non http base untouched, got %q", got)
	}
	if got := hikerResolveURL("", "/x"); got != "/x" {
		t.Fatalf("want empty base untouched, got %q", got)
	}
}

func TestHikerRelativeListResolvesAgainstSite(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`<html><body><ul class="list"><li><a title="A" href="/a">A</a><img src="/a.jpg"></li></ul></body></html>`))
	}))
	t.Cleanup(srv.Close)
	rule := HikerRule{
		URL:      srv.URL,
		FindRule: ".list&&li;a&&title;img&&src;*;a&&href",
	}
	e := NewHikerEngine("")
	res, err := e.Run(rule, "list", "/list/1")
	if err != nil {
		t.Fatal(err)
	}
	b, _ := json.Marshal(res)
	if !strings.Contains(string(b), srv.URL+"/a\"") {
		t.Fatalf("want absolute href in result, got %s", b)
	}
	if !strings.Contains(string(b), srv.URL+"/a.jpg") {
		t.Fatalf("want absolute pic in result, got %s", b)
	}
}

func TestHikerPlayResolvesLastChapterRule(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/ep/1" {
			_, _ = w.Write([]byte(`<html><body><a id="play" href="/media/1.m3u8">play</a></body></html>`))
			return
		}
		_, _ = w.Write([]byte(`<html><body>other</body></html>`))
	}))
	t.Cleanup(srv.Close)
	rule := HikerRule{
		URL:             srv.URL,
		LastChapterRule: "js:\nvar html = fetch(input);\nvar list = pdfa(html, 'body&&a');\nsetResult(pd(list[0], 'a&&href'));",
	}
	e := NewHikerEngine("")
	res, err := e.Run(rule, "play", "/ep/1")
	if err != nil {
		t.Fatal(err)
	}
	if res != srv.URL+"/media/1.m3u8" {
		t.Fatalf("want resolved media url, got %v", res)
	}
}

func TestHikerPlayWithoutLastChapterRuleErrors(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`<html><body>episode</body></html>`))
	}))
	t.Cleanup(srv.Close)
	e := NewHikerEngine("")
	if _, err := e.Run(HikerRule{URL: srv.URL}, "play", srv.URL+"/ep/1"); err == nil {
		t.Fatal("want error without last chapter rule")
	}
}

func TestHikerFetchResolvesRelativeURL(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/x" {
			_, _ = w.Write([]byte("RELATIVE-OK"))
			return
		}
		_, _ = w.Write([]byte("ROOT"))
	}))
	t.Cleanup(srv.Close)
	e := NewHikerEngine("")
	e.lastURL = srv.URL + "/start"
	rule := HikerRule{
		FindRule: "js:\nvar html = fetch('/api/x');\nsetResult(html);",
	}
	res, err := e.Run(rule, "find", "")
	if err != nil {
		t.Fatal(err)
	}
	if res != "RELATIVE-OK" {
		t.Fatalf("want relative fetch body, got %v", res)
	}
}

func TestHikerModuleRequire(t *testing.T) {
	e := NewHikerEngine("")
	rule := HikerRule{
		FindRule: `js:$.require("m").home()`,
		Pages:    json.RawMessage(`[{"path":"m","rule":"js: var M = { home: function() { setResult([{title: 'T1', url: 'http://x/1'}]); } }; $.exports = M;"}]`),
	}
	res, err := e.Run(rule, "list", "")
	if err != nil {
		t.Fatal(err)
	}
	b, _ := json.Marshal(res)
	if !strings.Contains(string(b), "T1") {
		t.Fatalf("require result missing T1: %s", b)
	}
}

func TestHikerModuleRequireNestedAndStringPages(t *testing.T) {
	inner, _ := json.Marshal([]HikerPage{
		{Path: "a", Rule: `js: var A = { go: function() { return $.require("b").val(); } }; $.exports = A;`},
		{Path: "b", Rule: `js: $.exports = { val: function() { return 'nested-ok'; } };`},
	})
	outer, _ := json.Marshal(string(inner))
	e := NewHikerEngine("")
	rule := HikerRule{
		FindRule: `js:$.require("a").go()`,
		Pages:    json.RawMessage(outer),
	}
	res, err := e.Run(rule, "list", "")
	if err != nil {
		t.Fatal(err)
	}
	b, _ := json.Marshal(res)
	if !strings.Contains(string(b), "nested-ok") {
		t.Fatalf("nested require result missing nested-ok: %s", b)
	}
}

func TestHikerModuleRequireMissing(t *testing.T) {
	e := NewHikerEngine("")
	rule := HikerRule{FindRule: `js:$.require("nope").home()`}
	_, err := e.Run(rule, "list", "")
	if err == nil || !strings.Contains(err.Error(), "module not found") {
		t.Fatalf("want module not found error, got %v", err)
	}
}

func TestHikerJavaShimRoundTrip(t *testing.T) {
	var gotMethod, gotHeader string
	var gotBody []byte
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotMethod = r.Method
		gotHeader = r.Header.Get("X-T")
		b, _ := io.ReadAll(r.Body)
		gotBody = b
		_, _ = w.Write(b)
	}))
	t.Cleanup(srv.Close)
	script := strings.ReplaceAll(`
		var conn = new java.net.URL('SERVER/echo').openConnection();
		conn.setRequestMethod('POST');
		conn.setRequestProperty('X-T', '1');
		conn.setDoOutput(true);
		var os = conn.getOutputStream();
		os.write([104, 105, -56]);
		os.flush(); os.close();
		var code = conn.getResponseCode();
		var is = conn.getInputStream();
		var baos = new java.io.ByteArrayOutputStream();
		var buf = java.lang.reflect.Array.newInstance(java.lang.Byte.TYPE, 8192);
		var r;
		while ((r = is.read(buf)) !== -1) baos.write(buf, 0, r);
		is.close();
		setResult([{title: 'code:' + code, url: 'http://x', desc: String.fromCharCode.apply(null, baos.toByteArray())}]);
	`, "SERVER", srv.URL)
	e := NewHikerEngine("")
	rule := HikerRule{FindRule: "js:" + script}
	res, err := e.Run(rule, "list", "")
	if err != nil {
		t.Fatal(err)
	}
	b, _ := json.Marshal(res)
	if !strings.Contains(string(b), "code:200") || !strings.Contains(string(b), "hi") {
		t.Fatalf("java shim result unexpected: %s", b)
	}
	if gotMethod != "POST" || gotHeader != "1" {
		t.Fatalf("server saw method %q header %q", gotMethod, gotHeader)
	}
	if len(gotBody) != 3 || gotBody[0] != 104 || gotBody[1] != 105 || gotBody[2] != 200 {
		t.Fatalf("server saw body %v, want [104 105 200]", gotBody)
	}
}

func TestHikerGetParamAndKeyword(t *testing.T) {
	e := NewHikerEngine("")
	rule := HikerRule{
		SearchURL:  "hiker://empty?kw=**",
		SearchFind: `js: setResult([{title: getParam('kw') + '|' + MY_KEYWORD, url: 'http://x'}]);`,
	}
	res, err := e.Run(rule, "search", "hello")
	if err != nil {
		t.Fatal(err)
	}
	b, _ := json.Marshal(res)
	if !strings.Contains(string(b), "hello|hello") {
		t.Fatalf("getParam/MY_KEYWORD result unexpected: %s", b)
	}
}

func TestHikerLazyRuleArgs(t *testing.T) {
	e := NewHikerEngine("")
	rule := HikerRule{
		FindRule: `js: var u = $('#x').lazyRule(function(s){}, 'real'); setResult([{title: 'nav', url: u}]);`,
	}
	res, err := e.Run(rule, "list", "")
	if err != nil {
		t.Fatal(err)
	}
	b, _ := json.Marshal(res)
	if !strings.Contains(string(b), "hiker://lazy?args=") || !strings.Contains(string(b), "real") {
		t.Fatalf("lazy rule url unexpected: %s", b)
	}
}

func TestHikerQueryVars(t *testing.T) {
	e := NewHikerEngine("")
	rule := HikerRule{
		FindRule: `js: setResult([{title: getMyVar('sd_cls','') + '/' + getMyVar('sd_page',''), url: 'http://x'}]);`,
	}
	res, err := e.Run(rule, "list", "hiker://empty?sd_cls=real&sd_page=3")
	if err != nil {
		t.Fatal(err)
	}
	b, _ := json.Marshal(res)
	if !strings.Contains(string(b), "real/3") {
		t.Fatalf("query vars result unexpected: %s", b)
	}
}

func TestHikerSetError(t *testing.T) {
	e := NewHikerEngine("")
	rule := HikerRule{FindRule: `js: setError('detail exploded');`}
	_, err := e.Run(rule, "list", "")
	if err == nil || !strings.Contains(err.Error(), "detail exploded") {
		t.Fatalf("want setError message, got %v", err)
	}
}

func TestHikerSaveReadFile(t *testing.T) {
	e := NewHikerEngine("")
	rule := HikerRule{
		FindRule: `js: saveFile('a', 'hello-file'); setResult([{title: readFile('a'), url: 'http://x'}]);`,
	}
	res, err := e.Run(rule, "list", "")
	if err != nil {
		t.Fatal(err)
	}
	b, _ := json.Marshal(res)
	if !strings.Contains(string(b), "hello-file") {
		t.Fatalf("save/read file result unexpected: %s", b)
	}
}

func TestHikerMd5AndRemoveItem(t *testing.T) {
	e := NewHikerEngine("")
	rule := HikerRule{
		FindRule: `js: setItem('k', 'v'); removeItem('k'); setResult([{title: md5('abc') + '|' + getItem('k', 'gone'), url: 'http://x'}]);`,
	}
	res, err := e.Run(rule, "list", "")
	if err != nil {
		t.Fatal(err)
	}
	b, _ := json.Marshal(res)
	if !strings.Contains(string(b), "900150983cd24fb0d6963f7d28e17f72|gone") {
		t.Fatalf("md5/removeItem result unexpected: %s", b)
	}
}

func TestHikerJavaCryptoECB(t *testing.T) {
	e := NewHikerEngine("")
	script := `
		var key = [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15];
		var data = [0,17,34,51,68,85,102,119,136,153,170,187,204,221,238,255];
		var cipher = javax.crypto.Cipher.getInstance('AES/ECB/PKCS5Padding');
		cipher.init(javax.crypto.Cipher.ENCRYPT_MODE, new javax.crypto.spec.SecretKeySpec(key, 'AES'));
		var out = cipher.doFinal(data);
		var hex = '';
		for (var i = 0; i < out.length; i++) hex += ('0' + (out[i] & 255).toString(16)).slice(-2);
		setResult(hex);
	`
	rule := HikerRule{FindRule: "js:" + script}
	res, err := e.Run(rule, "list", "")
	if err != nil {
		t.Fatal(err)
	}
	if res != "69c4e0d86a7b0430d8cdb78070b4c55a954f64f2e4e86e9eee82d20216684899" {
		t.Fatalf("ECB ciphertext unexpected: %v", res)
	}
}

func TestHikerJavaCryptoCBCRoundTrip(t *testing.T) {
	e := NewHikerEngine("")
	script := `
		var key = [43,126,21,22,40,174,210,166,171,247,21,136,9,207,79,60];
		var iv = [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15];
		var data = [104,101,108,108,111,33];
		var cipher = javax.crypto.Cipher.getInstance('AES/CBC/PKCS5Padding');
		cipher.init(javax.crypto.Cipher.ENCRYPT_MODE, new javax.crypto.spec.SecretKeySpec(key, 'AES'), new javax.crypto.spec.IvParameterSpec(iv));
		var out = cipher.doFinal(data);
		var hex = '';
		for (var i = 0; i < out.length; i++) hex += ('0' + (out[i] & 255).toString(16)).slice(-2);
		setResult(hex);
	`
	rule := HikerRule{FindRule: "js:" + script}
	res, err := e.Run(rule, "list", "")
	if err != nil {
		t.Fatal(err)
	}
	hexStr, ok := res.(string)
	if !ok || len(hexStr) != 32 {
		t.Fatalf("CBC result unexpected: %v", res)
	}
	raw, err := hex.DecodeString(hexStr)
	if err != nil {
		t.Fatal(err)
	}
	block, err := aes.NewCipher([]byte{43, 126, 21, 22, 40, 174, 210, 166, 171, 247, 21, 136, 9, 207, 79, 60})
	if err != nil {
		t.Fatal(err)
	}
	dec := make([]byte, len(raw))
	cipher.NewCBCDecrypter(block, []byte{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15}).CryptBlocks(dec, raw)
	if string(dec[:6]) != "hello!" || int(dec[15]) != 10 {
		t.Fatalf("CBC round trip failed: %v", dec)
	}
}

func TestHikerJavaCryptoRSA(t *testing.T) {
	priv, err := rsa.GenerateKey(rand.Reader, 1024)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.MarshalPKIXPublicKey(&priv.PublicKey)
	if err != nil {
		t.Fatal(err)
	}
	b64 := base64.StdEncoding.EncodeToString(der)
	script := strings.ReplaceAll(`
		var T = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
		function b64d(s) {
			var out = [];
			for (var i = 0; i < s.length; i += 4) {
				var a = T.indexOf(s.charAt(i)), b = T.indexOf(s.charAt(i + 1));
				var c = s.charAt(i + 2) === '=' ? -1 : T.indexOf(s.charAt(i + 2));
				var d = s.charAt(i + 3) === '=' ? -1 : T.indexOf(s.charAt(i + 3));
				if (a < 0 || b < 0) break;
				out.push(((a << 2) | (b >> 4)) & 255);
				if (c >= 0) out.push(((b << 4) | (c >> 2)) & 255);
				if (d >= 0 && c >= 0) out.push(((c << 6) | d) & 255);
			}
			return out;
		}
		function jb(arr) {
			var out = [];
			for (var i = 0; i < arr.length; i++) out.push(arr[i] > 127 ? arr[i] - 256 : arr[i]);
			return out;
		}
		var kf = java.security.KeyFactory.getInstance('RSA');
		var pub = kf.generatePublic(new java.security.spec.X509EncodedKeySpec(jb(b64d('PUBB64'))));
		var cipher = javax.crypto.Cipher.getInstance('RSA/ECB/PKCS1Padding');
		cipher.init(javax.crypto.Cipher.ENCRYPT_MODE, pub);
		var out = cipher.doFinal(jb([104, 105]));
		var hex = '';
		for (var i = 0; i < out.length; i++) hex += ('0' + (out[i] & 255).toString(16)).slice(-2);
		setResult(hex);
	`, "PUBB64", b64)
	e := NewHikerEngine("")
	rule := HikerRule{FindRule: "js:" + script}
	res, err := e.Run(rule, "list", "")
	if err != nil {
		t.Fatal(err)
	}
	hexStr, ok := res.(string)
	if !ok || len(hexStr) != 256 {
		t.Fatalf("RSA result unexpected: %v", res)
	}
	raw, err := hex.DecodeString(hexStr)
	if err != nil {
		t.Fatal(err)
	}
	plain, err := rsa.DecryptPKCS1v15(rand.Reader, priv, raw)
	if err != nil {
		t.Fatal(err)
	}
	if string(plain) != "hi" {
		t.Fatalf("RSA round trip failed: %q", plain)
	}
}
