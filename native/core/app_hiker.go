package core

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/dop251/goja"
	"golang.org/x/net/html"
)

type HikerRule struct {
	Title           string `json:"title"`
	Type            string `json:"type"`
	URL             string `json:"url"`
	ColType         string `json:"col_type"`
	FindRule        string `json:"find_rule"`
	SearchFind      string `json:"searchFind"`
	DetailFindRule  string `json:"detail_find_rule"`
	SearchURL       string `json:"search_url"`
	UA              string `json:"ua"`
	PreRule         string `json:"preRule"`
}

type HikerEngine struct {
	rt       *goja.Runtime
	result   interface{}
	hasResult bool
	lastHTML string
	vars     map[string]interface{}
	config   map[string]interface{}
	ua       string
	client   *http.Client
}

func NewHikerEngine(ua string) *HikerEngine {
	e := &HikerEngine{vars: map[string]interface{}{}, config: map[string]interface{}{}, ua: ua, client: &http.Client{Timeout: 20 * time.Second}}
	rt := goja.New()
	e.rt = rt
	rt.Set("config", e.config)
	rt.Set("initConfig", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) > 0 {
			if m, ok := call.Arguments[0].Export().(map[string]interface{}); ok {
				e.config = m
				_ = rt.Set("config", e.config)
			}
		}
		return goja.Undefined()
	})
	rt.Set("fetch", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) == 0 {
			return goja.Undefined()
		}
		u := call.Arguments[0].String()
		if strings.HasPrefix(u, "hiker://") {
			if u == "hiker://page/lazy" || strings.HasPrefix(u, "hiker://page/lazy") {
				return rt.ToValue(`{"rule":""}`)
			}
			return goja.Undefined()
		}
		onlyHeaders := false
		if len(call.Arguments) >= 2 {
			if opts, ok := call.Arguments[1].Export().(map[string]interface{}); ok {
				if v, ok2 := opts["onlyHeaders"]; ok2 {
					if b, ok3 := v.(bool); ok3 && b {
						onlyHeaders = true
					}
				}
			}
		}
		body, finalURL, err := e.httpRequest(u)
		if err != nil {
			return goja.Undefined()
		}
		if onlyHeaders {
			return rt.ToValue(`{"url":"` + finalURL + `"}`)
		}
		e.lastHTML = body
		return rt.ToValue(body)
	})
	rt.Set("request", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) == 0 {
			return goja.Undefined()
		}
		u := call.Arguments[0].String()
		if strings.HasPrefix(u, "hiker://") {
			if u == "hiker://page/lazy" || strings.HasPrefix(u, "hiker://page/lazy") {
				return rt.ToValue(`{"rule":""}`)
			}
			return goja.Undefined()
		}
		body, _, err := e.httpRequest(u)
		if err != nil {
			return goja.Undefined()
		}
		e.lastHTML = body
		return rt.ToValue(body)
	})
	rt.Set("getResCode", func(call goja.FunctionCall) goja.Value {
		return rt.ToValue(e.lastHTML)
	})
	rt.Set("setResult", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) > 0 {
			e.result = call.Arguments[0].Export()
			e.hasResult = true
		}
		return goja.Undefined()
	})
	rt.Set("getVar", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) == 0 {
			return goja.Undefined()
		}
		v, ok := e.vars[call.Arguments[0].String()]
		if !ok {
			if len(call.Arguments) >= 2 {
				return call.Arguments[1]
			}
			return goja.Undefined()
		}
		return rt.ToValue(v)
	})
	rt.Set("getMyVar", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) == 0 {
			return goja.Undefined()
		}
		v, ok := e.vars[call.Arguments[0].String()]
		if !ok {
			if len(call.Arguments) >= 2 {
				return call.Arguments[1]
			}
			return goja.Undefined()
		}
		return rt.ToValue(v)
	})
	rt.Set("putMyVar", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) >= 2 {
			e.vars[call.Arguments[0].String()] = call.Arguments[1].Export()
		}
		return goja.Undefined()
	})
	rt.Set("putVar", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) >= 2 {
			e.vars[call.Arguments[0].String()] = call.Arguments[1].Export()
		}
		return goja.Undefined()
	})
	rt.Set("parseDomForHtml", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) < 2 {
			return goja.Undefined()
		}
		out := hikerParseSingle(call.Arguments[0].String(), call.Arguments[1].String())
		return rt.ToValue(out)
	})
	rt.Set("parseDomForArray", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) < 2 {
			return rt.ToValue([]string{})
		}
		out := hikerParseArray(call.Arguments[0].String(), call.Arguments[1].String())
		return rt.ToValue(out)
	})
	rt.Set("parseDom", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) < 2 {
			return goja.Undefined()
		}
		out := hikerParseSingle(call.Arguments[0].String(), call.Arguments[1].String())
		return rt.ToValue(out)
	})
	rt.Set("setItem", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) >= 2 {
			e.vars[call.Arguments[0].String()] = call.Arguments[1].Export()
		}
		return goja.Undefined()
	})
	rt.Set("getItem", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) == 0 {
			return goja.Undefined()
		}
		v, ok := e.vars[call.Arguments[0].String()]
		if !ok {
			if len(call.Arguments) >= 2 {
				return call.Arguments[1]
			}
			return goja.Undefined()
		}
		return rt.ToValue(v)
	})
	rt.Set("setHomeResult", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) > 0 {
			e.result = call.Arguments[0].Export()
			e.hasResult = true
		}
		return goja.Undefined()
	})
	rt.Set("pdfa", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) < 2 {
			return rt.ToValue([]string{})
		}
		return rt.ToValue(hikerParseArray(call.Arguments[0].String(), call.Arguments[1].String()))
	})
	rt.Set("pdfh", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) < 2 {
			return goja.Undefined()
		}
		return rt.ToValue(hikerParseSingle(call.Arguments[0].String(), call.Arguments[1].String()))
	})
	rt.Set("pd", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) < 2 {
			return goja.Undefined()
		}
		return rt.ToValue(hikerParseSingle(call.Arguments[0].String(), call.Arguments[1].String()))
	})
	rt.Set("confirm", func(call goja.FunctionCall) goja.Value { return goja.Undefined() })
	rt.Set("base64Decode", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) == 0 {
			return goja.Undefined()
		}
		b, err := base64.StdEncoding.DecodeString(call.Arguments[0].String())
		if err != nil {
			return goja.Undefined()
		}
		return rt.ToValue(string(b))
	})
	rt.Set("base64Encode", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) == 0 {
			return goja.Undefined()
		}
		return rt.ToValue(base64.StdEncoding.EncodeToString([]byte(call.Arguments[0].String())))
	})
	rt.Set("toast", func(call goja.FunctionCall) goja.Value { return goja.Undefined() })
	rt.Set("log", func(call goja.FunctionCall) goja.Value { return goja.Undefined() })
	rt.Set("st", func(call goja.FunctionCall) goja.Value { return goja.Undefined() })
	_, _ = rt.RunString(`
		String.prototype.myReplace = function(a, b) { return this.split(a).join(b); };
		if (!String.prototype.replaceAll) { String.prototype.replaceAll = function(a, b) { return this.split(a).join(b); }; }
		var console = { log: function(){}, warn: function(){}, error: function(){} };
		var $ = function(s) { return { lazyRule: function(f) { return ''; }, toString: function(f) { return ''; } }; };
		$.require = function(name) { return { baseParse: function(){ return []; }, searchParse: function(){ return []; }, detailParse: function(){ return []; }, parse: function(){ return []; } }; };
		$.toString = function(f) { return ''; };
	`)
	return e
}

