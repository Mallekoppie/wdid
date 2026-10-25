# People are names on work entries, not entities

**Status:** Accepted — 2026-10-25

A person is the `person` string on a support work entry. There is no Person
record, identifier, rename or migration path. A per-account **Person roster**
persists common names as a convenience for one-tap selection; it is a list of
names, so removing or editing one only changes the list of suggestions and never
rewrites a historical entry. Repeated names are deduplicated case-insensitively,
keeping the first spelling in stable order.

**Considered options:** a Person entity with identifiers and rename (rejected:
entries are immutable records of what happened, a rename would silently rewrite
recorded history, and no current workflow needs a people-management surface);
free text with no roster (rejected: every support entry would retype a name and
common people could not be chosen in one tap); deriving the roster from existing
entries at read time (rejected: a deliberately emptied roster would be
resurrected, so the roster is persisted with an internal seeded marker).

**Consequences:** the roster lives in the per-account settings record and its
internal `supportPeopleSeeded` marker is never exposed on the wire. It is seeded
once from existing support-role entries and then replaced wholesale by
`UpdateSettings`. Removing a name changes only the roster. Reports may show a
person's spelling differently from the roster because report aggregation picks
its own display spelling; that is acceptable while people are names rather than
entities.
