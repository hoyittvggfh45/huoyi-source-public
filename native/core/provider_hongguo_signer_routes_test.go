package core

import (
	"context"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"testing"
	"time"
)

func TestHongguoTicketBranchPicksBranchZero(t *testing.T) {
	now := time.Unix(1790000000, 0)
	bodies := [][]byte{nil, []byte(`{"video_id":"12345"}`), []byte(`{}`)}
	for _, body := range bodies {
		query := url.Values{
			"aid": {"8662"}, "device_id": {"7"}, "iid": {"8"},
			"version_code": {"73532"}, "video_id": {"12345"},
		}
		ticket, found := hongguoPickTicket(query, body, now)
		if !found {
			t.Fatal("ticket loop found no branch 0 offset")
		}
		if ticket < now.UnixMilli() || ticket >= now.UnixMilli()+128 {
			t.Fatal("ticket outside the 128 offset window", ticket)
		}
		trial := url.Values{}
		for key, values := range query {
			trial[key] = append([]string(nil), values...)
		}
		trial.Set("_rticket", strconv.FormatInt(ticket, 10))
		if hongguoTicketBranch(trial.Encode(), body, uint32(now.Unix())) != 0 {
			t.Fatal("picked ticket is not branch 0")
		}
	}
}

func TestHongguoSignRequestFullMorphology(t *testing.T) {
	body := []byte(`{"video_id":"12345"}`)
	request, err := http.NewRequest(http.MethodPost, "https://api5-normal-sinfonlineb.fqnovel.com/novel/player/multi_video_model/v1/?aid=8662&device_id=7&iid=8", strings.NewReader(string(body)))
	if err != nil {
		t.Fatal(err)
	}
	now := time.Unix(1790000000, 0)
	hongguoSignRequest(request, body, now, hongguoSignOptions{Identity: hongguoSignerIdentity{DeviceID: "7", InstallID: "8"}})
	header := request.Header
	for _, key := range []string{"X-Ss-Req-Ticket", "X-Khronos", "X-Gorgon", "X-Argus", "X-Ladon", "X-Helios", "X-Medusa", "X-Ss-Stub", "X-Tt-Request-Tag", "Passport-Sdk-Version", "Sdk-Version", "X-Xs-From-Web", "X-Vc-Bdturing-Sdk-Version"} {
		if header.Get(key) == "" {
			t.Fatal("full morphology missing header", key)
		}
	}
	if header.Get("X-Tt-Request-Tag") != "t=0;n=0" || header.Get("Passport-Sdk-Version") != "50561" || header.Get("Sdk-Version") != "2" || header.Get("X-Xs-From-Web") != "0" || header.Get("X-Vc-Bdturing-Sdk-Version") != "3.7.2.cn" {
		t.Fatal("full morphology header values changed", header)
	}
	if header.Get("X-Tt-Store-Region") != "" || header.Get("X-Tt-Store-Region-Src") != "" {
		t.Fatal("full morphology must not carry store region headers")
	}
	ticket := request.URL.Query().Get("_rticket")
	if ticket == "" || ticket != header.Get("X-Ss-Req-Ticket") {
		t.Fatal("query ticket and header ticket disagree", ticket, header.Get("X-Ss-Req-Ticket"))
	}
	if hongguoTicketBranch(request.URL.RawQuery, body, uint32(now.Unix())) != 0 {
		t.Fatal("signed query is not branch 0")
	}
}

func TestHongguoSignRequestPlaybackMorphology(t *testing.T) {
	body := []byte(`{"video_id":"12345"}`)
	request, err := http.NewRequest(http.MethodPost, "https://api5-normal-sinfonlineb.fqnovel.com/novel/player/multi_video_model/v1/?aid=8662&device_id=7&iid=8", strings.NewReader(string(body)))
	if err != nil {
		t.Fatal(err)
	}
	hongguoSignPlaybackRequest(request, body, time.Unix(1790000000, 0), hongguoSignerIdentity{DeviceID: "7", InstallID: "8"})
	header := request.Header
	for _, key := range []string{"X-Ss-Req-Ticket", "X-Khronos", "X-Gorgon", "X-Argus", "X-Ladon", "X-Helios", "X-Medusa", "X-Ss-Stub", "Sdk-Version", "X-Xs-From-Web"} {
		if header.Get(key) == "" {
			t.Fatal("playback morphology missing header", key)
		}
	}
	for _, key := range []string{"X-Tt-Request-Tag", "Passport-Sdk-Version", "X-Vc-Bdturing-Sdk-Version", "X-Tt-Store-Region", "X-Tt-Store-Region-Src"} {
		if header.Get(key) != "" {
			t.Fatal("playback morphology must not carry header", key)
		}
	}
}

