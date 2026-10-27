package seku

// TG频道 ZakaTgAmns — bespoke gateway over Telegram channel mirrors,
// recipe verified live 2026-10-24:
//   Mirror: https://tg.i-c-a.su (ext "mirror" of the jar config).
//   Catalog: GET {mirror}/json/{user}?limit=50&page={n} answers an
//   MTProto-shaped payload {count, messages:[{id, message, media}]}
//   (verified: cctv_av count 62019). Messages whose media is a video
//   document become cards; text is ad-filtered with the jar's keyword
//   list (isAd in the jar class).
//   Cover: {mirror}/media/{user}/{id}/preview/thumb.jpeg
//   Play:  {mirror}/media/{user}/{id}/video.mp4 (the jar's videoUrl
//   also knows a /media?ch=&id= form; the RESTful form matches the
//   mirror's own /media/{ch}/{id}/ routes used by its RSS mode).
//   Channels are the jar config's ext channels (7, hard-coded in the
//   class <clinit> as well).
//   Search: the jar filters channel message text locally; here the
//   first page of every channel is scanned for the keyword.

import (
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"time"
)

const tgMirror = "https://tg.i-c-a.su"
const tgUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
const tgPageSize = 50

var tgChannels = []htmlCat{
	{ID: "cctv_av", Name: "超清AV"},
	{ID: "zfjp1024", Name: "那些极品姐姐"},
	{ID: "madougirl", Name: "麻豆 girl"},
	{ID: "hgmanju", Name: "黄果漫剧"},
	{ID: "hjgc0", Name: "海角 AV"},
	{ID: "wmav91", Name: "无码 91"},
	{ID: "shoucangav", Name: "收藏 AV"},
}

func tgChannelName(user string) string {
	for _, c := range tgChannels {
		if c.ID == user {
			return c.Name
		}
	}
	return user
}

func tgHeaders() map[string]string {
	return map[string]string{
		"User-Agent": tgUA,
		"Accept":     "application/json, text/plain, */*",
		"Referer":    tgMirror + "/",
	}
}

// tgAdWords is the jar's isAd keyword list (trimmed to the strongest
// signals) plus its @mention / group-lure regex behaviour.
var tgAdWords = []string{
	"博彩", "首存", "彩金", "返水", "招代理", "代理加盟", "包网", "招商",
	"加群", "客服", "下载app", "app下载", "看片神器", "发布页", "防失联",
	"备用域名", "永久域名", "资源站", "点击链接", "刷单", "日结", "外围",
	"楼凤", "推广", "广告位", "资源群", "进群", "电报", "订阅", "点赞",
	"获取更多", "更多资源", "最新地址", "导航", "防走失", "加微信", "微信号",
	"娱乐城", "真人荷官", "百家乐", "棋牌", "首充", "充值送", "官方直营",
	"秒到账", "注册送", "商务合作",
}

func tgIsAd(text string) bool {
	for _, w := range tgAdWords {
		if strings.Contains(text, w) {
			return true
		}
	}
	return false
}

type tgDocAttr struct {
	Type     string  `json:"_"`
	FileName string  `json:"file_name"`
	Duration float64 `json:"duration"`
	W        int     `json:"w"`
	H        int     `json:"h"`
}

type tgMessage struct {
	ID      int    `json:"id"`
	Message string `json:"message"`
	Media   *struct {
		Type     string `json:"_"`
		Document *struct {
			MimeType   string      `json:"mime_type"`
			Size       int64       `json:"size"`
			Attributes []tgDocAttr `json:"attributes"`
		} `json:"document"`
		Photo *json.RawMessage `json:"photo"`
	} `json:"media"`
}

type tgBlockResp struct {
	Count    int         `json:"count"`
	Messages []tgMessage `json:"messages"`
}

func tgFetchBlock(user string, page int) (*tgBlockResp, error) {
	return tgFetchBlockTO(user, page, 0)
}

func tgFetchBlockTO(user string, page int, timeout time.Duration) (*tgBlockResp, error) {
	u := fmt.Sprintf("%s/json/%s?limit=%d&page=%d", tgMirror, user, tgPageSize, page)
	var body []byte
	var code int
	var err error
	if timeout > 0 {
		body, code, _, err = httpGetTimeout(u, tgHeaders(), timeout)
	} else {
		body, code, _, err = httpGet(u, tgHeaders())
	}
	if err != nil {
		return nil, err
	}
	if code != 200 {
		return nil, fmt.Errorf("tg http %d for %s", code, u)
	}
	var resp tgBlockResp
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, fmt.Errorf("tg parse: %v", err)
	}
	return &resp, nil
}

