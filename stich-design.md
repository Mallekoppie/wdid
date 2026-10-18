# Product Requirements Document (PRD): wdid

**Project Title:** wdid — what did I do? — Personal & Self-Hosted Work Journal, Rapid Time Attribution & AI Check-in Vault
**Document Version:** 1.0.0
**Status:** Approved for Implementation / Architecture Baseline
**Target Environment:** Dockerized Go/BoltDB Service with OIDC Federation (Zitadel Primary)

---

## 1. Executive Summary & Vision

### 1.1 Problem Statement
Engineers, engineering leaders, and specialized knowledge workers spend substantial non-coding hours in support, cross-team unblocking, architectural design reviews, and strategic execution. Traditional time-tracking software treats work as punch-cards for payroll or client billing, optimizing for managerial surveillance and invoicing rather than individual agency, review preparation, and verifiable impact demonstration.

Conversely, manual developer journals and markdown notes often fall out of sync or take too long to update mid-flow, resulting in end-of-quarter "review amnesia." The product must work for a single developer using it locally today, while supporting multi-user and hosted deployment models without redesigning the core experience later.

### 1.2 Vision & Value Proposition
**wdid** is a high-velocity, keyboard-first, work telemetry vault designed for both local-first and hosted deployment. It enables knowledge workers to capture work blocks, attribute time against strategic initiatives or operational categories, and record concrete outcome evidence in under five seconds.

At check-in or review cycles, wdid synthesizes granular telemetry into verified, review-ready accomplishments tailored for 1:1 manager updates, performance evaluations, or external LLM ingestions (e.g., Claude, local Ollama), without sacrificing data privacy or incurring costly multi-tenant SaaS overhead.

---

## 2. Core User Personas & Permissions

### 2.1 Personas
1. **Primary Operator / Contributor (Alex - "User"):**
   - Wants zero friction (<5 seconds) to track rapid timers or manual entries.
   - Needs automated aggregation of achievements with concrete evidence proofs.
   - Requires zero-data crossover: their journal, timers, and AI prompts are private to their account.
2. **Self-Hosting Administrator / Hosted Operator (Alex / Server Admin - "Admin"):**
   - Owns the physical container host or hosted deployment environment.
   - Needs automated zero-downtime hot backups, external offsite replication (S3/R2/SFTP), and invite-gated access control to keep compute/storage budgets low.
   - Manages identity bridges (Zitadel OIDC, Google SSO) and role assignments.
3. **Multi-User Team Member (future / not initial usage, but planned):**
   - Works inside a shared deployment with clear ownership boundaries and personal journal data.
   - Expects the same fast capture flow without being coupled to a single-user design.

### 2.2 RBAC Matrix
| Capability Area | Admin Role | User Role | Access & Scope Level |
| :--- | :---: | :---: | :--- |
| **Work Journal & Rapid Timers** | Full (Own Workspace) | Full (Own Workspace) | Strict tenant-isolated database buckets |
| **Strategic Initiatives & Allocation** | Full (Own Workspace) | Full (Own Workspace) | Scoped to individual account |
| **AI Check-in Synthesis & Prompt Buffer** | Full (Own Workspace) | Full (Own Workspace) | Scoped to individual account |
| **System Settings & Engine Config** | Read / Write | Restricted (HTTP 403) | System-level configuration |
| **BoltDB Backups & Remote Push** | Full Control | No Access | Host filesystem & replication level |
| **OIDC / SSO Identity Federation** | Full Control | No Access | IdP configuration & group mappings |
| **User Management & Invite Codes** | Full Control | No Access | Registration & user provisioning |

---

## 3. Product Scope & Boundary Conditions

### 3.1 In-Scope (v1 Release)
- **Sub-5-Second Capture:** Dedicated global hotkey / quick-entry input bar with keyboard triggers (`Space` or `Enter`), initiative switcher, running timer controls, and inline outcome logging.
- **Three-Tier Attribution Model:**
  - *Strategic Initiatives* (e.g., Billing Migration, Platform Hardening, Customer Ops Automation).
  - *Operational Support Categories* (Support, Design Reviews, Meetings, Admin, Learning).
  - *Other / Uncategorized Deep Work*.
