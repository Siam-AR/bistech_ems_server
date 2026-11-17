# FTL: Feature Ticket List (Agentic Development), BisTech EMS

Version: 2.0 | Date: 2026-11-17
Read first: PRD.md (what/why), TAD.md (structure), SAD.md (security), FSD.md (exact behaviour and tests T-xx).

Each ticket is one separately deliverable feature with its own **Priority, Dependencies, Checklist and Acceptance Criteria**.

**Priority scale**
- **P0**: blocks everything or is a security/data-integrity must. Build first.
- **P1**: core MVP feature. Required for release.
- **P2**: required for release but can follow P0/P1 work, or hardening and polish.

Build order is driven by **Dependencies** (ticket IDs), not by phases. A ticket may start only when all its dependencies are Done.

---

## 0. Rules for coding agents

1. Source of truth order: FSD.md (behaviour) > SAD.md (security) > TAD.md (structure) > PRD.md (intent). On conflict, stop and raise it.
2. One ticket = one PR-sized change (split if larger). Start only when dependencies are Done.
3. Never add: Redis, `forwardRef`, serverless backend, hard deletes, check-out, nightly absence jobs, file uploads, or any PRD non-goal.
4. Every controller handler has `@RequirePermission(...)` or `@Public()`. Permission keys come from the single definition in `packages/contracts`.
5. Schemas live in `packages/contracts` (strict Zod). Responses use explicit DTOs, never entities.
6. Org id comes from the session only; it is a required argument on every repository function.
7. Multi-step operations run in one `transactionService.run()`. Audit rows are written by `AuditService` in the same transaction. No email or network call inside a transaction; enqueue after commit.
8. Out-of-scope records return 404. Use error codes from FSD.md section 3 exactly.
9. Migrations are plain SQL, backward compatible, never run on app start.
10. Modules import only other modules' exported facades. Cross-module lifecycle calls use `EmployeeLifecycleHandler`.
11. Frontend: Next.js App Router, shadcn/ui, lucide-react (individual imports), next-themes dark default, Zod from contracts, react-hook-form + Zod resolver, no tokens in storage, dark mode passes axe contrast.
12. Never log or return passwords, tokens, OTPs, Gmail credentials, or personal profile values.
13. A ticket is not done until its listed tests exist and pass in CI.
14. If a ticket hits an unresolved Open Question (Q-id), use the default in PRD section 4 and note it in the PR.

### Definition of Done (applies to every ticket, in addition to its own checklist)
- [ ] Permission declared and matrix test passes
- [ ] Zod schema in `packages/contracts`
- [ ] Audit record where SAD.md section 8 requires one
- [ ] Transaction and duplicate guard per FSD.md sections 2 and 10
- [ ] New queries checked with `EXPLAIN`
- [ ] Tests listed in the ticket added and passing
- [ ] Docs updated; reviewed by a second developer

### Agent prompt template
```
Ticket: <ID> <title>
Read: FSD.md <sections>, SAD.md <sections>, TAD.md <sections>
Do: implement the ticket checklist
Constraints: section 0 rules; FSD.md error codes
Verify: every Acceptance Criterion and listed tests pass
Report: files changed, tests added, assumptions taken (with Q-id)
```

---

## 1. Ticket index

| ID | Feature | Priority | Depends on |
|---|---|---|---|
| F-001 | Monorepo and CI pipeline | P0 | none |
| F-002 | Database schema, constraints and seed | P0 | F-001 |
| F-003 | NestJS platform skeleton and request pipeline | P0 | F-001 |
| F-004 | Database module and TransactionService | P0 | F-002, F-003 |
| F-005 | Observability and health | P1 | F-003 |
| F-006 | Queue and email (pg-boss, Nodemailer Gmail) | P0 | F-003 |
| F-007 | Web app shell and UI foundation | P0 | F-001 |
| F-008 | Environments, secrets and staging deployment | P1 | F-001, F-002 |
| F-009 | Authorization test generator and route scan | P0 | F-002, F-003 |
| F-010 | Login, sessions, refresh, logout | P0 | F-004, F-011 |
| F-011 | Authentication and permissions guards (RBAC + scope) | P0 | F-002, F-003, F-004 |
| F-012 | CSRF protection | P0 | F-010 |
| F-013 | Audit service | P0 | F-004 |
| F-014 | Invite acceptance | P0 | F-010, F-006 |
| F-015 | Forgot password with OTP | P0 | F-010, F-006, F-013 |
| F-016 | Change password and session management | P1 | F-010 |
| F-017 | User and role administration | P1 | F-011, F-013 |
| F-018 | Rate limiting | P1 | F-003 |
| F-019 | Authentication UI | P1 | F-007, F-010, F-014, F-015, F-016 |
| F-020 | Organization settings | P1 | F-013, F-011 |
| F-021 | Departments, designations, holidays | P1 | F-020 |
| F-022 | Department head assignment | P1 | F-021, F-017 |
| F-023 | Employee creation and onboarding | P0 | F-021, F-014, F-013, F-006 |
| F-024 | Employee list, detail and sensitive profile | P1 | F-023 |
| F-025 | Department and designation change | P1 | F-024 |
| F-026 | Deactivate and reactivate employee | P1 | F-025, F-016 |
| F-027 | Organization and employee UI | P1 | F-007, F-021, F-023, F-024, F-025, F-026 |
| F-030 | Attendance check-in | P0 | F-020, F-021 |
| F-031 | Derived absence engine | P0 | F-030 |
| F-032 | Attendance views and summaries | P1 | F-031, F-024 |
| F-033 | HR attendance correction | P1 | F-030, F-013 |
| F-034 | Attendance UI | P1 | F-007, F-032, F-033 |
| F-040 | Teams | P1 | F-024 |
| F-041 | Task creation (self, individual, team) | P0 | F-040 |
| F-042 | Task status state machine | P0 | F-041 |
| F-043 | Task submissions | P0 | F-042 |
| F-044 | Submission review | P0 | F-043 |
| F-045 | Task read, update and cancel | P1 | F-041 |
| F-046 | Task comments | P2 | F-041 |
| F-047 | Team and department boards | P1 | F-041 |
| F-048 | In-app notifications | P1 | F-041 |
| F-049 | Employee lifecycle handlers for teams and tasks | P1 | F-025, F-026, F-040, F-041 |
| F-050 | Teams and tasks UI | P1 | F-007, F-040 to F-048 |
| F-051 | Issues and suggestions (feedback) | P1 | F-048 |
| F-052 | Dashboards | P1 | F-031, F-045 |
| F-053 | Audit log viewer | P2 | F-013 |
| F-054 | Feedback, dashboard and admin UI | P1 | F-007, F-017, F-051, F-052, F-053 |
| F-055 | Security alerts | P2 | F-013, F-005 |
| F-056 | Retention and cleanup jobs | P2 | F-006 |
| F-057 | Backups and restore drill | P1 | F-008 |
| F-058 | Performance and load testing | P1 | F-032, F-050, F-052 |
| F-059 | Security testing and hardening | P1 | F-054 |
| F-060 | Accessibility pass | P2 | F-054 |
| F-061 | Release readiness | P1 | F-055 to F-060 |