func TestHongguoSignRequestPlayerOnly(t *testing.T) {
	request, err := http.NewRequest(http.MethodGet, "https://api5-normal-sinfonlineb.fqnovel.com/reading/bookapi/video_tab/multi_video_model/v1/?aid=8662&device_id=7&iid=8", nil)
	if err != nil {
		t.Fatal(err)
	}
	hongguoSignRequest(request, nil, time.Unix(1790000000, 0), hongguoSignOptions{PlayerOnly: true, Identity: hongguoSignerIdentity{DeviceID: "7", InstallID: "8"}})
	header := request.Header
	for _, key := range []string{"X-Ss-Req-Ticket", "X-Khronos", "X-Argus", "X-Ladon"} {
		if header.Get(key) == "" {
			t.Fatal("player-only signing missing header", key)
		}
	}
	for _, key := range []string{"X-Gorgon", "X-Helios", "X-Medusa", "X-Ss-Stub", "X-Tt-Request-Tag", "Passport-Sdk-Version", "Sdk-Version", "X-Xs-From-Web"} {
		if header.Get(key) != "" {
			t.Fatal("player-only signing must not carry header", key)
		}
	}
}

func TestHongguoPlaybackRoutesPlan(t *testing.T) {
	routes := newHongguoPlaybackRoutes()
	now := time.Now()
	plan := routes.plan(now, false)
	if len(plan) != 3 || !plan[0].Get || plan[0].Host != hongguoAppBaseURL || plan[1].Get || plan[1].Host != hongguoAppBaseURL || plan[2].Get || plan[2].Host != hongguoOverseaAppBaseURL {
		t.Fatal("fresh routes must plan GET then both POST hosts", plan)
	}
	if got := routes.plan(now, true); len(got) != 1 {
		t.Fatal("speculative plan must probe a single route", got)
	}
	routes.success(plan[1], now)
	plan = routes.plan(now, false)
	if plan[0].Host != hongguoAppBaseURL || plan[0].Get {
		t.Fatal("most recently successful route must come first", plan)
	}
	routes.failed(hongguoPlaybackRoute{Get: true, Host: hongguoAppBaseURL}, now, true)
	routes.failed(hongguoPlaybackRoute{Get: false, Host: hongguoAppBaseURL}, now, false)
	plan = routes.plan(now.Add(6*time.Second), false)
	if len(plan) != 2 || plan[0].Get || plan[1].Get || plan[0].Host != hongguoAppBaseURL || plan[1].Host != hongguoOverseaAppBaseURL {
		t.Fatal("after 6s only the 5s failure must have recovered", plan)
	}
	if routes.exhausted(now) {
		t.Fatal("routes with a healthy host must not be exhausted")
	}
	routes.failed(hongguoPlaybackRoute{Get: false, Host: hongguoAppBaseURL}, now, true)
	routes.failed(hongguoPlaybackRoute{Get: false, Host: hongguoOverseaAppBaseURL}, now, true)
	if !routes.exhausted(now) {
		t.Fatal("all empty and cooling routes must be exhausted")
	}
	plan = routes.plan(now, false)
	if len(plan) != 1 || plan[0].Get || plan[0].Host != hongguoAppBaseURL {
		t.Fatal("exhausted foreground plan must probe the earliest recovering POST route", plan)
	}
	if got := routes.plan(now, true); len(got) != 0 {
		t.Fatal("exhausted speculative plan must probe nothing", got)
	}
}

func TestHongguoModelCacheAndHandover(t *testing.T) {
	d := &Downloader{}
	if _, found := d.hongguoTakeModel("12345"); found {
		t.Fatal("empty handover must miss")
	}
	entry := map[string]any{"video_model": map[string]any{"video_list": []any{map[string]any{"main_url": "https://media.example.test/high.mp4"}}}}
	d.hongguoOfferModel("12345", entry)
	d.hongguoOfferUpcomingModel("12345", entry)
	taken, found := d.hongguoTakeModel("12345")
	if !found || taken == nil {
		t.Fatal("handover offer must be takeable once")
	}
	if _, found := d.hongguoTakeModel("12345"); found {
		t.Fatal("handover take must delete the entry")
	}
	taken, found = d.hongguoTakeUpcomingModel("12345")
	if !found || taken == nil {
		t.Fatal("upcoming offer must be takeable once")
	}
	if _, found := d.hongguoTakeUpcomingModel("12345"); found {
		t.Fatal("upcoming take must delete the entry")
	}
	d.hongguoOfferModel("12345", entry)
	client := d.hongguoClient()
	client.mu.Lock()
	cached := client.handover["12345"]
	cached.savedAt = time.Now().Add(-16 * time.Second)
	client.handover["12345"] = cached
	client.mu.Unlock()
	if _, found := d.hongguoTakeModel("12345"); found {
		t.Fatal("handover older than 15s must expire")
	}
	d.hongguoOfferUpcomingModel("12345", entry)
	client.mu.Lock()
	cached = client.models["12345"]
	cached.savedAt = time.Now().Add(-61 * time.Second)
	client.models["12345"] = cached
	client.mu.Unlock()
	if _, found := d.hongguoTakeUpcomingModel("12345"); found {
		t.Fatal("upcoming model older than 60s must expire")
	}
	for i := 0; i < hongguoModelHandoverMax+2; i++ {
		d.hongguoOfferModel("id"+strconv.Itoa(i), entry)
	}
	client.mu.Lock()
	count := len(client.handover)
	client.mu.Unlock()
	if count != hongguoModelHandoverMax {
		t.Fatal("handover must cap at 6 entries", count)
	}
	big := map[string]any{"video_model": map[string]any{"blob": strings.Repeat("x", hongguoModelMaxBytes)}}
	d.hongguoOfferModel("big", big)
	if _, found := d.hongguoTakeModel("big"); found {
		t.Fatal("oversize model must not be cached")
	}
}