- **Qualitative Outcome Capture:** Every log slice captures what was shipped/verified (e.g., "Script runs against staging", "Identified root cause in retry policy"), not merely elapsed minutes.
- **AI Check-in Synthesis & Prompt Handoff:**
  - Dynamic generation of bulleted achievements formatted for Manager 1:1s, Sprint Retros, and Annual Reviews.
  - LLM Prompt Buffer compatible with local Ollama runtimes and Claude/GPT web interfaces.
  - Review Readiness Score calculation (density of evidence vs. raw hours).
- **Deployment Modes:**
  - Local-first, self-hosted single-user deployment for privacy and portability.
  - Hosted deployment path for multi-user access, backup, identity, and centralized operation.
  - Shared architecture and UX that support both modes without forcing a single-user design decision.
- **Self-Hosted Storage Engine:**
  - BoltDB (`bbolt v1.3.8`) single-file embedded B+ tree database running in Docker with persistent host volume mounts (`/var/lib/logloop/data`).
  - Zero-lock atomic hot snapshot backup via read-only transaction copy (`db.View(tx.WriteTo)`).
  - Configurable offsite backup push destinations: Cloudflare R2 / AWS S3, secondary bind mounts, SSH/SFTP nodes.
- **Identity & Invite-Gated Access Control:**
  - Federated OIDC authentication: primary integration with Zitadel, plus Google Account and Generic Enterprise OIDC.
  - Break-glass local master passkey login.
  - Closed-alpha registration gating requiring single-use or admin-generated Operator Invite Codes to prevent unauthorized registration on self-funded compute.
- **Portable Multi-Format Exports:**
  - Stitch UI Builder JSON (`stitch-input.json`) for instant dashboard prototyping.
  - Human-readable Markdown work journal (`.md`) compatible with Obsidian, Logseq, and Notion.
  - Raw normalized CSV dump for DuckDB, pandas, or spreadsheet modeling.

### 3.2 Explicit Non-Goals (Out of Scope for v1)
- Payroll, invoicing, and approval-chain workflow tooling.
- Team timesheet enforcement or manager sign-off processes beyond basic review generation.
- Continuous invasive background telemetry (no keystroke logging, active window spying, or browser history tracking).
- Replacing full ticketing systems (e.g., Jira, Linear); initiatives are high-level umbrellas, not decomposed task boards.
- Public SaaS subscription billing, payment gateways, or public self-registration.

---

## 4. Architectural & Technical Specifications

```
                     +-------------------------------------------------+
                     |                 Docker Container                |
                     |                                                 |
  Browser Client <-> |  wdid Web App (Go Engine + Embedded UI)           |
  (Keyboard-First    |   - OIDC Auth Handler & Invite Gate             |
   Obsidian Slate)   |   - RBAC Middleware (Admin vs User)             |
                     |   - Timer & Rapid Journaling Engine             |
                     |   - AI Prompt & Synthesis Formatter             |
                     |                                                 |
                     |           bbolt Engine (v1.3.8)                 |
                     +-----------------------+-------------------------+
                                             |
                         Read-Tx Copy (`db.View`) / Mounted Volume
                                             |
                                             v
                     +-------------------------------------------------+
                     | Host Volume: /var/lib/logloop/data/logloop.db   |
                     |                                                 |
                     | Automated Hot Snapshots (.db Ledger)            |
                     +-------+--------------------+--------------------+
                             |                    |
                             v                    v
                  [Cloudflare R2 / S3]   [SFTP / Secondary Mount]
```

