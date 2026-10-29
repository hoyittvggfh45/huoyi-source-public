package core

import (
	"encoding/json"
	"fmt"
	"html"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"golang.org/x/text/encoding/simplifiedchinese"
	"golang.org/x/text/transform"
)

type LegadoSource struct {
	Name            string `json:"bookSourceName"`
	URL             string `json:"bookSourceUrl"`
	Type            int    `json:"bookSourceType"`
	Comment         string `json:"bookSourceComment"`
	LoginURL        string `json:"loginUrl"`
	SearchURL       string `json:"searchUrl"`
	BookList        string `json:"bookList"`
	NameRule        string `json:"name"`
	AuthorRule      string `json:"author"`
	CoverRule       string `json:"coverUrl"`
	BookURLRule     string `json:"bookUrl"`
	IntroRule       string `json:"intro"`
	TocList         string `json:"tocList"`
	TocURL          string `json:"tocUrl"`
	NextTocURL      string `json:"nextTocUrl"`
	ChapterName     string `json:"chapterName"`
	ChapterURL      string `json:"chapterUrl"`
	ContentRule     string `json:"content"`
	NextContent     string `json:"nextContentUrl"`
	ExploreURL      string `json:"exploreUrl"`
	ImageStyle      string `json:"imageStyle"`
	BookInfo        map[string]string
	ExploreBookList string
	ExploreName     string
	ExploreAuthor   string
	ExploreCover    string
	ExploreBookURL  string
	ExploreIntro    string
}

type legadoRaw struct {
	Name         string            `json:"bookSourceName"`
	URL          string            `json:"bookSourceUrl"`
	Type         int               `json:"bookSourceType"`
	Comment      string            `json:"bookSourceComment"`
	LoginURL     string            `json:"loginUrl"`
	SearchURL    string            `json:"searchUrl"`
	ExploreURL   string            `json:"exploreUrl"`
	ImageStyle   string            `json:"imageStyle"`
	RuleSearch   map[string]string `json:"ruleSearch"`
	RuleBookInfo map[string]string `json:"ruleBookInfo"`
	RuleToc      map[string]string `json:"ruleToc"`
	RuleContent  map[string]string `json:"ruleContent"`
	RuleExplore  map[string]string `json:"ruleExplore"`
}

var legadoHTTP = &http.Client{Timeout: 20 * time.Second}

func legadoParseSource(data []byte) (LegadoSource, error) {
	var raw legadoRaw
	if err := json.Unmarshal(data, &raw); err != nil {
		return LegadoSource{}, err
	}
	s := LegadoSource{Name: raw.Name, URL: raw.URL, Type: raw.Type, Comment: raw.Comment, LoginURL: raw.LoginURL, SearchURL: raw.SearchURL, ExploreURL: raw.ExploreURL, ImageStyle: raw.ImageStyle, BookInfo: raw.RuleBookInfo}
	if raw.RuleSearch != nil {
		s.BookList = raw.RuleSearch["bookList"]
		s.NameRule = raw.RuleSearch["name"]
		s.AuthorRule = raw.RuleSearch["author"]
		s.CoverRule = raw.RuleSearch["coverUrl"]
		s.BookURLRule = raw.RuleSearch["bookUrl"]
		s.IntroRule = raw.RuleSearch["intro"]
	}
	if raw.RuleBookInfo != nil {
		s.TocURL = raw.RuleBookInfo["tocUrl"]
	}
	if raw.RuleToc != nil {
		s.TocList = raw.RuleToc["tocList"]
		if s.TocList == "" {
			s.TocList = raw.RuleToc["chapterList"]
		}
		s.NextTocURL = raw.RuleToc["nextTocUrl"]
		s.ChapterName = raw.RuleToc["chapterName"]
		s.ChapterURL = raw.RuleToc["chapterUrl"]
	}
	if raw.RuleContent != nil {
		s.ContentRule = raw.RuleContent["content"]
		s.NextContent = raw.RuleContent["nextContentUrl"]
	}
	if raw.RuleExplore != nil {
		s.ExploreBookList = raw.RuleExplore["bookList"]
		s.ExploreName = raw.RuleExplore["name"]
		s.ExploreAuthor = raw.RuleExplore["author"]
		s.ExploreCover = raw.RuleExplore["coverUrl"]
		s.ExploreBookURL = raw.RuleExplore["bookUrl"]
		s.ExploreIntro = raw.RuleExplore["intro"]
	}
	return s, nil
}