---

## 2. Platform tickets

### F-001 Monorepo and CI pipeline
**Priority:** P0 | **Depends on:** none
**Checklist**
- [ ] Monorepo with `apps/web`, `apps/api`, `packages/contracts`
- [ ] TypeScript configs, ESLint, Prettier, path aliases
- [ ] GitHub Actions: lint, type-check, tests, `npm audit`, secret scan, migration check, boundary lint
- [ ] Lockfile committed; pre-commit secret scan hook
- [ ] Compatibility spike: pin nestjs-zod, nestjs-cls, nestjs-pino, @sentry/nestjs and `@nestjs/*` versions
**Acceptance criteria**
- Lint and type-check pass on a clean checkout.
- The spike app boots with all pinned packages together; versions documented.
- CI fails on a deliberately committed test secret and on a critical audit finding.

### F-002 Database schema, constraints and seed
**Priority:** P0 | **Depends on:** F-001
**Checklist**
- [ ] SQL migrations for all 28 tables (FSD.md section 8)
- [ ] Composite tenant FKs `(organization_id, x_id)`
- [ ] CHECKs, partial unique indexes, triggers (`updated_at`, append-only `audit_logs` and `task_status_events`, team-member department check)
- [ ] Grants: app role INSERT+SELECT only on `audit_logs` and `task_status_events`; no DDL rights; separate migration role
- [ ] High-priority indexes (FSD.md section 9)
- [ ] `seed_system_roles(org)` generating 32 permissions and 4 roles from the definition in `packages/contracts`
- [ ] `managed_employee_ids(org, head_employee_id)` function
- [ ] Regenerate ERD from final DDL
**Acceptance criteria**
- Migration applies to an empty database.
- Every rule in TAD.md/FSD.md "rules the database enforces" has a passing constraint test (cross-tenant FK insert fails, second pending submission fails, reviewer = submitter fails, UPDATE/DELETE/TRUNCATE on audit tables fails for the app role, etc.).
- Seed creates exactly 32 permissions and 4 system roles.
**Tests:** T-20 (DB part), T-32 (DB part)

### F-003 NestJS platform skeleton and request pipeline
**Priority:** P0 | **Depends on:** F-001
**Checklist**
- [ ] `AppModule`, `main.ts`, `worker.ts` (`createApplicationContext`), global prefix `api/v1`, `enableShutdownHooks`
- [ ] `ConfigModule` with Zod env schema
- [ ] Middleware: request id, Helmet, 1 MB body limit, strict CORS, cookie parser
- [ ] Global `ZodValidationPipe` (unknown fields rejected)
- [ ] Interceptors: idempotency, request logging, response envelope
- [ ] Global exception filter + domain error classes with codes
- [ ] Decorators `@Public()`, `@RequirePermission()`, `@CurrentUser()`, `@Scope()`
- [ ] Module boundary lint rule (no `forwardRef`)
**Acceptance criteria**
- App refuses to boot with invalid environment.
- Success and error envelopes match FSD.md section 3; error responses include `requestId` and never a stack trace (T-29).
- A route with neither decorator is denied with 403.
- Importing another module's internal file fails CI.

