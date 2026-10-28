package core

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"crypto/md5"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/dop251/goja"
	"golang.org/x/net/html"
)

type HikerPage struct {
	Path string `json:"path"`
	Rule string `json:"rule"`
}

type HikerRule struct {
	Title           string          `json:"title"`
	Type            string          `json:"type"`
	URL             string          `json:"url"`
	ColType         string          `json:"col_type"`
	FindRule        string          `json:"find_rule"`
	SearchFind      string          `json:"searchFind"`
	DetailFindRule  string          `json:"detail_find_rule"`
	SearchURL       string          `json:"search_url"`
	UA              string          `json:"ua"`
	PreRule         string          `json:"preRule"`
	LastChapterRule string          `json:"last_chapter_rule"`
	Pages           json.RawMessage `json:"pages"`
}

func (r HikerRule) parsedPages() map[string]string {
	out := map[string]string{}
	if len(r.Pages) == 0 {
		return out
	}
	var list []HikerPage
	if err := json.Unmarshal(r.Pages, &list); err == nil {
		for _, p := range list {
			if p.Path != "" {
				out[p.Path] = p.Rule
			}
		}
		return out
	}
	var text string
	if err := json.Unmarshal(r.Pages, &text); err != nil {
		return out
	}
	if err := json.Unmarshal([]byte(text), &list); err != nil {
		return out
	}
	for _, p := range list {
		if p.Path != "" {
			out[p.Path] = p.Rule
		}
	}
	return out
}

type HikerEngine struct {
	rt         *goja.Runtime
	result     interface{}
	hasResult  bool
	lastHTML   string
	lastURL    string
	vars       map[string]interface{}
	config     map[string]interface{}
	ua         string
	client     *http.Client
	pages      map[string]string
	modules    map[string]goja.Value
	files      map[string]string
	myURL      string
	lastError  string
	requireErr string
	pubKeys    map[int]*rsa.PublicKey
	nextPubID  int
}

func (e *HikerEngine) requireModule(name string) (goja.Value, error) {
	if v, ok := e.modules[name]; ok {
		return v, nil
	}
	src, ok := e.pages[name]
	if !ok {
		return nil, errors.New("module not found: " + name)
	}
	src = strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(src), "js:"))
	dollarVal := e.rt.Get("$")
	if dollarVal == nil || goja.IsUndefined(dollarVal) {
		return nil, errors.New("missing $ runtime")
	}
	dollar := dollarVal.ToObject(e.rt)
	_ = dollar.Set("exports", goja.Undefined())
	if _, err := e.rt.RunString(src); err != nil {
		return nil, err
	}
	v := dollar.Get("exports")
	if v == nil || goja.IsUndefined(v) {
		return nil, errors.New("module has no exports: " + name)
	}
	if e.modules == nil {
		e.modules = map[string]goja.Value{}
	}
	e.modules[name] = v
	return v, nil
}

func jsIntRange(v goja.Value, rt *goja.Runtime, off, ln int) []int {
	obj := v.ToObject(rt)
	total := int(obj.Get("length").ToInteger())
	if off < 0 {
		off = 0
	}
	if ln < 0 {
		ln = 0
	}
	if off+ln > total {
		ln = total - off
	}
	if ln <= 0 {
		return nil
	}
	out := make([]int, 0, ln)
	for i := 0; i < ln; i++ {
		out = append(out, int(obj.Get(strconv.Itoa(off+i)).ToInteger()))
	}
	return out
}

func jsSignedBytes(v goja.Value, rt *goja.Runtime) []byte {
	obj := v.ToObject(rt)
	total := int(obj.Get("length").ToInteger())
	out := make([]byte, 0, total)
	for i := 0; i < total; i++ {
		n := int(obj.Get(strconv.Itoa(i)).ToInteger())
		if n < 0 {
			n += 256
		}
		out = append(out, byte(n))
	}
	return out
}

type javaConnState struct {
	url     string
	method  string
	headers map[string]string
	reqBody []byte
	done    bool
	status  int
	body    []byte
	execErr error
}

