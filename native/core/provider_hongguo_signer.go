package core

import (
	"crypto/md5"
	"net/http"
	"net/url"
	"strconv"
	"time"
)

type hongguoSignOptionsKey struct{}

type hongguoSignerIdentity struct {
	DeviceID  string
	InstallID string
}

type hongguoSignOptions struct {
	Playback       bool
	PlayerOnly     bool
	Identity       hongguoSignerIdentity
	MedusaDeviceID string
}

func hongguoTicketBranch(query string, body []byte, ts uint32) int {
	queryHash := hongguoSM3([]byte(query))
	var bodyHash [16]byte
	if body != nil {
		bodyHash = md5.Sum(body)
	}
	iv := sixGodGetIv(0x20230928, queryHash[:])
	iv = sixGodGetIv(iv, bodyHash[:])
	iv = sixGodGetIv(iv, sixGodU32LE(ts))
	return int(iv&15) % 3
}

func hongguoPickTicket(query url.Values, body []byte, now time.Time) (int64, bool) {
	ts := uint32(now.Unix())
	base := now.UnixMilli()
	for offset := int64(0); offset < 128; offset++ {
		ticket := base + offset
		trial := url.Values{}
		for key, values := range query {
			trial[key] = append([]string(nil), values...)
		}
		trial.Set("_rticket", strconv.FormatInt(ticket, 10))
		if hongguoTicketBranch(trial.Encode(), body, ts) == 0 {
			return ticket, true
		}
	}
	return base, false
}

func hongguoSignRequest(request *http.Request, body []byte, now time.Time, opts hongguoSignOptions) {
	query := request.URL.Query()
	if opts.Identity.DeviceID != "" {
		query.Set("device_id", opts.Identity.DeviceID)
	}
	if opts.Identity.InstallID != "" {
		query.Set("iid", opts.Identity.InstallID)
	}
	ticket, _ := hongguoPickTicket(query, body, now)
	query.Set("_rticket", strconv.FormatInt(ticket, 10))
	request.URL.RawQuery = query.Encode()
	signHongguoPlayerRequestTicketMedusa(request, body, now, ticket, opts.PlayerOnly, sixGodMedusaOpts{DeviceID: opts.MedusaDeviceID})
	if opts.PlayerOnly {
		return
	}
	request.Header.Set("sdk-version", "2")
	request.Header.Set("x-xs-from-web", "0")
	if opts.Playback {
		return
	}
	request.Header.Set("x-tt-request-tag", "t=0;n=0")
	request.Header.Set("passport-sdk-version", "50561")
	if body != nil {
		request.Header.Set("x-vc-bdturing-sdk-version", "3.7.2.cn")
	}
}

func hongguoSignPlaybackRequest(request *http.Request, body []byte, now time.Time, identity hongguoSignerIdentity) {
	hongguoSignRequest(request, body, now, hongguoSignOptions{Playback: true, Identity: identity})
}
