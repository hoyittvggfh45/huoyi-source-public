package core

import (
	"bytes"
	"compress/gzip"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

const hongguoPassportBaseURL = "https://security.snssdk.com"
const hongguoWebLoginBaseURL = "https://hongguoduanju.com"
const hongguoAccountCloudBaseURL = hongguoOverseaAppBaseURL
const hongguoAccountRequestTimeout = 20 * time.Second
const hongguoAccountMaxBodyBytes = 2 * 1024 * 1024
const hongguoPassportAppUA = "com.phoenix.read/72232 (Linux; U; Android 16; zh_CN; 25053RT47C; Build/BP2A.250605.031.A3)"
const hongguoPassportVideoUA = "com.phoenix.read/71332 (Linux; U; Android 16; zh_CN; 25053RT47C; Build/BP2A.250605.031.A3; Cronet/TTNetVersion:04657795 2026-01-23 QuicVersion:c67e9834 2025-09-08)"
const hongguoWebLoginUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"

var hongguoAccountSeriesID = regexp.MustCompile(`^[0-9]{1,30}$`)
var hongguoAccountReserveID = regexp.MustCompile(`^[0-9]{1,19}$`)
var errHongguoAccountEmptyBody = errors.New("账号接口返回空响应")

type hongguoAccountPhoneSession struct {
	mobile    string
	ticket    string
	deviceID  string
	installID string
	cookies   map[string]string
	expired   bool
}

type hongguoAccountQRSession struct {
	token   string
	cookies []*http.Cookie
}

func hongguoAccountMix(value string) string {
	var out strings.Builder
	for _, b := range []byte(value) {
		out.WriteString(strconv.FormatInt(int64(b^5), 16))
	}
	return out.String()
}

type hongguoAccountFormField struct {
	key   string
	value string
}

func hongguoAccountFormEscape(value string) string {
	escaped := url.QueryEscape(value)
	escaped = strings.ReplaceAll(escaped, "+", "%20")
	escaped = strings.ReplaceAll(escaped, "%7E", "~")
	return escaped
}

func hongguoAccountFormEncode(fields []hongguoAccountFormField) string {
	parts := make([]string, 0, len(fields))
	for _, field := range fields {
		if field.value == "" {
			continue
		}
		parts = append(parts, hongguoAccountFormEscape(field.key)+"="+hongguoAccountFormEscape(field.value))
	}
	return strings.Join(parts, "&")
}

func hongguoAccountQuery(deviceID, installID, versionCode, versionName string, includeIDs bool) url.Values {
	query := hongguoAppQuery(deviceID, installID)
	query.Set("version_code", versionCode)
	query.Set("version_name", versionName)
	query.Set("manifest_version_code", versionCode)
	query.Set("update_version_code", versionCode)
	query.Set("pv_player", versionCode)
	if !includeIDs {
		query.Del("device_id")
		query.Del("iid")
	}
	return query
}

func hongguoAccountInt(row map[string]any, key string, fallback int) int {
	return int(hongguoAccountInt64(row, key, int64(fallback)))
}

func hongguoAccountInt64(row map[string]any, key string, fallback int64) int64 {
	value, ok := row[key]
	if !ok || value == nil {
		return fallback
	}
	switch number := value.(type) {
	case json.Number:
		if parsed, err := number.Int64(); err == nil {
			return parsed
		}
		if parsed, err := number.Float64(); err == nil {
			return int64(parsed)
		}
	case float64:
		return int64(number)
	case int:
		return int64(number)
	case int64:
		return number
	case string:
		if parsed, err := strconv.ParseInt(number, 10, 64); err == nil {
			return parsed
		}
	}
	return fallback
}

func hongguoAccountErrorCode(data map[string]any) int {
	return hongguoAccountInt(data, "error_code", 0)
}

func hongguoAccountDescribe(data map[string]any) string {
	description := mapString(data, "description")
	if description == "" {
		return ""
	}
	return description + "（错误码 " + mapString(data, "error_code") + "）"
}

func hongguoAccountServerMessage(result map[string]any) string {
	for _, key := range []string{"message", "msg", "description"} {
		if value := mapString(result, key); value != "" {
			return value
		}
	}
	if data, ok := result["data"].(map[string]any); ok {
		return mapString(data, "description")
	}
	return ""
}

func hongguoAccountTransportError(err error) error {
	if err == nil {
		return nil
	}
	if errors.Is(err, context.Canceled) {
		return err
	}
	if errors.Is(err, context.DeadlineExceeded) || os.IsTimeout(err) {
		return errors.New("请求超时，请检查网络后重试")
	}
	var urlErr *url.Error
	if errors.As(err, &urlErr) {
		return errors.New("网络连接失败，请检查网络后重试")
	}
	var netErr *net.OpError
	if errors.As(err, &netErr) {
		return errors.New("网络连接失败，请检查网络后重试")
	}
	return err
}

func hongguoAccountReadJSON(response *http.Response) (map[string]any, error) {
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("账号接口返回 HTTP %d，请稍后重试", response.StatusCode)
	}
	content, err := io.ReadAll(io.LimitReader(response.Body, hongguoAccountMaxBodyBytes+1))
	if err != nil {
		return nil, err
	}
	if len(content) == 0 {
		return nil, errHongguoAccountEmptyBody
	}
	if len(content) > hongguoAccountMaxBodyBytes {
		return nil, errors.New("账号接口响应过大")
	}
	var result map[string]any
	decoder := json.NewDecoder(bytes.NewReader(content))
	decoder.UseNumber()
	if err := decoder.Decode(&result); err != nil || result == nil {
		return nil, errors.New("账号接口返回格式异常")
	}
	return result, nil
}

func hongguoAccountEpisodeCount(row map[string]any) int {
	for _, key := range []string{"episode_cnt", "episode_count", "drama_chapter_number"} {
		if count := hongguoAccountInt(row, key, 0); count > 0 {
			return count
		}
	}
	return 0
}