func legadoFetch(rawurl string) (string, error) {
	return legadoRequest(rawurl, "GET", "", nil)
}

func legadoRequest(rawurl, method, body string, headers map[string]string) (string, error) {
	var reader io.Reader
	if body != "" {
		reader = strings.NewReader(body)
	}
	req, err := http.NewRequest(method, rawurl, reader)
	if err != nil {
		return "", err
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0 Mobile Safari/537.36")
	if method == "POST" {
		if strings.HasPrefix(strings.TrimSpace(body), "{") {
			req.Header.Set("Content-Type", "application/json; charset=UTF-8")
		} else {
			req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
		}
	}
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	resp, err := legadoHTTP.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return "", fmt.Errorf("legado http %d", resp.StatusCode)
	}
	b, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}
	text := string(b)
	if !utf8.ValidString(text) {
		if decoded, _, decodeErr := transform.String(simplifiedchinese.GB18030.NewDecoder(), text); decodeErr == nil {
			text = decoded
		}
	}
	return text, nil
}

func legadoSplitAttr(rule string) (string, string) {
	rule = strings.TrimSpace(rule)
	rule = strings.TrimPrefix(rule, "@@")
	rule = strings.TrimPrefix(rule, "@CSS:")
	if strings.HasPrefix(rule, "@js:") || strings.HasPrefix(rule, "//") || strings.Contains(rule, "@js:") {
		return "", ""
	}
	if strings.HasPrefix(rule, "css:") {
		rule = strings.TrimSpace(rule[4:])
	}
	idx := strings.LastIndex(rule, "@")
	if idx < 0 {
		return rule, "text"
	}
	sel := strings.TrimSpace(rule[:idx])
	attr := strings.TrimSpace(rule[idx+1:])
	if sel == "" {
		return "", ""
	}
	return sel, attr
}

func legadoChain(sel string) string {
	sel = strings.ReplaceAll(sel, ">", " ")
	sel = strings.ReplaceAll(sel, ",", " ")
	fields := strings.Fields(sel)
	return strings.Join(fields, "&&")
}

func legadoTryRules(block string, rules []string, fn func(string) string) string {
	for _, r := range rules {
		if v := fn(strings.TrimSpace(r)); v != "" {
			return v
		}
	}
	return ""
}

func legadoField(block, rule string) string {
	if body, spec := legadoSplitReplace(rule); spec != nil {
		return legadoApplyReplace(legadoField(block, body), spec)
	}
	if strings.Contains(rule, "||") {
		return legadoTryRules(block, strings.Split(rule, "||"), func(r string) string {
			return legadoField(block, r)
		})
	}
	if strings.HasPrefix(strings.TrimSpace(rule), "$") {
		return legadoJSONFieldAny(block, rule)
	}
	trimmed := strings.TrimSpace(rule)
	if strings.HasPrefix(trimmed, "/") || strings.HasPrefix(trimmed, "@XPath:") {
		if nodes, value, ok := legadoEvalXPath(block, trimmed, false); ok {
			return legadoScalarFromNodes(nodes, value)
		}
		return ""
	}
	if strings.HasPrefix(trimmed, "@") && !strings.HasPrefix(trimmed, "@@") && !strings.HasPrefix(trimmed, "@CSS:") {
		attr := strings.TrimSpace(strings.TrimPrefix(trimmed, "@"))
		switch attr {
		case "text":
			return strings.TrimSpace(legadoHTMLToText(block))
		case "html":
			return strings.TrimSpace(block)
		default:
			m := regexp.MustCompile(attr + `="([^"]*)"`).FindStringSubmatch(block)
			if m != nil {
				return m[1]
			}
			return ""
		}
	}
	sel, attr := legadoSplitAttr(rule)
	if sel == "" {
		return ""
	}
	if nodes, value, ok := legadoEvalDialect(block, rule, false); ok && len(nodes) > 0 {
		if v := legadoScalarFromNodes(nodes, value); v != "" {
			return v
		}
	}
	if legadoBareIdentRe.MatchString(sel) && attr == "text" && legadoIsJSONBody(block) {
		if v := legadoJSONFieldAny(block, "$."+sel); v != "" {
			return v
		}
	}
	if !legadoIsJSONBody(block) {
		switch trimmed {
		case "text":
			return strings.TrimSpace(legadoHTMLToText(block))
		case "html", "all", "outerHtml":
			return strings.TrimSpace(block)
		case "ownText":
			if doc, _ := legadoParseDoc(block); doc != nil {
				if root := legadoBlockRoot(doc); root != nil {
					return strings.TrimSpace(legadoNodeOwnText(root))
				}
			}
			return ""
		case "textNodes":
			if doc, _ := legadoParseDoc(block); doc != nil {
				if root := legadoBlockRoot(doc); root != nil {
					return strings.TrimSpace(legadoNodeTextNodes(root))
				}
			}
			return ""
		}
		if legadoBareAttrRe.MatchString(trimmed) && !legadoKnownTags[strings.ToLower(trimmed)] {
			if doc, _ := legadoParseDoc(block); doc != nil {
				if root := legadoBlockRoot(doc); root != nil {
					if v, ok := hikerAttr(root, trimmed); ok {
						return v
					}
				}
			}
			return ""
		}
	}
	chain := legadoChain(sel)
	switch attr {
	case "text":
		return strings.TrimSpace(hikerParseSingle(block, chain+"&&Text"))
	case "html":
		return strings.TrimSpace(hikerParseSingle(block, chain+"&&Html"))
	default:
		return strings.TrimSpace(hikerParseSingle(block, chain+"&&"+attr))
	}
}

