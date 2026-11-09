package core

import (
	"context"
	"net/http"
	"strconv"
	"strings"
	"testing"
)

const hongguoRotationModelOK = `{"code":0,"data":{"video_model":{"video_list":[{"main_url":"https://media.example.test/high.mp4","video_meta":{"codec_type":"h264","definition":"1080p"}}],"video_duration":"60"}}}`

func hongguoRotationFixture(t *testing.T, emptyDevices map[string]bool, emptyModelDevices map[string]bool, registerFails bool) (*Downloader, *[]string) {
	var requests []string
	registered := 0
	d := sourceFixtureDownloader(t, func(request *http.Request) (*http.Response, error) {
		if strings.Contains(request.URL.Path, "device_register") {
			registered++
			requests = append(requests, "register")
			if registerFails {
				return sourceFixtureResponse(request, http.StatusOK, `{"device_id":0,"install_id":0}`), nil
			}
			id := strconv.Itoa(1000 + registered)
			return sourceFixtureResponse(request, http.StatusOK, `{"device_id_str":"`+id+`","install_id_str":"`+id+`9"}`), nil
		}
		device := request.URL.Query().Get("device_id")
		requests = append(requests, "model@"+device)
		if emptyDevices[device] {
			return sourceFixtureResponse(request, http.StatusOK, ""), nil
		}
		if emptyModelDevices[device] {
			return sourceFixtureResponse(request, http.StatusOK, `{"code":0,"data":{}}`), nil
		}
		return sourceFixtureResponse(request, http.StatusOK, hongguoRotationModelOK), nil
	})
	d.cfg.Retries = 1
	return d, &requests
}

func TestHongguoAppMediaRotatesOnEmptyBody(t *testing.T) {
	d, requests := hongguoRotationFixture(t, map[string]bool{"7": true}, nil, false)
	client := d.hongguoClient()
	client.state.DeviceID, client.state.InstallID, client.state.Registered = "7", "8", true
	media, err := d.resolveHongguoAppMedia(context.Background(), "12345")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasSuffix(media.URL, "high.mp4") {
		t.Fatal("rotated request did not return media", media)
	}
	if state := d.hongguoCatalogSnapshot(); state.DeviceID != "1001" {
		t.Fatal("device was not rotated", state)
	}
	if d.hongguoPlayerSuspended() {
		t.Fatal("successful rotation must not suspend the player")
	}
	if got := *requests; len(got) != 5 || got[0] != "model@7" || got[1] != "model@7" || got[2] != "model@7" || got[3] != "register" || got[4] != "model@1001" {
		t.Fatal("unexpected request sequence", got)
	}
}

func TestHongguoAppMediaRotatesOnEmptyModel(t *testing.T) {
	d, requests := hongguoRotationFixture(t, nil, map[string]bool{"7": true}, false)
	client := d.hongguoClient()
	client.state.DeviceID, client.state.InstallID, client.state.Registered = "7", "8", true
	if _, err := d.resolveHongguoAppMedia(context.Background(), "12345"); err != nil {
		t.Fatal(err)
	}
	if state := d.hongguoCatalogSnapshot(); state.DeviceID != "1001" {
		t.Fatal("empty model did not rotate the device", state)
	}
	if got := *requests; len(got) != 5 || got[0] != "model@7" || got[1] != "model@7" || got[2] != "model@7" || got[3] != "register" || got[4] != "model@1001" {
		t.Fatal("unexpected request sequence", got)
	}
}

func TestHongguoAppMediaSuspendsOnlyAfterRotationsExhausted(t *testing.T) {
	d, requests := hongguoRotationFixture(t, map[string]bool{"7": true, "1001": true, "1002": true, "1003": true, "1004": true, "1005": true, "1006": true}, nil, false)
	client := d.hongguoClient()
	client.state.DeviceID, client.state.InstallID, client.state.Registered = "7", "8", true
	if _, err := d.resolveHongguoAppMedia(context.Background(), "12345"); err == nil || !strings.Contains(err.Error(), "限流") {
		t.Fatal("exhausted rotation must report rate limiting", err)
	}
	if !d.hongguoPlayerSuspended() {
		t.Fatal("suspension must start only after rotations are exhausted")
	}
	models, registers := 0, 0
	for _, r := range *requests {
		if strings.HasPrefix(r, "model@") {
			models++
		}
		if r == "register" {
			registers++
		}
	}
	if models != 2*(1+2*(1+hongguoDeviceRotations)) || registers != 2*hongguoDeviceRotations {
		t.Fatal("unexpected rotation counts", *requests)
	}
}