func hongguoAccountEpisodeBadge(row map[string]any) string {
	if count := hongguoAccountEpisodeCount(row); count > 0 {
		return fmt.Sprintf("全 %d 集", count)
	}
	return ""
}

func hongguoAccountFirstMap(row map[string]any, keys ...string) map[string]any {
	for _, key := range keys {
		if nested, ok := row[key].(map[string]any); ok {
			return nested
		}
	}
	return row
}

func hongguoAccountContentParams(content string) (map[string]any, error) {
	if strings.TrimSpace(content) == "" {
		return map[string]any{}, nil
	}
	var params map[string]any
	decoder := json.NewDecoder(strings.NewReader(content))
	decoder.UseNumber()
	if err := decoder.Decode(&params); err != nil || params == nil {
		return nil, errors.New("请求格式无效")
	}
	return params, nil
}

func hongguoAccountContentBool(params map[string]any, key string) bool {
	value, _ := params[key].(bool)
	return value
}

func hongguoAccountPassportCall(ctx context.Context, client *http.Client, baseURL, deviceID, installID, path string, params []hongguoAccountFormField, form bool, session *hongguoAccountPhoneSession) (map[string]any, error) {
	query := hongguoAccountQuery(deviceID, installID, "73932", "7.3.9.32", false)
	var body []byte
	method := http.MethodGet
	if form {
		fields := []hongguoAccountFormField{
			{key: "aid", value: "8662"},
			{key: "app_name", value: "novelread"},
			{key: "device_platform", value: "android"},
		}
		fields = append(fields, params...)
		body = []byte(hongguoAccountFormEncode(fields))
		method = http.MethodPost
	} else {
		for _, field := range params {
			if field.value != "" {
				query.Set(field.key, field.value)
			}
		}
		query.Set("aid", "8662")
		query.Set("app_name", "novelread")
		query.Set("device_platform", "android")
	}
	request, err := http.NewRequestWithContext(ctx, method, strings.TrimRight(baseURL, "/")+path+"?"+query.Encode(), bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	if form {
		request.Header.Set("User-Agent", hongguoPassportVideoUA)
	} else {
		request.Header.Set("User-Agent", hongguoPassportAppUA)
	}
	request.Header.Set("Accept", "application/json")
	if form {
		request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	}
	hongguoSignRequest(request, body, time.Now(), hongguoSignOptions{MedusaDeviceID: deviceID})
	callCtx, cancel := context.WithTimeout(ctx, hongguoAccountRequestTimeout)
	defer cancel()
	response, err := client.Do(request.WithContext(callCtx))
	if err != nil {
		return nil, hongguoAccountTransportError(err)
	}
	for _, cookie := range response.Cookies() {
		if cookie.Name == "" || cookie.Value == "" {
			continue
		}
		session.cookies[cookie.Name] = cookie.Value
	}
	return hongguoAccountReadJSON(response)
}

func hongguoAccountEmptyStage(path string) string {
	switch path {
	case "/reading/user/info/v1/":
		return "账号资料"
	case "/reading/bookapi/read_progress/list/v1/":
		return "云端历史列表"
	case "/reading/bookapi/multi-detail/v1/":
		return "云端剧集资料"
	default:
		return "账号"
	}
}

func hongguoAccountCloudCall(ctx context.Context, client *http.Client, baseURL, deviceID, installID, cookie, path string, params map[string]string, body []byte, gzipBody bool) (map[string]any, error) {
	versionCode, versionName := "72232", "7.2.2.32"
	if body != nil {
		versionCode, versionName = "73932", "7.3.9.32"
	}
	query := hongguoAccountQuery(deviceID, installID, versionCode, versionName, true)
	for key, value := range params {
		if value != "" {
			query.Set(key, value)
		}
	}
	wireBody := body
	if gzipBody && body != nil {
		var buf bytes.Buffer
		writer := gzip.NewWriter(&buf)
		if _, err := writer.Write(body); err != nil {
			return nil, err
		}
		if err := writer.Close(); err != nil {
			return nil, err
		}
		wireBody = buf.Bytes()
	}
	method := http.MethodGet
	if wireBody != nil {
		method = http.MethodPost
	}
	request, err := http.NewRequestWithContext(ctx, method, strings.TrimRight(baseURL, "/")+path+"?"+query.Encode(), bytes.NewReader(wireBody))
	if err != nil {
		return nil, err
	}
	request.Header.Set("User-Agent", hongguoAppUserAgent)
	request.Header.Set("Accept", "application/json")
	if cookie != "" {
		request.Header.Set("Cookie", cookie)
	}
	if wireBody != nil {
		request.Header.Set("Content-Type", "application/json; charset=utf-8")
	}
	if gzipBody {
		request.Header.Set("Content-Encoding", "gzip")
	}
	hongguoSignRequest(request, wireBody, time.Now(), hongguoSignOptions{Identity: hongguoSignerIdentity{DeviceID: deviceID, InstallID: installID}})
	callCtx, cancel := context.WithTimeout(ctx, hongguoAccountRequestTimeout)
	defer cancel()
	response, err := client.Do(request.WithContext(callCtx))
	if err != nil {
		return nil, hongguoAccountTransportError(err)
	}
	result, err := hongguoAccountReadJSON(response)
	if err != nil {
		if errors.Is(err, errHongguoAccountEmptyBody) {
			return nil, fmt.Errorf("%s接口返回空响应，可刷新重试；持续失败可尝试重新登录", hongguoAccountEmptyStage(path))
		}
		return nil, err
	}
	code := hongguoAccountInt(result, "code", -1)
	if code != 0 {
		if message := hongguoAccountServerMessage(result); message != "" {
			return nil, fmt.Errorf("%s（错误码 %d）", message, code)
		}
		return nil, fmt.Errorf("账号接口不可用（错误码 %d），请重新登录或稍后重试", code)
	}
	return result, nil
}

func hongguoAccountCookieMatches(cookie *http.Cookie, rawURL string) bool {
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return false
	}
	host := parsed.Hostname()
	domain := strings.ToLower(strings.TrimPrefix(cookie.Domain, "."))
	if domain != "" && host != domain && !strings.HasSuffix(host, "."+domain) {
		return false
	}
	if cookie.Path != "" {
		path := parsed.Path
		if path == "" {
			path = "/"
		}
		if !strings.HasPrefix(path, cookie.Path) {
			return false
		}
	}
	return true
}

