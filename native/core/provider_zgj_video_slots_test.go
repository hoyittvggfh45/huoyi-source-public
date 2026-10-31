package core

import (
	"testing"

	"duanjuapp/native/core/seku"
)

func TestZgjVideoSlotsRegistryShape(t *testing.T) {
	seen := map[string]bool{}
	counts := map[string]int{}
	confirmed := []string{}
	for _, slot := range zgjVideoSlots {
		if slot.ID == "" || slot.Segment == "" {
			t.Fatalf("slot with empty ID or Segment: %+v", slot)
		}
		if seen[slot.ID] {
			t.Fatalf("duplicate slot ID %q", slot.ID)
		}
		seen[slot.ID] = true
		switch slot.Tier {
		case zgjTierComplete, zgjTierRegistered, zgjTierBlocked:
		default:
			t.Fatalf("slot %q has unknown tier %q", slot.ID, slot.Tier)
		}
		counts[slot.Tier]++
		if slot.NameConfirmed {
			confirmed = append(confirmed, slot.ID)
		}
		if slot.Tier == zgjTierRegistered && slot.ExistingSlot != "" {
			t.Fatalf("registered slot %q must not claim an existing slot", slot.ID)
		}
	}
	if len(zgjVideoSlots) != 58 {
		t.Fatalf("registry has %d slots, want 58", len(zgjVideoSlots))
	}
	if counts[zgjTierComplete] != 19 || counts[zgjTierRegistered] != 36 || counts[zgjTierBlocked] != 3 {
		t.Fatalf("tier counts = %v, want complete 19 registered 36 blocked 3", counts)
	}
	wantConfirmed := map[string]bool{"hongguo": true, "xingguo": true, "huangdou": true}
	if len(confirmed) != len(wantConfirmed) {
		t.Fatalf("name-confirmed slots = %v, want %v", confirmed, wantConfirmed)
	}
	for _, id := range confirmed {
		if !wantConfirmed[id] {
			t.Fatalf("unexpected name-confirmed slot %q", id)
		}
	}
	names := map[string]bool{}
	for _, name := range zgjGenericHeaderNamesUnpaired {
		if name == "" || names[name] {
			t.Fatalf("bad generic header name %q", name)
		}
		names[name] = true
	}
	if !names["User-Agent"] || !names["Referer"] {
		t.Fatalf("generic header names lack User-Agent or Referer: %v", zgjGenericHeaderNamesUnpaired)
	}
}

func TestZgjVideoSlotLookup(t *testing.T) {
	cases := []struct {
		in   string
		id   string
		tier string
		ok   bool
	}{
		{"pornhub", "pornhub", zgjTierRegistered, true},
		{"redtube", "redtube", zgjTierRegistered, true},
		{"legacy", "legacy", zgjTierBlocked, true},
		{"single", "single", zgjTierBlocked, true},
		{"miguo", "miguo", zgjTierBlocked, true},
		{"hongguo", "hongguo", zgjTierComplete, true},
		{"hsck", "hsck", zgjTierComplete, true},
		{"youtube", "youtube", zgjTierComplete, true},
		{"HUANGJU", "huangju", zgjTierComplete, true},
		{"huangguoai.com", "huangguoai", zgjTierComplete, true},
		{"", "", "", false},
		{"not-a-slot", "", "", false},
	}
	for _, c := range cases {
		slot, ok := zgjVideoSlotFor(c.in)
		if ok != c.ok {
			t.Fatalf("zgjVideoSlotFor(%q) ok = %v, want %v", c.in, ok, c.ok)
		}
		if !c.ok {
			continue
		}
		if slot.ID != c.id || slot.Tier != c.tier {
			t.Fatalf("zgjVideoSlotFor(%q) = %q/%q, want %q/%q", c.in, slot.ID, slot.Tier, c.id, c.tier)
		}
	}
}

func TestZgjVideoSlotsCompleteAreLive(t *testing.T) {
	providerFileVerified := map[string]bool{
		"hongguo": true, "huangdou": true, "huangju": true, "yeguo": true,
		"huangguo-video": true, "huangguoai": true, "dsd": true,
		"maccms": true, "duanju": true, "youtube": true,
	}
	for _, slot := range zgjVideoSlots {
		if slot.Tier != zgjTierComplete {
			continue
		}
		if isDuanjuProviderSource(slot.ID) {
			continue
		}
		if slot.ExistingSlot != "" && slot.ExistingSlot != slot.ID {
			continue
		}
		if seku.HasSlot(slot.ID) {
			continue
		}
		if providerFileVerified[slot.ID] {
			continue
		}
		t.Fatalf("complete slot %q has no live predicate", slot.ID)
	}
	if !isDuanjuProviderSource("yaguo") || !isDuanjuProviderSource("xingguo") {
		t.Fatal("duanju family predicate unexpectedly false")
	}
}