func (e *HikerEngine) httpGet(u string) (string, error) {
	body, _, err := e.httpRequest(u)
	return body, err
}

func (e *HikerEngine) httpRequest(u string) (string, string, error) {
	req, err := http.NewRequest("GET", u, nil)
	if err != nil {
		return "", "", err
	}
	if e.ua != "" {
		req.Header.Set("User-Agent", e.ua)
	} else {
		req.Header.Set("User-Agent", "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36")
	}
	resp, err := e.client.Do(req)
	if err != nil {
		return "", "", err
	}
	defer resp.Body.Close()
	finalURL := u
	if resp.Request != nil && resp.Request.URL != nil {
		finalURL = resp.Request.URL.String()
	}
	b, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", finalURL, err
	}
	return string(b), finalURL, nil
}

func hikerCleanListURL(u string) string {
	if i := strings.Index(u, "["); i >= 0 {
		u = u[:i]
	}
	u = strings.ReplaceAll(u, "fypage", "1")
	return u
}

func (e *HikerEngine) Run(rule HikerRule, action, input string) (interface{}, error) {
	e.result = nil
	e.hasResult = false
	_ = e.rt.Set("MY_RULE", map[string]interface{}{
		"title": rule.Title, "type": rule.Type, "url": rule.URL,
		"col_type": rule.ColType, "find_rule": rule.FindRule,
		"searchFind": rule.SearchFind, "detail_find_rule": rule.DetailFindRule,
		"search_url": rule.SearchURL, "ua": rule.UA,
	})
	myURL := rule.URL
	myPage := 1
	var script string
	switch action {
	case "search":
		script = rule.SearchFind
		if rule.SearchURL != "" {
			myURL = strings.ReplaceAll(rule.SearchURL, "**", input)
			myURL = strings.ReplaceAll(myURL, "fypage", "1")
		}
		if strings.HasPrefix(myURL, "http") {
			if body, err := e.httpGet(myURL); err == nil {
				e.lastHTML = body
			}
		}
	case "detail":
		script = rule.DetailFindRule
		if input != "" {
			myURL = hikerCleanListURL(input)
			if strings.HasPrefix(myURL, "http") {
				if body, err := e.httpGet(myURL); err == nil {
					e.lastHTML = body
				}
			}
		}
	case "list":
		script = rule.FindRule
		if input != "" {
			myURL = hikerCleanListURL(input)
			if strings.HasPrefix(myURL, "http") {
				if body, err := e.httpGet(myURL); err == nil {
					e.lastHTML = body
				}
			}
		}
	default:
		script = rule.FindRule
		if rule.URL != "" && strings.HasPrefix(rule.URL, "http") {
			if body, err := e.httpGet(rule.URL); err == nil {
				e.lastHTML = body
			}
		}
	}
	_ = e.rt.Set("MY_URL", myURL)
	_ = e.rt.Set("MY_PAGE", myPage)
	_ = e.rt.Set("input", input)
	if strings.TrimSpace(rule.PreRule) != "" {
		if _, err := e.rt.RunString(strings.TrimSpace(rule.PreRule)); err != nil {
			return nil, err
		}
		_ = e.rt.Set("MY_URL", myURL)
		_ = e.rt.Set("MY_PAGE", myPage)
		_ = e.rt.Set("input", input)
	}
	script = strings.TrimSpace(script)
	if script == "" {
		return nil, errors.New("empty rule")
	}
	if !strings.HasPrefix(script, "js:") {
		return hikerRunListRule(e, script), nil
	}
	script = strings.TrimSpace(strings.TrimPrefix(script, "js:"))
	v, err := e.rt.RunString(script)
	if err != nil {
		return nil, err
	}
	if e.hasResult {
		return e.result, nil
	}
	if v != nil && !goja.IsUndefined(v) && !goja.IsNull(v) {
		return v.Export(), nil
	}
	return nil, errors.New("no result")
}

