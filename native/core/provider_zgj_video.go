package core

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"regexp"
	"strconv"
	"strings"

	"golang.org/x/net/html"
)

const (
	chengguoBaseURL = "https://chengguodj.com"
	pornhubBaseURL  = "https://cn.pornhub.com"
	redtubeBaseURL  = "https://www.redtube.net"
)

var (
	zgjVideoChengguoDramaPath = regexp.MustCompile(`^/drama/(dj-[0-9a-fA-F]{8})$`)
	zgjVideoChengguoPlayPath  = regexp.MustCompile(`^/play/(dj-[0-9a-fA-F]{8})/(\d+)$`)
	zgjVideoRedtubeVideoPath  = regexp.MustCompile(`^/(\d+)/?$`)
)

func zgjVideoWalk(n *html.Node, visit func(*html.Node)) {
	if n == nil {
		return
	}
	visit(n)
	for c := n.FirstChild; c != nil; c = c.NextSibling {
		zgjVideoWalk(c, visit)
	}
}

func zgjVideoFindAll(root *html.Node, match func(*html.Node) bool) []*html.Node {
	var out []*html.Node
	zgjVideoWalk(root, func(n *html.Node) {
		if match(n) {
			out = append(out, n)
		}
	})
	return out
}

func zgjVideoFindFirst(root *html.Node, match func(*html.Node) bool) *html.Node {
	var found *html.Node
	zgjVideoWalk(root, func(n *html.Node) {
		if found == nil && match(n) {
			found = n
		}
	})
	return found
}

func zgjVideoIsElement(n *html.Node, tag string) bool {
	return n != nil && n.Type == html.ElementNode && n.Data == tag
}

func zgjVideoAttr(n *html.Node, name string) string {
	if n == nil {
		return ""
	}
	for _, attr := range n.Attr {
		if attr.Key == name {
			return attr.Val
		}
	}
	return ""
}

func zgjVideoHasClass(n *html.Node, class string) bool {
	for _, field := range strings.Fields(zgjVideoAttr(n, "class")) {
		if field == class {
			return true
		}
	}
	return false
}

func zgjVideoText(n *html.Node) string {
	if n == nil {
		return ""
	}
	var parts []string
	zgjVideoWalk(n, func(node *html.Node) {
		if node.Type == html.TextNode {
			parts = append(parts, node.Data)
		}
	})
	return strings.Join(strings.Fields(strings.Join(parts, " ")), " ")
}

func zgjVideoResolve(base, href string) string {
	href = strings.TrimSpace(href)
	if href == "" {
		return ""
	}
	parsedBase, err := url.Parse(base)
	if err != nil {
		return href
	}
	parsed, err := url.Parse(href)
	if err != nil {
		return href
	}
	return parsedBase.ResolveReference(parsed).String()
}

func zgjVideoParse(body string) (*html.Node, error) {
	return html.Parse(strings.NewReader(body))
}

func zgjVideoFirstImage(n *html.Node, base string) string {
	img := zgjVideoFindFirst(n, func(node *html.Node) bool { return zgjVideoIsElement(node, "img") })
	if img == nil {
		return ""
	}
	return zgjVideoResolve(base, firstNonEmpty(zgjVideoAttr(img, "data-src"), zgjVideoAttr(img, "src")))
}

func chengguoDramasFromHTML(body, base string) []Drama {
	doc, err := zgjVideoParse(body)
	if err != nil {
		return nil
	}
	episodeRe := regexp.MustCompile(`更新至(\d+)集`)
	var items []Drama
	seen := map[string]bool{}
	for _, anchor := range zgjVideoFindAll(doc, func(n *html.Node) bool { return zgjVideoIsElement(n, "a") }) {
		parsed, err := url.Parse(zgjVideoAttr(anchor, "href"))
		if err != nil {
			continue
		}
		match := zgjVideoChengguoDramaPath.FindStringSubmatch(parsed.Path)
		if match == nil {
			continue
		}
		djID := match[1]
		if seen[djID] {
			continue
		}
		seen[djID] = true
		img := zgjVideoFindFirst(anchor, func(n *html.Node) bool { return zgjVideoIsElement(n, "img") })
		title := ""
		if img != nil {
			title = firstNonEmpty(zgjVideoAttr(img, "title"), zgjVideoAttr(img, "alt"))
		}
		if title == "" {
			title = firstNonEmpty(zgjVideoAttr(anchor, "title"), zgjVideoText(anchor))
		}
		cover := ""
		if img != nil {
			cover = zgjVideoResolve(base, firstNonEmpty(zgjVideoAttr(img, "data-src"), zgjVideoAttr(img, "src")))
		}
		container := anchor.Parent
		desc := ""
		episodes := 0
		for i := 0; i < 3 && container != nil; i++ {
			text := zgjVideoText(container)
			if desc == "" {
				desc = text
			}
			if found := episodeRe.FindStringSubmatch(text); found != nil {
				if n, err := strconv.Atoi(found[1]); err == nil {
					episodes = n
				}
			}
			container = container.Parent
		}
		if len(desc) > 300 {
			desc = desc[:300]
		}
		drama := Drama{
			ID: providerDramaID(sourceChengguo, djID), Source: sourceChengguo, SourceID: djID,
			Title: title, Cover: cover, Desc: desc,
		}
		if episodes > 0 {
			drama.TotalEpisode = episodes
		}
		items = append(items, drama)
	}
	return items
}