func hongguoAccountCookieAlive(cookie *http.Cookie) bool {
	return cookie.Expires.IsZero() || time.Now().Before(cookie.Expires)
}

func hongguoAccountSessionCookies(session *hongguoAccountQRSession, rawURL string) []*http.Cookie {
	var matched []*http.Cookie
	for _, cookie := range session.cookies {
		if hongguoAccountCookieMatches(cookie, rawURL) && hongguoAccountCookieAlive(cookie) {
			matched = append(matched, cookie)
		}
	}
	return matched
}

func hongguoAccountSessionCookieHeader(session *hongguoAccountQRSession, rawURL string) string {
	matched := hongguoAccountSessionCookies(session, rawURL)
	parts := make([]string, 0, len(matched))
	for _, cookie := range matched {
		parts = append(parts, cookie.Name+"="+cookie.Value)
	}
	return strings.Join(parts, "; ")
}

func hongguoAccountCollectCookies(session *hongguoAccountQRSession, response *http.Response) {
	for _, cookie := range response.Cookies() {
		if cookie.Name == "" {
			continue
		}
		replaced := false
		for index, kept := range session.cookies {
			if kept.Name == cookie.Name && kept.Domain == cookie.Domain && kept.Path == cookie.Path {
				session.cookies[index] = cookie
				replaced = true
				break
			}
		}
		if !replaced {
			session.cookies = append(session.cookies, cookie)
		}
	}
}

func hongguoAccountHasSession(session *hongguoAccountQRSession) bool {
	for _, cookie := range hongguoAccountSessionCookies(session, hongguoWebLoginBaseURL) {
		if cookie.Name == "sessionid" || cookie.Name == "sessionid_ss" {
			return true
		}
	}
	return false
}

func hongguoAccountWebCall(ctx context.Context, client *http.Client, baseURL string, session *hongguoAccountQRSession, path string, params map[string]string, form map[string]string) (map[string]any, error) {
	webClient := *client
	webClient.CheckRedirect = func(*http.Request, []*http.Request) error {
		return http.ErrUseLastResponse
	}
	query := url.Values{
		"aid":                    {"513755"},
		"passport_jssdk_version": {"3.4.10"},
		"passport_jssdk_type":    {"normal"},
		"account_sdk_source":     {"web"},
		"is_from_ttaccountsdk":   {"1"},
		"language":               {"zh"},
	}
	for key, value := range params {
		if value != "" {
			query.Set(key, value)
		}
	}
	method := http.MethodGet
	var body io.Reader
	if form != nil {
		values := url.Values{}
		for key, value := range form {
			if value != "" {
				values.Set(key, value)
			}
		}
		body = strings.NewReader(values.Encode())
		method = http.MethodPost
	}
	target := strings.TrimRight(baseURL, "/") + path + "?" + query.Encode()
	request, err := http.NewRequestWithContext(ctx, method, target, body)
	if err != nil {
		return nil, err
	}
	request.Header.Set("User-Agent", hongguoWebLoginUA)
	request.Header.Set("Referer", strings.TrimRight(baseURL, "/")+"/")
	request.Header.Set("Origin", strings.TrimRight(baseURL, "/"))
	request.Header.Set("Accept", "application/json, text/javascript")
	if header := hongguoAccountSessionCookieHeader(session, target); header != "" {
		request.Header.Set("Cookie", header)
	}
	for _, cookie := range hongguoAccountSessionCookies(session, target) {
		if cookie.Name == "passport_csrf_token" {
			request.Header.Set("x-tt-passport-csrf-token", cookie.Value)
			break
		}
	}
	if form != nil {
		request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	}
	callCtx, cancel := context.WithTimeout(ctx, hongguoAccountRequestTimeout)
	defer cancel()
	response, err := webClient.Do(request.WithContext(callCtx))
	if err != nil {
		return nil, hongguoAccountTransportError(err)
	}
	hongguoAccountCollectCookies(session, response)
	result, err := hongguoAccountReadJSON(response)
	if err != nil {
		return nil, err
	}
	data, _ := result["data"].(map[string]any)
	if data == nil {
		return nil, errors.New("官网登录返回格式异常")
	}
	if mapString(result, "message") != "success" {
		if _, slider := data["verify_center_decision_conf"]; slider {
			return nil, errors.New("红果要求完成滑块验证，请改用扫码登录")
		}
		message := mapString(data, "description")
		if message == "" {
			message = "官网登录失败"
		}
		return nil, fmt.Errorf("%s（错误码 %s）", message, mapString(data, "error_code"))
	}
	return data, nil
}