### F-004 Database module and TransactionService
**Priority:** P0 | **Depends on:** F-002, F-003
**Checklist**
- [ ] `DatabaseModule` with explicit pool limits (API 10 to 20, worker 5)
- [ ] `TransactionService.run()` on AsyncLocalStorage
- [ ] Repositories join the active transaction automatically
- [ ] Statement timeout 10 s; request timeout 30 s
- [ ] Reference module (e.g. holidays) end to end as the template for others
**Acceptance criteria**
- Integration test: nested repository calls share one connection; a thrown error rolls back all rows.
- Reference module reviewed and approved by all three developers.

### F-005 Observability and health
**Priority:** P1 | **Depends on:** F-003
**Checklist**
- [ ] nestjs-pino JSON logs with redaction list (password, token, authorization, cookie, refresh, OTP, personal fields); no bodies
- [ ] Sentry for API, worker, web with personal-data scrubbing
- [ ] `/health` liveness only; `/ready` internal (DB + queue)
- [ ] Metrics: request rate/latency/error per route, pool usage, queue depth/age
- [ ] Alert rules from TAD.md section 13
**Acceptance criteria**
- `/health` returns exactly `{"status":"ok"}`.
- Log capture during login, OTP and profile update contains no secrets or personal fields (T-24).
- `/ready` is not reachable from the public edge.

### F-006 Queue and email (pg-boss, Nodemailer Gmail)
**Priority:** P0 | **Depends on:** F-003
**Checklist**
- [ ] `QueueModule` (pg-boss): 5 attempts, exponential backoff from 30 s, failed-job alert, singleton keys
- [ ] `EmailModule` using Nodemailer Gmail transport (OAuth2 preferred; app password fallback), credentials from secret manager, never logged
- [ ] Fake email provider and fake clock for tests
- [ ] Jobs enqueued only after commit
- [ ] Decide sender account/domain (Q9); SPF/DKIM/DMARC if own domain
**Acceptance criteria**
- A queued email is sent by the worker; with the provider down, the job retries with backoff and the originating request still succeeds (T-51).
- Gmail credentials appear in no log line.
- Test email delivers from staging.

### F-007 Web app shell and UI foundation
**Priority:** P0 | **Depends on:** F-001
**Checklist**
- [ ] Next.js App Router + TypeScript
- [ ] Tailwind CSS + shadcn/ui (Radix), lucide-react with individual imports
- [ ] Google Sans via `next/font` (confirm web licence) or fallback DM Sans / Figtree
- [ ] next-themes: `defaultTheme="dark"`, class strategy, shadcn dark variables
- [ ] react-hook-form + Zod resolver using schemas from `packages/contracts`
- [ ] `/api/*` proxy to backend; typed API client reading `error.code`
- [ ] Navigation built from `GET /auth/me` permissions
**Acceptance criteria**
- App renders dark by default.
- A sample form passes axe including text and field contrast in dark mode.
- No token is stored in localStorage/sessionStorage.

### F-008 Environments, secrets and staging deployment
**Priority:** P1 | **Depends on:** F-001, F-002
**Checklist**
- [ ] Development, staging, production, each with own DB and secrets
- [ ] Secret manager holding JWT keys (with key id), OTP HMAC secret, email credentials, DB credentials
- [ ] Web on Vercel (staging); API and worker as persistent containers; managed PostgreSQL
- [ ] Migrations run as a separate deploy step on a direct connection
- [ ] Staging uses synthetic data only
**Acceptance criteria**
- Staging deploys from CI.
- Migration step runs before the new version starts and never on app start.
- Hosting terms for commercial use checked and recorded.

### F-009 Authorization test generator and route scan
**Priority:** P0 | **Depends on:** F-002, F-003
**Checklist**
- [ ] Table-driven generator: each permission x each role x each scope from the single definition
- [ ] Union-of-roles handling (Employee included for HR and Dept Head)
- [ ] CI test walking the Nest route table
**Acceptance criteria**
- A handler lacking `@RequirePermission()` and `@Public()` fails the build (T-14).
- Generator produces the 32 x 4 matrix and passes against a sample route (T-15).

---

## 3. Identity and access tickets

### F-010 Login, sessions, refresh, logout
**Priority:** P0 | **Depends on:** F-004, F-011
**Checklist**
- [ ] Argon2id password service (configurable params, rehash on login)
- [ ] JWT via jose (15 min) and opaque refresh token (12 h idle, 7 d absolute), hashed in `user_sessions`
- [ ] Cookies HttpOnly, Secure, SameSite=Lax (`__Host-` where possible); refresh cookie scoped `/api/v1/auth`
- [ ] `POST /auth/login`, `/auth/refresh`, `/auth/logout`, `GET /auth/me`
- [ ] Lockout: 5 failures in 5 min locks 15 min; identical error for unknown user and wrong password
**Acceptance criteria**
- Hash stored in Argon2id format; plaintext never stored or logged (T-01).
- Unknown user and wrong password return identical 401 bodies; fifth failure locks; Super Admin unlock works (T-03).
- Tokens only in HttpOnly cookies, none in body or storage (T-04).
- Replaying a used refresh token returns 401 and revokes the whole family (T-05).
- `/auth/me` returns roles, permissions with scopes and employee id.