func (e *HikerEngine) javaConnExecute(st *javaConnState) {
	if st.done {
		return
	}
	st.done = true
	var body io.Reader
	if len(st.reqBody) > 0 {
		body = bytes.NewReader(st.reqBody)
	}
	req, err := http.NewRequest(st.method, st.url, body)
	if err != nil {
		st.execErr = err
		return
	}
	for k, v := range st.headers {
		req.Header.Set(k, v)
	}
	if req.Header.Get("User-Agent") == "" {
		if e.ua != "" {
			req.Header.Set("User-Agent", e.ua)
		} else {
			req.Header.Set("User-Agent", "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36")
		}
	}
	resp, err := e.client.Do(req)
	if err != nil {
		st.execErr = err
		return
	}
	defer resp.Body.Close()
	b, err := io.ReadAll(resp.Body)
	if err != nil {
		st.execErr = err
		return
	}
	st.status = resp.StatusCode
	st.body = b
	if resp.Request != nil && resp.Request.URL != nil {
		e.lastURL = resp.Request.URL.String()
	}
}

func (e *HikerEngine) javaStreamObject(body []byte) goja.Value {
	pos := 0
	obj := e.rt.NewObject()
	_ = obj.Set("read", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) == 0 {
			return e.rt.ToValue(-1)
		}
		if pos >= len(body) {
			return e.rt.ToValue(-1)
		}
		bufObj := call.Arguments[0].ToObject(e.rt)
		capLen := int(bufObj.Get("length").ToInteger())
		n := len(body) - pos
		if n > capLen {
			n = capLen
		}
		for i := 0; i < n; i++ {
			signed := int(body[pos+i])
			if signed > 127 {
				signed -= 256
			}
			_ = bufObj.Set(strconv.Itoa(i), signed)
		}
		pos += n
		return e.rt.ToValue(n)
	})
	_ = obj.Set("close", func(goja.FunctionCall) goja.Value { return goja.Undefined() })
	return obj
}

func (e *HikerEngine) javaURLCreate(rawURL string) goja.Value {
	obj := e.rt.NewObject()
	_ = obj.Set("openConnection", func(goja.FunctionCall) goja.Value {
		return e.javaConnObject(rawURL)
	})
	return obj
}

func (e *HikerEngine) javaConnObject(rawURL string) goja.Value {
	st := &javaConnState{url: rawURL, method: "GET", headers: map[string]string{}}
	obj := e.rt.NewObject()
	_ = obj.Set("setConnectTimeout", func(goja.FunctionCall) goja.Value { return goja.Undefined() })
	_ = obj.Set("setReadTimeout", func(goja.FunctionCall) goja.Value { return goja.Undefined() })
	_ = obj.Set("setRequestMethod", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) > 0 {
			st.method = call.Arguments[0].String()
		}
		return goja.Undefined()
	})
	_ = obj.Set("setRequestProperty", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) >= 2 {
			st.headers[call.Arguments[0].String()] = call.Arguments[1].String()
		}
		return goja.Undefined()
	})
	_ = obj.Set("setDoOutput", func(goja.FunctionCall) goja.Value { return goja.Undefined() })
	_ = obj.Set("getOutputStream", func(goja.FunctionCall) goja.Value {
		sObj := e.rt.NewObject()
		_ = sObj.Set("write", func(call goja.FunctionCall) goja.Value {
			if len(call.Arguments) > 0 {
				st.reqBody = append(st.reqBody, jsSignedBytes(call.Arguments[0], e.rt)...)
			}
			return goja.Undefined()
		})
		_ = sObj.Set("flush", func(goja.FunctionCall) goja.Value { return goja.Undefined() })
		_ = sObj.Set("close", func(goja.FunctionCall) goja.Value { return goja.Undefined() })
		return sObj
	})
	_ = obj.Set("getResponseCode", func(goja.FunctionCall) goja.Value {
		e.javaConnExecute(st)
		if st.execErr != nil {
			return e.rt.ToValue(-1)
		}
		return e.rt.ToValue(st.status)
	})
	_ = obj.Set("getInputStream", func(goja.FunctionCall) goja.Value {
		e.javaConnExecute(st)
		if st.execErr != nil || st.status < 200 || st.status >= 400 {
			return goja.Null()
		}
		return e.javaStreamObject(st.body)
	})
	_ = obj.Set("getErrorStream", func(goja.FunctionCall) goja.Value {
		e.javaConnExecute(st)
		if st.execErr != nil {
			return goja.Null()
		}
		if st.status >= 200 && st.status < 400 {
			return goja.Null()
		}
		return e.javaStreamObject(st.body)
	})
	return obj
}