func hikerRunListRule(e *HikerEngine, script string) interface{} {
	parts := strings.Split(script, ";")
	if len(parts) < 2 {
		return []interface{}{}
	}
	htmlText := e.lastHTML
	if htmlText == "" {
		return []interface{}{}
	}
	containers := hikerParseArray(htmlText, strings.TrimSpace(parts[0]))
	out := []interface{}{}
	for _, c := range containers {
		m := map[string]interface{}{}
		for i, f := range parts[1:] {
			f = strings.TrimSpace(f)
			if f == "" || f == "*" {
				continue
			}
			val := hikerParseSingle(c, f)
			m["field"+itoa(i)] = val
			switch i {
			case 0:
				m["title"] = val
			case 1:
				m["pic"] = val
			case 2:
				m["desc"] = val
			default:
				m["url"] = val
			}
		}
		if u, ok := m["url"]; !ok || u == "" {
			if v, ok2 := m["field"+itoa(len(parts)-2)]; ok2 {
				m["url"] = v
			}
		}
		out = append(out, m)
	}
	return out
}

func itoa(i int) string {
	if i == 0 {
		return "0"
	}
	s := ""
	for i > 0 {
		s = string(rune('0'+i%10)) + s
		i /= 10
	}
	return s
}

func hikerParseSingle(htmlText, rule string) string {
	nodes := hikerSelectChain(htmlText, rule)
	if len(nodes) == 0 {
		return ""
	}
	parts := strings.Split(rule, "&&")
	last := strings.TrimSpace(parts[len(parts)-1])
	switch last {
	case "Text":
		return hikerNodeText(nodes[0])
	case "Html":
		return hikerOuterHTML(nodes[0])
	default:
		if hikerIsAttr(last) {
			if v, ok := hikerAttr(nodes[0], last); ok {
				return v
			}
			return ""
		}
		if hikerIsTag(last) {
			return hikerOuterHTML(nodes[0])
		}
		if v, ok := hikerAttr(nodes[0], last); ok {
			return v
		}
		return hikerNodeText(nodes[0])
	}
}

