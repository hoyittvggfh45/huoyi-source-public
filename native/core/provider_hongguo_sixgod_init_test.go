package core

import (
	"sync"
	"testing"
)

func resetSixGodTablesForTest() {
	sixGodTablesOnce = sync.Once{}
	sixGodBranchOne = nil
	sixGodSBox = nil
	sixGodTablesErr = nil
}

func TestSixGodHashF13Branch1WithoutPriorTableInit(t *testing.T) {
	querySm3 := make([]byte, 32)
	bodyMd5Bytes := make([]byte, 16)
	covered := map[int]bool{}
	for khronos := uint32(0); khronos < 500000 && len(covered) < 5; khronos++ {
		tsBytes := sixGodU32LE(khronos)
		iv := sixGodGetIv(0x20230928, querySm3)
		iv = sixGodGetIv(iv, bodyMd5Bytes)
		iv = sixGodGetIv(iv, tsBytes)
		ivV0 := ((iv & 15) * 171) >> 9
		branch := int(iv&15) - int((ivV0*3)&255)
		if branch != 1 || covered[int(ivV0)] {
			continue
		}
		covered[int(ivV0)] = true
		resetSixGodTablesForTest()
		out, err := sixGodHashF13(querySm3, bodyMd5Bytes, tsBytes, khronos)
		if err != nil {
			t.Fatalf("branch1 ivV0=%d: unexpected error: %v", ivV0, err)
		}
		if len(out) != 20 {
			t.Fatalf("branch1 ivV0=%d: got %d bytes, want 20", ivV0, len(out))
		}
	}
	if len(covered) == 0 {
		t.Fatal("no branch1 inputs found")
	}
	t.Logf("covered branch1 ivV0 values: %v", covered)
}

func TestSixGodGenMedusaWithoutPriorTableInit(t *testing.T) {
	for i := 0; i < 20; i++ {
		resetSixGodTablesForTest()
		medusa, err := sixGodGenMedusa("https://api5-normal-sinfonlineb.fqnovel.com/reading/distribution/category/landpage/v/?aid=8662&device_id=12345", []byte(`{"offset":0}`), uint32(1700000000+i), sixGodMedusaOpts{})
		if err != nil {
			t.Fatalf("call %d: unexpected error: %v", i, err)
		}
		if medusa == "" {
			t.Fatalf("call %d: empty medusa", i)
		}
	}
}