var legadoBareIdentRe = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`)

var legadoBareAttrRe = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_-]*$`)

func legadoAbs(base, u string) string {
	u = strings.TrimSpace(u)
	if u == "" || strings.HasPrefix(u, "http") {
		return u
	}
	if base == "" {
		return u
	}
	bu, err := url.Parse(base)
	if err != nil {
		return u
	}
	ru, err := url.Parse(u)
	if err != nil {
		return u
	}
	return bu.ResolveReference(ru).String()
}

var legadoTagRe = regexp.MustCompile(`(?i)<br[^>]*>|</p>|</div>`)
var legadoStripRe = regexp.MustCompile(`(?i)<[^>]+>`)

func legadoHTMLToText(outer string) string {
	s := legadoTagRe.ReplaceAllString(outer, "\n")
	s = legadoStripRe.ReplaceAllString(s, "")
	s = html.UnescapeString(s)
	lines := strings.Split(s, "\n")
	out := make([]string, 0, len(lines))
	for _, l := range lines {
		l = strings.TrimSpace(l)
		if l != "" {
			out = append(out, l)
		}
	}
	return strings.Join(out, "\n")
}

func legadoSplitPostSuffix(rawURL string) (string, string, bool) {
	for i := 0; i+1 < len(rawURL); i++ {
		if rawURL[i] != ',' {
			continue
		}
		j := i + 1
		for j < len(rawURL) && (rawURL[j] == ' ' || rawURL[j] == '\t') {
			j++
		}
		if j < len(rawURL) && rawURL[j] == '{' {
			return rawURL[:i], rawURL[i+1:], true
		}
	}
	return rawURL, "", false
}

type legadoJSONSeg struct {
	key       string
	index     int
	hasKey    bool
	hasIndex  bool
	recursive bool
	wildcard  bool
}

func legadoParseJSONPath(rule string) ([]legadoJSONSeg, bool) {
	r := strings.TrimSpace(rule)
	if r == "" || r[0] != '$' {
		return nil, false
	}
	rest := r[1:]
	segs := []legadoJSONSeg{}
	i := 0
	parseBracket := func() (legadoJSONSeg, bool) {
		j := strings.IndexByte(rest[i:], ']')
		if j < 0 {
			return legadoJSONSeg{}, false
		}
		inner := rest[i+1 : i+j]
		if inner == "*" {
			i += j + 1
			return legadoJSONSeg{hasIndex: true, index: -2, wildcard: true}, true
		}
		if inner == "" {
			return legadoJSONSeg{}, false
		}
		for k := 0; k < len(inner); k++ {
			if inner[k] < '0' || inner[k] > '9' {
				return legadoJSONSeg{}, false
			}
		}
		n := 0
		for k := 0; k < len(inner); k++ {
			n = n*10 + int(inner[k]-'0')
		}
		i += j + 1
		return legadoJSONSeg{index: n, hasIndex: true}, true
	}
	for i < len(rest) {
		if rest[i] == '.' {
			recursive := false
			if i+1 < len(rest) && rest[i+1] == '.' {
				recursive = true
				i += 2
			} else {
				i++
			}
			if i >= len(rest) {
				return nil, false
			}
			if rest[i] == '[' {
				seg, ok := parseBracket()
				if !ok {
					return nil, false
				}
				seg.recursive = recursive
				segs = append(segs, seg)
			} else {
				start := i
				for i < len(rest) && rest[i] != '.' && rest[i] != '[' {
					i++
				}
				if start == i {
					return nil, false
				}
				key := rest[start:i]
				if key == "*" {
					segs = append(segs, legadoJSONSeg{wildcard: true, recursive: recursive})
				} else {
					segs = append(segs, legadoJSONSeg{key: key, hasKey: true, recursive: recursive})
				}
			}
			for i < len(rest) && rest[i] == '[' {
				seg, ok := parseBracket()
				if !ok {
					return nil, false
				}
				segs = append(segs, seg)
			}
		} else if rest[i] == '[' {
			seg, ok := parseBracket()
			if !ok {
				return nil, false
			}
			segs = append(segs, seg)
		} else {
			return nil, false
		}
	}
	return segs, true
}

