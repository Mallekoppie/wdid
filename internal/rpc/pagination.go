package rpc

import (
	"strconv"

	"github.com/Mallekoppie/wdid/internal/domain"
)

const (
	defaultPageSize = 100
	maxPageSize     = 500
)

// paginate applies the contract's page_size/page_token convention to an
// already-loaded list. Taxonomy lists are bounded, so a numeric offset token is
// sufficient and stable for the lifetime of one read.
func paginate[T any](items []T, pageSize int32, pageToken string) ([]T, string, error) {
	offset := 0
	if pageToken != "" {
		parsed, err := strconv.Atoi(pageToken)
		if err != nil || parsed < 0 {
			return nil, "", domain.ValidationError{
				Field:   "pageToken",
				Message: "is invalid",
			}
		}
		offset = parsed
	}

	size := int(pageSize)
	if size <= 0 {
		size = defaultPageSize
	}
	if size > maxPageSize {
		size = maxPageSize
	}
	if offset >= len(items) {
		return nil, "", nil
	}

	end := offset + size
	if end > len(items) {
		end = len(items)
	}

	nextPageToken := ""
	if end < len(items) {
		nextPageToken = strconv.Itoa(end)
	}
	return items[offset:end], nextPageToken, nil
}
