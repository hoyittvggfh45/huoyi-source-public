package core

import (
	"sync"
	"time"
)

type hongguoPlaybackRoute struct {
	Get  bool
	Host string
}

type hongguoRouteHealth struct {
	success      time.Time
	blockedUntil time.Time
	empty        bool
}

type hongguoPlaybackRoutes struct {
	mu     sync.Mutex
	routes []hongguoPlaybackRoute
	health map[hongguoPlaybackRoute]hongguoRouteHealth
}

func newHongguoPlaybackRoutes() *hongguoPlaybackRoutes {
	routes := []hongguoPlaybackRoute{
		{Get: true, Host: hongguoAppBaseURL},
		{Get: false, Host: hongguoAppBaseURL},
		{Get: false, Host: hongguoOverseaAppBaseURL},
	}
	health := make(map[hongguoPlaybackRoute]hongguoRouteHealth, len(routes))
	for _, route := range routes {
		health[route] = hongguoRouteHealth{}
	}
	return &hongguoPlaybackRoutes{routes: routes, health: health}
}

func (r *hongguoPlaybackRoutes) reset() {
	r.mu.Lock()
	defer r.mu.Unlock()
	for _, route := range r.routes {
		r.health[route] = hongguoRouteHealth{}
	}
}

func (r *hongguoPlaybackRoutes) plan(now time.Time, speculative bool) []hongguoPlaybackRoute {
	r.mu.Lock()
	defer r.mu.Unlock()
	var available []hongguoPlaybackRoute
	for _, route := range r.routes {
		if !r.health[route].blockedUntil.After(now) {
			available = append(available, route)
		}
	}
	for i := 1; i < len(available); i++ {
		for j := i; j > 0 && r.health[available[j]].success.After(r.health[available[j-1]].success); j-- {
			available[j], available[j-1] = available[j-1], available[j]
		}
	}
	if len(available) > 0 {
		if speculative {
			return available[:1]
		}
		hasPost := false
		for _, route := range available {
			hasPost = hasPost || !route.Get
		}
		if hasPost {
			return available
		}
		earliest := r.routes[0]
		for _, route := range r.routes {
			if route.Get {
				continue
			}
			if r.health[route].blockedUntil.Before(r.health[earliest].blockedUntil) || earliest.Get {
				earliest = route
			}
		}
		return append(available, earliest)
	}
	if speculative {
		return nil
	}
	earliest := r.routes[0]
	for _, route := range r.routes {
		if route.Get {
			continue
		}
		if r.health[route].blockedUntil.Before(r.health[earliest].blockedUntil) || earliest.Get {
			earliest = route
		}
	}
	return []hongguoPlaybackRoute{earliest}
}

func (r *hongguoPlaybackRoutes) exhausted(now time.Time) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	for _, route := range r.routes {
		health := r.health[route]
		if !health.empty || !health.blockedUntil.After(now) {
			return false
		}
	}
	return true
}

func (r *hongguoPlaybackRoutes) success(route hongguoPlaybackRoute, now time.Time) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.health[route] = hongguoRouteHealth{success: now}
}

func (r *hongguoPlaybackRoutes) failed(route hongguoPlaybackRoute, now time.Time, empty bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	cooldown := 5 * time.Second
	if empty {
		cooldown = 30 * time.Second
	}
	r.health[route] = hongguoRouteHealth{success: r.health[route].success, blockedUntil: now.Add(cooldown), empty: empty}
}
