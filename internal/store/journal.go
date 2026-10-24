package store

import (
	"encoding/json"
	"errors"
	"fmt"
	"sort"

	"github.com/Mallekoppie/goslow/platform"
	"go.etcd.io/bbolt"

	"github.com/Mallekoppie/wdid/internal/domain"
)

// SaveMilestone creates or replaces a dated checkpoint. Its subcategory must
// belong to the same user.
func (s *Store) SaveMilestone(milestone domain.Milestone) error {
	milestone.Normalize()
	if err := domain.ValidateMilestone(milestone); err != nil {
		return err
	}
	return platform.Database.BoltDb.Update(func(tx *bbolt.Tx) error {
		if err := requireSubcategoryTx(tx, milestone.UserID, milestone.SubcategoryID); err != nil {
			return err
		}
		return putJSON(tx, userBucket(milestone.UserID, milestonesBucket), milestone.ID, milestone)
	})
}

// Milestone returns one milestone owned by the user.
func (s *Store) Milestone(userID, id string) (domain.Milestone, error) {
	var milestone domain.Milestone
	if err := readObject(userBucket(userID, milestonesBucket), id, &milestone); err != nil {
		return domain.Milestone{}, err
	}
	return milestone, nil
}

// Milestones returns the user's milestones, optionally narrowed to one
// subcategory, ordered by due date with undated milestones last.
func (s *Store) Milestones(userID, subcategoryID string) ([]domain.Milestone, error) {
	raw, err := readAllRaw(userBucket(userID, milestonesBucket))
	if err != nil {
		return nil, err
	}

	milestones := make([]domain.Milestone, 0, len(raw))
	for _, value := range raw {
		var milestone domain.Milestone
		if err := json.Unmarshal([]byte(value), &milestone); err != nil {
			return nil, fmt.Errorf("decode milestone: %w", err)
		}
		if subcategoryID != "" && milestone.SubcategoryID != subcategoryID {
			continue
		}
		milestones = append(milestones, milestone)
	}

	sort.Slice(milestones, func(i, j int) bool {
		if (milestones[i].DueDate == "") != (milestones[j].DueDate == "") {
			return milestones[j].DueDate == ""
		}
		if milestones[i].DueDate != milestones[j].DueDate {
			return milestones[i].DueDate < milestones[j].DueDate
		}
		return milestones[i].CreatedAt.Before(milestones[j].CreatedAt)
	})

	return milestones, nil
}

// DeleteMilestone removes one milestone owned by the user.
func (s *Store) DeleteMilestone(userID, id string) error {
	if _, err := s.Milestone(userID, id); err != nil {
		return err
	}
	return platform.Database.BoltDb.RemoveObject(userBucket(userID, milestonesBucket), id)
}

// SaveNote creates or replaces a day or project note. A note attached to a
// subcategory requires that subcategory to exist for the same user.
func (s *Store) SaveNote(note domain.Note) error {
	note.Normalize()
	if err := domain.ValidateNote(note); err != nil {
		return err
	}
	return platform.Database.BoltDb.Update(func(tx *bbolt.Tx) error {
		if note.SubcategoryID != "" {
			if err := requireSubcategoryTx(tx, note.UserID, note.SubcategoryID); err != nil {
				return err
			}
		}
		return putJSON(tx, userBucket(note.UserID, notesBucket), note.ID, note)
	})
}

// Note returns one note owned by the user.
func (s *Store) Note(userID, id string) (domain.Note, error) {
	var note domain.Note
	if err := readObject(userBucket(userID, notesBucket), id, &note); err != nil {
		return domain.Note{}, err
	}
	return note, nil
}

// NoteFilter narrows a note listing.
type NoteFilter struct {
	Date          string
	SubcategoryID string
}

// Notes returns the user's notes matching the filter, newest first.
func (s *Store) Notes(userID string, filter NoteFilter) ([]domain.Note, error) {
	raw, err := readAllRaw(userBucket(userID, notesBucket))
	if err != nil {
		return nil, err
	}

	notes := make([]domain.Note, 0, len(raw))
	for _, value := range raw {
		var note domain.Note
		if err := json.Unmarshal([]byte(value), &note); err != nil {
			return nil, fmt.Errorf("decode note: %w", err)
		}
		if filter.Date != "" && note.Date != filter.Date {
			continue
		}
		if filter.SubcategoryID != "" && note.SubcategoryID != filter.SubcategoryID {
			continue
		}
		notes = append(notes, note)
	}

	sort.Slice(notes, func(i, j int) bool {
		return notes[i].CreatedAt.After(notes[j].CreatedAt)
	})

	return notes, nil
}

