# People are names on work entries, not entities

**Status:** Accepted — 2026-10-25

A person is a name on a support work entry or active support timer. An entry
holds an ordered list of names, and a support entry requires at least one. There
is no Person record, identifier or rename. A per-account **Person roster**
persists common names as a convenience for selection; it is a list of names, so
removing or editing one only changes the list of suggestions and never rewrites
a historical entry. Repeated names are deduplicated case-insensitively, keeping
the first spelling in stable order.

**JSON migration:** records written before multi-person support carry a single
`"person":"Priya"` field. `WorkEntry.UnmarshalJSON` and
`ActiveTimer.UnmarshalJSON` read it as a one-name list, so stored records
continue to load without a rewrite pass. Every save writes the new
`"people":["Priya"]` shape. The person index version is bumped so existing
databases rebuild the index with one key per name.

**Considered options:** a Person entity with identifiers and rename (rejected:
entries are immutable records of what happened, a rename would silently rewrite
recorded history, and no current workflow needs a people-management surface);
free text with no roster (rejected: every support entry would retype a name and
common people could not be chosen in one tap); deriving the roster from existing
entries at read time (rejected: a deliberately emptied roster would be
resurrected, so the roster is persisted with an internal seeded marker).

**Attribution:** because the names are not entities, a multi-person support
entry is credited in full to every name it lists: each named person receives the
entry's minutes and one interaction. Per-person rollups may therefore add up to
more than the total support time. All total-support figures — the Support
header, Review, check-in detail, export totals and check-in snapshots — come
from the authoritative entry total and entry count, never from summing the
per-person rows. `support.csv` stays one row per entry with the names joined by
`;`.

**Consequences:** the roster lives in the per-account settings record and its
internal `supportPeopleSeeded` marker is never exposed on the wire. It is seeded
once from every name on existing support-role entries and then replaced wholesale
by `UpdateSettings`. Removing a name changes only the roster. Reports may show a
person's spelling differently from the roster because report aggregation picks
its own display spelling; that is acceptable while people are names rather than
entities. Clients must render the authoritative support totals rather than
deriving them from the per-person allocation list.