### F-011 Authentication and permissions guards (RBAC + scope)
**Priority:** P0 | **Depends on:** F-002, F-003, F-004
**Checklist**
- [ ] Authentication guard: signature, issuer, audience, expiry; skips `@Public()`
- [ ] Permissions guard: loads permissions and scopes from DB per request; deny by default
- [ ] Scope resolver (own, team, department, managed, org) with union across roles
- [ ] Service-level record scope helper returning 404 when out of scope
- [ ] Organization id taken from the session only
**Acceptance criteria**
- Role changes take effect on the next request.
- Each permission is allowed exactly where FSD.md section 1 grants it (T-15).
- Another user's record by id returns 404, with no data in lists (T-16).
- Cross-tenant access returns nothing (T-20).

### F-012 CSRF protection
**Priority:** P0 | **Depends on:** F-010
**Checklist**
- [ ] Double-submit `X-CSRF-Token` bound to session
- [ ] Origin check on every state-changing request
- [ ] GET requests never change state
**Acceptance criteria**
- POST/PATCH/PUT/DELETE without token or with a foreign Origin returns 403 `CSRF_FAILED` (T-08).
- Frontend client attaches the token automatically.

### F-013 Audit service
**Priority:** P0 | **Depends on:** F-004
**Checklist**
- [ ] `AuditService.write()` called inside the caller's transaction
- [ ] Fields: actor, action, entity type/id, changed fields, IP, user agent, request id
- [ ] No passwords, OTPs, tokens or personal profile values (field names only for sensitive)
- [ ] Event list from SAD.md section 8 wired by each feature ticket
**Acceptance criteria**
- A rolled-back change leaves no audit row; every committed audited action has one (T-32).
- UPDATE, DELETE, TRUNCATE on `audit_logs` are rejected for the app role.

### F-014 Invite acceptance
**Priority:** P0 | **Depends on:** F-010, F-006
**Checklist**
- [ ] Invite token: single use, 72 h, stored hashed
- [ ] `POST /auth/accept-invite` sets first password; account becomes active
- [ ] Password policy: 12 to 128, compromised-password check, not equal to email/name
- [ ] Invite email job (singleton key per token id); resend creates a new token
**Acceptance criteria**
- Second use and expired token both fail (T-07).
- Short, common or compromised passwords return 422 `VALIDATION_ERROR` (T-02).
- Account stays `invited` until a password is set.

### F-015 Forgot password with OTP
**Priority:** P0 | **Depends on:** F-010, F-006, F-013
**Checklist**
- [ ] `POST /auth/forgot-password` always 202 with identical body
- [ ] OTP: CSPRNG 6 digits, HMAC-SHA256 of `challengeId:code`, 10 min, 5 attempts, one live code, 60 s cooldown, 3/h per account, 10/h per IP
- [ ] `POST /auth/verify-otp` with identical 422 `OTP_INVALID` for unknown, wrong, expired, exhausted; similar timing
- [ ] Reset token: single use, 15 min, hashed, cookie scoped `/api/v1/auth/reset-password`
- [ ] `POST /auth/reset-password`: policy check, new hash, revoke all sessions, clear lockout, "password changed" email
- [ ] OTP email job: singleton key per challenge, payload encrypted AES-256-GCM, deleted on completion, high-priority queue
**Acceptance criteria**
- After 5 wrong attempts even the right code fails; a second code kills the first; code stored only as HMAC (T-09).
- Cooldown and hourly cap hold; every response is 202 (T-10).
- Known and unknown email give identical status, body and near-identical timing (T-11).
- Reset token cannot be reused or used after 15 min; all sessions revoked; lockout cleared; notice email queued (T-12).
- The OTP never appears in logs or audit metadata.

### F-016 Change password and session management
**Priority:** P1 | **Depends on:** F-010
**Checklist**
- [ ] `POST /auth/change-password` (current password required; revokes other sessions)
- [ ] `GET /auth/sessions`, `DELETE /auth/sessions/{id}` (own only)
- [ ] Sessions revoked on logout, password change, reset, disable, deactivation
**Acceptance criteria**
- Another user's session id returns 404.
- After revocation, refresh fails (T-06).

### F-017 User and role administration
**Priority:** P1 | **Depends on:** F-011, F-013
**Checklist**
- [ ] `GET/POST /users`, `GET/PATCH /users/{id}`, `POST /users/{id}/unlock`, `GET /roles`, `GET /permissions`
- [ ] `PUT /users/{id}/roles` (requires `role.manage`; not on oneself; audited)
- [ ] Last active Super Admin protected; system roles cannot be deleted or renamed
- [ ] Disabling a user revokes sessions
**Acceptance criteria**
- Changing own roles returns 403 `SELF_MODIFICATION_NOT_ALLOWED`; disabling the last Super Admin returns 409 `LAST_SUPER_ADMIN` (T-19).
- Every role change writes an audit row.

### F-018 Rate limiting
**Priority:** P1 | **Depends on:** F-003
**Checklist**
- [ ] `@nestjs/throttler` named throttlers per route class (SAD.md section 7)
- [ ] Custom key generators: user id for authenticated, IP + email for public
- [ ] 429 `RATE_LIMITED` with `Retry-After`
**Acceptance criteria**
- Exceeding each route-class limit returns 429 with `Retry-After` (T-30).
- A shared office IP does not throttle every authenticated employee.

