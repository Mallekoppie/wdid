// Package invite generates and hashes single-use registration invite codes.
package invite

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base32"
	"encoding/hex"
	"fmt"
	"io"
	"strings"
)

const (
	prefix    = "wdid"
	codeBytes = 10
	groupSize = 4
)

// Generate returns a new invite code from the supplied random source. The code
// is human-transcribable: a fixed prefix over four base32 groups.
func Generate(source io.Reader) (string, error) {
	raw := make([]byte, codeBytes)
	if _, err := io.ReadFull(source, raw); err != nil {
		return "", fmt.Errorf("read invite randomness: %w", err)
	}

	encoded := base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(raw)

	var groups []string
	for start := 0; start < len(encoded); start += groupSize {
		end := start + groupSize
		if end > len(encoded) {
			end = len(encoded)
		}
		groups = append(groups, encoded[start:end])
	}

	return prefix + "-" + strings.Join(groups, "-"), nil
}

// New returns a new invite code using the operating system's secure random
// source.
func New() (string, error) {
	return Generate(rand.Reader)
}

// Hash returns the storage key for an invite code. Codes are case-insensitive
// and ignore spaces and hyphens so a hand-typed code still works.
func Hash(code string) string {
	canonical := strings.ToUpper(code)
	canonical = strings.NewReplacer("-", "", " ", "", "\t", "").Replace(canonical)
	sum := sha256.Sum256([]byte(canonical))
	return hex.EncodeToString(sum[:])
}
