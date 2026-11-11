package core

import (
	"bytes"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/sha512"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"time"
)

var hongguoSpadeDerivationConstants = func() []byte {
	decoded, err := hex.DecodeString("4dd4c2e6b83162090e52b3c7a6733ba41cb2462b829ab58a196b39db57177524f49baf7f08e8d68d26a72e37c1a95a2f1f05a51892aef2949732b62a38aadd58")
	if err != nil {
		return nil
	}
	return decoded
}()

func (downloader *Downloader) resolveHongguoAppMedia(ctx context.Context, videoID string) (providerMedia, error) {
	if !hongguoNumericID.MatchString(videoID) {
		return providerMedia{}, errors.New("红果视频 ID 无效")
	}
	if entry, found := downloader.hongguoTakeUpcomingModel(videoID); found {
		if media, err := downloader.hongguoMediaFromModelEntry(ctx, entry); err == nil {
			return media, nil
		}
	} else if entry, found := downloader.hongguoTakeModel(videoID); found {
		if media, err := downloader.hongguoMediaFromModelEntry(ctx, entry); err == nil {
			return media, nil
		}
	}
	if err := downloader.ensureHongguoDevice(ctx, ""); err != nil {
		return providerMedia{}, err
	}
	if downloader.hongguoDeviceLimited() {
		downloader.ensureHongguoDevice(ctx, downloader.hongguoDeviceID())
	}
	routes := downloader.hongguoPlaybackRoutes()
	plan := routes.plan(time.Now(), false)
	var lastErr error
	var lastEmpty, lastAuthRejected bool
	rejectedRetried := false
	attempt := func(route hongguoPlaybackRoute) (providerMedia, error) {
		if route.Get {
			return downloader.resolveHongguoVideoTab(ctx, videoID)
		}
		routeCtx := ctx
		if route.Host == hongguoOverseaAppBaseURL {
			routeCtx = context.WithValue(ctx, hongguoBaseURLOverrideKey{}, hongguoOverseaAppBaseURL)
		}
		return downloader.resolveHongguoAppMediaLine(routeCtx, videoID)
	}
	for _, route := range plan {
		media, err := attempt(route)
		if err == nil {
			routes.success(route, time.Now())
			downloader.clearHongguoDeviceLimited()
			return media, nil
		}
		if ctx.Err() != nil {
			return providerMedia{}, ctx.Err()
		}
		if hongguoIsDeviceRejected(err) && !rejectedRetried {
			rejectedRetried = true
			if rerr := downloader.reregisterHongguoDevice(ctx); rerr == nil {
				if media, rerr := attempt(route); rerr == nil {
					routes.success(route, time.Now())
					downloader.clearHongguoDeviceLimited()
					return media, nil
				} else if ctx.Err() != nil {
					return providerMedia{}, ctx.Err()
				} else {
					err = rerr
				}
			}
		}
		empty := errors.Is(err, errHongguoAppEmptyBody)
		routes.failed(route, time.Now(), empty)
		lastErr, lastEmpty, lastAuthRejected = err, empty, hongguoIsHTTPAuthRejected(err)
		if route.Get {
			continue
		}
		if !empty && !hongguoIsDeviceRejected(err) {
			return providerMedia{}, err
		}
	}
	if lastErr == nil {
		return providerMedia{}, errHongguoAppEmptyBody
	}
	if lastEmpty || lastAuthRejected {
		if media, err := downloader.hongguoPlayerLadder(ctx, videoID); err == nil {
			return media, nil
		} else if ctx.Err() != nil {
			return providerMedia{}, ctx.Err()
		}
	}
	if errors.Is(lastErr, errHongguoAppEmptyBody) {
		downloader.markHongguoPlayerSuspended()
		return providerMedia{}, fmt.Errorf("红果 App 大陆线与海外线轮换后仍未返回有效数据，可能被限流: %w", lastErr)
	}
	return providerMedia{}, lastErr
}