func legadoJSONEval(root interface{}, segs []legadoJSONSeg) []interface{} {
	if len(segs) == 0 {
		return []interface{}{root}
	}
	seg := segs[0]
	rest := segs[1:]
	if seg.recursive {
		var out []interface{}
		out = append(out, legadoJSONEvalStep(root, seg, rest)...)
		switch node := root.(type) {
		case map[string]interface{}:
			for _, v := range node {
				out = append(out, legadoJSONEval(v, segs)...)
			}
		case []interface{}:
			for _, v := range node {
				out = append(out, legadoJSONEval(v, segs)...)
			}
		}
		return out
	}
	return legadoJSONEvalStep(root, seg, rest)
}

func legadoJSONEvalStep(node interface{}, seg legadoJSONSeg, rest []legadoJSONSeg) []interface{} {
	if seg.wildcard {
		var out []interface{}
		switch n := node.(type) {
		case []interface{}:
			for _, v := range n {
				out = append(out, legadoJSONEval(v, rest)...)
			}
		case map[string]interface{}:
			for _, v := range n {
				out = append(out, legadoJSONEval(v, rest)...)
			}
		}
		return out
	}
	if seg.hasKey {
		if m, ok := node.(map[string]interface{}); ok {
			if v, ok := m[seg.key]; ok {
				return legadoJSONEval(v, rest)
			}
		}
		return nil
	}
	if seg.hasIndex {
		if arr, ok := node.([]interface{}); ok {
			if seg.index == -2 {
				var out []interface{}
				for _, v := range arr {
					out = append(out, legadoJSONEval(v, rest)...)
				}
				return out
			}
			if seg.index >= 0 && seg.index < len(arr) {
				return legadoJSONEval(arr[seg.index], rest)
			}
		}
		return nil
	}
	return nil
}

func legadoIsJSONBody(s string) bool {
	t := strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(s), "\uFEFF"))
	return strings.HasPrefix(t, "{") || strings.HasPrefix(t, "[")
}

func legadoJSONValueString(v interface{}) string {
	switch x := v.(type) {
	case nil:
		return ""
	case string:
		return x
	case float64:
		return strconv.FormatFloat(x, 'f', -1, 64)
	case bool:
		if x {
			return "true"
		}
		return "false"
	case []interface{}:
		parts := make([]string, 0, len(x))
		for _, el := range x {
			s, ok := el.(string)
			if !ok {
				return ""
			}
			parts = append(parts, s)
		}
		return strings.Join(parts, "\n")
	default:
		return ""
	}
}

func legadoJSONFieldAny(block, rule string) string {
	for _, alt := range strings.Split(rule, "||") {
		alt = strings.TrimSpace(alt)
		segs, ok := legadoParseJSONPath(alt)
		if !ok {
			continue
		}
		cleaned := strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(block), "\uFEFF"))
		var root interface{}
		if err := json.Unmarshal([]byte(cleaned), &root); err != nil {
			return ""
		}
		nodes := legadoJSONEval(root, segs)
		if len(nodes) > 0 {
			if v := legadoJSONValueString(nodes[0]); v != "" {
				return v
			}
		}
	}
	return ""
}

