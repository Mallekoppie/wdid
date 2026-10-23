package invite_test

import (
	"bytes"
	"strings"
	"testing"

	"github.com/Mallekoppie/wdid/internal/invite"
)

func TestGenerateUsesTheReadableFormat(t *testing.T) {
	// Ten bytes of 0xff encode to sixteen '7' characters in base32, giving a
	// worked example independent of the implementation.
	code, err := invite.Generate(bytes.NewReader(bytes.Repeat([]byte{0xff}, 10)))
	if err != nil {
		t.Fatalf("generate: %v", err)
	}

	if code != "wdid-7777-7777-7777-7777" {
		t.Fatalf("code = %q, want wdid-7777-7777-7777-7777", code)
	}
}

func TestGenerateRejectsAShortReader(t *testing.T) {
	if _, err := invite.Generate(bytes.NewReader([]byte{1, 2, 3})); err == nil {
		t.Fatal("expected an error for a short random source")
	}
}

func TestHashIgnoresCaseSpacingAndHyphens(t *testing.T) {
	want := invite.Hash("wdid-ABCD-EFGH-IJKL-MNOP")

	for _, variant := range []string{
		"wdid-ABCD-EFGH-IJKL-MNOP",
		"WDID-ABCD-EFGH-IJKL-MNOP",
		"wdid-abcd-efgh-ijkl-mnop",
		" WDID ABCD EFGH IJKL MNOP ",
		"wdidabcdefghijklmnop",
	} {
		if got := invite.Hash(variant); got != want {
			t.Errorf("Hash(%q) = %q, want %q", variant, got, want)
		}
	}

	if invite.Hash("wdid-ABCD-EFGH-IJKL-MNOP") == invite.Hash("wdid-ABCD-EFGH-IJKL-MNOQ") {
		t.Fatal("different codes must hash differently")
	}
}

func TestHashIsHexSHA256(t *testing.T) {
	got := invite.Hash("wdid-AAAA-AAAA-AAAA-AAAA")
	if len(got) != 64 || strings.Trim(got, "0123456789abcdef") != "" {
		t.Fatalf("hash = %q, want 64 lowercase hex characters", got)
	}
}