func TestHongguoAppMediaRegisterFailureDoesNotStream(t *testing.T) {
	d, requests := hongguoRotationFixture(t, nil, nil, true)
	client := d.hongguoClient()
	client.state.DeviceID, client.state.InstallID, client.state.Registered = "7", "8", false
	if _, err := d.resolveHongguoAppMedia(context.Background(), "12345"); err == nil {
		t.Fatal("failed registration must not stream silently")
	}
	for _, r := range *requests {
		if strings.HasPrefix(r, "model@") {
			t.Fatal("streamed with an unregistered device", *requests)
		}
	}
}

const hongguoRotationLandpageOK = `{"code":0,"data":{"video_data":[{"series_id_str":"111","series_title":"测试剧"}],"has_more":false,"next_offset":"0","session_id":""}}`

const hongguoRotationDetailOK = `{"code":0,"data":{"video_data":{"series_id_str":"6975711477277655048","series_title":"测试剧","episode_cnt":"1","video_list":[{"vid":"123","vid_index":"1"}]}}}`

func hongguoRotationPageFixture(t *testing.T, emptyDevices map[string]bool, statusDevices map[string]int, bodyDevices map[string]string, registerFails bool) (*Downloader, *[]string) {
	var requests []string
	registered := 0
	d := sourceFixtureDownloader(t, func(request *http.Request) (*http.Response, error) {
		if strings.Contains(request.URL.Path, "device_register") {
			registered++
			requests = append(requests, "register")
			if registerFails {
				return sourceFixtureResponse(request, http.StatusOK, `{"device_id":0,"install_id":0}`), nil
			}
			id := strconv.Itoa(1000 + registered)
			return sourceFixtureResponse(request, http.StatusOK, `{"device_id_str":"`+id+`","install_id_str":"`+id+`9"}`), nil
		}
		device := request.URL.Query().Get("device_id")
		kind := "page"
		if strings.Contains(request.URL.Path, "landpage") {
			kind = "landpage"
		} else if strings.Contains(request.URL.Path, "video_detail") {
			kind = "detail"
		}
		requests = append(requests, kind+"@"+device)
		if body, ok := bodyDevices[device]; ok {
			return sourceFixtureResponse(request, http.StatusOK, body), nil
		}
		if status, ok := statusDevices[device]; ok {
			return sourceFixtureResponse(request, status, ""), nil
		}
		if emptyDevices[device] {
			return sourceFixtureResponse(request, http.StatusOK, ""), nil
		}
		if kind == "detail" {
			return sourceFixtureResponse(request, http.StatusOK, hongguoRotationDetailOK), nil
		}
		return sourceFixtureResponse(request, http.StatusOK, hongguoRotationLandpageOK), nil
	})
	d.cfg.Retries = 1
	return d, &requests
}

func TestHongguoCatalogRotatesOnEmptyBody(t *testing.T) {
	d, requests := hongguoRotationPageFixture(t, map[string]bool{"7": true}, nil, nil, false)
	client := d.hongguoClient()
	client.state.DeviceID, client.state.InstallID, client.state.Registered = "7", "8", true
	dramas, err := d.fetchHongguoAppCatalogCategory(context.Background(), "short_play")
	if err != nil {
		t.Fatal(err)
	}
	if len(dramas) != 1 || dramas[0].SourceID != "111" || dramas[0].Title != "测试剧" {
		t.Fatal("rotated catalog did not return the drama", dramas)
	}
	if state := d.hongguoCatalogSnapshot(); state.DeviceID != "1001" {
		t.Fatal("catalog did not rotate the device", state)
	}
	if got := *requests; len(got) != 3 || got[0] != "landpage@7" || got[1] != "register" || got[2] != "landpage@1001" {
		t.Fatal("unexpected request sequence", got)
	}
}