func (downloader *Downloader) resolveHongguoAppMediaLine(ctx context.Context, videoID string) (providerMedia, error) {
	if media, err := downloader.resolveHongguoMultiModel(ctx, videoID); err == nil {
		downloader.clearHongguoDeviceLimited()
		return media, nil
	} else if ctx.Err() != nil {
		return providerMedia{}, ctx.Err()
	}
	var lastErr error
	for attempt := 0; attempt <= hongguoDeviceRotations; attempt++ {
		if attempt > 0 {
			if err := downloader.ensureHongguoDevice(ctx, downloader.hongguoDeviceID()); err != nil {
				return providerMedia{}, err
			}
		}
		media, err := downloader.resolveHongguoVideoModel(ctx, videoID)
		if err != nil {
			if errors.Is(err, errHongguoAppEmptyBody) {
				downloader.markHongguoDeviceLimited()
				lastErr = err
				continue
			}
			return providerMedia{}, err
		}
		downloader.clearHongguoDeviceLimited()
		return media, nil
	}
	if lastErr != nil {
		return providerMedia{}, lastErr
	}
	return providerMedia{}, errHongguoAppEmptyBody
}

var hongguoVideoModelContentTypes = []int{1, 1001}

func hongguoPlayerBizParam(videoIDType int) map[string]any {
	return map[string]any{
		"video_platform": 1024, "need_all_video_definition": true, "use_os_player": false,
		"video_id_type": videoIDType, "from_video_id": "", "device_level": 3, "source": 4,
		"need_mp4_align": false, "image_shrink_datas_str": "", "screen_width_px": "1080",
		"item_map": map[string]any{}, "caller_scene": "0", "detail_page_version": 0,
		"use_server_dns": false, "use_server_dns_scene": "0", "expire_strategy": "0",
		"disable_digg_stat": false,
	}
}

func (downloader *Downloader) resolveHongguoVideoModel(ctx context.Context, videoID string) (providerMedia, error) {
	ctx = context.WithValue(ctx, hongguoSignOptionsKey{}, hongguoSignOptions{PlayerOnly: true})
	var lastErr error
	for _, contentType := range hongguoVideoModelContentTypes {
		payload := map[string]any{
			"video_id": videoID, "content_type": contentType,
			"biz_param": hongguoPlayerBizParam(0),
		}
		result, err := downloader.hongguoAppRequestInternal(ctx, http.MethodPost, "/novel/player/video_model/v1/", nil, payload, true)
		if err != nil {
			if ctx.Err() != nil {
				return providerMedia{}, ctx.Err()
			}
			lastErr = err
			continue
		}
		data := nestedMap(result, "data")
		model, err := hongguoVideoModelValue(data["video_model"])
		if err != nil {
			return providerMedia{}, errors.New("红果 App 播放信息格式异常")
		}
		if len(model) == 0 {
			if rows := anyList(data["video_list"]); len(rows) > 0 {
				model = map[string]any{
					"video_list":     data["video_list"],
					"video_duration": data["video_duration"],
					"duration":       data["duration"],
				}
			}
		}
		hongguoAttachKeySeed(model, data)
		downloader.hongguoMergeFallbackAPI(ctx, model)
		if len(model) == 0 {
			lastErr = errHongguoAppEmptyBody
			continue
		}
		downloader.clearHongguoDeviceLimited()
		media, err := selectHongguoAppMedia(model)
		if err == nil {
			media = downloader.hongguoApplyPlayAuth(ctx, media, data)
			offer := map[string]any{"video_model": model}
			if token, expires := hongguoPlayAuthFromData(data); token != "" {
				offer["play_auth_token"] = token
				offer["expire_time"] = expires
			}
			downloader.hongguoOfferModel(videoID, offer)
		}
		return media, err
	}
	if lastErr != nil {
		return providerMedia{}, lastErr
	}
	return providerMedia{}, errHongguoAppEmptyBody
}