func hikerIsAttr(s string) bool {
	switch s {
	case "title", "href", "src", "data-original", "realsrc", "alt", "data-src", "value", "content", "id", "class", "name", "data-url", "data-href", "data-title", "data-id":
		return true
	}
	return false
}

func hikerIsTag(s string) bool {
	switch s {
	case "a", "li", "ul", "ol", "div", "span", "p", "img", "h1", "h2", "h3", "h4", "h5", "h6", "body", "html", "table", "tr", "td", "section", "article", "header", "footer", "nav", "main", "em", "strong", "i", "b", "button", "input", "select", "option", "video", "source", "script", "style", "link", "meta", "label", "form":
		return true
	}
	return false
}

func hikerParseArray(htmlText, rule string) []string {
	nodes := hikerSelectChain(htmlText, rule)
	parts := strings.Split(rule, "&&")
	last := ""
	if len(parts) > 0 {
		last = strings.TrimSpace(parts[len(parts)-1])
	}
	out := []string{}
	for _, n := range nodes {
		switch last {
		case "Text":
			out = append(out, hikerNodeText(n))
		case "Html":
			out = append(out, hikerOuterHTML(n))
		default:
			if hikerIsAttr(last) {
				if v, ok := hikerAttr(n, last); ok {
					out = append(out, v)
				} else {
					out = append(out, "")
				}
			} else if hikerIsTag(last) {
				out = append(out, hikerOuterHTML(n))
			} else if v, ok := hikerAttr(n, last); ok {
				out = append(out, v)
			} else {
				out = append(out, hikerOuterHTML(n))
			}
		}
	}
	return out
}

func hikerSelectChain(htmlText, rule string) []*html.Node {
	doc, err := html.Parse(strings.NewReader(htmlText))
	if err != nil {
		return nil
	}
	parts := strings.Split(rule, "&&")
	last := strings.TrimSpace(parts[len(parts)-1])
	selectors := parts
	if last == "Text" || last == "Html" {
		selectors = parts[:len(parts)-1]
	} else if len(parts) > 1 && (hikerIsAttr(last) || !hikerIsTag(last)) && !strings.ContainsAny(last, ".# :[]") {
		selectors = parts[:len(parts)-1]
	}
	current := []*html.Node{doc}
	for _, sel := range selectors {
		sel = strings.TrimSpace(sel)
		if sel == "" {
			continue
		}
		next := []*html.Node{}
		for _, n := range current {
			next = append(next, hikerSelectAll(n, sel)...)
		}
		current = next
		if len(current) == 0 {
			return nil
		}
	}
	return current
}

func hikerAttr(n *html.Node, name string) (string, bool) {
	for _, a := range n.Attr {
		if a.Key == name {
			return a.Val, true
		}
	}
	return "", false
}