func TestHongguoCatalogRotatesOnHTTP403(t *testing.T) {
	d, requests := hongguoRotationPageFixture(t, nil, map[string]int{"7": http.StatusForbidden}, nil, false)
	client := d.hongguoClient()
	client.state.DeviceID, client.state.InstallID, client.state.Registered = "7", "8", true
	dramas, err := d.fetchHongguoAppCatalogCategory(context.Background(), "short_play")
	if err == nil || !strings.Contains(err.Error(), "HTTP 403") || !strings.Contains(err.Error(), "后重试") {
		t.Fatal("403 rotation must surface the host backoff", err)
	}
	if len(dramas) != 0 {
		t.Fatal("403 rotation must not return dramas before the backoff window", dramas)
	}
	if state := d.hongguoCatalogSnapshot(); state.DeviceID != "1001" {
		t.Fatal("catalog did not rotate the device on HTTP 403", state)
	}
	if got := *requests; len(got) != 2 || got[0] != "landpage@7" || got[1] != "register" {
		t.Fatal("unexpected request sequence", got)
	}
}

func TestHongguoCatalogDoesNotRotateOnAPICodeError(t *testing.T) {
	d, requests := hongguoRotationPageFixture(t, nil, nil, map[string]string{"7": `{"code":101000,"data":{}}`, "1001": `{"code":101000,"data":{}}`}, false)
	client := d.hongguoClient()
	client.state.DeviceID, client.state.InstallID, client.state.Registered = "7", "8", true
	dramas, err := d.fetchHongguoAppCatalogCategory(context.Background(), "short_play")
	if err == nil {
		t.Fatal("API code error must stay an error")
	}
	if len(dramas) != 0 {
		t.Fatal("API code error must not return dramas", dramas)
	}
	if state := d.hongguoCatalogSnapshot(); state.DeviceID != "7" {
		t.Fatal("API code error must not rotate the device", state)
	}
	if got := *requests; len(got) != 1 || got[0] != "landpage@7" {
		t.Fatal("unexpected request sequence", got)
	}
}

func TestHongguoDetailRotatesOnEmptyBody(t *testing.T) {
	d, requests := hongguoRotationPageFixture(t, map[string]bool{"7": true}, nil, nil, false)
	client := d.hongguoClient()
	client.state.DeviceID, client.state.InstallID, client.state.Registered = "7", "8", true
	entry, err := d.hongguoAppDetail(context.Background(), "6975711477277655048")
	if err != nil {
		t.Fatal(err)
	}
	if len(entry.Chapters) != 1 || entry.Drama.SourceID != "6975711477277655048" {
		t.Fatal("rotated detail did not return chapters", entry)
	}
	if state := d.hongguoCatalogSnapshot(); state.DeviceID != "1001" {
		t.Fatal("detail did not rotate the device", state)
	}
	if d.hongguoPlayerSuspended() {
		t.Fatal("successful rotation must clear the player suspension")
	}
	if got := *requests; len(got) != 3 || got[0] != "detail@7" || got[1] != "register" || got[2] != "detail@1001" {
		t.Fatal("unexpected request sequence", got)
	}
}

func TestHongguoDetailRegisterFailureKeepsOldDevice(t *testing.T) {
	d, requests := hongguoRotationPageFixture(t, map[string]bool{"7": true}, nil, nil, true)
	client := d.hongguoClient()
	client.state.DeviceID, client.state.InstallID, client.state.Registered = "7", "8", true
	if _, err := d.hongguoAppDetail(context.Background(), "6975711477277655048"); err == nil {
		t.Fatal("detail must fail when rotation cannot register")
	}
	if state := d.hongguoCatalogSnapshot(); state.DeviceID != "7" {
		t.Fatal("failed rotation changed the device", state)
	}
	if !d.hongguoDeviceLimited() {
		t.Fatal("empty-body detail failure must mark the device limited")
	}
	if got := *requests; len(got) != 2 || got[0] != "detail@7" || got[1] != "register" {
		t.Fatal("unexpected request sequence", got)
	}
}
