package main

import (
	"bytes"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/Mallekoppie/wdid/internal/config"
	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/invite"
	"github.com/Mallekoppie/wdid/internal/store"
)

func TestInviteCommandsRoundTrip(t *testing.T) {
	t.Setenv("WDID_DB_PATH", filepath.Join(t.TempDir(), "wdid-cli.db"))

	var created bytes.Buffer
	if err := runInvite([]string{"create", "--email", "New@Example.com"}, &created); err != nil {
		t.Fatalf("create invite: %v", err)
	}

	output := created.String()
	if !strings.Contains(output, "new@example.com") {
		t.Fatalf("create output = %q, want the normalized email", output)
	}
	if !strings.Contains(output, "wdid-") {
		t.Fatalf("create output = %q, want an invite code", output)
	}

	id := inviteIDFromOutput(t, output)

	var listed bytes.Buffer
	if err := runInvite([]string{"list"}, &listed); err != nil {
		t.Fatalf("list invites: %v", err)
	}
	if !strings.Contains(listed.String(), "new@example.com") || !strings.Contains(listed.String(), "unused") {
		t.Fatalf("list output = %q, want the unused invite", listed.String())
	}

	var revoked bytes.Buffer
	if err := runInvite([]string{"revoke", id}, &revoked); err != nil {
		t.Fatalf("revoke invite: %v", err)
	}
	if !strings.Contains(revoked.String(), id) {
		t.Fatalf("revoke output = %q, want the invite id", revoked.String())
	}

	var empty bytes.Buffer
	if err := runInvite([]string{"list"}, &empty); err != nil {
		t.Fatalf("list after revoke: %v", err)
	}
	if !strings.Contains(empty.String(), "No invites") {
		t.Fatalf("list after revoke = %q, want an empty state", empty.String())
	}
}

func TestCreatedInviteCodeCanBeRedeemed(t *testing.T) {
	t.Setenv("WDID_DB_PATH", filepath.Join(t.TempDir(), "wdid-cli.db"))

	var created bytes.Buffer
	if err := runInvite([]string{"create", "--email", "new@example.com"}, &created); err != nil {
		t.Fatalf("create invite: %v", err)
	}
	code := inviteCodeFromOutput(t, created.String())

	database, err := store.Open(config.LoadStorage())
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	defer database.Close()

	user := domain.User{
		ID:          domain.NewID(),
		Email:       "new@example.com",
		DisplayName: "New User",
		Role:        domain.RoleUser,
		CreatedAt:   time.Now().UTC(),
	}
	if _, err := database.CreateInvitedUser(user, "hash", invite.Hash(code), time.Now().UTC()); err != nil {
		t.Fatalf("redeem CLI invite code: %v", err)
	}
}

func TestInviteCreateRequiresAValidEmail(t *testing.T) {
	t.Setenv("WDID_DB_PATH", filepath.Join(t.TempDir(), "wdid-cli.db"))

	var out bytes.Buffer
	if err := runInvite([]string{"create"}, &out); err == nil {
		t.Fatal("expected an error when --email is missing")
	}
	if err := runInvite([]string{"create", "--email", "not-an-email"}, &out); err == nil {
		t.Fatal("expected an error for an invalid email")
	}
}

func TestInviteRejectsAnUnknownCommand(t *testing.T) {
	t.Setenv("WDID_DB_PATH", filepath.Join(t.TempDir(), "wdid-cli.db"))

	if err := runInvite([]string{"delete"}, &bytes.Buffer{}); err == nil {
		t.Fatal("expected an error for an unknown command")
	}
}

// inviteCodeFromOutput reads the one-time code from the stable create output.
func inviteCodeFromOutput(t *testing.T, output string) string {
	t.Helper()

	for _, line := range strings.Split(output, "\n") {
		if code, ok := strings.CutPrefix(line, "Invite code: "); ok {
			return strings.TrimSpace(code)
		}
	}
	t.Fatalf("create output = %q, want an Invite code line", output)
	return ""
}

// inviteIDFromOutput reads the identifier from the stable create output line.
func inviteIDFromOutput(t *testing.T, output string) string {
	t.Helper()

	for _, line := range strings.Split(output, "\n") {
		fields := strings.Fields(line)
		if len(fields) >= 3 && fields[0] == "Created" && fields[1] == "invite" {
			return fields[2]
		}
	}
	t.Fatalf("create output = %q, want a Created invite line", output)
	return ""
}