func TestHongguoSelectLadderCapsAt1080(t *testing.T) {
	model := map[string]any{"video_list": []any{
		map[string]any{"main_url": "https://media.test/2160.mp4", "video_meta": map[string]any{"codec_type": "h264", "definition": "2160p"}},
		map[string]any{"main_url": "https://media.test/1080.mp4", "video_meta": map[string]any{"codec_type": "h264", "definition": "1080p"}},
		map[string]any{"main_url": "https://media.test/720.mp4", "video_meta": map[string]any{"codec_type": "h264", "definition": "720p"}},
	}}
	media, compatible, err := hongguoSelectLadder(model, 1080, func(codec string, height int) bool { return hongguoSupportedCodec(codec) })
	if err != nil || media.Quality != 1080 || !strings.HasSuffix(media.URL, "1080.mp4") || compatible {
		t.Fatal("ladder must pick 1080 without the compatibility mark", media, compatible, err)
	}
	only2160 := map[string]any{"video_list": []any{
		map[string]any{"main_url": "https://media.test/2160.mp4", "video_meta": map[string]any{"codec_type": "h264", "definition": "2160p"}},
	}}
	media, compatible, err = hongguoSelectLadder(only2160, 1080, func(codec string, height int) bool { return hongguoSupportedCodec(codec) })
	if err != nil || media.Quality != 2160 || !compatible {
		t.Fatal("above-cap ladder pick must be marked compatible", media, compatible, err)
	}
	onlyBytevc2 := map[string]any{"video_list": []any{
		map[string]any{"main_url": "https://media.test/bvc.mp4", "video_meta": map[string]any{"codec_type": "bytevc2", "definition": "2160p"}},
	}}
	if _, _, err := hongguoSelectLadder(onlyBytevc2, 1080, func(codec string, height int) bool { return hongguoSupportedCodec(codec) }); err == nil {
		t.Fatal("bytevc2-only model must not select")
	}
}

func hongguoCodeFixture(t *testing.T, codeBody string) (*Downloader, *[]string) {
	var requests []string
	registered := 0
	d := sourceFixtureDownloader(t, func(request *http.Request) (*http.Response, error) {
		if strings.Contains(request.URL.Path, "device_register") {
			registered++
			requests = append(requests, "register")
			id := strconv.Itoa(1000 + registered)
			return sourceFixtureResponse(request, http.StatusOK, `{"device_id_str":"`+id+`","install_id_str":"`+id+`9"}`), nil
		}
		requests = append(requests, "model@"+request.URL.Query().Get("device_id"))
		if codeBody != "" {
			return sourceFixtureResponse(request, http.StatusOK, codeBody), nil
		}
		return sourceFixtureResponse(request, http.StatusOK, hongguoRotationModelOK), nil
	})
	d.cfg.Retries = 1
	client := d.hongguoClient()
	client.state.DeviceID, client.state.InstallID, client.state.Registered = "7", "8", true
	return d, &requests
}