func hongguoAccountFinishRedirect(ctx context.Context, client *http.Client, session *hongguoAccountQRSession, redirect string) error {
	webClient := *client
	webClient.CheckRedirect = func(*http.Request, []*http.Request) error {
		return http.ErrUseLastResponse
	}
	base, err := url.Parse(hongguoWebLoginBaseURL)
	if err != nil {
		return errors.New("登录确认地址无效")
	}
	current, err := base.Parse(redirect)
	if err != nil {
		return errors.New("登录确认地址无效")
	}
	for i := 0; i < 5; i++ {
		if current.Scheme != "https" || current.Hostname() != "hongguoduanju.com" {
			return errors.New("登录确认跳转到不支持的站点")
		}
		request, err := http.NewRequestWithContext(ctx, http.MethodGet, current.String(), nil)
		if err != nil {
			return err
		}
		request.Header.Set("User-Agent", hongguoWebLoginUA)
		request.Header.Set("Referer", hongguoWebLoginBaseURL+"/")
		if header := hongguoAccountSessionCookieHeader(session, current.String()); header != "" {
			request.Header.Set("Cookie", header)
		}
		callCtx, cancel := context.WithTimeout(ctx, hongguoAccountRequestTimeout)
		response, err := webClient.Do(request.WithContext(callCtx))
		cancel()
		if err != nil {
			return hongguoAccountTransportError(err)
		}
		hongguoAccountCollectCookies(session, response)
		if response.StatusCode >= 300 && response.StatusCode < 400 {
			location := response.Header.Get("Location")
			response.Body.Close()
			if location == "" {
				return nil
			}
			next, err := current.Parse(location)
			if err != nil {
				return errors.New("登录确认地址无效")
			}
			current = next
			continue
		}
		status := response.StatusCode
		response.Body.Close()
		if status < 200 || status >= 300 {
			return fmt.Errorf("登录确认失败（HTTP %d）", status)
		}
		return nil
	}
	return errors.New("登录确认跳转次数过多")
}

func (downloader *Downloader) hongguoAccountDevice(ctx context.Context) (string, string, error) {
	if err := downloader.ensureHongguoDevice(ctx, ""); err != nil {
		return "", "", err
	}
	client := downloader.hongguoClient()
	client.mu.Lock()
	defer client.mu.Unlock()
	return client.state.DeviceID, client.state.InstallID, nil
}

func (downloader *Downloader) hongguoAccountPhoneSession() *hongguoAccountPhoneSession {
	client := downloader.hongguoClient()
	client.accountMu.Lock()
	defer client.accountMu.Unlock()
	return client.phoneAccount
}

func (downloader *Downloader) hongguoAccountSetPhoneSession(session *hongguoAccountPhoneSession) {
	client := downloader.hongguoClient()
	client.accountMu.Lock()
	defer client.accountMu.Unlock()
	client.phoneAccount = session
}

func (downloader *Downloader) hongguoAccountQRSession() *hongguoAccountQRSession {
	client := downloader.hongguoClient()
	client.accountMu.Lock()
	defer client.accountMu.Unlock()
	return client.qrAccount
}

func (downloader *Downloader) hongguoAccountSetQRSession(session *hongguoAccountQRSession) {
	client := downloader.hongguoClient()
	client.accountMu.Lock()
	defer client.accountMu.Unlock()
	client.qrAccount = session
}

func (downloader *Downloader) hongguoAccountCloud(ctx context.Context, cookie, path string, params map[string]string, body []byte, gzipBody bool) (map[string]any, error) {
	deviceID, installID, err := downloader.hongguoAccountDevice(ctx)
	if err != nil {
		return nil, err
	}
	return hongguoAccountCloudCall(ctx, downloader.client, hongguoAccountCloudBaseURL, deviceID, installID, cookie, path, params, body, gzipBody)
}

func (downloader *Downloader) hongguoAccountSendSms(ctx context.Context, mobile string) (map[string]any, error) {
	deviceID, installID, err := downloader.hongguoAccountDevice(ctx)
	if err != nil {
		return nil, err
	}
	session := &hongguoAccountPhoneSession{
		mobile:    mobile,
		deviceID:  deviceID,
		installID: installID,
		cookies:   map[string]string{},
	}
	downloader.hongguoAccountSetPhoneSession(session)
	reply, err := hongguoAccountPassportCall(ctx, downloader.client, hongguoPassportBaseURL, deviceID, installID, "/passport/mobile/send_code/v1/", []hongguoAccountFormField{
		{key: "mobile", value: mobile},
		{key: "type", value: "24"},
	}, false, session)
	if err != nil {
		return nil, err
	}
	data, _ := reply["data"].(map[string]any)
	if data == nil {
		data = map[string]any{}
	}
	if _, slider := data["verify_center_decision_conf"]; slider {
		return nil, errors.New("平台要求先完成滑块验证，当前电视登录流程不支持，尚未完成登录")
	}
	if mapString(reply, "message") != "success" {
		if hongguoAccountErrorCode(data) == 7 {
			return nil, errors.New("平台限流：请求太频繁，请等 60 秒后再试（错误码 7）")
		}
		if described := hongguoAccountDescribe(data); described != "" {
			return nil, errors.New(described)
		}
		return nil, errors.New("验证码没发出去")
	}
	session.ticket = mapString(data, "mobile_ticket")
	masked := mapString(data, "mobile")
	if masked == "" {
		masked = mobile
	}
	return map[string]any{
		"maskedMobile": masked,
		"retrySeconds": hongguoAccountInt(data, "retry_time", 60),
	}, nil
}

var hongguoAccountVerifyAttempts = []struct {
	path string
	form bool
}{
	{"/passport/mobile/sms_login/", true},
	{"/passport/mobile/sms_login_only/", true},
	{"/passport/mobile/sms_login_continue/", true},
	{"/passport/mobile/validate_code/v1/", false},
	{"/passport/mobile/validate_code/v1/", true},
}