### 4.1 Storage & Data Isolation Model
- **Engine:** BoltDB (`go.etcd.io/bbolt`).
- **Data Isolation:** User records are isolated via prefixed bucket structures (e.g., `user_<uuid>:work_items`, `user_<uuid>:initiatives`, `user_<uuid>:summaries`). Administrative tables (`sys:users`, `sys:oidc_config`, `sys:snapshots`, `sys:invites`) reside in protected system buckets inaccessible to user session scopes.
- **Multi-User Design:** The storage model is created for multiple user accounts from day one, even if the initial live deployment is a single developer instance. This avoids a later migration from a single-user schema to a multi-user architecture.
- **Backup Architecture:** Backups execute via BoltDB's built-in transaction streaming:
  ```go
  err := db.View(func(tx *bbolt.Tx) error {
      return tx.WriteTo(backupFileWriter)
  })
  ```
  This creates an exact, point-in-time byte copy of the database without holding write locks or pausing active timers.

### 4.2 Authentication & Token Pipeline
- **OIDC Discovery & JWKS Verification:** Validates tokens against provider JWKS endpoints (supporting RS256 and EdDSA).
- **Claim Mapping:** Admin role elevation triggered by customizable JWT claim filters (e.g., `groups` contains `logloop-admins`).
- **Invite Token Verification:** User registration endpoint accepts `invite_code`; validates against `sys:invites` prior to creating account credentials and provisioning user buckets.

---

## 5. UI Architecture & Screen Manifest

The wdid suite comprises six core desktop views styled in the `Obsidian Slate Utility` design system:

| Screen # | Screen Title | Primary User Job & Key Interactions |
| :--- | :--- | :--- |
| **01** | **Today & Rapid Timer** (`SCREEN_18`) | Active timer ticker (`00:42:21`), sub-5s quick-capture bar with outcome pill, chronological daily work feed, standup evidence digest, and Q3 goal progress meters. |
| **02** | **Initiatives & Time Allocation** (`SCREEN_16`) | Three-tier time attribution (Strategic vs. Ops vs. Other), quarterly interactive stacked distribution bar, initiative progress vs. target outcomes, and operational category drilldowns. |
| **03** | **AI Check-in Summary & Bullets** (`SCREEN_14`) | Executive synthesis generation, audience selector (1:1 Manager, Performance Review, Sprint Retro), structured markdown prompt buffer, review readiness score, and cross-team impact logs. |
| **04** | **Vault & Backups** (`SCREEN_10`) | Docker volume status, `bbolt check` diagnostic integrity log, point-in-time `.db` snapshot ledger, and destination cards for Cloudflare R2, secondary mount, and SFTP. |
| **05** | **Data Exports** (`SCREEN_6`) | Modular download feeds: Stitch UI Builder JSON, Obsidian-compatible Markdown Work Journal, normalized CSV raw dump, AI prompt digest, and feed webhooks. |
| **06** | **Users & Access** (`SCREEN_4`) | Multi-account inventory, authentication source badges, role dropdown toggles (`Admin` vs `User`), granular zero-trust permission matrix, and wildcard bulk OIDC invite configurator. |
| **07** | **OIDC & Authentication** (`SCREEN_8`) | IdP discovery URL inspector, client secret storage, priority-based claim role mapping rules, synthetic handshake probe trace, and local password disable toggle. |
| **08** | **Login & Registration** (`SCREEN_2`) | Federated IdP action hub (Zitadel primary button, Google SSO, Enterprise OIDC), closed-alpha invite code input gate, and break-glass master passkey fallback. |

---

## 6. Success Metrics & Validation Criteria

1. **Capture Latency:** Time from keyboard trigger (`T` or hotkey) to completed log entry < 5.0 seconds.
2. **Review Prep Time:** Time required to assemble a verifiable, evidence-backed quarterly review draft reduced from hours to < 3 minutes.
3. **Data Durability & Recovery:** 100% of hot backups pass `bbolt check` verification with 0 corrupt pages; automated offsite push executes within 60 seconds of snapshot creation.
4. **Cost & Boundary Integrity:** 0 unintended self-registrations permitted without valid invite codes; zero compute or storage overhead incurred from unauthenticated public traffic.
