package domain

import (
	"strings"
	"time"

	"github.com/google/uuid"
)

// Role is the coarse access level of a user account.
type Role string

const (
	RoleAdmin Role = "admin"
	RoleUser  Role = "user"
)

// NewID returns a new UUIDv7 so bucket scans are chronological by key.
func NewID() string {
	id, err := uuid.NewV7()
	if err != nil {
		return uuid.NewString()
	}
	return id.String()
}

// User is an account. Credentials are stored separately from the profile.
type User struct {
	ID          string    `json:"id"`
	Email       string    `json:"email"`
	DisplayName string    `json:"displayName"`
	Role        Role      `json:"role"`
	CreatedAt   time.Time `json:"createdAt"`
}

// Invite is a single-use registration code issued for one email address.
// Only a SHA-256 hash of the code is stored; the code itself is shown once.
type Invite struct {
	ID        string     `json:"id"`
	Email     string     `json:"email"`
	CreatedAt time.Time  `json:"createdAt"`
	UsedAt    *time.Time `json:"usedAt,omitempty"`
	UsedBy    string     `json:"usedBy,omitempty"`
}

// Normalize trims invite input into its canonical form.
func (i *Invite) Normalize() {
	i.Email = strings.ToLower(strings.TrimSpace(i.Email))
}

// Normalize trims user input into its canonical form.
func (u *User) Normalize() {
	u.Email = strings.ToLower(strings.TrimSpace(u.Email))
	u.DisplayName = strings.TrimSpace(u.DisplayName)
}

// NormalizeList trims entries, drops empties and removes case-insensitive duplicates.
func NormalizeList(values []string) []string {
	if len(values) == 0 {
		return nil
	}

	seen := make(map[string]struct{}, len(values))
	result := make([]string, 0, len(values))
	for _, value := range values {
		trimmed := strings.TrimSpace(value)
		if trimmed == "" {
			continue
		}
		key := strings.ToLower(trimmed)
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = struct{}{}
		result = append(result, trimmed)
	}

	if len(result) == 0 {
		return nil
	}
	return result
}