func chengguoDetailFromHTML(body, base, djID string) (Drama, []Chapter, error) {
	doc, err := zgjVideoParse(body)
	if err != nil {
		return Drama{}, nil, err
	}
	title := ""
	if h1 := zgjVideoFindFirst(doc, func(n *html.Node) bool { return zgjVideoIsElement(n, "h1") }); h1 != nil {
		title = zgjVideoText(h1)
	}
	if title == "" {
		if titleNode := zgjVideoFindFirst(doc, func(n *html.Node) bool { return zgjVideoIsElement(n, "title") }); titleNode != nil {
			title = zgjVideoText(titleNode)
		}
	}
	desc := ""
	for _, node := range zgjVideoFindAll(doc, func(n *html.Node) bool {
		if n.Type != html.ElementNode {
			return false
		}
		class := strings.ToLower(zgjVideoAttr(n, "class"))
		return strings.Contains(class, "desc") || strings.Contains(class, "intro") || strings.Contains(class, "synopsis")
	}) {
		if text := zgjVideoText(node); text != "" {
			desc = text
			break
		}
	}
	if desc == "" {
		for _, p := range zgjVideoFindAll(doc, func(n *html.Node) bool { return zgjVideoIsElement(n, "p") }) {
			if text := zgjVideoText(p); len(text) > 20 {
				desc = text
				break
			}
		}
	}
	if len(desc) > 600 {
		desc = desc[:600]
	}
	var chapters []Chapter
	for _, anchor := range zgjVideoFindAll(doc, func(n *html.Node) bool { return zgjVideoIsElement(n, "a") }) {
		parsed, err := url.Parse(zgjVideoAttr(anchor, "href"))
		if err != nil {
			continue
		}
		match := zgjVideoChengguoPlayPath.FindStringSubmatch(parsed.Path)
		if match == nil || match[1] != djID {
			continue
		}
		ep := match[2]
		chapters = append(chapters, Chapter{
			ID:     providerChapterID(sourceChengguo, djID, ep),
			Source: sourceChengguo, Title: "第" + ep + "集",
			PageURL: zgjVideoResolve(base, zgjVideoAttr(anchor, "href")), Referer: base + "/",
		})
	}
	if len(chapters) == 0 {
		return Drama{}, nil, errors.New("详情页未找到选集")
	}
	return Drama{
		ID: providerDramaID(sourceChengguo, djID), Source: sourceChengguo, SourceID: djID,
		Title: title, Cover: zgjVideoFirstImage(doc, base), Desc: desc,
	}, chapters, nil
}

func zgjVideoOGImage(doc *html.Node, base string) string {
	for _, meta := range zgjVideoFindAll(doc, func(n *html.Node) bool {
		return zgjVideoIsElement(n, "meta") && zgjVideoAttr(n, "property") == "og:image"
	}) {
		if content := zgjVideoAttr(meta, "content"); content != "" {
			return zgjVideoResolve(base, content)
		}
	}
	return ""
}

func zgjVideoDetailTitle(doc *html.Node, suffixes ...string) string {
	if h1 := zgjVideoFindFirst(doc, func(n *html.Node) bool { return zgjVideoIsElement(n, "h1") }); h1 != nil {
		if text := zgjVideoText(h1); text != "" {
			return text
		}
	}
	if titleNode := zgjVideoFindFirst(doc, func(n *html.Node) bool { return zgjVideoIsElement(n, "title") }); titleNode != nil {
		title := zgjVideoText(titleNode)
		for _, suffix := range suffixes {
			title = strings.TrimSuffix(title, suffix)
		}
		return title
	}
	return ""
}

