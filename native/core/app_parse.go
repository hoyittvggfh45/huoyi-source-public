package core

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const parseAPIRequestTimeout = 15 * time.Second

const parseAPIResponseLimit = 4 << 20

func applyParseTemplate(template, rawURL string) string {
	if strings.Contains(template, "{url}") {
		return strings.ReplaceAll(template, "{url}", parseURLEncode(rawURL))
	}
	return template + rawURL
}

func parseURLEncode(raw string) string {
	return strings.ReplaceAll(url.QueryEscape(raw), "+", "%20")
}

func parseFlagFromMap(m map[string]interface{}) bool {
	for _, key := range []string{"parse", "jx"} {
		switch v := m[key].(type) {
		case bool:
			if v {
				return true
			}
		case float64:
			if v == 1 {
				return true
			}
		case int:
			if v == 1 {
				return true
			}
		case json.Number:
			if v.String() == "1" {
				return true
			}
		case string:
			if strings.TrimSpace(v) == "1" {
				return true
			}
		}
	}
	return false
}

func jsonStringField(m map[string]interface{}, key string) string {
	if value, ok := m[key].(string); ok {
		return strings.TrimSpace(value)
	}
	return ""
}

func parsedHeadersFromJSON(m map[string]interface{}) map[string]string {
	for _, key := range []string{"header", "headers"} {
		if node, ok := m[key].(map[string]interface{}); ok {
			out := map[string]string{}
			for k, v := range node {
				if s, ok := v.(string); ok && strings.TrimSpace(s) != "" {
					out[k] = s
				}
			}
			if len(out) > 0 {
				return out
			}
		}
	}
	return nil
}

func parsedURLFromJSON(decoded map[string]interface{}) (string, map[string]string, bool) {
	headers := parsedHeadersFromJSON(decoded)
	for _, key := range []string{"url", "playUrl", "play_url", "src"} {
		if found := jsonStringField(decoded, key); found != "" && isProviderHTTPMediaURL(found) {
			return found, headers, true
		}
	}
	switch data := decoded["data"].(type) {
	case string:
		if found := strings.TrimSpace(data); isProviderHTTPMediaURL(found) {
			return found, headers, true
		}
	case map[string]interface{}:
		for k, v := range parsedHeadersFromJSON(data) {
			if _, exists := headers[k]; !exists {
				if headers == nil {
					headers = map[string]string{}
				}
				headers[k] = v
			}
		}
		for _, key := range []string{"url", "playUrl", "play_url", "src"} {
			if found := jsonStringField(data, key); found != "" && isProviderHTTPMediaURL(found) {
				return found, headers, true
			}
		}
	case []interface{}:
		if len(data) > 0 {
			if first, ok := data[0].(map[string]interface{}); ok {
				for _, key := range []string{"url", "playUrl", "play_url", "src"} {
					if found := jsonStringField(first, key); found != "" && isProviderHTTPMediaURL(found) {
						return found, headers, true
					}
				}
			}
		}
	}
	return "", nil, false
}

func isParseMediaContentType(contentType string) bool {
	mediaType := strings.ToLower(strings.TrimSpace(strings.Split(contentType, ";")[0]))
	if mediaType == "application/vnd.apple.mpegurl" || mediaType == "application/x-mpegurl" {
		return true
	}
	return strings.HasPrefix(mediaType, "video/") || strings.HasPrefix(mediaType, "audio/")
}

func extractParsedURL(body []byte, contentType, finalURL string) (string, map[string]string, bool) {
	trimmed := strings.TrimSpace(string(body))
	if trimmed != "" {
		if strings.HasPrefix(trimmed, "{") {
			var decoded map[string]interface{}
			if err := json.Unmarshal(body, &decoded); err == nil {
				if found, headers, ok := parsedURLFromJSON(decoded); ok {
					return found, headers, true
				}
			}
		}
		if isProviderHTTPMediaURL(trimmed) && !strings.ContainsAny(trimmed, " \n\r\t") {
			return trimmed, nil, true
		}
	}
	if isParseMediaContentType(contentType) && isProviderHTTPMediaURL(finalURL) {
		return finalURL, nil, true
	}
	return "", nil, false
}

func resolveViaParseAPIs(ctx context.Context, rawURL, referer string, apis []string) (string, map[string]string, error) {
	if len(apis) == 0 {
		return "", nil, errors.New("需要解析但未配置解析接口")
	}
	client := &http.Client{Timeout: parseAPIRequestTimeout}
	var lastErr error
	for _, template := range apis {
		template = strings.TrimSpace(template)
		if template == "" {
			continue
		}
		requestURL := applyParseTemplate(template, rawURL)
		if !isProviderHTTPMediaURL(requestURL) {
			lastErr = errors.New("解析接口地址无效")
			continue
		}
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, requestURL, nil)
		if err != nil {
			lastErr = err
			continue
		}
		req.Header.Set("User-Agent", userAgent)
		if referer != "" {
			req.Header.Set("Referer", referer)
		}
		resp, err := client.Do(req)
		if err != nil {
			lastErr = err
			continue
		}
		body, readErr := io.ReadAll(io.LimitReader(resp.Body, parseAPIResponseLimit))
		finalURL := resp.Request.URL.String()
		contentType := resp.Header.Get("Content-Type")
		status := resp.StatusCode
		resp.Body.Close()
		if readErr != nil {
			lastErr = readErr
			continue
		}
		if status != http.StatusOK {
			lastErr = fmt.Errorf("解析接口返回 %d", status)
			continue
		}
		if found, headers, ok := extractParsedURL(body, contentType, finalURL); ok {
			return found, headers, nil
		}
		lastErr = errors.New("解析接口未返回可用播放地址")
	}
	if lastErr == nil {
		lastErr = errors.New("解析接口全部失败")
	}
	return "", nil, fmt.Errorf("解析接口全部失败：%w", lastErr)
}

func (engine *nativeEngine) nativeResolveParse(ctx context.Context, input nativeInput) (nativePlan, error) {
	if !isProviderHTTPMediaURL(input.URL) {
		return nativePlan{}, errors.New("待解析地址无效")
	}
	referer := ""
	if input.Headers != nil {
		referer = firstNonEmpty(input.Headers["Referer"], input.Headers["referer"])
	}
	real, parsedHeaders, err := resolveViaParseAPIs(ctx, input.URL, referer, input.ParseAPIs)
	if err != nil {
		return nativePlan{}, err
	}
	if h := parsedHeaders["Referer"]; h != "" {
		referer = h
	} else if h := parsedHeaders["referer"]; h != "" {
		referer = h
	}
	media := providerMedia{URL: real, Referer: referer}
	choice := nativePlaybackChoices(media, 0)
	choice.adBlock = input.AdBlock == nil || *input.AdBlock
	choice.index = nativePreferredRoute(input.Route, len(choice.media))
	if choice.index < 0 || choice.index >= len(choice.media) {
		return nativePlan{}, errors.New("解析结果没有可用播放地址")
	}
	plan, err := engine.nativeOpenPlayback(ctx, choice)
	if err != nil {
		return nativePlan{}, err
	}
	plan.OriginalURL = input.URL
	return plan, nil
}