func (e *HikerEngine) javaBAOSCreate() goja.Value {
	var buf []byte
	obj := e.rt.NewObject()
	_ = obj.Set("write", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) < 3 {
			return goja.Undefined()
		}
		off := int(call.Arguments[1].ToInteger())
		ln := int(call.Arguments[2].ToInteger())
		for _, v := range jsIntRange(call.Arguments[0], e.rt, off, ln) {
			if v < 0 {
				v += 256
			}
			buf = append(buf, byte(v))
		}
		return goja.Undefined()
	})
	_ = obj.Set("toByteArray", func(goja.FunctionCall) goja.Value {
		out := make([]interface{}, len(buf))
		for i, b := range buf {
			out[i] = int(b)
		}
		return e.rt.ToValue(out)
	})
	_ = obj.Set("close", func(goja.FunctionCall) goja.Value { return goja.Undefined() })
	_ = obj.Set("flush", func(goja.FunctionCall) goja.Value { return goja.Undefined() })
	return obj
}

func javaPKCS7Pad(data []byte, bs int) []byte {
	pad := bs - len(data)%bs
	out := make([]byte, len(data)+pad)
	copy(out, data)
	for i := len(data); i < len(out); i++ {
		out[i] = byte(pad)
	}
	return out
}

func javaECBEncrypt(block cipher.Block, data []byte) []byte {
	out := make([]byte, len(data))
	bs := block.BlockSize()
	for i := 0; i < len(data); i += bs {
		block.Encrypt(out[i:i+bs], data[i:i+bs])
	}
	return out
}

func javaCipherDoFinal(transformation string, mode int64, key []byte, hasKey bool, iv []byte, pubID int, hasPub bool, pubs map[int]*rsa.PublicKey, data []byte) ([]byte, bool) {
	if mode != 1 {
		return nil, false
	}
	switch transformation {
	case "AES/ECB/PKCS5Padding":
		if !hasKey {
			return nil, false
		}
		block, err := aes.NewCipher(key)
		if err != nil {
			return nil, false
		}
		return javaECBEncrypt(block, javaPKCS7Pad(data, block.BlockSize())), true
	case "AES/CBC/PKCS5Padding":
		if !hasKey || len(iv) == 0 {
			return nil, false
		}
		block, err := aes.NewCipher(key)
		if err != nil {
			return nil, false
		}
		padded := javaPKCS7Pad(data, block.BlockSize())
		out := make([]byte, len(padded))
		cipher.NewCBCEncrypter(block, iv).CryptBlocks(out, padded)
		return out, true
	case "RSA/ECB/PKCS1Padding":
		if !hasPub {
			return nil, false
		}
		pub, ok := pubs[pubID]
		if !ok {
			return nil, false
		}
		out, err := rsa.EncryptPKCS1v15(rand.Reader, pub, data)
		if err != nil {
			return nil, false
		}
		return out, true
	}
	return nil, false
}

func (e *HikerEngine) javaCipherCreate(transformation string) goja.Value {
	var mode int64
	var keyBytes []byte
	var ivBytes []byte
	var pubID int
	hasKey := false
	hasPub := false
	obj := e.rt.NewObject()
	_ = obj.Set("init", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) > 0 {
			mode = call.Arguments[0].ToInteger()
		}
		if len(call.Arguments) > 1 {
			keyObj := call.Arguments[1].ToObject(e.rt)
			if b := keyObj.Get("__bytes"); b != nil && !goja.IsUndefined(b) {
				keyBytes = jsSignedBytes(b, e.rt)
				hasKey = true
			}
			if p := keyObj.Get("__pubId"); p != nil && !goja.IsUndefined(p) {
				pubID = int(p.ToInteger())
				hasPub = true
			}
		}
		if len(call.Arguments) > 2 {
			ivObj := call.Arguments[2].ToObject(e.rt)
			if b := ivObj.Get("__bytes"); b != nil && !goja.IsUndefined(b) {
				ivBytes = jsSignedBytes(b, e.rt)
			}
		}
		return goja.Undefined()
	})
	_ = obj.Set("doFinal", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) == 0 {
			return goja.Undefined()
		}
		data := jsSignedBytes(call.Arguments[0], e.rt)
		out, ok := javaCipherDoFinal(transformation, mode, keyBytes, hasKey, ivBytes, pubID, hasPub, e.pubKeys, data)
		if !ok {
			return goja.Undefined()
		}
		arr := make([]interface{}, len(out))
		for i, b := range out {
			arr[i] = int(b)
		}
		return e.rt.ToValue(arr)
	})
	return obj
}