// DeleteNote removes one note owned by the user.
func (s *Store) DeleteNote(userID, id string) error {
	if _, err := s.Note(userID, id); err != nil {
		return err
	}
	return platform.Database.BoltDb.RemoveObject(userBucket(userID, notesBucket), id)
}

// SaveCheckIn creates or replaces a manager check-in or personal review. Once
// a manager check-in is final it is read-only; drafts and personal reviews
// remain editable.
func (s *Store) SaveCheckIn(checkIn domain.CheckIn) error {
	checkIn.Normalize()
	if err := domain.ValidateCheckIn(checkIn); err != nil {
		return err
	}

	return platform.Database.BoltDb.Update(func(tx *bbolt.Tx) error {
		bucket := userBucket(checkIn.UserID, checkInsBucket)

		var existing domain.CheckIn
		err := readTxObject(tx, bucket, checkIn.ID, &existing)
		switch {
		case err == nil:
			if err := ensureCheckInWritable(existing); err != nil {
				return err
			}
		case !errors.Is(err, ErrNotFound):
			return err
		}

		return putJSON(tx, bucket, checkIn.ID, checkIn)
	})
}

// LastFinalManagerCheckIn returns the final manager check-in whose period ends
// latest. It is the boundary the next manager check-in starts from, so drafts,
// personal reviews and earlier finals never move it.
func (s *Store) LastFinalManagerCheckIn(userID string) (domain.CheckIn, bool, error) {
	raw, err := readAllRaw(userBucket(userID, checkInsBucket))
	if err != nil {
		return domain.CheckIn{}, false, err
	}

	var latest domain.CheckIn
	found := false
	for _, value := range raw {
		var checkIn domain.CheckIn
		if err := json.Unmarshal([]byte(value), &checkIn); err != nil {
			return domain.CheckIn{}, false, fmt.Errorf("decode check-in: %w", err)
		}
		if checkIn.Kind != domain.CheckInKindManager || checkIn.State != domain.CheckInStateFinal {
			continue
		}
		if !found ||
			checkIn.PeriodEnd > latest.PeriodEnd ||
			(checkIn.PeriodEnd == latest.PeriodEnd && checkIn.CreatedAt.After(latest.CreatedAt)) {
			latest = checkIn
			found = true
		}
	}

	return latest, found, nil
}

// CheckIn returns one check-in owned by the user.
func (s *Store) CheckIn(userID, id string) (domain.CheckIn, error) {
	var checkIn domain.CheckIn
	if err := readObject(userBucket(userID, checkInsBucket), id, &checkIn); err != nil {
		return domain.CheckIn{}, err
	}
	return checkIn, nil
}

// CheckIns returns the user's check-ins, optionally narrowed to one kind,
// newest first.
func (s *Store) CheckIns(userID string, kind domain.CheckInKind) ([]domain.CheckIn, error) {
	raw, err := readAllRaw(userBucket(userID, checkInsBucket))
	if err != nil {
		return nil, err
	}

	checkIns := make([]domain.CheckIn, 0, len(raw))
	for _, value := range raw {
		var checkIn domain.CheckIn
		if err := json.Unmarshal([]byte(value), &checkIn); err != nil {
			return nil, fmt.Errorf("decode check-in: %w", err)
		}
		if kind != "" && checkIn.Kind != kind {
			continue
		}
		checkIns = append(checkIns, checkIn)
	}

	sort.Slice(checkIns, func(i, j int) bool {
		return checkIns[i].CreatedAt.After(checkIns[j].CreatedAt)
	})

	return checkIns, nil
}

// DeleteCheckIn removes one check-in owned by the user. A final manager
// check-in cannot be deleted; a personal review or draft can.
func (s *Store) DeleteCheckIn(userID, id string) error {
	return platform.Database.BoltDb.Update(func(tx *bbolt.Tx) error {
		bucket := userBucket(userID, checkInsBucket)

		var existing domain.CheckIn
		if err := readTxObject(tx, bucket, id, &existing); err != nil {
			return err
		}
		if err := ensureCheckInWritable(existing); err != nil {
			return err
		}

		return tx.Bucket([]byte(bucket)).Delete([]byte(id))
	})
}

func ensureCheckInWritable(checkIn domain.CheckIn) error {
	if checkIn.Kind == domain.CheckInKindManager && checkIn.State == domain.CheckInStateFinal {
		return ErrFinalCheckInReadOnly
	}
	return nil
}

func requireSubcategoryTx(tx *bbolt.Tx, userID, subcategoryID string) error {
	var subcategory domain.Subcategory
	err := readTxObject(tx, userBucket(userID, subcategoriesBucket), subcategoryID, &subcategory)
	if errors.Is(err, ErrNotFound) {
		return ErrSubcategoryNotFound
	}
	return err
}
