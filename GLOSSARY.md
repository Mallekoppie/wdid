# wdid

wdid is a personal work ledger: it records time against a user-configurable
taxonomy, captures outcomes and support work, and produces manager check-ins and
personal reviews.

## Language

**Work entry**:
A recorded block of work time with one category, an optional subcategory, a
description, an outcome, and authoritative minutes.
_Avoid_: work item, task, ticket, log entry, time log

**Category**:
A user-defined top-level grouping of work with one immutable reporting role, a
name, and an archived state.
_Avoid_: tag, label, bucket, project

**Subcategory**:
The optional second level under a category; it never has children. Under an
initiative-role category it is the specific project the user is working on.
_Avoid_: child category, sub-project, third level, project (in domain discussion)

**Reporting role**:
What a category means for reporting and validation: `initiative`, `support`, or
`other`. Reports use the role, never the category name.
_Avoid_: type, kind, category type

**Initiative**:
Work in a category whose reporting role is `initiative`: a major body of work
spanning days or weeks. The specific effort is its subcategory.
_Avoid_: epic, goal, objective

**Support**:
Work in a category whose reporting role is `support`: time spent helping another
person succeed. A support entry holds an ordered list of people and requires at
least one name; its mode is its subcategory and its impact is its outcome.
Reporting credits each named person the entry's **full minutes and one
interaction**. The support totals (minutes and interactions) count each entry
once, so per-person rollups may add up to more than the total support time.
_Avoid_: assistance, help, mentoring (that is a mode)

**Person roster**:
The per-account list of common support-person names offered wherever a support
person is entered. An entry may name several people from it. It is a convenience
list of names, not a directory of entities: adding or removing a name never
changes any work entry, and there is no rename.
_Avoid_: contacts, people directory, person entity, team members

**Other**:
Work in a category whose reporting role is `other`: meetings, admin, learning,
and unplanned work.
_Avoid_: misc, uncategorized, overhead

**Invite**:
A single-use registration code issued for one email address, redeemable once by
that person.
_Avoid_: token, referral code, invite link, signup secret

**Bootstrap secret**:
The deployment-provided secret used once to create the first account, which
becomes admin. It is not accepted after that account exists.
_Avoid_: registration secret, signup secret, setup key, admin password

**Local mode**:
The default deployment: one account identified by a username, with an optional
password, created on first run. There is no email, bootstrap secret, invite or
OIDC, and no second account can be created.
_Avoid_: single-user mode, standalone mode, personal install

**Server mode**:
The opt-in multi-user deployment (`WDID_AUTH_MODE=server`, and always the
effective mode when development mode is on): a bootstrap admin, email/password
accounts, single-use invites, and optional Zitadel OIDC.
_Avoid_: hosted mode, cloud mode, multi-user mode (the domain model is always
multi-user)

**Username**:
The identity a local account signs in with. It is compared case-insensitively,
stored with its original spelling for display, and is empty for server accounts,
which are addressed by email.
_Avoid_: handle, login name, user id

**Check-in**:
A saved artifact covering a period, with focus notes, aggregates, an optional
additional context, and an optional summary. Every check-in has a kind. A
generated summary records the exact prompt sent to the model as a prompt
snapshot, plus the summary it replaced for a one-step revert.
_Avoid_: report, review, summary

**Manager check-in**:
A check-in whose kind is `manager`. Only a final manager check-in moves the
boundary for the next manager check-in.
_Avoid_: 1:1 (that is an audience), status report, checkpoint

**Personal review**:
A check-in whose kind is `personal`. It is used for weekly or monthly self-review,
never moves the manager boundary, and remains editable.
_Avoid_: self-check-in, retro, personal check-in

**Period**:
The date range a check-in covers; it is not necessarily a calendar quarter.
_Avoid_: range, window, cycle, sprint

**Milestone**:
A dated checkpoint attached to a subcategory.
_Avoid_: task, ticket

**Note**:
Free text attached to a day or to a subcategory.
_Avoid_: comment, memo, annotation

**Prompt template**:
A per-user, per-variant instruction body for check-in generation, stored in the
caller's settings. An absent or blank template means that variant's built-in
body. The server resolves the template and appends the prompt rules, so the
client never composes a prompt.
_Avoid_: system prompt, custom prompt (when meaning the whole instruction)

**Prompt rules**:
The server-owned honesty suffix appended to every resolved prompt template: use
only the supplied data, invent nothing, cite links only when present, and output
Markdown. A user can never edit, omit, replace or reorder them.
_Avoid_: guardrails, constraints

**Additional context**:
Free text a user records on a check-in for facts the ledger did not capture. It
is authoritative supplied data for generation, is never redacted, and appears
under `## Notes and context` in the export.
_Avoid_: notes, extra notes, comments

**AI provider key**:
The per-account Anthropic-compatible API key stored write-only in that account's
settings. The account sets, replaces or clears its own key; AI generation is
disabled until one is stored, and the key never appears in an RPC response or an
export.
_Avoid_: OpenAI key, deployment key, global API key, API token