func legadoJSONListBlocks(body, rule string) []string {
	cleaned := strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(body), "\uFEFF"))
	var root interface{}
	if err := json.Unmarshal([]byte(cleaned), &root); err != nil {
		return nil
	}
	for _, alt := range strings.Split(rule, "||") {
		alt = strings.TrimSpace(alt)
		segs, ok := legadoParseJSONPath(alt)
		if !ok {
			continue
		}
		nodes := legadoJSONEval(root, segs)
		if len(nodes) == 0 {
			continue
		}
		blocks := []string{}
		for _, n := range nodes {
			if arr, ok := n.([]interface{}); ok {
				for _, el := range arr {
					b, err := json.Marshal(el)
					if err != nil {
						continue
					}
					blocks = append(blocks, string(b))
				}
			} else {
				b, err := json.Marshal(n)
				if err != nil {
					continue
				}
				blocks = append(blocks, string(b))
			}
		}
		if len(blocks) > 0 {
			return blocks
		}
	}
	return nil
}

func legadoURLOptions(suffix string) (string, string, map[string]string, string) {
	method := "GET"
	body := ""
	headers := map[string]string{}
	charset := ""
	var opts map[string]interface{}
	if json.Unmarshal([]byte(suffix), &opts) == nil {
		if m, ok := opts["method"].(string); ok && m != "" {
			method = strings.ToUpper(m)
		}
		if b, ok := opts["body"].(string); ok {
			body = b
		}
		if c, ok := opts["charset"].(string); ok {
			charset = c
		}
		if h, ok := opts["headers"].(map[string]interface{}); ok {
			for k, v := range h {
				if vs, ok := v.(string); ok {
					headers[k] = vs
				}
			}
		}
	}
	return method, body, headers, charset
}

func legadoEscapeKey(keyword, charset string) string {
	switch strings.ToLower(strings.TrimSpace(charset)) {
	case "gbk", "gb18030", "gb2312":
		encoded, _, err := transform.String(simplifiedchinese.GBK.NewEncoder(), keyword)
		if err != nil {
			return url.QueryEscape(keyword)
		}
		var out strings.Builder
		for i := 0; i < len(encoded); i++ {
			c := encoded[i]
			if c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '-' || c == '_' || c == '.' || c == '~' {
				out.WriteByte(c)
			} else {
				fmt.Fprintf(&out, "%%%02X", c)
			}
		}
		return out.String()
	default:
		return url.QueryEscape(keyword)
	}
}

func legadoSearch(src LegadoSource, keyword string, page int) (interface{}, error) {
	if src.SearchURL == "" || src.BookList == "" {
		return nil, fmt.Errorf("legado source missing searchUrl or bookList rule")
	}
	rawURL := strings.TrimRight(src.SearchURL, " \t")
	ctx := newLegadoJSCtx(src.URL)
	ctx.setSource(src)
	ctx.key = keyword
	ctx.page = page
	trimmedSearch := strings.TrimSpace(rawURL)
	if strings.HasPrefix(trimmedSearch, "@js:") || strings.HasPrefix(trimmedSearch, "<js>") {
		script := strings.TrimSpace(strings.TrimPrefix(trimmedSearch, "@js:"))
		if strings.HasPrefix(trimmedSearch, "<js>") {
			script = strings.TrimSpace(trimmedSearch[4:])
			script = strings.TrimSuffix(script, "</js>")
		}
		rt := ctx.runtime()
		v, err := ctx.evalJSCur(script, "")
		if err != nil {
			return nil, err
		}
		res := legadoJSValueString(rt, v)
		if res == "" {
			return nil, fmt.Errorf("legado search js empty")
		}
		if strings.HasPrefix(res, "http") {
			u2 := res
			method2 := "GET"
			body2 := ""
			headers2 := map[string]string{}
			if base, suffix, ok := legadoSplitPostSuffix(u2); ok {
				method2, body2, headers2, _ = legadoURLOptions(suffix)
				u2 = base
			}
			u2 = legadoAbs(src.URL, u2)
			pageBody, err := legadoRequest(u2, method2, body2, headers2)
			if err != nil {
				return nil, err
			}
			return legadoSearchExtract(src, ctx, pageBody)
		}
		return legadoSearchExtract(src, ctx, res)
	}
	method := "GET"
	body := ""
	headers := map[string]string{}
	charset := ""
	if base, suffix, ok := legadoSplitPostSuffix(rawURL); ok {
		method, body, headers, charset = legadoURLOptions(suffix)
		rawURL = base
	}
	keyEsc := legadoEscapeKey(keyword, charset)
	sub := func(v string) string {
		v = strings.ReplaceAll(v, "{{key}}", keyEsc)
		v = strings.ReplaceAll(v, "{{page}}", fmt.Sprint(page))
		v = strings.ReplaceAll(v, "{key}", keyEsc)
		v = strings.ReplaceAll(v, "{page}", fmt.Sprint(page))
		return v
	}
	u := legadoAbs(src.URL, sub(rawURL))
	body = sub(body)
	for k := range headers {
		headers[k] = sub(headers[k])
	}
	pageBody, err := legadoRequest(u, method, body, headers)
	if err != nil {
		return nil, err
	}
	return legadoSearchExtract(src, ctx, pageBody)
}

