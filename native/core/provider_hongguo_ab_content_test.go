package core

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"testing"
)

func TestHongguoAppRequestRoutesByPath(t *testing.T) {
	var hosts []string
	d := sourceFixtureDownloader(t, func(request *http.Request) (*http.Response, error) {
		hosts = append(hosts, request.URL.Host+" "+request.URL.Path)
		return sourceFixtureResponse(request, http.StatusOK, `{"code":0,"data":{}}`), nil
	})
	d.cfg.Retries = 1
	client := d.hongguoClient()
	client.state.DeviceID, client.state.InstallID, client.state.Registered = "7", "8", true
	routes := []struct {
		path string
		host string
	}{
		{"/reading/bookapi/bookmall/tab/v1/", "api5-normal-sinfonlinea.fqnovel.com"},
		{"/reading/distribution/category/landpage/v/", "api5-normal-sinfonlinea.fqnovel.com"},
		{"/novel/player/video_detail/v1/", "api5-normal-sinfonlinea.fqnovel.com"},
		{"/reading/bookapi/search/tab/v1/", "api5-normal-sinfonlinea.fqnovel.com"},
		{"/novel/player/video_model/v1/", "api5-normal-sinfonlineb.fqnovel.com"},
		{"/novel/player/multi_video_model/v1/", "api5-normal-sinfonlineb.fqnovel.com"},
		{"/novel/commentapi/comment/list/123/v1/", "api5-normal-sinfonlineb.fqnovel.com"},
	}
	ctx := context.Background()
	for _, route := range routes {
		callCtx := ctx
		if strings.Contains(route.path, "commentapi") {
			callCtx = context.WithValue(ctx, hongguoCommentKey{}, true)
		}
		if _, err := d.hongguoAppRequest(callCtx, http.MethodPost, route.path, nil, map[string]any{"series_id": "123"}); err != nil {
			t.Fatal(route.path, err)
		}
	}
	overseaCtx := context.WithValue(ctx, hongguoBaseURLOverrideKey{}, hongguoAppBaseURL)
	if _, err := d.hongguoAppRequest(overseaCtx, http.MethodPost, "/novel/player/video_detail/v1/", nil, map[string]any{"series_id": "123"}); err != nil {
		t.Fatal("override detail", err)
	}
	if len(hosts) != len(routes)+1 {
		t.Fatal("unexpected request count", hosts)
	}
	for index, route := range routes {
		if !strings.HasPrefix(hosts[index], route.host+" ") {
			t.Fatal("unexpected route", route.path, hosts[index])
		}
	}
	if !strings.HasPrefix(hosts[len(routes)], "api5-normal-sinfonlineb.fqnovel.com ") {
		t.Fatal("explicit base override must win over path routing", hosts[len(routes)])
	}
}

func hongguoVideoModelContentFixture(t *testing.T, firstBody, secondBody string) (*Downloader, *[]string, *[]string) {
	var paths []string
	var bodies []string
	d := sourceFixtureDownloader(t, func(request *http.Request) (*http.Response, error) {
		paths = append(paths, request.URL.Path)
		if request.Body != nil {
			content, _ := io.ReadAll(request.Body)
			bodies = append(bodies, string(content))
		}
		if strings.Contains(request.URL.Path, "multi_video_model") {
			return sourceFixtureResponse(request, http.StatusOK, `{"code":0,"data":{}}`), nil
		}
		var parsed map[string]any
		_ = json.Unmarshal([]byte(bodies[len(bodies)-1]), &parsed)
		if parsed["content_type"] == float64(1001) {
			return sourceFixtureResponse(request, http.StatusOK, secondBody), nil
		}
		return sourceFixtureResponse(request, http.StatusOK, firstBody), nil
	})
	d.cfg.Retries = 1
	client := d.hongguoClient()
	client.state.DeviceID, client.state.InstallID, client.state.Registered = "7", "8", true
	return d, &paths, &bodies
}

func TestHongguoVideoModelFallsBackToContentType1001(t *testing.T) {
	d, paths, bodies := hongguoVideoModelContentFixture(t, `{"code":0,"data":{}}`, hongguoRotationModelOK)
	media, err := d.resolveHongguoAppMediaLine(context.Background(), "12345")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasSuffix(media.URL, "high.mp4") {
		t.Fatal("content_type 1001 did not rescue the stream", media)
	}
	models := 0
	for index, path := range *paths {
		if strings.HasSuffix(path, "/video_model/v1/") {
			models++
			var parsed map[string]any
			if err := json.Unmarshal([]byte((*bodies)[index]), &parsed); err != nil {
				t.Fatal(err)
			}
			if models == 1 && parsed["content_type"] != float64(1) {
				t.Fatal("first video_model must use content_type 1", (*bodies)[index])
			}
			if models == 2 && parsed["content_type"] != float64(1001) {
				t.Fatal("second video_model must use content_type 1001", (*bodies)[index])
			}
		}
		if strings.Contains(path, "device_register") {
			t.Fatal("content_type fallback must not rotate the device", *paths)
		}
	}
	if models != 2 {
		t.Fatal("unexpected video_model count", *paths)
	}
}

func TestHongguoVideoModelSkips1001OnSuccess(t *testing.T) {
	d, paths, bodies := hongguoVideoModelContentFixture(t, hongguoRotationModelOK, hongguoRotationModelOK)
	media, err := d.resolveHongguoAppMediaLine(context.Background(), "12345")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasSuffix(media.URL, "high.mp4") {
		t.Fatal("content_type 1 success did not stream", media)
	}
	models := 0
	for index, path := range *paths {
		if strings.HasSuffix(path, "/video_model/v1/") {
			models++
			var parsed map[string]any
			if err := json.Unmarshal([]byte((*bodies)[index]), &parsed); err != nil {
				t.Fatal(err)
			}
			if parsed["content_type"] != float64(1) {
				t.Fatal("successful first attempt must stay on content_type 1", (*bodies)[index])
			}
		}
	}
	if models != 1 {
		t.Fatal("content_type 1 success must not send a 1001 request", *paths)
	}
}