func (e *HikerEngine) javaKeyFactoryCreate(alg string) goja.Value {
	obj := e.rt.NewObject()
	_ = obj.Set("generatePublic", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) == 0 {
			return goja.Undefined()
		}
		specObj := call.Arguments[0].ToObject(e.rt)
		b := specObj.Get("__bytes")
		if b == nil || goja.IsUndefined(b) {
			return goja.Undefined()
		}
		der := jsSignedBytes(b, e.rt)
		var pub *rsa.PublicKey
		if parsed, err := x509.ParsePKIXPublicKey(der); err == nil {
			if rp, ok := parsed.(*rsa.PublicKey); ok {
				pub = rp
			}
		}
		if pub == nil {
			if rp, err := x509.ParsePKCS1PublicKey(der); err == nil {
				pub = rp
			}
		}
		if pub == nil {
			return goja.Undefined()
		}
		if e.pubKeys == nil {
			e.pubKeys = map[int]*rsa.PublicKey{}
		}
		e.nextPubID++
		id := e.nextPubID
		e.pubKeys[id] = pub
		pubObj := e.rt.NewObject()
		_ = pubObj.Set("__pubId", id)
		return pubObj
	})
	return obj
}

func (e *HikerEngine) javaBytesSpecCreate(call goja.FunctionCall) goja.Value {
	obj := e.rt.NewObject()
	if len(call.Arguments) > 0 {
		_ = obj.Set("__bytes", call.Arguments[0])
	}
	return obj
}