func TestZgjVideoSlotsRegisteredAreNotLive(t *testing.T) {
	for _, slot := range zgjVideoSlots {
		if slot.Tier != zgjTierRegistered {
			continue
		}
		if isDuanjuProviderSource(slot.ID) {
			t.Fatalf("registered slot %q is unexpectedly a duanju source", slot.ID)
		}
	}
}

func TestZgjVideoSlotsDialogTotals(t *testing.T) {
	slots := zgjVideoSlotsAll()
	if len(slots) != 58 {
		t.Fatalf("slot total = %d, want 58", len(slots))
	}
	seen := map[string]bool{}
	green, restricted, unknown := 0, 0, 0
	names := map[string]string{}
	for _, slot := range slots {
		if slot.ID == "" || seen[slot.ID] {
			t.Fatalf("duplicate or empty slot id %q", slot.ID)
		}
		seen[slot.ID] = true
		names[slot.DisplayName] = slot.ID
		switch slot.Group {
		case zgjGroupGreen:
			green++
		case zgjGroupRestricted:
			restricted++
		case zgjGroupUnknown:
			unknown++
		default:
			t.Fatalf("slot %s has ungrouped group %q", slot.ID, slot.Group)
		}
	}
	if green != 12 || restricted != 39 || unknown != 7 {
		t.Fatalf("groups green=%d restricted=%d unknown=%d, want 12/39/7", green, restricted, unknown)
	}
	screenshot := []string{"豆果", "剧果", "野果", "帝果", "黄果", "智果", "故果", "艳果", "桃果", "柚果", "榴果", "美果", "城果", "宵果", "樱果", "露果", "荔果", "橘果", "枣果", "柠果", "芒果", "橙果", "角果", "贞果", "学果", "二果", "会果", "撩果", "春果", "波果", "仓果", "巴果", "杰果", "档果", "汉果", "番果"}
	for _, name := range screenshot {
		id, ok := names[name]
		if !ok {
			t.Fatalf("screenshot name %s missing from registry", name)
		}
		slot, found := zgjVideoSlotFor(id)
		if !found || slot.Group != zgjGroupRestricted {
			t.Fatalf("screenshot name %s (slot %s) group = %s, want restricted", name, id, slot.Group)
		}
	}
	newIDs := []string{"douguo", "zhiguo", "guguo", "taoguo", "youguo", "liuguo", "meiguo", "chengguo", "xiaoguo", "yingguo", "luguo", "liguo", "juguo", "zaoguo", "ningguo", "mangguo", "jiaoguo", "zhenguo", "xueguo", "erguo", "huiguo", "liaoguo", "chunguo", "boguo", "cangguo", "baguo", "jieguo", "dangguo", "hanguo", "fanguo2", "huangguo"}
	for _, id := range newIDs {
		slot, found := zgjVideoSlotFor(id)
		if !found {
			t.Fatalf("new slot %s missing", id)
		}
		if slot.Tier != zgjTierRegistered || slot.Group != zgjGroupRestricted {
			t.Fatalf("new slot %s tier=%s group=%s, want registered/restricted", id, slot.Tier, slot.Group)
		}
		if slot.HasCatalog || slot.HasDetail || slot.HasSearch || slot.HasResolve {
			t.Fatalf("new slot %s must not claim any working route", id)
		}
	}
	fills := map[string]string{"艳果": "yangguo"}
	for name, id := range fills {
		slot, _ := zgjVideoSlotFor(id)
		if slot.DisplayName != name || slot.NameConfirmed {
			t.Fatalf("fill slot %s name=%s confirmed=%v, want %s/false", id, slot.DisplayName, slot.NameConfirmed, name)
		}
	}
	mapped := map[string]string{"剧果": "huangju", "野果": "yeguo", "帝果": "dsd", "橙果": "chengguodj"}
	for name, id := range mapped {
		slot, _ := zgjVideoSlotFor(id)
		if slot.DisplayName != name || slot.Group != zgjGroupRestricted {
			t.Fatalf("mapped slot %s name=%s group=%s, want %s/restricted", id, slot.DisplayName, slot.Group, name)
		}
	}
	for _, id := range []string{"legacy", "single", "miguo"} {
		slot, _ := zgjVideoSlotFor(id)
		if slot.Group != zgjGroupUnknown {
			t.Fatalf("blocked slot %s group=%s, want unknown", id, slot.Group)
		}
	}
}