func (downloader *Downloader) resolveHongguoVideoTab(ctx context.Context, videoID string) (providerMedia, error) {
	extra := url.Values{
		"video_id": {videoID}, "video_id_type": {"0"}, "device_level": {"1"},
		"need_all_video_definition": {"1"}, "need_mp4_align": {"0"}, "use_os_player": {"0"},
		"video_platform": {"1024"}, "source": {"0"}, "from_video_id": {""},
	}
	result, err := downloader.hongguoAppRequestInternal(ctx, http.MethodGet, "/reading/bookapi/video_tab/multi_video_model/v1/", extra, nil, true)
	if err != nil {
		return providerMedia{}, err
	}
	data := nestedMap(result, "data")
	rows := nestedMap(data, "video_model_data")
	if len(rows) == 0 {
		rows = data
	}
	entry := hongguoMultiEntry(rows, videoID)
	if entry == nil {
		return providerMedia{}, errHongguoAppEmptyBody
	}
	media, err := downloader.hongguoMediaFromModelEntry(ctx, entry, rows)
	if err != nil {
		return providerMedia{}, err
	}
	downloader.hongguoOfferModel(videoID, entry)
	return media, nil
}

func (downloader *Downloader) resolveHongguoMultiModel(ctx context.Context, videoID string) (providerMedia, error) {
	payload := map[string]any{
		"mixed_video_id_map": map[string]any{"1004": []any{videoID}},
		"biz_param":          hongguoPlayerBizParam(0),
	}
	result, err := downloader.hongguoAppRequestInternal(ctx, http.MethodPost, "/novel/player/multi_video_model/v1/", nil, payload, true)
	if err != nil {
		return providerMedia{}, err
	}
	data := nestedMap(result, "data")
	entry := hongguoMultiEntry(data, videoID)
	if entry == nil {
		return providerMedia{}, errHongguoAppEmptyBody
	}
	for key, value := range data {
		if key == videoID {
			continue
		}
		if sibling, ok := value.(map[string]any); ok {
			downloader.hongguoOfferUpcomingModel(key, sibling)
		}
	}
	media, err := downloader.hongguoMediaFromModelEntry(ctx, entry, data)
	if err != nil {
		return providerMedia{}, err
	}
	downloader.hongguoOfferModel(videoID, entry)
	return media, nil
}

func hongguoMultiEntry(data map[string]any, videoID string) map[string]any {
	if entry, ok := data[videoID].(map[string]any); ok {
		return entry
	}
	for _, value := range data {
		if entry, ok := value.(map[string]any); ok {
			return entry
		}
		if rows := anyList(value); len(rows) > 0 {
			if entry, ok := rows[0].(map[string]any); ok {
				return entry
			}
		}
	}
	if _, ok := data["video_model"]; ok {
		return data
	}
	if _, ok := data["video_list"]; ok {
		return data
	}
	return nil
}

func hongguoVideoModelValue(value any) (map[string]any, error) {
	if model, ok := value.(map[string]any); ok {
		return model, nil
	}
	encoded, ok := value.(string)
	if !ok || encoded == "" {
		return nil, nil
	}
	if decoded, err := decodeHongguoBase64(encoded); err == nil && len(decoded) > 0 {
		encoded = string(decoded)
	}
	var model map[string]any
	decoder := json.NewDecoder(strings.NewReader(encoded))
	decoder.UseNumber()
	if err := decoder.Decode(&model); err != nil {
		return nil, err
	}
	return model, nil
}

func hongguoAttachKeySeed(model map[string]any, sources ...map[string]any) {
	if model == nil || mapString(model, "key_seed") != "" {
		return
	}
	for _, source := range sources {
		if seed := hongguoFindKeySeed(source, 0); len(seed) > 0 {
			model["key_seed"] = base64.StdEncoding.EncodeToString(seed)
			return
		}
	}
}