func hikerNodeText(n *html.Node) string {
	var b bytes.Buffer
	var walk func(*html.Node)
	walk = func(x *html.Node) {
		if x.Type == html.TextNode {
			b.WriteString(x.Data)
		}
		for c := x.FirstChild; c != nil; c = c.NextSibling {
			walk(c)
		}
	}
	walk(n)
	return strings.Join(strings.Fields(b.String()), " ")
}

func hikerOuterHTML(n *html.Node) string {
	var b bytes.Buffer
	_ = html.Render(&b, n)
	return b.String()
}

func hikerSelectAll(root *html.Node, selector string) []*html.Node {
	selector = hikerStripPseudo(selector)
	tokens := strings.Fields(selector)
	if len(tokens) == 0 {
		return nil
	}
	current := []*html.Node{root}
	for _, tok := range tokens {
		next := []*html.Node{}
		for _, n := range current {
			var walk func(*html.Node)
			walk = func(x *html.Node) {
				for c := x.FirstChild; c != nil; c = c.NextSibling {
					if hikerMatch(c, tok) {
						next = append(next, c)
					}
					walk(c)
				}
			}
			walk(n)
		}
		current = next
		if len(current) == 0 {
			return nil
		}
	}
	return current
}

func hikerStripPseudo(selector string) string {
	if i := strings.Index(selector, ":contains("); i >= 0 {
		end := strings.Index(selector[i:], ")")
		if end >= 0 {
			selector = selector[:i] + selector[i+end+1:]
		}
	}
	if i := strings.Index(selector, ":not("); i >= 0 {
		depth := 0
		end := -1
		for j := i; j < len(selector); j++ {
			if selector[j] == '(' {
				depth++
			} else if selector[j] == ')' {
				depth--
				if depth == 0 {
					end = j
					break
				}
			}
		}
		if end >= 0 {
			selector = selector[:i] + selector[end+1:]
		}
	}
	selector = strings.ReplaceAll(selector, ":matches", "")
	return strings.TrimSpace(selector)
}

func hikerMatch(n *html.Node, tok string) bool {
	if n.Type != html.ElementNode {
		return false
	}
	contains := ""
	if i := strings.Index(tok, ":contains("); i >= 0 {
		end := strings.Index(tok[i:], ")")
		if end >= 0 {
			contains = tok[i+len(":contains(") : i+end]
			tok = tok[:i]
		}
	}
	tag := ""
	cls := ""
	id := ""
	rest := tok
	for len(rest) > 0 {
		if rest[0] == '.' {
			end := strings.IndexAny(rest[1:], ".#")
			if end < 0 {
				cls = rest[1:]
				rest = ""
			} else {
				cls = rest[1 : 1+end]
				rest = rest[1+end:]
			}
		} else if rest[0] == '#' {
			end := strings.IndexAny(rest[1:], ".#")
			if end < 0 {
				id = rest[1:]
				rest = ""
			} else {
				id = rest[1 : 1+end]
				rest = rest[1+end:]
			}
		} else {
			end := strings.IndexAny(rest, ".#")
			if end < 0 {
				tag = rest
				rest = ""
			} else {
				tag = rest[:end]
				rest = rest[end:]
			}
		}
	}
	if tag != "" && n.Data != tag {
		return false
	}
	if id != "" {
		v, ok := hikerAttr(n, "id")
		if !ok || v != id {
			return false
		}
	}
	if cls != "" {
		v, ok := hikerAttr(n, "class")
		if !ok {
			return false
		}
		found := false
		for _, c := range strings.Fields(v) {
			if c == cls {
				found = true
				break
			}
		}
		if !found {
			return false
		}
	}
	if contains != "" && !strings.Contains(hikerNodeText(n), contains) {
		return false
	}
	return true
}

func HikerRunJSON(ruleJSON, action, input, ua string) (string, error) {
	var rule HikerRule
	if err := json.Unmarshal([]byte(ruleJSON), &rule); err != nil {
		return "", err
	}
	if ua == "" {
		ua = rule.UA
	}
	e := NewHikerEngine(ua)
	res, err := e.Run(rule, action, input)
	if err != nil {
		return "", err
	}
	b, err := json.Marshal(res)
	if err != nil {
		return "", err
	}
	return string(b), nil
}
