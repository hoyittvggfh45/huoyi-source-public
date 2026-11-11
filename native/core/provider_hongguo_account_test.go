package core

import (
	"bytes"
	"compress/gzip"
	"context"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"strconv"
	"strings"
	"testing"
	"time"
)

func hongguoAccountFixture(t *testing.T, handler func(request *http.Request) (*http.Response, error)) *Downloader {
	t.Helper()
	d := sourceFixtureDownloader(t, handler)
	d.cfg.Retries = 1
	client := d.hongguoClient()
	client.state.DeviceID, client.state.InstallID, client.state.Registered = "123456789", "987654321", true
	return d
}

func hongguoAccountJSONResponse(request *http.Request, body string) *http.Response {
	response := sourceFixtureResponse(request, http.StatusOK, body)
	response.Header.Set("Content-Type", "application/json")
	return response
}

func TestHongguoAccountMix(t *testing.T) {
	if got := hongguoAccountMix("24"); got != "3731" {
		t.Fatal("mix 24 mismatch", got)
	}
	if got := hongguoAccountMix("+86 138"); got != "2e3d332534363d" {
		t.Fatal("mix +86 138 mismatch", got)
	}
	if got := hongguoAccountMix(""); got != "" {
		t.Fatal("mix empty mismatch", got)
	}
	if got := hongguoAccountMix("中"); got != "e1bda8" {
		t.Fatal("mix multibyte mismatch", got)
	}
	if got := hongguoAccountMix("\x05\x04"); got != "01" {
		t.Fatal("mix single hex digit mismatch", got)
	}
}

func TestHongguoAccountFormEncode(t *testing.T) {
	encoded := hongguoAccountFormEncode([]hongguoAccountFormField{
		{key: "aid", value: "8662"},
		{key: "app_name", value: "novelread"},
		{key: "mobile", value: "+86 13800138000"},
		{key: "empty", value: ""},
	})
	if encoded != "aid=8662&app_name=novelread&mobile=%2B86%2013800138000" {
		t.Fatal("form encode mismatch", encoded)
	}
	if got := hongguoAccountFormEncode([]hongguoAccountFormField{{key: "v", value: "a~b c"}}); got != "v=a~b%20c" {
		t.Fatal("form escape mismatch", got)
	}
}

func TestHongguoAccountQrCodeExpireClamp(t *testing.T) {
	now := time.Now().Unix()
	cases := []struct {
		expire int64
		want   int
	}{
		{180, 180},
		{30, 30},
		{-5, 0},
		{now + 300, 300},
		{now + 900, 600},
		{now - 10, 0},
	}
	for _, item := range cases {
		d := hongguoAccountFixture(t, func(request *http.Request) (*http.Response, error) {
			if !strings.Contains(request.URL.Path, "/passport/web/get_qrcode/") {
				t.Fatal("unexpected path", request.URL.Path)
			}
			if request.URL.Query().Get("aid") != "513755" {
				t.Fatal("qr query aid mismatch", request.URL.RawQuery)
			}
			body := `{"message":"success","data":{"token":"tok1","qrcode":"data:image/png;base64,` + base64.StdEncoding.EncodeToString([]byte("image")) + `","expire_time":` + strconv.FormatInt(item.expire, 10) + `}}`
			return hongguoAccountJSONResponse(request, body), nil
		})
		result, err := d.hongguoAccountQrCode(context.Background())
		if err != nil {
			t.Fatal(err)
		}
		image, err := base64.StdEncoding.DecodeString(result["imageBase64"].(string))
		if err != nil || string(image) != "image" {
			t.Fatal("qr image mismatch", result["imageBase64"])
		}
		if result["expiresInSeconds"].(int) != item.want {
			t.Fatal("qr expire mismatch", item.expire, result["expiresInSeconds"])
		}
	}
}