func hongguoFindKeySeed(value any, depth int) []byte {
	if depth > 5 {
		return nil
	}
	switch item := value.(type) {
	case map[string]any:
		if raw, ok := item["key_seed"].(string); ok && strings.TrimSpace(raw) != "" {
			if seed, err := decodeHongguoSpadeBase64(raw); err == nil && len(seed) > 0 {
				return seed
			}
		}
		for _, key := range []string{"dynamic_video", "video_info", "data"} {
			if seed := hongguoFindKeySeed(item[key], depth+1); len(seed) > 0 {
				return seed
			}
		}
		for _, child := range item {
			if seed := hongguoFindKeySeed(child, depth+1); len(seed) > 0 {
				return seed
			}
		}
	}
	return nil
}

func decodeHongguoSpadeBase64(value string) ([]byte, error) {
	if decoded, err := decodeHongguoBase64(value); err == nil {
		return decoded, nil
	}
	normalized := strings.NewReplacer("-", "+", "_", "/").Replace(strings.TrimSpace(value))
	decoded, err := base64.StdEncoding.Strict().DecodeString(normalized)
	if err == nil {
		return decoded, nil
	}
	return base64.RawStdEncoding.Strict().DecodeString(normalized)
}

func decryptHongguoSpadeURL(value string, seed []byte) (string, error) {
	if len(seed) == 0 || len(hongguoSpadeDerivationConstants) == 0 {
		return "", errors.New("红果 spade 解密缺少密钥材料")
	}
	raw, err := decodeHongguoSpadeBase64(value)
	if err != nil || len(raw) < 20 {
		return "", errors.New("红果 spade 地址格式无效")
	}
	if raw[0] != 0xA8 || raw[2] != 0x01 || raw[3] != 0x00 {
		return "", errors.New("红果 spade 地址头无效")
	}
	cipherLen := (len(raw) - 4) / aes.BlockSize * aes.BlockSize
	if cipherLen == 0 {
		return "", errors.New("红果 spade 地址无完整密文块")
	}
	first := sha512.Sum512(seed)
	secondInput := make([]byte, 0, len(first)+len(hongguoSpadeDerivationConstants))
	secondInput = append(secondInput, first[:]...)
	secondInput = append(secondInput, hongguoSpadeDerivationConstants...)
	second := sha512.Sum512(secondInput)
	block, err := aes.NewCipher(second[:16])
	if err != nil {
		return "", err
	}
	plain := make([]byte, cipherLen)
	cipher.NewCBCDecrypter(block, second[16:32]).CryptBlocks(plain, raw[4:4+cipherLen])
	if len(plain) == 0 {
		return "", errors.New("红果 spade 地址解密为空")
	}
	if padding := int(plain[len(plain)-1]); padding >= 1 && padding <= aes.BlockSize && padding <= len(plain) {
		plain = plain[:len(plain)-padding]
	}
	plain = bytes.TrimRight(plain, "\x00")
	return strings.TrimSpace(string(plain)), nil
}

func (downloader *Downloader) hongguoMergeFallbackAPI(ctx context.Context, model map[string]any) {
	if fallbackURL := hongguoFallbackAPIURL(model); fallbackURL == "" {
		return
	} else if body, fetchErr := downloader.fetchProviderText(ctx, fallbackURL, "https://novel.snssdk.com/"); fetchErr == nil {
		if rows, parseErr := hongguoFallbackVideoRows(body); parseErr == nil && len(rows) > 0 {
			merged := anyList(model["video_list"])
			if rowsMap, ok := model["video_list"].(map[string]any); ok && len(merged) == 0 {
				keys := make([]string, 0, len(rowsMap))
				for key := range rowsMap {
					keys = append(keys, key)
				}
				sort.Strings(keys)
				for _, key := range keys {
					merged = append(merged, rowsMap[key])
				}
			}
			model["video_list"] = append(merged, rows...)
		}
	}
}