func legadoSearchExtract(src LegadoSource, ctx *legadoJSCtx, pageBody string) (interface{}, error) {
	blocks := ctx.evalList(pageBody, src.BookList)
	out := []map[string]string{}
	for _, b := range blocks {
		ctx.setBlock(b)
		title := ctx.evalScalar(b, src.NameRule)
		bookURL := legadoAbs(src.URL, ctx.evalScalar(b, src.BookURLRule))
		if title == "" && bookURL == "" {
			continue
		}
		out = append(out, map[string]string{
			"title":  title,
			"author": ctx.evalScalar(b, src.AuthorRule),
			"cover":  legadoAbs(src.URL, ctx.evalScalar(b, src.CoverRule)),
			"url":    bookURL,
			"intro":  ctx.evalScalar(b, src.IntroRule),
		})
	}
	return out, nil
}

func legadoSplitSel(rule string) string {
	sel, _ := legadoSplitAttr(rule)
	return sel
}

func legadoToc(src LegadoSource, bookURL string) (interface{}, error) {
	if src.TocList == "" {
		return nil, fmt.Errorf("legado source missing tocList rule")
	}
	ctx := newLegadoJSCtx(src.URL)
	ctx.setSource(src)
	ctx.bookURL = bookURL
	pageBody, err := legadoFetch(bookURL)
	if err != nil {
		return nil, err
	}
	ctx.setBlock(pageBody)
	orderedKeys := []string{"name", "author", "coverUrl", "intro", "tocUrl"}
	seenKeys := map[string]bool{}
	for _, k := range orderedKeys {
		seenKeys[k] = true
	}
	restKeys := []string{}
	for k := range src.BookInfo {
		if !seenKeys[k] {
			restKeys = append(restKeys, k)
		}
	}
	sort.Strings(restKeys)
	orderedKeys = append(orderedKeys, restKeys...)
	tocURLVal := ""
	for _, k := range orderedKeys {
		r, ok := src.BookInfo[k]
		if !ok || strings.TrimSpace(r) == "" {
			continue
		}
		v := ctx.evalScalar(pageBody, r)
		if k == "tocUrl" {
			tocURLVal = v
		}
	}
	if tocURLVal != "" {
		if tocURL := legadoAbs(bookURL, tocURLVal); tocURL != "" && tocURL != bookURL {
			if b2, err2 := legadoFetch(tocURL); err2 == nil {
				pageBody = b2
				bookURL = tocURL
			}
		}
	}
	blocks := ctx.evalList(pageBody, src.TocList)
	blockBases := []string{}
	for range blocks {
		blockBases = append(blockBases, bookURL)
	}
	if src.NextTocURL != "" {
		seenToc := map[string]bool{bookURL: true}
		ctx.setBlock(pageBody)
		next := legadoAbs(bookURL, ctx.evalScalar(pageBody, src.NextTocURL))
		for i := 0; i < 5 && next != "" && !seenToc[next]; i++ {
			seenToc[next] = true
			b2, err := legadoFetch(next)
			if err != nil {
				break
			}
			more := ctx.evalList(b2, src.TocList)
			blocks = append(blocks, more...)
			for range more {
				blockBases = append(blockBases, next)
			}
			pageBody = b2
			ctx.setBlock(pageBody)
			next = legadoAbs(next, ctx.evalScalar(pageBody, src.NextTocURL))
		}
	}
	out := []map[string]string{}
	for bi, b := range blocks {
		ctx.setBlock(b)
		title := ctx.evalScalar(b, src.ChapterName)
		u := legadoAbs(blockBases[bi], ctx.evalScalar(b, src.ChapterURL))
		if title == "" && u == "" {
			continue
		}
		out = append(out, map[string]string{"title": title, "url": u})
	}
	return out, nil
}