func (downloader *Downloader) hongguoAccountVerifySms(ctx context.Context, mobile, code string) (map[string]any, error) {
	session := downloader.hongguoAccountPhoneSession()
	if session == nil || session.deviceID == "" {
		return nil, errors.New("请先发送验证码")
	}
	if session.expired {
		return nil, errors.New("本次登录会话已失效，请重新获取验证码")
	}
	var firstFailure error
	for _, attempt := range hongguoAccountVerifyAttempts {
		reply, err := hongguoAccountPassportCall(ctx, downloader.client, hongguoPassportBaseURL, session.deviceID, session.installID, attempt.path, []hongguoAccountFormField{
			{key: "mobile", value: mobile},
			{key: "code", value: code},
			{key: "type", value: "24"},
			{key: "mobile_ticket", value: session.ticket},
		}, attempt.form, session)
		if err != nil {
			return nil, err
		}
		if _, ok := session.cookies["sessionid"]; ok {
			break
		}
		data, _ := reply["data"].(map[string]any)
		if data == nil {
			data = map[string]any{}
		}
		if fresh := mapString(data, "mobile_ticket"); fresh != "" {
			session.ticket = fresh
		}
		errorCode := hongguoAccountErrorCode(data)
		switch {
		case errorCode == 0 || errorCode == 1:
			if errorCode == 1 && firstFailure == nil {
				firstFailure = errors.New("会话过期，请重新登录（错误码 1）")
			}
			continue
		case errorCode == 1203:
			session.expired = true
			session.cookies = map[string]string{}
			session.ticket = ""
			if described := hongguoAccountDescribe(data); described != "" {
				return nil, errors.New(described)
			}
			return nil, errors.New("错误次数过多或验证码过期，请重新获取验证码（错误码 1203）")
		default:
			if described := hongguoAccountDescribe(data); described != "" {
				return nil, errors.New(described)
			}
			return nil, fmt.Errorf("验证码校验失败（错误码 %d）", errorCode)
		}
	}
	if _, ok := session.cookies["sessionid"]; !ok {
		if firstFailure != nil {
			return nil, firstFailure
		}
		return nil, errors.New("登录没有成功，平台没有下发登录态")
	}
	parts := make([]string, 0, len(session.cookies))
	for name, value := range session.cookies {
		parts = append(parts, name+"="+value)
	}
	sort.Strings(parts)
	return map[string]any{
		"cookie":    strings.Join(parts, "; "),
		"deviceId":  session.deviceID,
		"installId": session.installID,
	}, nil
}

func hongguoAccountQRSeconds(expiry, now int64) int {
	if expiry > 1000000000 {
		seconds := expiry - now
		if seconds < 0 {
			seconds = 0
		}
		if seconds > 600 {
			seconds = 600
		}
		return int(seconds)
	}
	if expiry < 0 {
		expiry = 0
	}
	if expiry > 600 {
		expiry = 600
	}
	return int(expiry)
}

func (downloader *Downloader) hongguoAccountQrCode(ctx context.Context) (map[string]any, error) {
	session := &hongguoAccountQRSession{}
	downloader.hongguoAccountSetQRSession(session)
	data, err := hongguoAccountWebCall(ctx, downloader.client, hongguoWebLoginBaseURL, session, "/passport/web/get_qrcode/", map[string]string{"next": hongguoWebLoginBaseURL + "/"}, nil)
	if err != nil {
		return nil, err
	}
	token := mapString(data, "token")
	if token == "" {
		return nil, errors.New("官网登录返回格式异常")
	}
	encoded := mapString(data, "qrcode")
	if index := strings.Index(encoded, "base64,"); index >= 0 {
		encoded = encoded[index+len("base64,"):]
	}
	image, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return nil, errors.New("官网登录返回格式异常")
	}
	seconds := hongguoAccountQRSeconds(hongguoAccountInt64(data, "expire_time", 180), time.Now().Unix())
	session.token = token
	return map[string]any{
		"imageBase64":      base64.StdEncoding.EncodeToString(image),
		"expiresInSeconds": seconds,
	}, nil
}

func (downloader *Downloader) hongguoAccountQrPoll(ctx context.Context) (map[string]any, error) {
	session := downloader.hongguoAccountQRSession()
	if session == nil || session.token == "" {
		return nil, errors.New("请先获取二维码")
	}
	data, err := hongguoAccountWebCall(ctx, downloader.client, hongguoWebLoginBaseURL, session, "/passport/web/check_qrconnect/", map[string]string{
		"next":  hongguoWebLoginBaseURL + "/",
		"token": session.token,
	}, nil)
	if err != nil {
		return nil, err
	}
	switch status := mapString(data, "status"); status {
	case "5", "expired":
		return map[string]any{"result": "expired"}, nil
	case "3", "confirmed":
		if redirect := mapString(data, "redirect_url"); redirect != "" {
			if err := hongguoAccountFinishRedirect(ctx, downloader.client, session, redirect); err != nil {
				return nil, err
			}
		}
		if hongguoAccountHasSession(session) {
			return map[string]any{"result": "confirmed"}, nil
		}
		return map[string]any{"result": "scanned"}, nil
	case "2":
		return map[string]any{"result": "scanned"}, nil
	default:
		return map[string]any{"result": "waiting"}, nil
	}
}

func (downloader *Downloader) hongguoAccountQrConfirm(ctx context.Context) (map[string]any, error) {
	session := downloader.hongguoAccountQRSession()
	if session == nil || !hongguoAccountHasSession(session) {
		return nil, errors.New("官网尚未下发登录态，请先在手机确认登录")
	}
	if _, err := hongguoAccountWebCall(ctx, downloader.client, hongguoWebLoginBaseURL, session, "/passport/account/info/v2/", nil, nil); err != nil {
		return nil, err
	}
	return map[string]any{
		"cookie":    hongguoAccountSessionCookieHeader(session, hongguoWebLoginBaseURL),
		"deviceId":  "",
		"installId": "",
	}, nil
}

func (downloader *Downloader) hongguoAccountProfile(ctx context.Context, cookie string) (map[string]any, error) {
	reply, err := downloader.hongguoAccountCloud(ctx, cookie, "/reading/user/info/v1/", nil, nil, false)
	if err != nil {
		return nil, err
	}
	data, _ := reply["data"].(map[string]any)
	if data == nil {
		return nil, errors.New("账号资料为空")
	}
	return map[string]any{"profile": data}, nil
}