func TestHongguoAccountQrPollStates(t *testing.T) {
	statuses := []struct {
		status string
		want   string
	}{
		{"1", "waiting"},
		{"2", "scanned"},
		{"5", "expired"},
		{"expired", "expired"},
		{"9", "waiting"},
	}
	for _, item := range statuses {
		d := hongguoAccountFixture(t, func(request *http.Request) (*http.Response, error) {
			switch {
			case strings.Contains(request.URL.Path, "/passport/web/get_qrcode/"):
				return hongguoAccountJSONResponse(request, `{"message":"success","data":{"token":"tok1","qrcode":"data:image/png;base64,aW1hZ2U=","expire_time":180}}`), nil
			case strings.Contains(request.URL.Path, "/passport/web/check_qrconnect/"):
				return hongguoAccountJSONResponse(request, `{"message":"success","data":{"status":"`+item.status+`"}}`), nil
			default:
				t.Fatal("unexpected path", request.URL.Path)
				return nil, nil
			}
		})
		if _, err := d.hongguoAccountQrCode(context.Background()); err != nil {
			t.Fatal(err)
		}
		result, err := d.hongguoAccountQrPoll(context.Background())
		if err != nil {
			t.Fatal(err)
		}
		if result["result"].(string) != item.want {
			t.Fatal("poll state mismatch", item.status, result["result"])
		}
	}
}

func TestHongguoAccountQrPollWithoutCode(t *testing.T) {
	d := hongguoAccountFixture(t, func(request *http.Request) (*http.Response, error) {
		return hongguoAccountJSONResponse(request, `{}`), nil
	})
	if _, err := d.hongguoAccountQrPoll(context.Background()); err == nil || !strings.Contains(err.Error(), "请先获取二维码") {
		t.Fatal("expected qr first error", err)
	}
}