func legadoContent(src LegadoSource, chapterURL string) (interface{}, error) {
	if src.ContentRule == "" {
		return nil, fmt.Errorf("legado source missing content rule")
	}
	ctx := newLegadoJSCtx(src.URL)
	ctx.setSource(src)
	contentOf := func(body, pageURL string) (string, []legadoImage, bool) {
		ctx.setBlock(body)
		if legadoHasMarkers(src.ContentRule) {
			r := ctx.evalScalar(body, src.ContentRule)
			if r == "" {
				return "", nil, false
			}
			images, text := legadoExtractImages(r, pageURL)
			if len(images) > 0 {
				return text, images, true
			}
			return legadoHTMLToText(r), nil, true
		}
		if strings.HasPrefix(strings.TrimSpace(src.ContentRule), "$") && legadoIsJSONBody(body) {
			outer := legadoField(body, src.ContentRule)
			if outer == "" {
				return "", nil, false
			}
			images, text := legadoExtractImages(outer, pageURL)
			if len(images) > 0 {
				return text, images, true
			}
			return outer, nil, true
		}
		sel, _ := legadoSplitAttr(src.ContentRule)
		if sel == "" {
			return "", nil, false
		}
		outer := ""
		if nodes, value, ok := legadoEvalDialect(body, src.ContentRule, false); ok && len(nodes) > 0 {
			outer = legadoScalarFromNodes(nodes, value)
		}
		if outer == "" {
			outer = hikerParseSingle(body, legadoChain(sel)+"&&Html")
		}
		if outer == "" {
			return "", nil, false
		}
		images, text := legadoExtractImages(outer, pageURL)
		if len(images) > 0 {
			return text, images, true
		}
		return legadoHTMLToText(outer), nil, true
	}
	pageBody, err := legadoFetch(chapterURL)
	if err != nil {
		return nil, err
	}
	finishContent := func(text string, images []legadoImage, pageURL string) (string, []legadoImage) {
		if len(images) > 0 {
			return text, images
		}
		imgs, rest := legadoExtractBareImageLines(text, pageURL, src.ImageStyle == "FULL")
		if len(imgs) > 0 {
			return rest, imgs
		}
		return text, nil
	}
	text, images, ok := contentOf(pageBody, chapterURL)
	if !ok {
		return nil, fmt.Errorf("legado content empty")
	}
	text, images = finishContent(text, images, chapterURL)
	seen := map[string]bool{chapterURL: true}
	next := ""
	if src.NextContent != "" {
		ctx.setBlock(pageBody)
		next = legadoAbs(chapterURL, ctx.evalScalar(pageBody, src.NextContent))
	}
	for i := 0; i < 5 && next != "" && !seen[next]; i++ {
		seen[next] = true
		b2, err := legadoFetch(next)
		if err != nil {
			break
		}
		t2, imgs2, ok2 := contentOf(b2, next)
		if !ok2 {
			break
		}
		t2, imgs2 = finishContent(t2, imgs2, next)
		if t2 != "" {
			text += "\n" + t2
		}
		images = append(images, imgs2...)
		pageBody = b2
		ctx.setBlock(pageBody)
		next = legadoAbs(next, ctx.evalScalar(pageBody, src.NextContent))
	}
	result := map[string]string{"content": text}
	if len(images) > 0 {
		if b, err := json.Marshal(images); err == nil {
			result["images"] = string(b)
		}
	}
	return result, nil
}

func legadoExploreCategories(src LegadoSource) interface{} {
	out := []map[string]string{}
	trimmed := strings.TrimSpace(src.ExploreURL)
	if strings.HasPrefix(trimmed, "[") {
		var arr []map[string]interface{}
		if json.Unmarshal([]byte(trimmed), &arr) == nil {
			for _, item := range arr {
				title, _ := item["title"].(string)
				url, _ := item["url"].(string)
				if title == "" && url == "" {
					continue
				}
				out = append(out, map[string]string{"title": title, "url": url})
			}
			return out
		}
	}
	for _, line := range strings.Split(src.ExploreURL, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		if i := strings.Index(line, "::"); i >= 0 {
			out = append(out, map[string]string{"title": strings.TrimSpace(line[:i]), "url": strings.TrimSpace(line[i+2:])})
		} else {
			out = append(out, map[string]string{"title": line, "url": line})
		}
	}
	return out
}