func TestHongguoDeviceRejected110001ReregistersOnce(t *testing.T) {
	var requests []string
	registered := 0
	d := sourceFixtureDownloader(t, func(request *http.Request) (*http.Response, error) {
		if strings.Contains(request.URL.Path, "device_register") {
			registered++
			requests = append(requests, "register")
			id := strconv.Itoa(1000 + registered)
			return sourceFixtureResponse(request, http.StatusOK, `{"device_id_str":"`+id+`","install_id_str":"`+id+`9"}`), nil
		}
		device := request.URL.Query().Get("device_id")
		requests = append(requests, "model@"+device)
		if device == "7" {
			return sourceFixtureResponse(request, http.StatusOK, `{"code":110001,"data":{}}`), nil
		}
		return sourceFixtureResponse(request, http.StatusOK, hongguoRotationModelOK), nil
	})
	d.cfg.Retries = 1
	client := d.hongguoClient()
	client.state.DeviceID, client.state.InstallID, client.state.Registered = "7", "8", true
	media, err := d.resolveHongguoAppMedia(context.Background(), "12345")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasSuffix(media.URL, "high.mp4") {
		t.Fatal("device rejection must recover with a fresh device", media)
	}
	if state := d.hongguoCatalogSnapshot(); state.DeviceID != "1001" {
		t.Fatal("device was not re-registered after 110001", state)
	}
	registers := 0
	for _, item := range requests {
		if item == "register" {
			registers++
		}
	}
	if registers != 1 {
		t.Fatal("110001 must re-register exactly once", requests)
	}
}

func TestHongguoCode101000HasNoDeviceBranch(t *testing.T) {
	d, requests := hongguoCodeFixture(t, `{"code":101000,"data":{}}`)
	_, err := d.resolveHongguoAppMedia(context.Background(), "12345")
	if err == nil || !strings.Contains(err.Error(), "101000") {
		t.Fatal("101000 must surface as an error carrying the code", err)
	}
	for _, item := range *requests {
		if item == "register" {
			t.Fatal("101000 must not trigger a device rotation", *requests)
		}
	}
	if state := d.hongguoCatalogSnapshot(); state.DeviceID != "7" {
		t.Fatal("101000 must keep the current device", state)
	}
}

func TestHongguoVideoModelPlayerOnlyDirect(t *testing.T) {
	var requests []string
	registered := 0
	sawPlayerOnlyModel := false
	d := sourceFixtureDownloader(t, func(request *http.Request) (*http.Response, error) {
		if strings.Contains(request.URL.Path, "device_register") {
			registered++
			requests = append(requests, "register")
			id := strconv.Itoa(1000 + registered)
			return sourceFixtureResponse(request, http.StatusOK, `{"device_id_str":"`+id+`","install_id_str":"`+id+`9"}`), nil
		}
		requests = append(requests, "model@"+request.URL.Query().Get("device_id"))
		if strings.Contains(request.URL.Path, "video_model") && request.Header.Get("X-Gorgon") == "" {
			sawPlayerOnlyModel = true
		}
		if request.Header.Get("X-Gorgon") != "" {
			return sourceFixtureResponse(request, http.StatusOK, ""), nil
		}
		return sourceFixtureResponse(request, http.StatusOK, hongguoRotationModelOK), nil
	})
	d.cfg.Retries = 1
	client := d.hongguoClient()
	client.state.DeviceID, client.state.InstallID, client.state.Registered = "7", "8", true
	media, err := d.resolveHongguoAppMedia(context.Background(), "12345")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasSuffix(media.URL, "high.mp4") {
		t.Fatal("video_model direct with player-only signing must return the stream", media)
	}
	if !sawPlayerOnlyModel {
		t.Fatal("video_model direct must go out without X-Gorgon", requests)
	}
	if state := d.hongguoCatalogSnapshot(); state.DeviceID != "7" {
		t.Fatal("player-only direct must not burn device rotations", state)
	}
}

func TestHongguoPlayerLadderFallsBackOnEmptyBody(t *testing.T) {
	var requests []string
	registered := 0
	sawLadderTab := false
	d := sourceFixtureDownloader(t, func(request *http.Request) (*http.Response, error) {
		if strings.Contains(request.URL.Path, "device_register") {
			registered++
			requests = append(requests, "register")
			id := strconv.Itoa(1000 + registered)
			return sourceFixtureResponse(request, http.StatusOK, `{"device_id_str":"`+id+`","install_id_str":"`+id+`9"}`), nil
		}
		requests = append(requests, "model@"+request.URL.Query().Get("device_id"))
		if strings.Contains(request.URL.Path, "video_tab") && request.Header.Get("X-Gorgon") == "" {
			sawLadderTab = true
			return sourceFixtureResponse(request, http.StatusOK, hongguoRotationModelOK), nil
		}
		return sourceFixtureResponse(request, http.StatusOK, ""), nil
	})
	d.cfg.Retries = 1
	client := d.hongguoClient()
	client.state.DeviceID, client.state.InstallID, client.state.Registered = "7", "8", true
	media, err := d.resolveHongguoAppMedia(context.Background(), "12345")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasSuffix(media.URL, "high.mp4") {
		t.Fatal("player ladder did not rescue the empty-body stream", media)
	}
	if !sawLadderTab {
		t.Fatal("player ladder must reach video_tab with player-only signing", requests)
	}
}