### F-019 Authentication UI
**Priority:** P1 | **Depends on:** F-007, F-010, F-014, F-015, F-016
**Checklist**
- [ ] Login, accept-invite, forgot-password, verify-otp, reset-password, change-password, sessions pages
- [ ] Generic error handling by `error.code`; OTP errors never reveal account existence
- [ ] Dark-mode accessible forms with labels and keyboard support
**Acceptance criteria**
- E2E: login and OTP reset flows pass.
- axe reports no violations on all auth pages in dark mode.

---

## 4. Organization and employee tickets

### F-020 Organization settings
**Priority:** P1 | **Depends on:** F-013, F-011
**Checklist**
- [ ] `GET/PATCH /organization`: name, timezone, work start, grace minutes, work end, weekend days, employee code prefix
- [ ] Defaults: Asia/Dhaka, 09:00, 15 min, 17:00, Fri+Sat
- [ ] Audit on change; optional in-process cache with 60 s TTL
**Acceptance criteria**
- Only `org.settings.manage` can change settings; changes are audited.
- Invalid times or weekend values return 422.

### F-021 Departments, designations, holidays
**Priority:** P1 | **Depends on:** F-020
**Checklist**
- [ ] Departments CRUD (flat, archive via DELETE, 409 while active employees remain)
- [ ] Designations CRUD (archive)
- [ ] Holidays create/list/delete with year filter
- [ ] Read by every authenticated user; manage by HR and Super Admin
**Acceptance criteria**
- Unique name/title/date per organization enforced (409).
- Matrix tests pass for `org.structure.read` and `org.structure.manage`.

### F-022 Department head assignment
**Priority:** P1 | **Depends on:** F-021, F-017
**Checklist**
- [ ] `PUT /departments/{id}/head` (employeeId or null)
- [ ] One transaction sets `head_employee_id` and grants/revokes Department Head role
- [ ] Lock the department row
- [ ] Role revoked only when the person heads no other department
**Acceptance criteria**
- Only Super Admin can call it.
- Setting and clearing a head grants and revokes the role correctly (T-19).

### F-023 Employee creation and onboarding
**Priority:** P0 | **Depends on:** F-021, F-014, F-013, F-006
**Checklist**
- [ ] `POST /employees` with required `Idempotency-Key`
- [ ] One transaction: code counter under row lock (BST-00124), employee, profile, `hired` history, invited user with Employee role, hashed invite token, audit
- [ ] Invite email after commit; `POST /employees/{id}/invite` resends
- [ ] `roles` accepted only with `role.manage`
- [ ] HR cannot create HR Manager, Dept Head or Super Admin accounts
**Acceptance criteria**
- Two concurrent hires get different employee codes; same idempotency key replays one result (T-35).
- A forced failure mid-onboarding leaves no partial rows; with email down the invite retries and HR can resend (T-36).
- Duplicate work email returns 409.

### F-024 Employee list, detail and sensitive profile
**Priority:** P1 | **Depends on:** F-023
**Checklist**
- [ ] `GET /employees` with filters and sort allow-list, offset pagination
- [ ] `GET /employees/{id}` (work profile only)
- [ ] `GET/PATCH /employees/{id}/profile` guarded by `employee.read.sensitive`; non-owner reads audited
- [ ] `GET/PATCH /me/profile` (phone, address, personal and emergency contacts only)
- [ ] `GET /employees/{id}/history`
- [ ] Explicit response DTOs
**Acceptance criteria**
- Dept Head and Employee cannot read another employee's sensitive profile; HR read writes an audit row (T-21).
- Employee scopes (own, managed, org) match the matrix (T-16).
- List query count does not grow with page size.

### F-025 Department and designation change
**Priority:** P1 | **Depends on:** F-024
**Checklist**
- [ ] `PATCH /employees/{id}` with reason (required) and optional effectiveDate
- [ ] Append `department_change`/`designation_change` history with old/new values
- [ ] Cannot target own record; refused with 409 if employee heads the old department
- [ ] Runs registered `EmployeeLifecycleHandler`s inside the transaction
**Acceptance criteria**
- Self change returns 403 `SELF_MODIFICATION_NOT_ALLOWED` (T-19).
- History row written; lock on employee row prevents concurrent change.
- Team and task effects verified once F-049 is Done (T-38).

### F-026 Deactivate and reactivate employee
**Priority:** P1 | **Depends on:** F-025, F-016
**Checklist**
- [ ] `POST /employees/{id}/deactivate` (effectiveDate, reason 1 to 500)
- [ ] One transaction: status inactive + exit_date, history, handlers run, disable user and revoke sessions if date is today or earlier
- [ ] Scheduled job for future effective dates (conditional update, idempotent)
- [ ] `POST /employees/{id}/reactivate` restores status and user; user resets password via OTP
- [ ] Department heads blocked until replaced
**Acceptance criteria**
- Deactivating a head returns 409 `DEPARTMENT_HEAD_REQUIRED`, then succeeds after reassignment (T-37).
- Sessions revoked on the effective date; nothing is hard-deleted (T-50).

### F-027 Organization and employee UI
**Priority:** P1 | **Depends on:** F-007, F-021, F-023, F-024, F-025, F-026
**Checklist**
- [ ] Employee list/search/filters, create form, detail, profile, history
- [ ] Departments, designations, holidays, organization settings screens
- [ ] Department change, deactivate/reactivate dialogs with required reason
- [ ] Invite resend action
- [ ] Hide actions the user lacks permission for (server still enforces)
**Acceptance criteria**
- E2E: HR onboards an employee who accepts the invite and logs in.
- axe clean in dark mode on all screens.