func legadoExplore(src LegadoSource, urlTmpl string, page int) (interface{}, error) {
	if src.ExploreURL == "" || src.ExploreBookList == "" {
		return nil, fmt.Errorf("legado source missing exploreUrl or explore bookList rule")
	}
	ctx := newLegadoJSCtx(src.URL)
	ctx.setSource(src)
	ctx.page = page
	u := legadoAbs(src.URL, ctx.expandURLTemplate(urlTmpl))
	if u == "" {
		return nil, fmt.Errorf("legado explore url empty")
	}
	pageBody, err := legadoFetch(u)
	if err != nil {
		return nil, err
	}
	blocks := ctx.evalList(pageBody, src.ExploreBookList)
	out := []map[string]string{}
	for _, b := range blocks {
		ctx.setBlock(b)
		title := ctx.evalScalar(b, src.ExploreName)
		bookURL := legadoAbs(src.URL, ctx.evalScalar(b, src.ExploreBookURL))
		if title == "" && bookURL == "" {
			continue
		}
		out = append(out, map[string]string{
			"title":  title,
			"author": ctx.evalScalar(b, src.ExploreAuthor),
			"cover":  legadoAbs(src.URL, ctx.evalScalar(b, src.ExploreCover)),
			"url":    bookURL,
			"intro":  ctx.evalScalar(b, src.ExploreIntro),
		})
	}
	return out, nil
}

type legadoCheckField struct {
	Field  string `json:"field"`
	Rule   string `json:"rule"`
	Reason string `json:"reason"`
}

type legadoCheckResult struct {
	Supported         bool               `json:"supported"`
	UnsupportedFields []legadoCheckField `json:"unsupportedFields"`
}

func legadoRuleUnsupportedReason(rule string) string {
	t := strings.TrimSpace(rule)
	if strings.HasPrefix(t, "$") {
		if _, ok := legadoParseJSONPath(t); ok {
			return ""
		}
		return "jsonpath"
	}
	if strings.Contains(t, ":nth-") && !strings.Contains(t, ":nth-child(") && !strings.Contains(t, ":nth-of-type(") {
		return "nth"
	}
	return ""
}

func legadoCheck(src LegadoSource) legadoCheckResult {
	fields := []struct {
		name string
		rule string
	}{
		{"bookList", src.BookList},
		{"name", src.NameRule},
		{"author", src.AuthorRule},
		{"coverUrl", src.CoverRule},
		{"bookUrl", src.BookURLRule},
		{"intro", src.IntroRule},
	}
	out := legadoCheckResult{Supported: true, UnsupportedFields: []legadoCheckField{}}
	for _, f := range fields {
		reason := ""
		hasSupported := false
		for _, alt := range strings.Split(f.rule, "||") {
			alt = strings.TrimSpace(alt)
			if alt == "" {
				continue
			}
			if r := legadoRuleUnsupportedReason(alt); r != "" {
				if reason == "" {
					reason = r
				}
			} else {
				hasSupported = true
			}
		}
		if reason != "" && !hasSupported {
			out.Supported = false
			out.UnsupportedFields = append(out.UnsupportedFields, legadoCheckField{Field: f.name, Rule: f.rule, Reason: reason})
		}
	}
	return out
}

func LegadoRunJSON(sourceJSON, action, input string) (string, error) {
	src, err := legadoParseSource([]byte(sourceJSON))
	if err != nil {
		return "", err
	}
	var result interface{}
	switch action {
	case "check":
		result = legadoCheck(src)
	case "search":
		keyword := input
		page := 1
		if i := strings.LastIndex(input, "\x01"); i >= 0 {
			keyword = input[:i]
			fmt.Sscan(input[i+1:], &page)
			if page < 1 {
				page = 1
			}
		}
		result, err = legadoSearch(src, keyword, page)
	case "toc":
		result, err = legadoToc(src, input)
	case "content":
		result, err = legadoContent(src, input)
	case "exploreCategories":
		result = legadoExploreCategories(src)
	case "explore":
		urlTmpl := input
		page := 1
		if i := strings.LastIndex(input, "\x01"); i >= 0 {
			urlTmpl = input[:i]
			fmt.Sscan(input[i+1:], &page)
			if page < 1 {
				page = 1
			}
		}
		result, err = legadoExplore(src, urlTmpl, page)
	default:
		return "", fmt.Errorf("unknown legado action %s", action)
	}
	if err != nil {
		return "", err
	}
	b, err := json.Marshal(result)
	if err != nil {
		return "", err
	}
	return string(b), nil
}