func NewHikerEngine(ua string) *HikerEngine {
	e := &HikerEngine{vars: map[string]interface{}{}, config: map[string]interface{}{}, ua: ua, client: &http.Client{Timeout: 20 * time.Second}, pages: map[string]string{}, modules: map[string]goja.Value{}, files: map[string]string{}}
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
		u = hikerResolveURL(e.lastURL, u)
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
		u = hikerResolveURL(e.lastURL, u)
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
	rt.Set("getParam", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) == 0 {
			return goja.Undefined()
		}
		if u, err := url.Parse(e.myURL); err == nil {
			if vals, ok := u.Query()[call.Arguments[0].String()]; ok && len(vals) > 0 {
				return rt.ToValue(vals[0])
			}
		}
		if len(call.Arguments) >= 2 {
			return call.Arguments[1]
		}
		return goja.Undefined()
	})
	rt.Set("clearMyVar", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) > 0 {
			delete(e.vars, call.Arguments[0].String())
		}
		return goja.Undefined()
	})
	rt.Set("removeItem", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) > 0 {
			delete(e.vars, call.Arguments[0].String())
		}
		return goja.Undefined()
	})
	rt.Set("md5", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) == 0 {
			return rt.ToValue("")
		}
		sum := md5.Sum([]byte(call.Arguments[0].String()))
		return rt.ToValue(hex.EncodeToString(sum[:]))
	})
	rt.Set("registerTask", func(goja.FunctionCall) goja.Value { return goja.Undefined() })
	rt.Set("unRegisterTask", func(goja.FunctionCall) goja.Value { return goja.Undefined() })
	rt.Set("getIP", func(goja.FunctionCall) goja.Value { return rt.ToValue("") })
	rt.Set("refreshPage", func(goja.FunctionCall) goja.Value { return goja.Undefined() })
	rt.Set("setPreResult", func(goja.FunctionCall) goja.Value { return goja.Undefined() })
	rt.Set("setError", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) > 0 {
			e.lastError = call.Arguments[0].String()
		}
		return goja.Undefined()
	})
	rt.Set("saveFile", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) >= 2 {
			e.files[call.Arguments[0].String()] = call.Arguments[1].String()
		}
		return goja.Undefined()
	})
	rt.Set("readFile", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) == 0 {
			return goja.Undefined()
		}
		v, ok := e.files[call.Arguments[0].String()]
		if !ok {
			return goja.Undefined()
		}
		return rt.ToValue(v)
	})
	rt.Set("lazyRuleEncode", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) == 0 {
			return rt.ToValue("hiker://lazy?args=%5B%5D")
		}
		b, err := json.Marshal(call.Arguments[0].Export())
		if err != nil {
			return rt.ToValue("hiker://lazy?args=%5B%5D")
		}
		return rt.ToValue("hiker://lazy?args=" + url.QueryEscape(string(b)))
	})
	rt.Set("javaURLCreate", func(call goja.FunctionCall) goja.Value {
		u := ""
		if len(call.Arguments) > 0 {
			u = call.Arguments[0].String()
		}
		return e.javaURLCreate(u)
	})
	rt.Set("javaBAOSCreate", func(goja.FunctionCall) goja.Value {
		return e.javaBAOSCreate()
	})
	javaObj := rt.NewObject()
	netObj := rt.NewObject()
	ioObj := rt.NewObject()
	langObj := rt.NewObject()
	byteObj := rt.NewObject()
	reflectObj := rt.NewObject()
	arrayObj := rt.NewObject()
	_ = byteObj.Set("TYPE", "byte")
	_ = langObj.Set("Byte", byteObj)
	_ = langObj.Set("reflect", reflectObj)
	_ = reflectObj.Set("Array", arrayObj)
	_ = javaObj.Set("net", netObj)
	_ = javaObj.Set("io", ioObj)
	_ = javaObj.Set("lang", langObj)
	rt.Set("java", javaObj)
	_ = arrayObj.Set("newInstance", func(call goja.FunctionCall) goja.Value {
		n := 0
		if len(call.Arguments) >= 2 {
			n = int(call.Arguments[1].ToInteger())
		}
		if n < 0 {
			n = 0
		}
		return rt.ToValue(make([]interface{}, n))
	})
	rt.Set("javaxCipherGetInstance", func(call goja.FunctionCall) goja.Value {
		trans := ""
		if len(call.Arguments) > 0 {
			trans = call.Arguments[0].String()
		}
		return e.javaCipherCreate(trans)
	})
	rt.Set("javaxKeyFactoryGetInstance", func(call goja.FunctionCall) goja.Value {
		alg := ""
		if len(call.Arguments) > 0 {
			alg = call.Arguments[0].String()
		}
		return e.javaKeyFactoryCreate(alg)
	})
	rt.Set("javaxBytesSpecCreate", func(call goja.FunctionCall) goja.Value {
		return e.javaBytesSpecCreate(call)
	})
	javaxObj := rt.NewObject()
	javaxCryptoObj := rt.NewObject()
	javaxSpecObj := rt.NewObject()
	securityObj := rt.NewObject()
	securitySpecObj := rt.NewObject()
	_ = javaxCryptoObj.Set("spec", javaxSpecObj)
	_ = javaxObj.Set("crypto", javaxCryptoObj)
	_ = securityObj.Set("spec", securitySpecObj)
	_ = javaObj.Set("security", securityObj)
	rt.Set("javax", javaxObj)
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
		var $ = function(s) { return { lazyRule: function(f) { return lazyRuleEncode(Array.prototype.slice.call(arguments, 1)); }, toString: function(f) { return ''; } }; };
		$.toString = function(f) { return ''; };
		java.net.URL = function(u) { return javaURLCreate(u); };
		java.io.ByteArrayOutputStream = function() { return javaBAOSCreate(); };
		javax.crypto.Cipher = { getInstance: javaxCipherGetInstance, ENCRYPT_MODE: 1, DECRYPT_MODE: 2 };
		java.security.KeyFactory = { getInstance: javaxKeyFactoryGetInstance };
		javax.crypto.spec.SecretKeySpec = function(k, a) { return javaxBytesSpecCreate(k); };
		javax.crypto.spec.IvParameterSpec = function(iv) { return javaxBytesSpecCreate(iv); };
		java.security.spec.X509EncodedKeySpec = function(k) { return javaxBytesSpecCreate(k); };
	`)
	if dollar := rt.Get("$"); dollar != nil {
		if obj := dollar.ToObject(rt); obj != nil {
			_ = obj.Set("require", func(call goja.FunctionCall) goja.Value {
				if len(call.Arguments) == 0 {
					return goja.Undefined()
				}
				v, err := e.requireModule(call.Arguments[0].String())
				if err != nil {
					e.requireErr = err.Error()
					return goja.Undefined()
				}
				return v
			})
		}
	}
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
	e.lastURL = finalURL
	b, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", finalURL, err
	}
	return string(b), finalURL, nil
}

func hikerResolveURL(base, ref string) string {
	if ref == "" || !strings.HasPrefix(ref, "/") {
		return ref
	}
	b, err := url.Parse(base)
	if err != nil || (b.Scheme != "http" && b.Scheme != "https") || b.Host == "" {
		return ref
	}
	r, err := url.Parse(ref)
	if err != nil {
		return ref
	}
	return b.ResolveReference(r).String()
}

var hikerURLKeys = map[string]bool{
	"url": true, "href": true, "pic": true, "pic_url": true, "img": true,
	"src": true, "cover": true, "image": true, "playUrl": true,
	"play_url": true, "videoUrl": true,
}

func hikerResolveResult(v interface{}, base string) interface{} {
	switch t := v.(type) {
	case map[string]interface{}:
		for k, val := range t {
			if s, ok := val.(string); ok && hikerURLKeys[k] {
				t[k] = hikerResolveURL(base, s)
			} else {
				t[k] = hikerResolveResult(val, base)
			}
		}
		return t
	case map[string]string:
		for k, val := range t {
			if hikerURLKeys[k] {
				t[k] = hikerResolveURL(base, val)
			}
		}
		return t
	case []interface{}:
		for i, val := range t {
			t[i] = hikerResolveResult(val, base)
		}
		return t
	case []map[string]string:
		for _, m := range t {
			hikerResolveResult(m, base)
		}
		return t
	case []map[string]interface{}:
		for _, m := range t {
			hikerResolveResult(m, base)
		}
		return t
	default:
		return v
	}
}

var hikerPlayURLKeys = []string{
	"url", "playUrl", "play_url", "videoUrl", "value", "src",
}

func hikerExtractPlayURL(v interface{}) string {
	switch t := v.(type) {
	case string:
		return strings.TrimSpace(t)
	case map[string]interface{}:
		for _, k := range hikerPlayURLKeys {
			if s, ok := t[k].(string); ok && strings.TrimSpace(s) != "" {
				return strings.TrimSpace(s)
			}
		}
		if data, ok := t["data"]; ok {
			return hikerExtractPlayURL(data)
		}
		return ""
	case map[string]string:
		for _, k := range hikerPlayURLKeys {
			if s, ok := t[k]; ok && strings.TrimSpace(s) != "" {
				return strings.TrimSpace(s)
			}
		}
		return ""
	case []interface{}:
		if len(t) == 0 {
			return ""
		}
		return hikerExtractPlayURL(t[0])
	case []map[string]interface{}:
		if len(t) == 0 {
			return ""
		}
		return hikerExtractPlayURL(t[0])
	case []map[string]string:
		if len(t) == 0 {
			return ""
		}
		return hikerExtractPlayURL(t[0])
	default:
		return ""
	}
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
	e.pages = rule.parsedPages()
	e.modules = map[string]goja.Value{}
	e.lastError = ""
	e.requireErr = ""
	_ = e.rt.Set("MY_RULE", map[string]interface{}{
		"title": rule.Title, "type": rule.Type, "url": rule.URL,
		"col_type": rule.ColType, "find_rule": rule.FindRule,
		"searchFind": rule.SearchFind, "detail_find_rule": rule.DetailFindRule,
		"search_url": rule.SearchURL, "ua": rule.UA,
	})
	myURL := rule.URL
	myPage := 1
	playMode := false
	var script string
	switch action {
	case "search":
		script = rule.SearchFind
		if rule.SearchURL != "" {
			myURL = strings.ReplaceAll(rule.SearchURL, "**", input)
			myURL = strings.ReplaceAll(myURL, "fypage", "1")
		}
		myURL = hikerResolveURL(rule.URL, myURL)
		if strings.HasPrefix(myURL, "http") {
			if body, err := e.httpGet(myURL); err == nil {
				e.lastHTML = body
			}
		}
	case "detail":
		script = rule.DetailFindRule
		if input != "" {
			myURL = hikerCleanListURL(input)
			myURL = hikerResolveURL(rule.URL, myURL)
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
			myURL = hikerResolveURL(rule.URL, myURL)
			if strings.HasPrefix(myURL, "http") {
				if body, err := e.httpGet(myURL); err == nil {
					e.lastHTML = body
				}
			}
		}
	case "play":
		playMode = true
		script = rule.LastChapterRule
		if input != "" {
			myURL = hikerCleanListURL(input)
			myURL = hikerResolveURL(rule.URL, myURL)
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
	if action == "search" {
		_ = e.rt.Set("MY_KEYWORD", input)
	} else {
		_ = e.rt.Set("MY_KEYWORD", "")
	}
	if strings.TrimSpace(rule.PreRule) != "" {
		if _, err := e.rt.RunString(strings.TrimSpace(rule.PreRule)); err != nil {
			return nil, err
		}
		_ = e.rt.Set("MY_URL", myURL)
		_ = e.rt.Set("MY_PAGE", myPage)
		_ = e.rt.Set("input", input)
	}
	e.myURL = myURL
	if strings.HasPrefix(input, "hiker://") {
		if u, err := url.Parse(input); err == nil {
			for k, vs := range u.Query() {
				if len(vs) > 0 {
					e.vars[k] = vs[0]
				}
			}
		}
	}
	script = strings.TrimSpace(script)
	if script == "" {
		if playMode {
			return nil, errors.New("no last chapter rule")
		}
		return nil, errors.New("empty rule")
	}
	if !strings.HasPrefix(script, "js:") {
		if playMode {
			return nil, errors.New("unsupported last chapter rule")
		}
		return hikerResolveResult(hikerRunListRule(e, script), hikerResolveBase(e, myURL, rule.URL)), nil
	}
	script = strings.TrimSpace(strings.TrimPrefix(script, "js:"))
	v, err := e.rt.RunString(script)
	if err != nil {
		if e.requireErr != "" {
			return nil, errors.New(e.requireErr)
		}
		return nil, err
	}
	if playMode {
		var raw interface{}
		if e.hasResult {
			raw = e.result
		} else if v != nil && !goja.IsUndefined(v) && !goja.IsNull(v) {
			raw = v.Export()
		}
		extracted := hikerExtractPlayURL(raw)
		if extracted == "" {
			return nil, errors.New("empty play url")
		}
		return hikerResolveURL(hikerResolveBase(e, myURL, rule.URL), extracted), nil
	}
	base := hikerResolveBase(e, myURL, rule.URL)
	if e.hasResult {
		return hikerResolveResult(e.result, base), nil
	}
	if e.lastError != "" {
		return nil, errors.New(e.lastError)
	}
	if v != nil && !goja.IsUndefined(v) && !goja.IsNull(v) {
		return hikerResolveResult(v.Export(), base), nil
	}
	return nil, errors.New("no result")
}

func hikerResolveBase(e *HikerEngine, myURL, ruleURL string) string {
	if e.lastURL != "" {
		return e.lastURL
	}
	if myURL != "" {
		return myURL
	}
	return ruleURL
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

type hikerAttrCond struct {
	name string
	op   string
	val  string
}

func hikerParseAttrCond(inner string) hikerAttrCond {
	inner = strings.TrimSpace(inner)
	for _, op := range []string{"*=", "^=", "$=", "="} {
		if i := strings.Index(inner, op); i >= 0 {
			val := strings.Trim(strings.TrimSpace(inner[i+len(op):]), `"'`)
			return hikerAttrCond{name: strings.TrimSpace(inner[:i]), op: op, val: val}
		}
	}
	return hikerAttrCond{name: inner}
}