func pornhubDramasFromHTML(body, base string) []Drama {
	doc, err := zgjVideoParse(body)
	if err != nil {
		return nil
	}
	var items []Drama
	seen := map[string]bool{}
	for _, anchor := range zgjVideoFindAll(doc, func(n *html.Node) bool { return zgjVideoIsElement(n, "a") }) {
		href := zgjVideoAttr(anchor, "href")
		if !strings.Contains(href, "view_video.php") {
			continue
		}
		parsed, err := url.Parse(href)
		if err != nil {
			continue
		}
		viewkey := parsed.Query().Get("viewkey")
		if viewkey == "" || seen[viewkey] {
			continue
		}
		if zgjVideoFindFirst(anchor, func(n *html.Node) bool { return zgjVideoIsElement(n, "img") }) == nil {
			continue
		}
		seen[viewkey] = true
		img := zgjVideoFindFirst(anchor, func(n *html.Node) bool { return zgjVideoIsElement(n, "img") })
		title := firstNonEmpty(zgjVideoAttr(img, "title"), zgjVideoAttr(img, "alt"), zgjVideoAttr(anchor, "title"), zgjVideoText(anchor))
		cover := zgjVideoResolve(base, firstNonEmpty(zgjVideoAttr(img, "data-src"), zgjVideoAttr(img, "src")))
		items = append(items, Drama{
			ID: providerDramaID(sourcePornhub, viewkey), Source: sourcePornhub, SourceID: viewkey,
			Title: title, Cover: cover,
		})
	}
	return items
}

func pornhubDetailFromHTML(body, base, viewkey string) (Drama, []Chapter, error) {
	doc, err := zgjVideoParse(body)
	if err != nil {
		return Drama{}, nil, err
	}
	videoURL := base + "/view_video.php?viewkey=" + viewkey
	cover := zgjVideoOGImage(doc, base)
	if cover == "" {
		cover = zgjVideoFirstImage(doc, base)
	}
	return Drama{
			ID: providerDramaID(sourcePornhub, viewkey), Source: sourcePornhub, SourceID: viewkey,
			Title: zgjVideoDetailTitle(doc, " - Pornhub.com", " - Pornhub"), Cover: cover,
		}, []Chapter{{
			ID:     providerChapterID(sourcePornhub, viewkey, "main"),
			Source: sourcePornhub, Title: "正片", PageURL: videoURL, Referer: base + "/",
		}}, nil
}

func redtubeDramasFromHTML(body, base string) []Drama {
	doc, err := zgjVideoParse(body)
	if err != nil {
		return nil
	}
	var items []Drama
	seen := map[string]bool{}
	for _, anchor := range zgjVideoFindAll(doc, func(n *html.Node) bool { return zgjVideoIsElement(n, "a") }) {
		parsed, err := url.Parse(zgjVideoAttr(anchor, "href"))
		if err != nil {
			continue
		}
		match := zgjVideoRedtubeVideoPath.FindStringSubmatch(parsed.Path)
		if match == nil {
			continue
		}
		id := match[1]
		if seen[id] {
			continue
		}
		if zgjVideoFindFirst(anchor, func(n *html.Node) bool { return zgjVideoIsElement(n, "img") }) == nil {
			continue
		}
		seen[id] = true
		img := zgjVideoFindFirst(anchor, func(n *html.Node) bool { return zgjVideoIsElement(n, "img") })
		title := firstNonEmpty(zgjVideoAttr(img, "title"), zgjVideoAttr(img, "alt"), zgjVideoAttr(anchor, "title"), zgjVideoText(anchor))
		cover := zgjVideoResolve(base, firstNonEmpty(zgjVideoAttr(img, "data-src"), zgjVideoAttr(img, "src")))
		items = append(items, Drama{
			ID: providerDramaID(sourceRedtube, id), Source: sourceRedtube, SourceID: id,
			Title: title, Cover: cover,
		})
	}
	return items
}

func redtubeDetailFromHTML(body, base, id string) (Drama, []Chapter, error) {
	doc, err := zgjVideoParse(body)
	if err != nil {
		return Drama{}, nil, err
	}
	videoURL := base + "/" + id
	cover := zgjVideoOGImage(doc, base)
	if cover == "" {
		cover = zgjVideoFirstImage(doc, base)
	}
	return Drama{
			ID: providerDramaID(sourceRedtube, id), Source: sourceRedtube, SourceID: id,
			Title: zgjVideoDetailTitle(doc, " - RedTube", " - Redtube"), Cover: cover,
		}, []Chapter{{
			ID:     providerChapterID(sourceRedtube, id, "main"),
			Source: sourceRedtube, Title: "正片", PageURL: videoURL, Referer: base + "/",
		}}, nil
}