func (downloader *Downloader) hongguoAccountFavorites(ctx context.Context, cookie string) (map[string]any, error) {
	reply, err := downloader.hongguoAccountCloud(ctx, cookie, "/reading/bookapi/bookshelf/video/info/v1/", nil, nil, false)
	if err != nil {
		return nil, err
	}
	data, _ := reply["data"].(map[string]any)
	if data == nil {
		return nil, errors.New("账户收藏数据格式已变化")
	}
	raw, present := data["video_shelf_info"]
	if !present {
		return nil, errors.New("账户收藏列表格式已变化")
	}
	if raw == nil {
		return map[string]any{"rows": []any{}}, nil
	}
	rows, ok := raw.([]any)
	if !ok {
		return nil, errors.New("账户收藏列表格式已变化")
	}
	return map[string]any{"rows": rows}, nil
}

func (downloader *Downloader) hongguoAccountSetFavorite(ctx context.Context, cookie, seriesID string, add bool) (map[string]any, error) {
	if !hongguoAccountSeriesID.MatchString(seriesID) {
		return nil, errors.New("剧集编号无效")
	}
	operateType := 1
	if add {
		operateType = 0
	}
	entry := map[string]any{
		"book_id":                  seriesID,
		"book_type":                2,
		"modify_time":              time.Now().UnixMilli(),
		"video_shelf_operate_type": operateType,
	}
	if !add {
		entry["group_name"] = ""
	}
	bodyMap := map[string]any{
		"is_cancelled":                false,
		"update_bookshelf_video_list": []any{entry},
	}
	if add {
		bodyMap["shark_extra"] = map[string]any{
			"enter_from":         "MainFragmentActivity",
			"previous_page":      "",
			"page_list":          "MainFragmentActivity",
			"is_active_behavior": "true",
			"inactive_type":      "0",
		}
	}
	body, err := json.Marshal(bodyMap)
	if err != nil {
		return nil, err
	}
	if _, err := downloader.hongguoAccountCloud(ctx, cookie, "/reading/bookapi/bookshelf/video/update/v1/", nil, body, false); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

func hongguoAccountHistoryRows(reply map[string]any) []map[string]any {
	var raw []any
	if data, ok := reply["data"].(map[string]any); ok {
		raw, _ = data["video_data"].([]any)
	}
	if raw == nil {
		raw, _ = reply["video_data"].([]any)
	}
	rows := []map[string]any{}
	seen := map[string]bool{}
	for _, item := range raw {
		row, _ := item.(map[string]any)
		if row == nil {
			continue
		}
		seriesID := mapString(row, "series_id")
		if seriesID == "" {
			seriesID = mapString(row, "book_id")
		}
		episodeID := mapString(row, "vid")
		if !hongguoAccountSeriesID.MatchString(seriesID) || !hongguoAccountSeriesID.MatchString(episodeID) {
			continue
		}
		if seen[seriesID] {
			continue
		}
		seen[seriesID] = true
		rows = append(rows, map[string]any{
			"series_id":          seriesID,
			"vid":                episodeID,
			"vid_index":          hongguoAccountInt(row, "vid_index", 1),
			"current_play_time":  hongguoAccountInt64(row, "current_play_time", 0),
			"current_total_time": hongguoAccountInt64(row, "current_total_time", 0),
			"last_watch_time":    hongguoAccountInt64(row, "last_watch_time", 0),
			"episode_count":      hongguoAccountInt(row, "episode_count", 0),
		})
	}
	return rows
}

func (downloader *Downloader) hongguoAccountHistory(ctx context.Context, cookie string) (map[string]any, error) {
	reply, err := downloader.hongguoAccountCloud(ctx, cookie, "/reading/bookapi/read_progress/list/v1/", map[string]string{"book_types": "2", "limit": "50"}, nil, false)
	if err != nil {
		return nil, err
	}
	rows := hongguoAccountHistoryRows(reply)
	if len(rows) == 0 {
		return map[string]any{"rows": []any{}}, nil
	}
	ids := make([]string, 0, len(rows))
	for _, row := range rows {
		ids = append(ids, row["series_id"].(string))
	}
	detailReply, err := downloader.hongguoAccountCloud(ctx, cookie, "/reading/bookapi/multi-detail/v1/", map[string]string{"book_id": strings.Join(ids, ","), "book_type": "2"}, nil, false)
	if err != nil {
		return nil, err
	}
	details, _ := detailReply["data"].([]any)
	if details == nil {
		return nil, errors.New("云端剧集资料格式已变化")
	}
	byID := map[string]map[string]any{}
	for _, item := range details {
		row, _ := item.(map[string]any)
		if row == nil {
			continue
		}
		byID[mapString(row, "book_id")] = row
	}
	merged := make([]any, 0, len(rows))
	for _, row := range rows {
		out := map[string]any{}
		for key, value := range row {
			out[key] = value
		}
		if detail, ok := byID[row["series_id"].(string)]; ok {
			out["title"] = mapString(detail, "book_name")
			out["thumb_url"] = mapString(detail, "thumb_url")
			out["episode_count"] = hongguoAccountEpisodeCount(detail)
		}
		merged = append(merged, out)
	}
	return map[string]any{"rows": merged}, nil
}

func (downloader *Downloader) hongguoAccountUploadProgress(ctx context.Context, cookie string, progress map[string]any) (map[string]any, error) {
	seriesID := mapString(progress, "seriesId")
	episodeID := mapString(progress, "episodeId")
	if !hongguoAccountSeriesID.MatchString(seriesID) || !hongguoAccountSeriesID.MatchString(episodeID) {
		return nil, errors.New("剧集编号无效")
	}
	episodeIndex := hongguoAccountInt(progress, "episodeIndex", 0)
	position := hongguoAccountInt64(progress, "position", 0)
	duration := hongguoAccountInt64(progress, "duration", 0)
	episodeCount := hongguoAccountInt(progress, "episodeCount", 0)
	updatedAt := hongguoAccountInt64(progress, "updatedAt", 0)
	if position < 0 {
		position = 0
	}
	if duration < 0 {
		duration = 0
	}
	rate := "0"
	if duration > 0 {
		value := float64(position) / float64(duration)
		if value < 0 {
			value = 0
		}
		if value > 1 {
			value = 1
		}
		rate = strconv.FormatFloat(value, 'g', -1, 64)
	}
	entry := map[string]any{
		"book_id":                          seriesID,
		"item_id":                          episodeID,
		"vid_index":                        episodeIndex + 1,
		"current_play_time":                position,
		"current_total_time":               duration,
		"episode_count":                    episodeCount,
		"read_timestamp_ms":                updatedAt,
		"book_type":                        2,
		"progress_rate":                    rate,
		"player_cumulative_total_duration": position,
	}
	body, err := json.Marshal(map[string]any{"books": []any{entry}, "write_mode": 1})
	if err != nil {
		return nil, err
	}
	if _, err := downloader.hongguoAccountCloud(ctx, cookie, "/reading/bookapi/read_progress/upload/v1/", nil, body, false); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

func hongguoAccountRowSeriesID(row, video map[string]any) string {
	seriesID := mapString(video, "series_id")
	if seriesID == "" {
		seriesID = mapString(row, "series_id")
	}
	if seriesID == "" {
		seriesID = mapString(row, "book_id")
	}
	return seriesID
}

func (downloader *Downloader) hongguoAccountReservations(ctx context.Context, cookie string, online bool) (map[string]any, error) {
	reply, err := downloader.hongguoAccountCloud(ctx, cookie, "/reading/user/subscribe/list/v0/", map[string]string{
		"offset":               "0",
		"limit":                "20",
		"is_online":            strconv.FormatBool(online),
		"tab_type":             "13",
		"subscribe_order_type": "0",
		"swipe_type":           "0",
		"need_calendar_schema": "false",
		"subscribe_offset":     "0",
	}, nil, false)
	if err != nil {
		return nil, err
	}
	data, _ := reply["data"].(map[string]any)
	if data == nil {
		return nil, errors.New("预约数据格式已变化，请稍后重试")
	}
	raw, present := data["subscribe_items"]
	if !present {
		return nil, errors.New("预约列表格式已变化，请稍后重试")
	}
	if raw == nil {
		return map[string]any{"rows": []any{}}, nil
	}
	items, ok := raw.([]any)
	if !ok {
		return nil, errors.New("预约列表格式已变化，请稍后重试")
	}
	rows := make([]any, 0, len(items))
	for _, item := range items {
		row, _ := item.(map[string]any)
		if row == nil {
			continue
		}
		rows = append(rows, row)
	}
	if online {
		rows = downloader.hongguoAccountReservationBadges(ctx, cookie, rows)
	}
	return map[string]any{"rows": rows}, nil
}

func (downloader *Downloader) hongguoAccountReservationBadges(ctx context.Context, cookie string, rows []any) []any {
	var missing []string
	seen := map[string]bool{}
	for _, item := range rows {
		row, _ := item.(map[string]any)
		if row == nil {
			continue
		}
		video := hongguoAccountFirstMap(row, "subscribe_data", "video_data")
		id := hongguoAccountRowSeriesID(row, video)
		if !hongguoAccountSeriesID.MatchString(id) || seen[id] {
			continue
		}
		if hongguoAccountEpisodeCount(video) == 0 && hongguoAccountEpisodeCount(row) == 0 {
			missing = append(missing, id)
			seen[id] = true
		}
	}
	if len(missing) == 0 {
		return rows
	}
	detailReply, err := downloader.hongguoAccountCloud(ctx, cookie, "/reading/bookapi/multi-detail/v1/", map[string]string{"book_id": strings.Join(missing, ","), "book_type": "2"}, nil, false)
	if err != nil {
		return rows
	}
	details, _ := detailReply["data"].([]any)
	if details == nil {
		return rows
	}
	badges := map[string]string{}
	for _, item := range details {
		row, _ := item.(map[string]any)
		if row == nil {
			continue
		}
		if badge := hongguoAccountEpisodeBadge(row); badge != "" {
			badges[mapString(row, "book_id")] = badge
		}
	}
	if len(badges) == 0 {
		return rows
	}
	out := make([]any, 0, len(rows))
	for _, item := range rows {
		row, _ := item.(map[string]any)
		if row == nil {
			out = append(out, item)
			continue
		}
		video := hongguoAccountFirstMap(row, "subscribe_data", "video_data")
		id := hongguoAccountRowSeriesID(row, video)
		if badge, ok := badges[id]; ok {
			copied := map[string]any{}
			for key, value := range row {
				copied[key] = value
			}
			copied["episode_badge"] = badge
			out = append(out, copied)
			continue
		}
		out = append(out, item)
	}
	return out
}

func (downloader *Downloader) hongguoAccountReserve(ctx context.Context, cookie, seriesID string) (map[string]any, error) {
	if !hongguoAccountReserveID.MatchString(seriesID) {
		return nil, errors.New("预约编号无效")
	}
	id, err := strconv.ParseInt(seriesID, 10, 64)
	if err != nil {
		return nil, errors.New("预约编号无效")
	}
	body, err := json.Marshal(map[string]any{
		"item_id":          id,
		"item_type":        3,
		"op_type":          1,
		"subscribe_source": 0,
	})
	if err != nil {
		return nil, err
	}
	if _, err := downloader.hongguoAccountCloud(ctx, cookie, "/reading/bookapi/search/uncover_subscribe/v1/", nil, body, true); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

const hongguoLoginRewardInfoPath = "/luckycat/novel/v1/task/getLoginRewardInfo"
const hongguoLoginRewardDonePath = "/luckycat/novel/v1/task/done/login_reward"

func hongguoAccountLuckycatCall(ctx context.Context, client *http.Client, deviceID, installID, cookie, path string, params map[string]string, body []byte) (map[string]any, error) {
	versionCode, versionName := "72232", "7.2.2.32"
	if body != nil {
		versionCode, versionName = "73932", "7.3.9.32"
	}
	call := func(playerOnly bool) (map[string]any, error) {
		query := hongguoAccountQuery(deviceID, installID, versionCode, versionName, true)
		for key, value := range params {
			if value != "" {
				query.Set(key, value)
			}
		}
		method := http.MethodGet
		if body != nil {
			method = http.MethodPost
		}
		request, err := http.NewRequestWithContext(ctx, method, strings.TrimRight(hongguoAccountCloudBaseURL, "/")+path+"?"+query.Encode(), bytes.NewReader(body))
		if err != nil {
			return nil, err
		}
		request.Header.Set("User-Agent", hongguoAppUserAgent)
		request.Header.Set("Accept", "application/json")
		if cookie != "" {
			request.Header.Set("Cookie", cookie)
		}
		if body != nil {
			request.Header.Set("Content-Type", "application/json; charset=utf-8")
		}
		opts := hongguoSignOptions{Identity: hongguoSignerIdentity{DeviceID: deviceID, InstallID: installID}}
		if playerOnly {
			opts.PlayerOnly = true
		}
		hongguoSignRequest(request, body, time.Now(), opts)
		callCtx, cancel := context.WithTimeout(ctx, hongguoAccountRequestTimeout)
		defer cancel()
		response, err := client.Do(request.WithContext(callCtx))
		if err != nil {
			return nil, hongguoAccountTransportError(err)
		}
		return hongguoAccountReadJSON(response)
	}
	result, err := call(false)
	if errors.Is(err, errHongguoAccountEmptyBody) {
		return call(true)
	}
	return result, err
}

func (downloader *Downloader) hongguoAccountLuckycat(ctx context.Context, cookie, path string, params map[string]string, body []byte) (map[string]any, error) {
	deviceID, installID, err := downloader.hongguoAccountDevice(ctx)
	if err != nil {
		return nil, err
	}
	return hongguoAccountLuckycatCall(ctx, downloader.client, deviceID, installID, cookie, path, params, body)
}

func hongguoLoginRewardExtra(nodeIndex int) (string, error) {
	raw, err := json.Marshal(map[string]any{"cur_node_index": nodeIndex})
	if err != nil {
		return "", err
	}
	return string(raw), nil
}

func (downloader *Downloader) hongguoAccountLoginRewardInfo(ctx context.Context, cookie string) (map[string]any, error) {
	extra, err := hongguoLoginRewardExtra(0)
	if err != nil {
		return nil, err
	}
	reply, err := downloader.hongguoAccountLuckycat(ctx, cookie, hongguoLoginRewardInfoPath, map[string]string{"271_extra_info": extra}, nil)
	if err != nil {
		return nil, err
	}
	if hongguoAccountInt(reply, "err_no", -1) != 0 {
		tips := mapString(reply, "err_tips")
		if tips == "" {
			tips = "登入奖励接口不可用"
		}
		return nil, fmt.Errorf("%s（错误码 %d）", tips, hongguoAccountInt(reply, "err_no", -1))
	}
	data, _ := reply["data"].(map[string]any)
	if data == nil {
		return nil, errors.New("登入奖励状态为空")
	}
	return map[string]any{
		"status":          mapString(data, "status"),
		"title":           mapString(data, "title"),
		"buttonTag":       mapString(data, "button_tag"),
		"rewardType":      mapString(data, "reward_type"),
		"rewardAmount":    hongguoAccountInt(data, "reward_amount", 0),
		"cooldownEndTime": hongguoAccountInt64(data, "cooldown_end_time", 0),
	}, nil
}

func (downloader *Downloader) hongguoAccountClaimLoginReward(ctx context.Context, cookie string) (map[string]any, error) {
	body, err := json.Marshal(map[string]any{
		"271_extra_info": map[string]any{"cur_node_index": 0},
		"growth_novel_base": map[string]any{
			"path":      hongguoLoginRewardDonePath,
			"timestamp": time.Now().UnixMilli(),
		},
	})
	if err != nil {
		return nil, err
	}
	reply, err := downloader.hongguoAccountLuckycat(ctx, cookie, hongguoLoginRewardDonePath, nil, body)
	if err != nil {
		return nil, err
	}
	errNo := hongguoAccountInt(reply, "err_no", -1)
	data, _ := reply["data"].(map[string]any)
	if data == nil {
		data = map[string]any{}
	}
	result := map[string]any{
		"claimed":         errNo == 0 && hongguoAccountInt(data, "reward_amount", 0) > 0,
		"errNo":           errNo,
		"errTips":         mapString(reply, "err_tips"),
		"rewardType":      mapString(data, "reward_type"),
		"rewardAmount":    hongguoAccountInt(data, "reward_amount", 0),
		"toast":           mapString(data, "toast"),
		"toastText":       mapString(data, "toast_text"),
		"cooldownEndTime": hongguoAccountInt64(data, "cooldown_end_time", 0),
	}
	return result, nil
}

func (downloader *Downloader) hongguoAccountClaimDailyCoins(ctx context.Context, cookie string) (map[string]any, error) {
	info, err := downloader.hongguoAccountLoginRewardInfo(ctx, cookie)
	if err != nil {
		return map[string]any{"claimed": false, "reason": "info-failed"}, nil
	}
	status := mapString(info, "status")
	rewardType := strings.ToLower(mapString(info, "rewardType"))
	if !strings.EqualFold(status, "AVAILABLE") || (rewardType != "" && rewardType != "gold" && rewardType != "rmb" && rewardType != "rmb_cash") {
		return map[string]any{"claimed": false, "status": status, "reason": "not-available"}, nil
	}
	claimed, err := downloader.hongguoAccountClaimLoginReward(ctx, cookie)
	if err != nil {
		return map[string]any{"claimed": false, "status": status, "reason": "claim-failed"}, nil
	}
	claimed["status"] = status
	return claimed, nil
}