type hikerPositional struct {
	kind  string
	index int
}

func hikerSplitPositional(tok string) (string, []hikerPositional) {
	var positions []hikerPositional
	depth := 0
	out := make([]byte, 0, len(tok))
	i := 0
	for i < len(tok) {
		c := tok[i]
		if c == '[' {
			depth++
			out = append(out, c)
			i++
			continue
		}
		if c == ']' && depth > 0 {
			depth--
			out = append(out, c)
			i++
			continue
		}
		if depth == 0 && c == ':' {
			rest := tok[i:]
			if strings.HasPrefix(rest, ":eq(") {
				end := strings.Index(rest, ")")
				if end >= 0 {
					if idx, err := strconv.Atoi(strings.TrimSpace(rest[4:end])); err == nil {
						positions = append(positions, hikerPositional{kind: "eq", index: idx})
						i += end + 1
						continue
					}
				}
			} else if strings.HasPrefix(rest, ":first") {
				after := rest[len(":first"):]
				if after == "" || after[0] == '.' || after[0] == '#' || after[0] == '[' || after[0] == ':' {
					positions = append(positions, hikerPositional{kind: "first"})
					i += len(":first")
					continue
				}
			} else if strings.HasPrefix(rest, ":last") {
				after := rest[len(":last"):]
				if after == "" || after[0] == '.' || after[0] == '#' || after[0] == '[' || after[0] == ':' {
					positions = append(positions, hikerPositional{kind: "last"})
					i += len(":last")
					continue
				}
			}
		}
		out = append(out, c)
		i++
	}
	return string(out), positions
}