---

## 5. Attendance tickets

### F-030 Attendance check-in
**Priority:** P0 | **Depends on:** F-020, F-021
**Checklist**
- [ ] Working-day and late-minute logic (org timezone, weekends, holidays, grace) with injected clock
- [ ] `POST /attendance/check-in`: server clock only, optional note max 200
- [ ] Status `present` or `late`; one record per employee per day
- [ ] No check-out route and no attendance-writing job
**Acceptance criteria**
- Second check-in same day returns 409 `ALREADY_CHECKED_IN`; client-sent time ignored (T-39).
- `late_minutes` computed from start + grace.
- `POST /attendance/check-out` returns 404.

### F-031 Derived absence engine
**Priority:** P0 | **Depends on:** F-030
**Checklist**
- [ ] One shared SQL definition: active, already-joined employee + working day + no record + work-day end passed (or past date)
- [ ] "Not checked in yet" for today before work-day end
- [ ] Stored `absent` correction overrides check-in
- [ ] Reused by attendance views, summaries and dashboards
**Acceptance criteria**
- Weekend, holiday, inactive and not-yet-joined employees never appear absent; today flips from "not checked in" to absent after end time (T-41).
- No row is ever inserted by a read or a job.
- Performance verified at A2 volumes.

### F-032 Attendance views and summaries
**Priority:** P1 | **Depends on:** F-031, F-024
**Checklist**
- [ ] `GET /attendance/me` with `isDerived: true` for derived absent days
- [ ] `GET /attendance` (filters employeeId, departmentId, from, to, status) scope-aware
- [ ] `GET /attendance/summary` (groupBy day or month)
- [ ] `GET /attendance/{id}` (stored records only)
**Acceptance criteria**
- Employee sees own; Dept Head managed; HR and Super Admin org (T-16).
- Status `absent` filter includes derived absences.
- Monthly summary matches FSD.md section 6 definitions.

### F-033 HR attendance correction
**Priority:** P1 | **Depends on:** F-030, F-013
**Checklist**
- [ ] `POST /attendance/corrections` (workDate not future, within 31 days, reason 10 to 500)
- [ ] One transaction: `original_snapshot`, upsert record with `source = hr_correction`, recalc `late_minutes`, audit
- [ ] Creates a record when the day had none; `absent` correction stores an absent row
- [ ] `GET /attendance/{id}/corrections`
**Acceptance criteria**
- Snapshot kept and `late_minutes` recalculated (T-40).
- Dept Head attempt returns 403.
- Concurrent corrections on the same day do not duplicate rows.

### F-034 Attendance UI
**Priority:** P1 | **Depends on:** F-007, F-032, F-033
**Checklist**
- [ ] Check-in button with today's status
- [ ] My history, HR and Dept Head attendance tables, summaries
- [ ] Correction form with mandatory reason
- [ ] Visible note that approved leave shows absent until corrected (A11)
**Acceptance criteria**
- E2E: employee checks in; HR corrects a record.
- axe clean in dark mode.

---

## 6. Teams and tasks tickets

### F-040 Teams
**Priority:** P1 | **Depends on:** F-024
**Checklist**
- [ ] `POST /teams`, `GET /teams`, `GET/PATCH /teams/{id}`, `DELETE /teams/{id}` (archive)
- [ ] `POST /teams/{id}/members`, `DELETE /teams/{id}/members/{employeeId}` (sets `removed_at`)
- [ ] Members must be active employees of the team's department; max 50
- [ ] Dept Head limited to departments they head; notify members; audit
**Acceptance criteria**
- Member from another department returns 422; other-department head returns 404 (T-42).
- Unique active team name per department and unique active membership enforced.
- Membership changes never alter existing assignments.

### F-041 Task creation (self, individual, team)
**Priority:** P0 | **Depends on:** F-040
**Checklist**
- [ ] `POST /tasks` with required `Idempotency-Key`
- [ ] `self` (anyone), `individual` and `team` (Dept Head managed, Super Admin)
- [ ] One transaction: task, one assignment per assignee (`todo`), first status events, notifications, audit
- [ ] `requires_review` defaults true for individual/team, false for self
- [ ] Task department fixed at creation
**Acceptance criteria**
- Team fan-out count equals current members (T-43).
- Empty team returns 422 `TEAM_EMPTY`; inactive assignee returns 422 `ASSIGNEE_INACTIVE`; Employee assigning to another returns 403.
- Duplicate request with the same key creates nothing new.

### F-042 Task status state machine
**Priority:** P0 | **Depends on:** F-041
**Checklist**
- [ ] `PATCH /task-assignments/{id}/status` (`todo` <-> `in_progress`; `changes_requested` -> `in_progress`)
- [ ] State machine per FSD.md section 2.8 as a unit-tested service
- [ ] Every change appends a `task_status_events` row
- [ ] `GET /task-assignments/{id}` with timeline and review status
**Acceptance criteria**
- Every legal transition succeeds and logs an event; every illegal one returns 409 `INVALID_TASK_TRANSITION` (T-44).
- Only the assignee can change status.

