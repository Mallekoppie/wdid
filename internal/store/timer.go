package store

import (
	"errors"
	"strings"
	"time"

	"github.com/Mallekoppie/goslow/platform"
	"go.etcd.io/bbolt"

	"github.com/Mallekoppie/wdid/internal/domain"
)

// StartTimer starts the user's single active timer. Starting while one is
// already running is a state conflict, and the category/subcategory pair is
// checked before anything is written.
func (s *Store) StartTimer(timer domain.ActiveTimer) error {
	timer.Normalize()
	if timer.CategoryID == "" {
		return domain.ValidationError{Field: "categoryId", Message: "is required"}
	}
	if err := domain.ValidateTimerStart(timer.Description); err != nil {
		return err
	}

	return platform.Database.BoltDb.Update(func(tx *bbolt.Tx) error {
		var existing domain.ActiveTimer
		err := readTxObject(tx, userBucket(timer.UserID, timerBucket), timerKey, &existing)
		switch {
		case err == nil:
			return ErrTimerRunning
		case !errors.Is(err, ErrNotFound):
			return err
		}

		var category domain.Category
		err = readTxObject(tx, userBucket(timer.UserID, categoriesBucket), timer.CategoryID, &category)
		if errors.Is(err, ErrNotFound) {
			return ErrCategoryNotFound
		}
		if err != nil {
			return err
		}

		if category.Role == domain.CategoryRoleSupport && len(timer.People) == 0 {
			return domain.ValidationError{Field: "person", Message: "is required for support timers"}
		}

		if timer.SubcategoryID != "" {
			var subcategory domain.Subcategory
			err = readTxObject(tx, userBucket(timer.UserID, subcategoriesBucket), timer.SubcategoryID, &subcategory)
			if errors.Is(err, ErrNotFound) {
				return ErrSubcategoryNotFound
			}
			if err != nil {
				return err
			}
			if subcategory.CategoryID != category.ID {
				return domain.ValidationError{Field: "subcategoryId", Message: "subcategory must belong to its category"}
			}
		}

		return putJSON(tx, userBucket(timer.UserID, timerBucket), timerKey, timer)
	})
}

// PauseTimer stops the elapsed clock and keeps the timer active. Pausing an
// already paused timer is idempotent, so a double click in two tabs is safe.
func (s *Store) PauseTimer(userID string, now time.Time) (domain.ActiveTimer, error) {
	now = now.UTC()
	var updated domain.ActiveTimer

	err := platform.Database.BoltDb.Update(func(tx *bbolt.Tx) error {
		timer, err := readTimerTx(tx, userID)
		if err != nil {
			return err
		}
		if !timer.Paused() {
			if !timer.SegmentStartedAt.IsZero() && now.After(timer.SegmentStartedAt) {
				timer.AccumulatedSeconds += int64(now.Sub(timer.SegmentStartedAt) / time.Second)
			}
			pausedAt := now
			timer.PausedAt = &pausedAt
			timer.SegmentStartedAt = now
			if err := putJSON(tx, userBucket(userID, timerBucket), timerKey, timer); err != nil {
				return err
			}
		}
		updated = timer
		return nil
	})
	return updated, err
}

// ResumeTimer restarts the elapsed clock after a pause. Resuming a running
// timer is idempotent.
func (s *Store) ResumeTimer(userID string, now time.Time) (domain.ActiveTimer, error) {
	now = now.UTC()
	var updated domain.ActiveTimer

	err := platform.Database.BoltDb.Update(func(tx *bbolt.Tx) error {
		timer, err := readTimerTx(tx, userID)
		if err != nil {
			return err
		}
		if timer.Paused() {
			timer.PausedAt = nil
			timer.SegmentStartedAt = now
			if err := putJSON(tx, userBucket(userID, timerBucket), timerKey, timer); err != nil {
				return err
			}
		}
		updated = timer
		return nil
	})
	return updated, err
}