func (d *Downloader) fetchChengguoCatalogPage(ctx context.Context, page int) ([]Drama, bool, error) {
	address := chengguoBaseURL + "/browse"
	if page > 1 {
		address = fmt.Sprintf("%s/browse/page-%d", chengguoBaseURL, page)
	}
	body, err := d.fetchProviderText(ctx, address, chengguoBaseURL+"/")
	if err != nil {
		return nil, false, err
	}
	return chengguoDramasFromHTML(body, chengguoBaseURL), strings.Contains(body, fmt.Sprintf("/browse/page-%d", page+1)), nil
}

func (d *Downloader) searchChengguo(ctx context.Context, query string) ([]Drama, error) {
	address := chengguoBaseURL + "/search/" + url.PathEscape(query)
	body, err := d.fetchProviderText(ctx, address, chengguoBaseURL+"/")
	if err != nil {
		return nil, err
	}
	return chengguoDramasFromHTML(body, chengguoBaseURL), nil
}

func (d *Downloader) fetchChengguoDetail(ctx context.Context, djID string) (Drama, []Chapter, error) {
	body, err := d.fetchProviderText(ctx, chengguoBaseURL+"/drama/"+djID, chengguoBaseURL+"/")
	if err != nil {
		return Drama{}, nil, err
	}
	return chengguoDetailFromHTML(body, chengguoBaseURL, djID)
}

func (d *Downloader) fetchPornhubCatalogPage(ctx context.Context, page int, category string) ([]Drama, bool, error) {
	address := pornhubBaseURL + "/video"
	if category != "" {
		address += "?c=" + url.QueryEscape(category)
	}
	if page > 1 {
		sep := "?"
		if strings.Contains(address, "?") {
			sep = "&"
		}
		address += sep + "page=" + strconv.Itoa(page)
	}
	body, err := d.fetchProviderText(ctx, address, pornhubBaseURL+"/")
	if err != nil {
		return nil, false, err
	}
	return pornhubDramasFromHTML(body, pornhubBaseURL), strings.Contains(body, "page="+strconv.Itoa(page+1)), nil
}

func (d *Downloader) fetchPornhubDetail(ctx context.Context, viewkey string) (Drama, []Chapter, error) {
	body, err := d.fetchProviderText(ctx, pornhubBaseURL+"/view_video.php?viewkey="+viewkey, pornhubBaseURL+"/")
	if err != nil {
		return Drama{}, nil, err
	}
	return pornhubDetailFromHTML(body, pornhubBaseURL, viewkey)
}

func (d *Downloader) fetchRedtubeCatalogPage(ctx context.Context, page int, category string) ([]Drama, bool, error) {
	name := category
	if name == "" {
		name = "amateur"
	}
	address := redtubeBaseURL + "/redtube/" + name
	if page > 1 {
		address += "?page=" + strconv.Itoa(page)
	}
	body, err := d.fetchProviderText(ctx, address, redtubeBaseURL+"/")
	if err != nil {
		return nil, false, err
	}
	return redtubeDramasFromHTML(body, redtubeBaseURL), strings.Contains(body, "page="+strconv.Itoa(page+1)), nil
}

func (d *Downloader) fetchRedtubeDetail(ctx context.Context, id string) (Drama, []Chapter, error) {
	body, err := d.fetchProviderText(ctx, redtubeBaseURL+"/"+id, redtubeBaseURL+"/")
	if err != nil {
		return Drama{}, nil, err
	}
	return redtubeDetailFromHTML(body, redtubeBaseURL, id)
}

func (d *Downloader) resolveChengguoMedia(ctx context.Context, task Task) (providerMedia, error) {
	return providerMedia{}, errors.New("橙果单集视频地址尚未从播放页源码确认")
}

func (d *Downloader) resolvePornhubMedia(ctx context.Context, task Task) (providerMedia, error) {
	return providerMedia{}, errors.New("Pornhub mediaDefinitions 尚未从视频页源码确认")
}

func (d *Downloader) resolveRedtubeMedia(ctx context.Context, task Task) (providerMedia, error) {
	return providerMedia{}, errors.New("RedTube 媒体地址尚未从视频页源码确认")
}