func tgCard(slot string, user string, m tgMessage) map[string]interface{} {
	if m.Media == nil || m.Media.Document == nil {
		return nil
	}
	doc := m.Media.Document
	if !strings.HasPrefix(doc.MimeType, "video/") && !strings.HasSuffix(doc.MimeType, "mp4") {
		return nil
	}
	text := strings.TrimSpace(m.Message)
	if tgIsAd(text) {
		return nil
	}
	var fileName string
	var dur float64
	var w, h int
	for _, a := range doc.Attributes {
		if a.FileName != "" {
			fileName = a.FileName
		}
		if a.Duration > 0 {
			dur = a.Duration
		}
		if a.W > 0 {
			w, h = a.W, a.H
		}
	}
	title := ""
	if text != "" {
		title = strings.SplitN(text, "\n", 2)[0]
	}
	if title == "" {
		title = fileName
	}
	if title == "" {
		title = "视频 " + strconv.Itoa(m.ID)
	}
	title = cleanText(title)
	if len([]rune(title)) > 80 {
		title = string([]rune(title)[:80])
	}
	remark := ""
	if doc.Size > 0 {
		remark = fmt.Sprintf("%.1fMB", float64(doc.Size)/1048576)
	}
	if dur > 0 {
		if remark != "" {
			remark += " · "
		}
		remark += strconv.Itoa(int(dur)/60) + "分钟"
	}
	if w > 0 {
		if remark != "" {
			remark += " · "
		}
		remark += strconv.Itoa(w) + "x" + strconv.Itoa(h)
	}
	rawID := user + ":" + strconv.Itoa(m.ID)
	pic := fmt.Sprintf("%s/media/%s/%d/preview/thumb.jpeg", tgMirror, user, m.ID)
	d := makeDrama(slot, rawID, title, pic, remark, tgChannelName(user), cleanText(text))
	return d
}

func tgCatalog(slot, category string, page int) ([]interface{}, int, bool, error) {
	if page < 1 {
		page = 1
	}
	user := category
	if user == "" {
		user = tgChannels[0].ID
	}
	resp, err := tgFetchBlock(user, page)
	if err != nil {
		return nil, 0, false, err
	}
	items := []interface{}{}
	for _, m := range resp.Messages {
		if c := tgCard(slot, user, m); c != nil {
			items = append(items, c)
		}
	}
	return items, resp.Count, page*tgPageSize < resp.Count, nil
}

func tgSplitRaw(rawID string) (string, string, bool) {
	user, id, found := strings.Cut(rawID, ":")
	if !found || user == "" || id == "" {
		return "", "", false
	}
	return user, id, true
}

func tgDetail(slot, rawID string) (map[string]interface{}, error) {
	user, id, ok := tgSplitRaw(rawID)
	if !ok {
		return nil, fmt.Errorf("tg: bad id %q", rawID)
	}
	// The message may live on any recent page; scan the first pages
	// for the id (messages are newest-first, ids descend).
	for page := 1; page <= 3; page++ {
		resp, err := tgFetchBlock(user, page)
		if err != nil {
			return nil, err
		}
		for _, m := range resp.Messages {
			if strconv.Itoa(m.ID) == id {
				if c := tgCard(slot, user, m); c != nil {
					return c, nil
				}
				return nil, fmt.Errorf("tg: message %s is not a playable video", rawID)
			}
		}
	}
	// Not found in recent pages (older post opened from cache/search):
	// still hand back a playable shell — resolve needs only the id.
	pic := fmt.Sprintf("%s/media/%s/%s/preview/thumb.jpeg", tgMirror, user, id)
	return makeDrama(slot, rawID, "视频 "+id, pic, "", tgChannelName(user), ""), nil
}

func tgResolve(slot, rawID string) (map[string]interface{}, error) {
	user, id, ok := tgSplitRaw(rawID)
	if !ok {
		return nil, fmt.Errorf("tg: bad id %q", rawID)
	}
	u := fmt.Sprintf("%s/media/%s/%s/video.mp4", tgMirror, user, id)
	return playResult(u, slot, rawID, tgUA, tgMirror+"/", "mp4", "file"), nil
}

func tgSearch(slot, kw string) ([]interface{}, error) {
	kw = strings.TrimSpace(kw)
	if kw == "" {
		return []interface{}{}, nil
	}
	items := []interface{}{}
	for _, ch := range tgChannels {
		resp, err := tgFetchBlockTO(ch.ID, 1, 8*time.Second)
		if err != nil {
			continue
		}
		for _, m := range resp.Messages {
			if !strings.Contains(m.Message, kw) {
				continue
			}
			if c := tgCard(slot, ch.ID, m); c != nil {
				items = append(items, c)
			}
		}
		if len(items) >= 40 {
			break
		}
	}
	return items, nil
}

func init() {
	impl := &siteImpl{
		Key: "tg", Name: "TG频道", DefaultCat: tgChannels[0].ID, HomeURL: tgMirror + "/",
		Headers: tgHeaders,
	}
	impl.Categories = func(slot string) []interface{} {
		out := []interface{}{}
		for _, c := range tgChannels {
			out = append(out, categoryObj(c.ID, c.Name))
		}
		return out
	}
	impl.Catalog = tgCatalog
	impl.Detail = tgDetail
	impl.Resolve = tgResolve
	impl.Search = tgSearch
	registerSite("tg", impl, "tg", "tg频道")
}