### F-043 Task submissions
**Priority:** P0 | **Depends on:** F-042
**Checklist**
- [ ] `POST /task-assignments/{id}/submissions` with `Idempotency-Key` (note 1 to 2000, up to 5 https links)
- [ ] Versioned submission (n+1), `review_status = pending`, assignment to `in_review` (or `done` when review not required)
- [ ] Lock assignment row; one pending submission per assignment
**Acceptance criteria**
- Resubmission after `changes_requested` increments version; earlier versions remain (T-45).
- Concurrent double submit: one succeeds, one fails.
- `javascript:` and non-https links rejected with 422 (T-28).

### F-044 Submission review
**Priority:** P0 | **Depends on:** F-043
**Checklist**
- [ ] `GET /task-submissions` review queue (filters reviewStatus, departmentId, employeeId, taskId)
- [ ] `PATCH /task-submissions/{id}/review` (approved / changes_requested with required note)
- [ ] Conditional update `WHERE review_status = 'pending'`
- [ ] Self-review blocked in service and by DB CHECK; Super Admin reviews Dept Head tasks
- [ ] Notify assignee; append status event; audit
**Acceptance criteria**
- Own submission returns 422 `SELF_REVIEW_NOT_ALLOWED`; direct DB write also rejected (T-18).
- Two reviewers at once: one 200, one 409 `ALREADY_REVIEWED` (T-46).
- Assignee sees status, reviewer, time and note.

### F-045 Task read, update and cancel
**Priority:** P1 | **Depends on:** F-041
**Checklist**
- [ ] `GET /tasks` (filters and sort allow-list), `GET /tasks/me`, `GET /tasks/{id}` with progress `{done, total}`
- [ ] `PATCH /tasks/{id}` (`task.manage` or creator ownership check in service; `requiresReview` only before any submission)
- [ ] `POST /tasks/{id}/cancel` with reason; cancels open assignments
**Acceptance criteria**
- A team task completes when every non-cancelled assignment is `done`.
- Non-creator without `task.manage` cannot update or cancel.
- No N+1 queries on list and detail.

### F-046 Task comments
**Priority:** P2 | **Depends on:** F-041
**Checklist**
- [ ] `GET/POST /tasks/{id}/comments` (cursor pagination, body 1 to 2000, immutable)
- [ ] Restricted to people who can act on the task
- [ ] Hidden from board-only viewers
**Acceptance criteria**
- Board-only viewer gets 404 on comments (T-17).
- Comment creation limited to 30/min per user.

### F-047 Team and department boards
**Priority:** P1 | **Depends on:** F-041
**Checklist**
- [ ] `GET /tasks/board/team` (teamId) and `GET /tasks/board/department`
- [ ] Reduced cards: title, status, assignee names, due date only
- [ ] Employee limited to own teams and department; Dept Head and Super Admin may pass departmentId
**Acceptance criteria**
- Employee of another department sees nothing; cards never include comments or submission text (T-47, T-17).

### F-048 In-app notifications
**Priority:** P1 | **Depends on:** F-041
**Checklist**
- [ ] Event subscribers (`@OnEvent`, emitted after commit) for task, team, feedback events
- [ ] `dedupe_key` unique per user
- [ ] `GET /notifications` (cursor, `unread=true`), `/unread-count`, `PATCH /{id}/read`, `POST /read-all`
- [ ] Cleanup 90 days after read (via F-056)
**Acceptance criteria**
- Job rerun or event replay creates no duplicate notification (T-51).
- Users see only their own notifications.

### F-049 Employee lifecycle handlers for teams and tasks
**Priority:** P1 | **Depends on:** F-025, F-026, F-040, F-041
**Checklist**
- [ ] `EmployeeLifecycleHandler` interface in shared kernel; multi-provider registration
- [ ] Teams handler: end memberships on department change/deactivation
- [ ] Tasks handler: cancel open team-task assignments from old teams / all open assignments on deactivation; notify creators
- [ ] Personal assignments stay on department change
**Acceptance criteria**
- Department change: history row, memberships ended, team-task assignments cancelled, creators notified (T-38).
- Deactivation with open assignments and sessions behaves per FSD.md 2.10 (T-50).
- No circular imports; no `forwardRef`.

### F-050 Teams and tasks UI
**Priority:** P1 | **Depends on:** F-007, F-040 to F-048
**Checklist**
- [ ] Teams management, task create (all three types), task list/detail, my tasks
- [ ] Submit, review queue and review screens
- [ ] Team and department boards
- [ ] Notification bell polling every 30 to 60 s
**Acceptance criteria**
- E2E: Dept Head assigns, employee submits, Dept Head reviews.
- axe clean in dark mode.

---

## 7. Feedback, reporting and admin tickets

### F-051 Issues and suggestions (feedback)
**Priority:** P1 | **Depends on:** F-048
**Checklist**
- [ ] `POST /feedback` with `Idempotency-Key` (kind, category, subject 5 to 150, body 10 to 4000)
- [ ] `GET /feedback` (own for everyone, all for Super Admin), `GET /feedback/{id}`
- [ ] `PATCH /feedback/{id}` (status, resolution note), conditional on current status
- [ ] Notify Super Admins on submit, submitter on handling; limit 5/hour per user
**Acceptance criteria**
- Same key twice creates one row; Employee PATCH returns 403; submitter sees status and note (T-48).
- Employees cannot read others' feedback.

