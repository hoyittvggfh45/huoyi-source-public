package core

import (
	"encoding/json"
	"fmt"
	"html"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"
)

type LegadoSource struct {
	Name        string `json:"bookSourceName"`
	URL         string `json:"bookSourceUrl"`
	SearchURL   string `json:"searchUrl"`
	BookList    string `json:"bookList"`
	NameRule    string `json:"name"`
	AuthorRule  string `json:"author"`
	CoverRule   string `json:"coverUrl"`
	BookURLRule string `json:"bookUrl"`
	IntroRule   string `json:"intro"`
	TocList     string `json:"tocList"`
	TocURL      string `json:"tocUrl"`
	ChapterName string `json:"chapterName"`
	ChapterURL  string `json:"chapterUrl"`
	ContentRule string `json:"content"`
	NextContent string `json:"nextContentUrl"`
}

type legadoRaw struct {
	Name         string `json:"bookSourceName"`
	URL          string `json:"bookSourceUrl"`
	SearchURL    string `json:"searchUrl"`
	RuleSearch   map[string]string `json:"ruleSearch"`
	RuleBookInfo map[string]string `json:"ruleBookInfo"`
	RuleToc      map[string]string `json:"ruleToc"`
	RuleContent  map[string]string `json:"ruleContent"`
}

var legadoHTTP = &http.Client{Timeout: 20 * time.Second}

func legadoParseSource(data []byte) (LegadoSource, error) {
	var raw legadoRaw
	if err := json.Unmarshal(data, &raw); err != nil {
		return LegadoSource{}, err
	}
	s := LegadoSource{Name: raw.Name, URL: raw.URL, SearchURL: raw.SearchURL}
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
		s.ChapterName = raw.RuleToc["chapterName"]
		s.ChapterURL = raw.RuleToc["chapterUrl"]
	}
	if raw.RuleContent != nil {
		s.ContentRule = raw.RuleContent["content"]
		s.NextContent = raw.RuleContent["nextContentUrl"]
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
	return string(b), nil
}

func legadoSplitAttr(rule string) (string, string) {
	rule = strings.TrimSpace(rule)
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
	if strings.Contains(rule, "||") {
		return legadoTryRules(block, strings.Split(rule, "||"), func(r string) string {
			return legadoField(block, r)
		})
	}
	if strings.HasPrefix(strings.TrimSpace(rule), "@") {
		attr := strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(rule), "@"))
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

func legadoSearch(src LegadoSource, keyword string, page int) (interface{}, error) {
	if src.SearchURL == "" || src.BookList == "" {
		return nil, fmt.Errorf("legado source missing searchUrl or bookList rule")
	}
	rawURL := src.SearchURL
	method := "GET"
	body := ""
	headers := map[string]string{}
	if i := strings.Index(rawURL, ",{"); i >= 0 {
		var opts map[string]interface{}
		if json.Unmarshal([]byte(rawURL[i+1:]), &opts) == nil {
			if m, ok := opts["method"].(string); ok && m != "" {
				method = strings.ToUpper(m)
			}
			if b, ok := opts["body"].(string); ok {
				body = b
			}
			if h, ok := opts["headers"].(map[string]interface{}); ok {
				for k, v := range h {
					if vs, ok := v.(string); ok {
						headers[k] = vs
					}
				}
			}
		}
		rawURL = rawURL[:i]
	}
	sub := func(v string) string {
		v = strings.ReplaceAll(v, "{{key}}", url.QueryEscape(keyword))
		v = strings.ReplaceAll(v, "{{page}}", fmt.Sprint(page))
		v = strings.ReplaceAll(v, "{key}", url.QueryEscape(keyword))
		v = strings.ReplaceAll(v, "{page}", fmt.Sprint(page))
		return v
	}
	u := sub(rawURL)
	body = sub(body)
	for k := range headers {
		headers[k] = sub(headers[k])
	}
	pageBody, err := legadoRequest(u, method, body, headers)
	if err != nil {
		return nil, err
	}
	blocks := []string{}
	for _, r := range strings.Split(src.BookList, "||") {
		blocks = hikerParseArray(pageBody, legadoChain(legadoSplitSel(strings.TrimSpace(r))))
		if len(blocks) > 0 {
			break
		}
	}
	out := []map[string]string{}
	for _, b := range blocks {
		title := legadoField(b, src.NameRule)
		bookURL := legadoAbs(src.URL, legadoField(b, src.BookURLRule))
		if title == "" && bookURL == "" {
			continue
		}
		out = append(out, map[string]string{
			"title":  title,
			"author": legadoField(b, src.AuthorRule),
			"cover":  legadoAbs(src.URL, legadoField(b, src.CoverRule)),
			"url":    bookURL,
			"intro":  legadoField(b, src.IntroRule),
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
	pageBody, err := legadoFetch(bookURL)
	if err != nil {
		return nil, err
	}
	if src.TocURL != "" {
		if tocURL := legadoAbs(bookURL, legadoField(pageBody, src.TocURL)); tocURL != "" && tocURL != bookURL {
			if b2, err2 := legadoFetch(tocURL); err2 == nil {
				pageBody = b2
				bookURL = tocURL
			}
		}
	}
	blocks := []string{}
	for _, r := range strings.Split(src.TocList, "||") {
		blocks = hikerParseArray(pageBody, legadoChain(legadoSplitSel(strings.TrimSpace(r))))
		if len(blocks) > 0 {
			break
		}
	}
	out := []map[string]string{}
	for _, b := range blocks {
		title := legadoField(b, src.ChapterName)
		u := legadoAbs(bookURL, legadoField(b, src.ChapterURL))
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
	pageBody, err := legadoFetch(chapterURL)
	if err != nil {
		return nil, err
	}
	sel, attr := legadoSplitAttr(src.ContentRule)
	if sel == "" {
		return nil, fmt.Errorf("legado content rule unsupported")
	}
	chain := legadoChain(sel)
	var outer string
	if attr == "text" {
		outer = hikerParseSingle(pageBody, chain+"&&Html")
	} else {
		outer = hikerParseSingle(pageBody, chain+"&&Html")
	}
	if outer == "" {
		return nil, fmt.Errorf("legado content empty")
	}
	text := legadoHTMLToText(outer)
	seen := map[string]bool{chapterURL: true}
	next := ""
	if src.NextContent != "" {
		next = legadoAbs(chapterURL, legadoField(pageBody, src.NextContent))
	}
	for i := 0; i < 5 && next != "" && !seen[next]; i++ {
		seen[next] = true
		b2, err := legadoFetch(next)
		if err != nil {
			break
		}
		o2 := hikerParseSingle(b2, chain+"&&Html")
		if o2 == "" {
			break
		}
		text += "\n" + legadoHTMLToText(o2)
		pageBody = b2
		next = legadoAbs(next, legadoField(pageBody, src.NextContent))
	}
	return map[string]string{"content": text}, nil
}

func LegadoRunJSON(sourceJSON, action, input string) (string, error) {
	src, err := legadoParseSource([]byte(sourceJSON))
	if err != nil {
		return "", err
	}
	var result interface{}
	switch action {
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