func hikerApplyPositionals(nodes []*html.Node, positions []hikerPositional) []*html.Node {
	for _, p := range positions {
		if len(nodes) == 0 {
			return nodes
		}
		switch p.kind {
		case "first":
			nodes = nodes[:1]
		case "last":
			nodes = nodes[len(nodes)-1:]
		case "eq":
			idx := p.index
			if idx < 0 {
				idx += len(nodes)
			}
			if idx < 0 || idx >= len(nodes) {
				return nil
			}
			nodes = nodes[idx : idx+1]
		}
	}
	return nodes
}

func hikerSelectAll(root *html.Node, selector string) []*html.Node {
	selector = hikerStripPseudo(selector)
	tokens := strings.Fields(selector)
	if len(tokens) == 0 {
		return nil
	}
	current := []*html.Node{root}
	for _, tok := range tokens {
		clean, positions := hikerSplitPositional(tok)
		next := []*html.Node{}
		for _, n := range current {
			var walk func(*html.Node)
			walk = func(x *html.Node) {
				for c := x.FirstChild; c != nil; c = c.NextSibling {
					if hikerMatch(c, clean) {
						next = append(next, c)
					}
					walk(c)
				}
			}
			walk(n)
		}
		current = hikerApplyPositionals(next, positions)
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
	conds := []hikerAttrCond{}
	rest := tok
	for len(rest) > 0 {
		switch rest[0] {
		case '.':
			end := strings.IndexAny(rest[1:], ".#[")
			if end < 0 {
				cls = rest[1:]
				rest = ""
			} else {
				cls = rest[1 : 1+end]
				rest = rest[1+end:]
			}
		case '#':
			end := strings.IndexAny(rest[1:], ".#[")
			if end < 0 {
				id = rest[1:]
				rest = ""
			} else {
				id = rest[1 : 1+end]
				rest = rest[1+end:]
			}
		case '[':
			end := strings.Index(rest, "]")
			if end < 0 {
				rest = ""
			} else {
				conds = append(conds, hikerParseAttrCond(rest[1:end]))
				rest = rest[end+1:]
			}
		default:
			end := strings.IndexAny(rest, ".#[")
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
	for _, c := range conds {
		v, ok := hikerAttr(n, c.name)
		if !ok {
			return false
		}
		switch c.op {
		case "=":
			if v != c.val {
				return false
			}
		case "*=":
			if !strings.Contains(v, c.val) {
				return false
			}
		case "^=":
			if !strings.HasPrefix(v, c.val) {
				return false
			}
		case "$=":
			if !strings.HasSuffix(v, c.val) {
				return false
			}
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