func hongguoFallbackAPIURL(model map[string]any) string {
	var extract func(value any) string
	extract = func(value any) string {
		switch item := value.(type) {
		case string:
			text := strings.TrimSpace(item)
			if strings.HasPrefix(text, "{") {
				var decoded map[string]any
				if err := json.Unmarshal([]byte(text), &decoded); err == nil {
					return strings.TrimSpace(mapString(decoded, "fallback_api"))
				}
				return ""
			}
			return text
		case []any:
			if len(item) > 0 {
				return extract(item[0])
			}
			return ""
		case map[string]any:
			return strings.TrimSpace(mapString(item, "fallback_api"))
		}
		return ""
	}
	return extract(model["fallback_api"])
}

func hongguoFallbackVideoRows(body string) ([]any, error) {
	var outer map[string]any
	decoder := json.NewDecoder(strings.NewReader(body))
	decoder.UseNumber()
	if err := decoder.Decode(&outer); err != nil {
		return nil, errors.New("红果备用取流返回了无效数据")
	}
	info := nestedMap(outer, "video_info", "data")
	if len(info) == 0 {
		info = nestedMap(outer, "data")
	}
	rows := anyList(info["video_list"])
	if rowsMap, ok := info["video_list"].(map[string]any); ok && len(rows) == 0 {
		keys := make([]string, 0, len(rowsMap))
		for key := range rowsMap {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		for _, key := range keys {
			rows = append(rows, rowsMap[key])
		}
	}
	if len(rows) == 0 {
		return nil, errors.New("红果备用取流未返回清晰度列表")
	}
	out := make([]any, 0, len(rows))
	for _, row := range rows {
		variant, _ := row.(map[string]any)
		if variant == nil {
			continue
		}
		if _, hasEncrypt := variant["encrypt_info"]; !hasEncrypt {
			if spade := mapString(variant, "spade_a"); spade != "" {
				variant["encrypt_info"] = map[string]any{"spade_a": spade}
			}
		}
		out = append(out, variant)
	}
	return out, nil
}

const hongguoDefaultMaxQuality = 1080

func hongguoSupportedCodec(codec string) bool {
	codec = strings.ToLower(codec)
	return codec != "bytevc2" && codec != "bvc2" && !strings.Contains(codec, "bytevc2")
}

func hongguoSelectLadder(model map[string]any, maxQuality int, supported func(codec string, height int) bool) (providerMedia, bool, error) {
	variants := anyList(model["video_list"])
	if rows, ok := model["video_list"].(map[string]any); ok && len(variants) == 0 {
		keys := make([]string, 0, len(rows))
		for key := range rows {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		for _, key := range keys {
			variants = append(variants, rows[key])
		}
	}
	duration, _ := strconv.ParseFloat(mapString(model, "video_duration", "duration"), 64)
	seed := hongguoFindKeySeed(model, 0)
	var keyErr error
	type scoredMedia struct {
		media providerMedia
		score int
	}
	var choices []scoredMedia
	for _, row := range variants {
		variant, _ := row.(map[string]any)
		meta := nestedMap(variant, "video_meta")
		codec := strings.ToLower(mapString(meta, "codec_type"))
		if codec == "" {
			codec = strings.ToLower(mapString(variant, "codec_type"))
		}
		height, _ := strconv.Atoi(mapString(meta, "vheight"))
		if definition, err := strconv.Atoi(hongguoQualityNumber.FindString(mapString(meta, "definition"))); err == nil && definition > 0 {
			height = definition
		} else if width, _ := strconv.Atoi(mapString(meta, "vwidth")); width > 0 && (height == 0 || width < height) {
			height = width
		}
		if supported != nil && !supported(codec, height) {
			continue
		}
		if strings.Contains(strings.ToLower(mapString(variant, "gear_des_key")), "bytevc2") {
			continue
		}
		addresses := hongguoMediaAddressesWithSeed(variant, seed)
		if len(addresses) == 0 {
			continue
		}
		media := providerMedia{Referer: "https://novel.snssdk.com/", Duration: time.Duration(duration * float64(time.Second))}
		encryption := nestedMap(variant, "encrypt_info")
		spade := mapString(encryption, "spade_a")
		if spade != "" || encryption["encrypt"] == true || mapString(encryption, "encryption_method") == "cenc-aes-ctr" {
			var err error
			media.CENCKey, err = hongguoContentKey(spade)
			if err != nil {
				keyErr = err
				continue
			}
		}
		media.Quality = height
		quality := height * 10
		if codec == "h264" || codec == "avc1" {
			quality++
		}
		for _, address := range addresses {
			media.URL = address
			choices = append(choices, scoredMedia{media: media, score: quality})
		}
	}
	if len(choices) > 0 {
		sort.SliceStable(choices, func(i, j int) bool { return choices[i].score > choices[j].score })
		selected := -1
		for index, choice := range choices {
			if choice.media.Quality > 0 && choice.media.Quality <= maxQuality {
				selected = index
				break
			}
		}
		if selected < 0 {
			for index, choice := range choices {
				if choice.media.Quality > 0 {
					selected = index
				}
			}
		}
		if selected < 0 {
			selected = 0
		}
		picked := choices[selected].media
		compatible := picked.Quality > maxQuality
		for _, choice := range choices {
			picked.Variants = append(picked.Variants, choice.media)
		}
		return picked, compatible, nil
	}
	if keyErr != nil {
		return providerMedia{}, false, fmt.Errorf("红果 App 媒体密钥不可用: %w", keyErr)
	}
	return providerMedia{}, false, errors.New("红果 App 未返回兼容的媒体，已跳过不支持的编码")
}

func selectHongguoAppMedia(model map[string]any) (providerMedia, error) {
	media, _, err := hongguoSelectLadder(model, hongguoDefaultMaxQuality, func(codec string, height int) bool {
		return hongguoSupportedCodec(codec)
	})
	return media, err
}

func (downloader *Downloader) hongguoPlayerLadder(ctx context.Context, videoID string) (providerMedia, error) {
	playerCtx := context.WithValue(ctx, hongguoSignOptionsKey{}, hongguoSignOptions{PlayerOnly: true})
	rejectedRetried := false
	rejected := false
	var lastErr error
	for source := 0; source < 2; source++ {
		var media providerMedia
		var err error
		if source == 0 {
			media, err = downloader.resolveHongguoVideoTab(playerCtx, videoID)
		} else {
			media, err = downloader.resolveHongguoMultiModel(playerCtx, videoID)
		}
		if err == nil {
			return media, nil
		}
		if ctx.Err() != nil {
			return providerMedia{}, ctx.Err()
		}
		if hongguoIsDeviceRejected(err) {
			rejected = true
			lastErr = err
			if !rejectedRetried {
				rejectedRetried = true
				if downloader.reregisterHongguoDevice(ctx) == nil {
					source--
				}
			}
			continue
		}
		lastErr = err
	}
	if rejected {
		return providerMedia{}, lastErr
	}
	if lastErr != nil {
		return providerMedia{}, lastErr
	}
	return providerMedia{}, errors.New("红果播放器设备源未返回可用媒体")
}

func hongguoMediaAddresses(info map[string]any) []string {
	return hongguoMediaAddressesWithSeed(info, nil)
}

func hongguoMediaAddressesWithSeed(info map[string]any, seed []byte) []string {
	var addresses []string
	seen := map[string]bool{}
	var add func(any)
	add = func(value any) {
		switch value := value.(type) {
		case string:
			address := strings.TrimSpace(value)
			if len(address) > 8192 {
				return
			}
			if !isProviderHTTPMediaURL(address) {
				if len(seed) > 0 {
					if decrypted, err := decryptHongguoSpadeURL(address, seed); err == nil && isProviderHTTPMediaURL(decrypted) {
						address = decrypted
					}
				}
			}
			if !isProviderHTTPMediaURL(address) {
				decoded, err := decodeHongguoBase64(address)
				if err != nil {
					return
				}
				address = strings.TrimSpace(string(decoded))
			}
			if isProviderHTTPMediaURL(address) && !seen[address] {
				seen[address] = true
				addresses = append(addresses, address)
			}
		case []any:
			for _, item := range value {
				add(item)
			}
		}
	}
	for _, key := range []string{"main_url", "backup_url", "backup_url_1", "backup_url_2", "backup_urls", "url_list"} {
		add(info[key])
	}
	return addresses
}

var hongguoPlayAuthAPIBase = "https://open.bytedanceapi.com/"

func hongguoPlayAuthFromData(data map[string]any) (string, int64) {
	if data == nil {
		return "", 0
	}
	token := strings.TrimSpace(mapString(data, "play_auth_token"))
	if token == "" {
		return "", 0
	}
	return token, int64(mapInt(data, "expire_time"))
}

func hongguoDecodePlayAuthToken(token string) (string, error) {
	normalized := strings.TrimSpace(token)
	if normalized == "" {
		return "", errors.New("红果播放鉴权为空")
	}
	for _, encoding := range []*base64.Encoding{base64.StdEncoding, base64.URLEncoding, base64.RawStdEncoding, base64.RawURLEncoding} {
		if decoded, err := encoding.DecodeString(normalized); err == nil && len(decoded) > 0 {
			return string(decoded), nil
		}
	}
	return "", errors.New("红果播放鉴权不是有效 Base64")
}

func hongguoCollectPlayAuthURLs(value any, found *[]string) {
	switch item := value.(type) {
	case string:
		if address := strings.TrimSpace(item); isProviderHTTPMediaURL(address) {
			*found = append(*found, address)
		}
	case []any:
		for _, child := range item {
			hongguoCollectPlayAuthURLs(child, found)
		}
	case map[string]any:
		for _, child := range item {
			hongguoCollectPlayAuthURLs(child, found)
		}
	}
}

func (downloader *Downloader) hongguoResolvePlayAuthSecondStage(ctx context.Context, token string, expires int64) (string, error) {
	if strings.TrimSpace(token) == "" {
		return "", errors.New("红果播放鉴权为空")
	}
	if expires > 0 && time.Now().Unix() >= expires-30 {
		return "", errors.New("红果播放鉴权已过期")
	}
	decoded, err := hongguoDecodePlayAuthToken(token)
	if err != nil {
		return "", err
	}
	if strings.TrimSpace(decoded) == "" {
		return "", errors.New("红果播放鉴权解码为空")
	}
	callCtx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	request, err := http.NewRequestWithContext(callCtx, http.MethodGet, hongguoPlayAuthAPIBase+"?"+decoded, nil)
	if err != nil {
		return "", err
	}
	client := downloader.client
	if client == nil {
		client = http.DefaultClient
	}
	response, err := client.Do(request)
	if err != nil {
		return "", err
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return "", fmt.Errorf("红果第二段鉴权返回 HTTP %d", response.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(response.Body, 256<<10))
	if err != nil {
		return "", err
	}
	text := strings.TrimSpace(string(body))
	if isProviderHTTPMediaURL(text) {
		return text, nil
	}
	var parsed any
	decoder := json.NewDecoder(strings.NewReader(text))
	decoder.UseNumber()
	if err := decoder.Decode(&parsed); err != nil {
		return "", errors.New("红果第二段鉴权未返回可用地址")
	}
	var found []string
	hongguoCollectPlayAuthURLs(parsed, &found)
	for _, address := range found {
		if strings.HasSuffix(strings.ToLower(address), ".m3u8") {
			return address, nil
		}
	}
	if len(found) > 0 {
		return found[0], nil
	}
	return "", errors.New("红果第二段鉴权未返回可用地址")
}

func (downloader *Downloader) hongguoApplyPlayAuth(ctx context.Context, media providerMedia, sources ...map[string]any) providerMedia {
	for _, source := range sources {
		token, expires := hongguoPlayAuthFromData(source)
		if token == "" {
			continue
		}
		media.PlayAuthToken = token
		media.PlayAuthExpires = expires
		if address, err := downloader.hongguoResolvePlayAuthSecondStage(ctx, token, expires); err == nil && address != "" && address != media.URL {
			media.URL = address
		}
		return media
	}
	return media
}
