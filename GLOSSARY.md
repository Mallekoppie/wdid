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

**Check-in**:
A saved artifact covering a period, with focus notes, aggregates, and an optional
summary. Every check-in has a kind.
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
