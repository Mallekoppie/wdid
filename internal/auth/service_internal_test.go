package auth

import (
	"errors"
	"testing"

	"github.com/Mallekoppie/wdid/internal/domain"
)

func TestRoleFromRoles(t *testing.T) {
	cases := []struct {
		name  string
		roles []string
		want  domain.Role
	}{
		{name: "admin", roles: []string{"admin"}, want: domain.RoleAdmin},
		{name: "user", roles: []string{"user"}, want: domain.RoleUser},
		{name: "admin wins", roles: []string{"user", "admin"}, want: domain.RoleAdmin},
		{name: "unknown role is a user", roles: []string{"wdid-admins"}, want: domain.RoleUser},
		{name: "no roles is a user", roles: nil, want: domain.RoleUser},
	}

	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			if got := roleFromRoles(testCase.roles); got != testCase.want {
				t.Fatalf("role = %q, want %q", got, testCase.want)
			}
		})
	}
}

func TestOIDCProfile(t *testing.T) {
	cases := []struct {
		name            string
		claims          map[string]interface{}
		wantEmail       string
		wantDisplayName string
		wantErr         bool
	}{
		{
			name:            "name wins over preferred username",
			claims:          map[string]interface{}{"email": " User@Example.com ", "name": "Full Name", "preferred_username": "handle"},
			wantEmail:       "user@example.com",
			wantDisplayName: "Full Name",
		},
		{
			name:            "preferred username falls back",
			claims:          map[string]interface{}{"email": "user@example.com", "preferred_username": "handle"},
			wantEmail:       "user@example.com",
			wantDisplayName: "handle",
		},
		{
			name:            "no display name",
			claims:          map[string]interface{}{"email": "user@example.com"},
			wantEmail:       "user@example.com",
			wantDisplayName: "",
		},
		{
			name:    "missing email",
			claims:  map[string]interface{}{"name": "Full Name"},
			wantErr: true,
		},
		{
			name:    "non-string email",
			claims:  map[string]interface{}{"email": 42},
			wantErr: true,
		},
	}

	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			email, displayName, err := oidcProfile(testCase.claims)
			if testCase.wantErr {
				if !errors.Is(err, ErrUnauthenticated) {
					t.Fatalf("error = %v, want ErrUnauthenticated", err)
				}
				return
			}
			if err != nil {
				t.Fatalf("profile: %v", err)
			}
			if email != testCase.wantEmail || displayName != testCase.wantDisplayName {
				t.Fatalf("profile = (%q, %q), want (%q, %q)", email, displayName, testCase.wantEmail, testCase.wantDisplayName)
			}
		})
	}
}