### F-052 Dashboards
**Priority:** P1 | **Depends on:** F-031, F-045
**Checklist**
- [ ] Shared metric definitions (FSD.md section 6) in `DashboardModule`
- [ ] `/dashboard/me`, `/team`, `/hr`, `/company`, `/summary`
- [ ] Aggregate SQL only; no caching of per-user data
**Acceptance criteria**
- Figures match a fixed fixture per scope, including overdue/due-soon boundaries and derived absence before and after work-day end (T-49).
- Each dashboard is accessible only to the permitted scope.

### F-053 Audit log viewer
**Priority:** P2 | **Depends on:** F-013
**Checklist**
- [ ] `GET /audit-logs` (filters actorUserId, entityType, entityId, action, from, to; cursor pagination)
- [ ] Viewer reads are themselves audited
**Acceptance criteria**
- Only `audit.read` holders can call it; no sensitive values in metadata.

### F-054 Feedback, dashboard and admin UI
**Priority:** P1 | **Depends on:** F-007, F-017, F-051, F-052, F-053
**Checklist**
- [ ] Feedback submit/list/triage
- [ ] Four role dashboards and summary
- [ ] User, role and audit admin screens
**Acceptance criteria**
- E2E: feedback submit and resolve.
- axe clean in dark mode.

### F-055 Security alerts
**Priority:** P2 | **Depends on:** F-013, F-005
**Checklist**
- [ ] Alerts: login failure spikes, repeated lockouts, refresh-token reuse, OTP abuse, role changes granting HR Manager/Super Admin, update attempts on `audit_logs`
- [ ] Named on-call contact (Q15)
**Acceptance criteria**
- Each alert condition triggered in staging produces an alert (T-33).

### F-056 Retention and cleanup jobs
**Priority:** P2 | **Depends on:** F-006
**Checklist**
- [ ] Nightly cleanup: sessions/tokens/OTP (30 d after expiry), idempotency keys (7 d), notifications (90 d after read)
- [ ] Review job listing records past retention (no hard deletion without legal sign-off)
**Acceptance criteria**
- Expired rows removed, others untouched; safe to rerun (T-25).

### F-057 Backups and restore drill
**Priority:** P1 | **Depends on:** F-008
**Checklist**
- [ ] Daily base backup + WAL archiving (PITR); retention 7 d PITR, 35 d daily, 12 months monthly
- [ ] Encrypted, separate account, two named roles, second-approver deletion
- [ ] Alerts: backup failure, WAL lag > 10 min, latest backup > 26 h
- [ ] Restore runbook and drill
**Acceptance criteria**
- Restore completes within RTO 4 h with passing integrity checks (T-34).
- Production restore drill passed before go-live.

### F-058 Performance and load testing
**Priority:** P1 | **Depends on:** F-032, F-050, F-052
**Checklist**
- [ ] Synthetic dataset: 500 employees, 12 departments, 3 years attendance, ~180k assignments
- [ ] k6 scenarios from TAD.md section 12 (check-in burst, browsing, search, summaries, boards, dashboards, login/OTP burst, 50-member team task)
- [ ] `EXPLAIN (ANALYZE, BUFFERS)` for routes over target; record results with commit id
**Acceptance criteria**
- p95 < 500 ms list/detail; check-in p95 < 300 ms at burst; no 5xx; error rate < 1%; DB connections < 70%; OTP emails queued within 2 min.

### F-059 Security testing and hardening
**Priority:** P1 | **Depends on:** F-054
**Checklist**
- [ ] OWASP ZAP baseline against staging; manual ASVS L2 review
- [ ] Header, CSP, CORS, HSTS and body-limit checks
- [ ] Walk SAD.md checklist S-01 to S-39 and mark each done with its test
- [ ] Incident contacts and breach procedure document (S-39)
**Acceptance criteria**
- No high findings open (T-31); T-23, T-26 to T-30 pass; checklist signed.

### F-060 Accessibility pass
**Priority:** P2 | **Depends on:** F-054
**Checklist**
- [ ] Playwright + axe in CI (nightly), dark mode included
- [ ] Manual keyboard and contrast review of key forms
**Acceptance criteria**
- Key forms meet WCAG 2.1 AA in dark mode with no axe violations.

### F-061 Release readiness
**Priority:** P1 | **Depends on:** F-055 to F-060
**Checklist**
- [ ] User acceptance with HR; defects closed
- [ ] Go-live checklist and runbooks (deploy, rollback, restore, on-call)
- [ ] Gmail sending plan confirmed (limits for bulk invites, sender domain, OAuth2 in production)
- [ ] Stakeholder sign-off on open questions Q1 to Q17
- [ ] Legal review of retention, erasure and breach notification
**Acceptance criteria**
- All P0 and P1 tickets Done; sign-off recorded; production restore drill passed.

---

## 8. Open items that may change tickets
- Q9 (email channel/domain): F-006, F-015, F-061.
- Q13 (MFA in MVP): adds a TOTP ticket (S-12, T-13) after F-010.
- Q14 (reassign, attachments, recurring): extends F-041 to F-045.
- Q16 / Q17 (check-out, stored absence): changes F-030, F-031, F-033.
- Q2 / Q5 (boards, review rules): F-044, F-047.
- Q11 / Q15 (retention, on-call): F-055, F-056, F-061.