func TestHongguoAccountQrConfirmRedirect(t *testing.T) {
	d := hongguoAccountFixture(t, func(request *http.Request) (*http.Response, error) {
		switch request.URL.Path {
		case "/passport/web/get_qrcode/":
			return hongguoAccountJSONResponse(request, `{"message":"success","data":{"token":"tok1","qrcode":"data:image/png;base64,aW1hZ2U=","expire_time":180}}`), nil
		case "/passport/web/check_qrconnect/":
			return hongguoAccountJSONResponse(request, `{"message":"success","data":{"status":"3","redirect_url":"/auth/a"}}`), nil
		case "/auth/a":
			response := sourceFixtureResponse(request, http.StatusFound, "")
			response.Header.Set("Location", "/auth/b")
			return response, nil
		case "/auth/b":
			response := hongguoAccountJSONResponse(request, `ok`)
			response.Header.Set("Set-Cookie", "sessionid=abc; Path=/; Secure; HttpOnly")
			return response, nil
		case "/passport/account/info/v2/":
			return hongguoAccountJSONResponse(request, `{"message":"success","data":{"user_id":"u1"}}`), nil
		default:
			t.Fatal("unexpected path", request.URL.Path)
			return nil, nil
		}
	})
	if _, err := d.hongguoAccountQrCode(context.Background()); err != nil {
		t.Fatal(err)
	}
	result, err := d.hongguoAccountQrPoll(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if result["result"].(string) != "confirmed" {
		t.Fatal("expected confirmed", result)
	}
	credentials, err := d.hongguoAccountQrConfirm(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(credentials["cookie"].(string), "sessionid=abc") {
		t.Fatal("confirm cookie mismatch", credentials["cookie"])
	}
}

func TestHongguoAccountQrConfirmRejectsForeignRedirect(t *testing.T) {
	d := hongguoAccountFixture(t, func(request *http.Request) (*http.Response, error) {
		switch {
		case strings.Contains(request.URL.Path, "/passport/web/get_qrcode/"):
			return hongguoAccountJSONResponse(request, `{"message":"success","data":{"token":"tok1","qrcode":"data:image/png;base64,aW1hZ2U=","expire_time":180}}`), nil
		case strings.Contains(request.URL.Path, "/passport/web/check_qrconnect/"):
			return hongguoAccountJSONResponse(request, `{"message":"success","data":{"status":"confirmed","redirect_url":"https://example.com/login"}}`), nil
		default:
			t.Fatal("unexpected path", request.URL.Path)
			return nil, nil
		}
	})
	if _, err := d.hongguoAccountQrCode(context.Background()); err != nil {
		t.Fatal(err)
	}
	if _, err := d.hongguoAccountQrPoll(context.Background()); err == nil || !strings.Contains(err.Error(), "不支持的站点") {
		t.Fatal("expected foreign redirect error", err)
	}
}

func hongguoAccountSendFixture(t *testing.T, verify func(request *http.Request) (*http.Response, error)) (*Downloader, *[]string) {
	t.Helper()
	var paths []string
	d := hongguoAccountFixture(t, func(request *http.Request) (*http.Response, error) {
		paths = append(paths, request.Method+" "+request.URL.Path)
		if strings.Contains(request.URL.Path, "/passport/mobile/send_code/") {
			if request.Method != http.MethodGet {
				t.Fatal("send_code must be GET", request.Method)
			}
			if request.Header.Get("Cookie") != "" {
				t.Fatal("passport must not send Cookie")
			}
			if request.URL.Query().Get("device_id") != "" || request.URL.Query().Get("iid") != "" {
				t.Fatal("passport query must not carry device ids", request.URL.RawQuery)
			}
			if request.URL.Query().Get("version_code") != "73932" {
				t.Fatal("passport version mismatch", request.URL.RawQuery)
			}
			return hongguoAccountJSONResponse(request, `{"message":"success","data":{"mobile":"138****8000","mobile_ticket":"tick1","retry_time":60}}`), nil
		}
		return verify(request)
	})
	return d, &paths
}

func TestHongguoAccountSendSms(t *testing.T) {
	d, _ := hongguoAccountSendFixture(t, func(request *http.Request) (*http.Response, error) {
		t.Fatal("unexpected path", request.URL.Path)
		return nil, nil
	})
	result, err := d.hongguoAccountSendSms(context.Background(), "13800138000")
	if err != nil {
		t.Fatal(err)
	}
	if result["maskedMobile"].(string) != "138****8000" || result["retrySeconds"].(int) != 60 {
		t.Fatal("send sms mismatch", result)
	}
}

func TestHongguoAccountSendSmsRateLimited(t *testing.T) {
	d := hongguoAccountFixture(t, func(request *http.Request) (*http.Response, error) {
		if !strings.Contains(request.URL.Path, "/passport/mobile/send_code/") {
			t.Fatal("unexpected path", request.URL.Path)
			return nil, nil
		}
		if request.Method != http.MethodGet {
			t.Fatal("send_code must be GET", request.Method)
			return nil, nil
		}
		return hongguoAccountJSONResponse(request, `{"message":"fail","data":{"error_code":7}}`), nil
	})
	_, err := d.hongguoAccountSendSms(context.Background(), "13800138000")
	if err == nil {
		t.Fatal("rate limited send must fail")
	}
	if !strings.Contains(err.Error(), "错误码 7") || !strings.Contains(err.Error(), "60 秒") {
		t.Fatal("rate limit message mismatch", err)
	}
}

func TestHongguoAccountVerifyFirstAttempt(t *testing.T) {
	d, paths := hongguoAccountSendFixture(t, func(request *http.Request) (*http.Response, error) {
		if !strings.Contains(request.URL.Path, "/passport/mobile/sms_login/") {
			t.Fatal("unexpected verify path", request.URL.Path)
		}
		response := hongguoAccountJSONResponse(request, `{"message":"success","data":{}}`)
		response.Header.Set("Set-Cookie", "sessionid=s1; Path=/")
		return response, nil
	})
	if _, err := d.hongguoAccountSendSms(context.Background(), "13800138000"); err != nil {
		t.Fatal(err)
	}
	result, err := d.hongguoAccountVerifySms(context.Background(), "13800138000", "123456")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(result["cookie"].(string), "sessionid=s1") {
		t.Fatal("verify cookie mismatch", result["cookie"])
	}
	if result["deviceId"].(string) != "123456789" || result["installId"].(string) != "987654321" {
		t.Fatal("verify device mismatch", result)
	}
	if len(*paths) != 2 || (*paths)[1] != "POST /passport/mobile/sms_login/" {
		t.Fatal("verify attempt order mismatch", *paths)
	}
}

func TestHongguoAccountVerifyFallbackTo1203(t *testing.T) {
	var bodies []string
	d, paths := hongguoAccountSendFixture(t, func(request *http.Request) (*http.Response, error) {
		raw, _ := io.ReadAll(request.Body)
		bodies = append(bodies, string(raw))
		switch {
		case strings.HasSuffix(request.URL.Path, "/passport/mobile/sms_login/"):
			return hongguoAccountJSONResponse(request, `{"message":"success","data":{"error_code":0}}`), nil
		case strings.HasSuffix(request.URL.Path, "/passport/mobile/sms_login_only/"):
			return hongguoAccountJSONResponse(request, `{"message":"success","data":{"error_code":1,"mobile_ticket":"tick2"}}`), nil
		case strings.HasSuffix(request.URL.Path, "/passport/mobile/sms_login_continue/"):
			return hongguoAccountJSONResponse(request, `{"message":"success","data":{"error_code":1203,"description":"验证码过期"}}`), nil
		default:
			t.Fatal("unexpected verify path", request.URL.Path)
			return nil, nil
		}
	})
	if _, err := d.hongguoAccountSendSms(context.Background(), "13800138000"); err != nil {
		t.Fatal(err)
	}
	if _, err := d.hongguoAccountVerifySms(context.Background(), "13800138000", "123456"); err == nil || !strings.Contains(err.Error(), "验证码过期") {
		t.Fatal("expected 1203 error", err)
	}
	if len(*paths) != 4 {
		t.Fatal("expected send plus 3 attempts", *paths)
	}
	if !strings.Contains(bodies[2], "mobile_ticket=tick2") {
		t.Fatal("ticket must refresh between attempts", bodies)
	}
	if _, err := d.hongguoAccountVerifySms(context.Background(), "13800138000", "123456"); err == nil || !strings.Contains(err.Error(), "会话已失效") {
		t.Fatal("expected expired session error", err)
	}
}

func TestHongguoAccountVerifyAllExpired(t *testing.T) {
	d, _ := hongguoAccountSendFixture(t, func(request *http.Request) (*http.Response, error) {
		return hongguoAccountJSONResponse(request, `{"message":"success","data":{"error_code":1}}`), nil
	})
	if _, err := d.hongguoAccountSendSms(context.Background(), "13800138000"); err != nil {
		t.Fatal(err)
	}
	if _, err := d.hongguoAccountVerifySms(context.Background(), "13800138000", "123456"); err == nil || !strings.Contains(err.Error(), "会话过期，请重新登录（错误码 1）") {
		t.Fatal("expected recorded session expired error", err)
	}
}

func TestHongguoAccountVerifyRetryCode(t *testing.T) {
	d, _ := hongguoAccountSendFixture(t, func(request *http.Request) (*http.Response, error) {
		return hongguoAccountJSONResponse(request, `{"message":"success","data":{"error_code":1102,"description":"验证码错误"}}`), nil
	})
	if _, err := d.hongguoAccountSendSms(context.Background(), "13800138000"); err != nil {
		t.Fatal(err)
	}
	if _, err := d.hongguoAccountVerifySms(context.Background(), "13800138000", "123456"); err == nil || !strings.Contains(err.Error(), "验证码错误（错误码 1102）") {
		t.Fatal("expected 1102 error", err)
	}
}

func hongguoAccountCloudFixture(t *testing.T, handler func(request *http.Request) (*http.Response, error)) *Downloader {
	t.Helper()
	return hongguoAccountFixture(t, func(request *http.Request) (*http.Response, error) {
		if request.Header.Get("Cookie") != "sessionid=s1" {
			t.Fatal("cloud must carry credential cookie", request.Header.Get("Cookie"))
		}
		return handler(request)
	})
}

func TestHongguoAccountProfile(t *testing.T) {
	d := hongguoAccountCloudFixture(t, func(request *http.Request) (*http.Response, error) {
		if !strings.Contains(request.URL.Path, "/reading/user/info/v1/") {
			t.Fatal("unexpected path", request.URL.Path)
		}
		if request.URL.Query().Get("version_code") != "72232" {
			t.Fatal("no-body cloud version must be 72232", request.URL.RawQuery)
		}
		return hongguoAccountJSONResponse(request, `{"code":0,"data":{"biz_user_id":"u1","user_name":"小明"}}`), nil
	})
	result, err := d.hongguoAccountProfile(context.Background(), "sessionid=s1")
	if err != nil {
		t.Fatal(err)
	}
	profile := result["profile"].(map[string]any)
	if mapString(profile, "biz_user_id") != "u1" || mapString(profile, "user_name") != "小明" {
		t.Fatal("profile mismatch", profile)
	}
}

func TestHongguoAccountProfileErrors(t *testing.T) {
	emptyBody := hongguoAccountCloudFixture(t, func(request *http.Request) (*http.Response, error) {
		return sourceFixtureResponse(request, http.StatusOK, ""), nil
	})
	if _, err := emptyBody.hongguoAccountProfile(context.Background(), "sessionid=s1"); err == nil || !strings.Contains(err.Error(), "账号资料接口返回空响应") {
		t.Fatal("expected staged empty body error", err)
	}
	badCode := hongguoAccountCloudFixture(t, func(request *http.Request) (*http.Response, error) {
		return hongguoAccountJSONResponse(request, `{"code":5,"data":{}}`), nil
	})
	if _, err := badCode.hongguoAccountProfile(context.Background(), "sessionid=s1"); err == nil || !strings.Contains(err.Error(), "账号接口不可用（错误码 5）") {
		t.Fatal("expected code error", err)
	}
}

func TestHongguoAccountFavorites(t *testing.T) {
	d := hongguoAccountCloudFixture(t, func(request *http.Request) (*http.Response, error) {
		return hongguoAccountJSONResponse(request, `{"code":0,"data":{"video_shelf_info":[{"series_id":"111","series_title":"剧一"}]}}`), nil
	})
	result, err := d.hongguoAccountFavorites(context.Background(), "sessionid=s1")
	if err != nil {
		t.Fatal(err)
	}
	rows := result["rows"].([]any)
	if len(rows) != 1 {
		t.Fatal("favorites rows mismatch", rows)
	}
	nullRows := hongguoAccountCloudFixture(t, func(request *http.Request) (*http.Response, error) {
		return hongguoAccountJSONResponse(request, `{"code":0,"data":{"video_shelf_info":null}}`), nil
	})
	empty, err := nullRows.hongguoAccountFavorites(context.Background(), "sessionid=s1")
	if err != nil || len(empty["rows"].([]any)) != 0 {
		t.Fatal("null shelf must be empty", empty, err)
	}
}

func TestHongguoAccountSetFavoriteBodies(t *testing.T) {
	var bodies []string
	d := hongguoAccountCloudFixture(t, func(request *http.Request) (*http.Response, error) {
		if !strings.Contains(request.URL.Path, "/reading/bookapi/bookshelf/video/update/v1/") {
			t.Fatal("unexpected path", request.URL.Path)
		}
		if request.URL.Query().Get("version_code") != "73932" {
			t.Fatal("body cloud version must be 73932", request.URL.RawQuery)
		}
		raw, _ := io.ReadAll(request.Body)
		bodies = append(bodies, string(raw))
		return hongguoAccountJSONResponse(request, `{"code":0,"data":{}}`), nil
	})
	if _, err := d.hongguoAccountSetFavorite(context.Background(), "sessionid=s1", "111", true); err != nil {
		t.Fatal(err)
	}
	if _, err := d.hongguoAccountSetFavorite(context.Background(), "sessionid=s1", "111", false); err != nil {
		t.Fatal(err)
	}
	if _, err := d.hongguoAccountSetFavorite(context.Background(), "sessionid=s1", "abc", true); err == nil || !strings.Contains(err.Error(), "剧集编号无效") {
		t.Fatal("expected invalid series error", err)
	}
	var addBody, removeBody map[string]any
	if err := json.Unmarshal([]byte(bodies[0]), &addBody); err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal([]byte(bodies[1]), &removeBody); err != nil {
		t.Fatal(err)
	}
	addEntry := addBody["update_bookshelf_video_list"].([]any)[0].(map[string]any)
	if addEntry["video_shelf_operate_type"].(float64) != 0 || addBody["shark_extra"] == nil {
		t.Fatal("add body mismatch", addBody)
	}
	removeEntry := removeBody["update_bookshelf_video_list"].([]any)[0].(map[string]any)
	if removeEntry["video_shelf_operate_type"].(float64) != 1 || removeEntry["group_name"].(string) != "" || removeBody["shark_extra"] != nil {
		t.Fatal("remove body mismatch", removeBody)
	}
}

func TestHongguoAccountHistoryMerge(t *testing.T) {
	var detailQuery string
	d := hongguoAccountCloudFixture(t, func(request *http.Request) (*http.Response, error) {
		switch {
		case strings.Contains(request.URL.Path, "/reading/bookapi/read_progress/list/v1/"):
			return hongguoAccountJSONResponse(request, `{"code":0,"data":{"video_data":[{"series_id":"111","vid":"222","vid_index":3,"current_play_time":120,"current_total_time":600,"last_watch_time":1700000000000,"episode_count":0},{"series_id":"333","vid":"444","vid_index":1,"current_play_time":10,"current_total_time":100,"last_watch_time":1700000001000,"episode_count":0}]}}`), nil
		case strings.Contains(request.URL.Path, "/reading/bookapi/multi-detail/v1/"):
			detailQuery = request.URL.Query().Get("book_id")
			return hongguoAccountJSONResponse(request, `{"code":0,"data":[{"book_id":"111","book_name":"剧一","thumb_url":"https://cover","abstract":"简介","episode_cnt":24}]}`), nil
		default:
			t.Fatal("unexpected path", request.URL.Path)
			return nil, nil
		}
	})
	result, err := d.hongguoAccountHistory(context.Background(), "sessionid=s1")
	if err != nil {
		t.Fatal(err)
	}
	if detailQuery != "111,333" {
		t.Fatal("detail query mismatch", detailQuery)
	}
	rows := result["rows"].([]any)
	if len(rows) != 2 {
		t.Fatal("history rows mismatch", rows)
	}
	first := rows[0].(map[string]any)
	if mapString(first, "title") != "剧一" || mapString(first, "thumb_url") != "https://cover" || hongguoAccountInt(first, "episode_count", 0) != 24 {
		t.Fatal("history merge mismatch", first)
	}
	second := rows[1].(map[string]any)
	if mapString(second, "title") != "" {
		t.Fatal("missing detail must leave title empty", second)
	}
}

func TestHongguoAccountUploadBody(t *testing.T) {
	var body string
	d := hongguoAccountCloudFixture(t, func(request *http.Request) (*http.Response, error) {
		raw, _ := io.ReadAll(request.Body)
		body = string(raw)
		return hongguoAccountJSONResponse(request, `{"code":0,"data":{}}`), nil
	})
	progress := map[string]any{
		"seriesId": "111", "episodeId": "222", "episodeIndex": 2,
		"position": 300, "duration": 600, "updatedAt": 1700000000000, "episodeCount": 24,
	}
	if _, err := d.hongguoAccountUploadProgress(context.Background(), "sessionid=s1", progress); err != nil {
		t.Fatal(err)
	}
	var decoded map[string]any
	if err := json.Unmarshal([]byte(body), &decoded); err != nil {
		t.Fatal(err)
	}
	if decoded["write_mode"].(float64) != 1 {
		t.Fatal("write mode mismatch", decoded)
	}
	entry := decoded["books"].([]any)[0].(map[string]any)
	if entry["vid_index"].(float64) != 3 || entry["progress_rate"].(string) != "0.5" || entry["book_type"].(float64) != 2 {
		t.Fatal("upload entry mismatch", entry)
	}
	if _, err := d.hongguoAccountUploadProgress(context.Background(), "sessionid=s1", map[string]any{"seriesId": "x", "episodeId": "222"}); err == nil || !strings.Contains(err.Error(), "剧集编号无效") {
		t.Fatal("expected invalid id error", err)
	}
}

func TestHongguoAccountReservationsBadgeMerge(t *testing.T) {
	var detailCalls int
	d := hongguoAccountCloudFixture(t, func(request *http.Request) (*http.Response, error) {
		switch {
		case strings.Contains(request.URL.Path, "/reading/user/subscribe/list/v0/"):
			return hongguoAccountJSONResponse(request, `{"code":0,"data":{"subscribe_items":[{"series_id":"111","series_title":"剧一","subscribe_data":{"series_id":"111"}},{"series_id":"333","series_title":"剧二","subscribe_data":{"series_id":"333","episode_cnt":12}}]}}`), nil
		case strings.Contains(request.URL.Path, "/reading/bookapi/multi-detail/v1/"):
			detailCalls++
			return hongguoAccountJSONResponse(request, `{"code":0,"data":[{"book_id":"111","episode_cnt":24}]}`), nil
		default:
			t.Fatal("unexpected path", request.URL.Path)
			return nil, nil
		}
	})
	result, err := d.hongguoAccountReservations(context.Background(), "sessionid=s1", true)
	if err != nil {
		t.Fatal(err)
	}
	if detailCalls != 1 {
		t.Fatal("expected one detail call", detailCalls)
	}
	rows := result["rows"].([]any)
	if len(rows) != 2 || mapString(rows[0].(map[string]any), "episode_badge") != "全 24 集" {
		t.Fatal("reservation badge mismatch", rows)
	}
	if _, has := rows[1].(map[string]any)["episode_badge"]; has {
		t.Fatal("row with count must not gain badge", rows[1])
	}
}

func TestHongguoAccountReservationsDetailFailureKeepsList(t *testing.T) {
	d := hongguoAccountCloudFixture(t, func(request *http.Request) (*http.Response, error) {
		switch {
		case strings.Contains(request.URL.Path, "/reading/user/subscribe/list/v0/"):
			return hongguoAccountJSONResponse(request, `{"code":0,"data":{"subscribe_items":[{"series_id":"111","series_title":"剧一"}]}}`), nil
		case strings.Contains(request.URL.Path, "/reading/bookapi/multi-detail/v1/"):
			return sourceFixtureResponse(request, http.StatusInternalServerError, "boom"), nil
		default:
			t.Fatal("unexpected path", request.URL.Path)
			return nil, nil
		}
	})
	result, err := d.hongguoAccountReservations(context.Background(), "sessionid=s1", true)
	if err != nil {
		t.Fatal(err)
	}
	if len(result["rows"].([]any)) != 1 {
		t.Fatal("detail failure must not hide list", result)
	}
}

func TestHongguoAccountReserveGzip(t *testing.T) {
	var encoding, rawBody string
	d := hongguoAccountCloudFixture(t, func(request *http.Request) (*http.Response, error) {
		encoding = request.Header.Get("Content-Encoding")
		raw, _ := io.ReadAll(request.Body)
		rawBody = string(raw)
		return hongguoAccountJSONResponse(request, `{"code":0,"data":{}}`), nil
	})
	if _, err := d.hongguoAccountReserve(context.Background(), "sessionid=s1", "123456"); err != nil {
		t.Fatal(err)
	}
	if encoding != "gzip" {
		t.Fatal("reserve must gzip body", encoding)
	}
	reader, err := gzip.NewReader(bytes.NewReader([]byte(rawBody)))
	if err != nil {
		t.Fatal(err)
	}
	decoded, err := io.ReadAll(reader)
	if err != nil {
		t.Fatal(err)
	}
	var body map[string]any
	if err := json.Unmarshal(decoded, &body); err != nil {
		t.Fatal(err)
	}
	if body["item_id"].(float64) != 123456 || body["item_type"].(float64) != 3 || body["op_type"].(float64) != 1 || body["subscribe_source"].(float64) != 0 {
		t.Fatal("reserve body mismatch", body)
	}
	if _, err := d.hongguoAccountReserve(context.Background(), "sessionid=s1", "abc"); err == nil || !strings.Contains(err.Error(), "预约编号无效") {
		t.Fatal("expected invalid reserve id error", err)
	}
}

func TestHongguoAccountLoginRewardInfo(t *testing.T) {
	d := hongguoAccountCloudFixture(t, func(request *http.Request) (*http.Response, error) {
		if !strings.Contains(request.URL.Path, "/luckycat/novel/v1/task/getLoginRewardInfo") {
			t.Fatal("unexpected path", request.URL.Path)
		}
		if request.Method != http.MethodGet {
			t.Fatal("info must be GET", request.Method)
		}
		if request.URL.Query().Get("271_extra_info") != `{"cur_node_index":0}` {
			t.Fatal("info extra mismatch", request.URL.RawQuery)
		}
		if request.URL.Query().Get("version_code") != "72232" {
			t.Fatal("no-body luckycat version must be 72232", request.URL.RawQuery)
		}
		return hongguoAccountJSONResponse(request, `{"err_no":0,"err_tips":"","data":{"status":"AVAILABLE","title":"登录奖励","button_tag":"领取","reward_type":"gold","reward_amount":100,"cooldown_end_time":0}}`), nil
	})
	result, err := d.hongguoAccountLoginRewardInfo(context.Background(), "sessionid=s1")
	if err != nil {
		t.Fatal(err)
	}
	if mapString(result, "status") != "AVAILABLE" || mapString(result, "rewardType") != "gold" || result["rewardAmount"].(int) != 100 {
		t.Fatal("info mismatch", result)
	}
}

func TestHongguoAccountLoginRewardInfoError(t *testing.T) {
	d := hongguoAccountCloudFixture(t, func(request *http.Request) (*http.Response, error) {
		return hongguoAccountJSONResponse(request, `{"err_no":10009,"err_tips":"触发风控","data":{}}`), nil
	})
	if _, err := d.hongguoAccountLoginRewardInfo(context.Background(), "sessionid=s1"); err == nil || !strings.Contains(err.Error(), "错误码 10009") {
		t.Fatal("expected err_no error", err)
	}
}

func TestHongguoAccountClaimDailyCoinsAvailable(t *testing.T) {
	var doneBody string
	var calls int
	d := hongguoAccountCloudFixture(t, func(request *http.Request) (*http.Response, error) {
		calls++
		if strings.Contains(request.URL.Path, "/luckycat/novel/v1/task/getLoginRewardInfo") {
			return hongguoAccountJSONResponse(request, `{"err_no":0,"data":{"status":"AVAILABLE","reward_type":"gold","reward_amount":100}}`), nil
		}
		if !strings.Contains(request.URL.Path, "/luckycat/novel/v1/task/done/login_reward") {
			t.Fatal("unexpected path", request.URL.Path)
		}
		if request.Method != http.MethodPost {
			t.Fatal("done must be POST", request.Method)
		}
		if request.URL.Query().Get("version_code") != "73932" {
			t.Fatal("body luckycat version must be 73932", request.URL.RawQuery)
		}
		raw, _ := io.ReadAll(request.Body)
		doneBody = string(raw)
		return hongguoAccountJSONResponse(request, `{"err_no":0,"err_tips":"","data":{"reward_type":"gold","reward_amount":100,"toast":"x","toast_text":"y","cooldown_end_time":0}}`), nil
	})
	result, err := d.hongguoAccountClaimDailyCoins(context.Background(), "sessionid=s1")
	if err != nil {
		t.Fatal(err)
	}
	if calls != 2 {
		t.Fatal("info then done expected", calls)
	}
	if result["claimed"] != true || mapString(result, "rewardType") != "gold" || result["rewardAmount"].(int) != 100 {
		t.Fatal("claim mismatch", result)
	}
	var body map[string]any
	if err := json.Unmarshal([]byte(doneBody), &body); err != nil {
		t.Fatal(err)
	}
	extra, _ := body["271_extra_info"].(map[string]any)
	if extra["cur_node_index"] != float64(0) {
		t.Fatal("done extra mismatch", doneBody)
	}
	base, _ := body["growth_novel_base"].(map[string]any)
	if base["path"] != "/luckycat/novel/v1/task/done/login_reward" || base["timestamp"] == nil {
		t.Fatal("done base mismatch", doneBody)
	}
}

func TestHongguoAccountClaimDailyCoinsCooldown(t *testing.T) {
	var calls int
	d := hongguoAccountCloudFixture(t, func(request *http.Request) (*http.Response, error) {
		calls++
		return hongguoAccountJSONResponse(request, `{"err_no":0,"data":{"status":"COOLDOWN","reward_type":"gold","reward_amount":100,"cooldown_end_time":1899999999000}}`), nil
	})
	result, err := d.hongguoAccountClaimDailyCoins(context.Background(), "sessionid=s1")
	if err != nil {
		t.Fatal(err)
	}
	if calls != 1 {
		t.Fatal("cooldown must not call done", calls)
	}
	if result["claimed"] != false || mapString(result, "reason") != "not-available" {
		t.Fatal("cooldown mismatch", result)
	}
}

func TestHongguoAccountClaimDailyCoinsAlreadyClaimed(t *testing.T) {
	d := hongguoAccountCloudFixture(t, func(request *http.Request) (*http.Response, error) {
		if strings.Contains(request.URL.Path, "/luckycat/novel/v1/task/getLoginRewardInfo") {
			return hongguoAccountJSONResponse(request, `{"err_no":0,"data":{"status":"AVAILABLE","reward_type":"gold","reward_amount":100}}`), nil
		}
		return hongguoAccountJSONResponse(request, `{"err_no":10001,"err_tips":"今日已领取","data":{}}`), nil
	})
	result, err := d.hongguoAccountClaimDailyCoins(context.Background(), "sessionid=s1")
	if err != nil {
		t.Fatal(err)
	}
	if result["claimed"] != false || result["errNo"].(int) != 10001 {
		t.Fatal("already claimed mismatch", result)
	}
}

func TestHongguoAccountLuckycatEmptyBodyFallback(t *testing.T) {
	var calls int
	var secondMedusa string
	d := hongguoAccountCloudFixture(t, func(request *http.Request) (*http.Response, error) {
		calls++
		if calls == 1 {
			return sourceFixtureResponse(request, http.StatusOK, ""), nil
		}
		secondMedusa = request.Header.Get("X-Medusa")
		return hongguoAccountJSONResponse(request, `{"err_no":0,"data":{"status":"AVAILABLE","reward_type":"gold","reward_amount":0}}`), nil
	})
	result, err := d.hongguoAccountLoginRewardInfo(context.Background(), "sessionid=s1")
	if err != nil {
		t.Fatal(err)
	}
	if calls != 2 {
		t.Fatal("empty body must retry once", calls)
	}
	if secondMedusa != "" {
		t.Fatal("retry must use minimal signature without medusa", secondMedusa)
	}
	if mapString(result, "status") != "AVAILABLE" {
		t.Fatal("fallback info mismatch", result)
	}
}