// StopTimer ends the active timer. It returns the saved work entry, or true
// for discarded when the caller chose not to record the block. Paused time is
// excluded from the entry length.
//
// A stop under one minute is rejected unless it is a discard. Above the block
// limit, the default save action is rejected until the caller chooses keep,
// trim or discard. Entries and the cleared timer are written in one
// transaction, so a failure never loses one without the other.
func (s *Store) StopTimer(userID string, now time.Time, action domain.TimerStopAction, blockLimitMinutes int) (domain.WorkEntry, bool, error) {
	now = now.UTC()
	if !action.Valid() {
		return domain.WorkEntry{}, false, domain.ValidationError{Field: "action", Message: "must be save, keep, trim or discard"}
	}

	var entry domain.WorkEntry
	discarded := false

	err := platform.Database.BoltDb.Update(func(tx *bbolt.Tx) error {
		timer, err := readTimerTx(tx, userID)
		if err != nil {
			return err
		}

		elapsed := timer.Elapsed(now)
		elapsedMinutes := int(elapsed / time.Minute)
		if elapsedMinutes < 1 && action != domain.TimerStopDiscard {
			return domain.TimerConflictError{
				Reason:         domain.TimerConflictTooShort,
				ElapsedMinutes: elapsedMinutes,
			}
		}

		// Compare durations, not floored minutes: 4h00m59s is still past a
		// four-hour block limit even though it floors to 240 minutes.
		blockLimit := time.Duration(blockLimitMinutes) * time.Minute
		if blockLimitMinutes > 0 && elapsed > blockLimit {
			switch action {
			case domain.TimerStopSave:
				return domain.TimerConflictError{
					Reason:            domain.TimerConflictBlockLimit,
					ElapsedMinutes:    elapsedMinutes,
					BlockLimitMinutes: blockLimitMinutes,
				}
			case domain.TimerStopTrim:
				elapsedMinutes = blockLimitMinutes
			case domain.TimerStopDiscard:
				discarded = true
				return deleteTimerTx(tx, userID)
			case domain.TimerStopKeep:
				// Keep the full elapsed length.
			}
		} else if action == domain.TimerStopDiscard {
			discarded = true
			return deleteTimerTx(tx, userID)
		}

		entry = domain.WorkEntry{
			ID:            domain.NewID(),
			UserID:        userID,
			CategoryID:    timer.CategoryID,
			SubcategoryID: timer.SubcategoryID,
			Description:   timer.Description,
			People:        timer.People,
			StartedAt:     timer.StartedAt,
			EndedAt:       timer.StartedAt.Add(time.Duration(elapsedMinutes) * time.Minute),
			Minutes:       elapsedMinutes,
			Source:        domain.EntrySourceTimer,
			CreatedAt:     now,
			UpdatedAt:     now,
		}
		entry.Normalize()
		if entry.Description == "" {
			entry.Description = timerDescription(tx, timer)
		}
		if err := saveWorkEntryTx(tx, entry); err != nil {
			return err
		}
		return deleteTimerTx(tx, userID)
	})
	if err != nil {
		return domain.WorkEntry{}, false, err
	}
	return entry, discarded, nil
}

func readTimerTx(tx *bbolt.Tx, userID string) (domain.ActiveTimer, error) {
	var timer domain.ActiveTimer
	err := readTxObject(tx, userBucket(userID, timerBucket), timerKey, &timer)
	if errors.Is(err, ErrNotFound) {
		return domain.ActiveTimer{}, ErrTimerNotRunning
	}
	return timer, err
}

func deleteTimerTx(tx *bbolt.Tx, userID string) error {
	bucket := tx.Bucket([]byte(userBucket(userID, timerBucket)))
	if bucket == nil {
		return nil
	}
	return bucket.Delete([]byte(timerKey))
}

// timerDescription falls back to the attribution name when the timer was
// started without a description, because every work entry needs one.
func timerDescription(tx *bbolt.Tx, timer domain.ActiveTimer) string {
	if timer.SubcategoryID != "" {
		var subcategory domain.Subcategory
		if err := readTxObject(tx, userBucket(timer.UserID, subcategoriesBucket), timer.SubcategoryID, &subcategory); err == nil {
			if name := strings.TrimSpace(subcategory.Name); name != "" {
				return name
			}
		}
	}

	var category domain.Category
	if err := readTxObject(tx, userBucket(timer.UserID, categoriesBucket), timer.CategoryID, &category); err == nil {
		if name := strings.TrimSpace(category.Name); name != "" {
			return name
		}
	}
	return "Timer"
}
