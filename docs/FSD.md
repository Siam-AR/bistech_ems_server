# FSD: Functional Specification Document, BisTech EMS

Version: 1.0 | Date: 2026-11-17
Authoritative behaviour spec for agents: roles, permissions, workflows, state machines, API, validation, data vocabularies, tests.
Rule: every handler declares `@RequirePermission()` or `@Public()`; every business rule below is enforced on the server.

---

## 1. Permission matrix (32 permissions, 4 roles)

Effective access, Employee role included. Scopes: Own, Team, Dept, Managed, Org. `-` = no access. The seed stores only each role's own grants; Employee carries every "own" permission and roles are additive (union of scopes).

| Permission | Super Admin | HR Manager | Dept Head | Employee |
|---|---|---|---|---|
| user.read | Org | - | - | - |
| user.manage | Org | - | - | - |
| role.manage | Org | - | - | - |
| audit.read | Org | - | - | - |
| org.settings.manage | Org | - | - | - |
| employee.read | Org | Org | Managed | Own |
| employee.read.sensitive | Org | Org | - | Own |
| employee.create | Org | Org | - | - |
| employee.update | Org | Org | - | - |
| employee.status.manage | Org | Org | - | - |
| employee.history.read | Org | Org | - | - |
| org.structure.read | Org | Org | Org | Org |
| org.structure.manage | Org | Org | - | - |
| department.head.assign | Org | - | - | - |
| attendance.self | Own | Own | Own | Own |
| attendance.read | Org | Org | Managed | Own |
| attendance.correct | Org | Org | - | - |
| task.create.self | Own | Own | Own | Own |
| task.assign | Org | - | Managed | - |
| task.read | Org | Own | Managed | Own |
| task.board.team | Org | Team | Managed | Team |
| task.board.department | Org | Dept | Managed | Dept |
| task.work | Own | Own | Own | Own |
| task.comment | Org | Own | Managed | Own |
| task.review | Org | - | Managed | - |
| task.manage | Org | - | Managed | - |
| team.read | Org | Team | Managed | Team |
| team.manage | Org | - | Managed | - |
| dashboard.read | Org | Org | Managed | Own |
| feedback.submit | Own | Own | Own | Own |
| feedback.read | Org | Own | Own | Own |
| feedback.manage | Org | - | - | - |

Implicit for any authenticated user: own notifications, own profile (`/me/profile`), own sessions.

### Scope resolution
| Scope | Meaning |
|---|---|
| own | Record belongs to caller's employee profile or user (tasks: assigned to or created by caller) |
| team | Teams the caller currently belongs to (read-only boards) |
| department | Caller's own department (read-only boards) |
| managed | Caller's own records + every employee, attendance row, team, task in departments where `departments.head_employee_id` = caller |
| org | Everything in the caller's organization |

- Out-of-scope record: **404 NOT_FOUND**, never 403.
- Board-only task view: title, status, assignee names, due date. Comments and submission text hidden.
- Organization id comes from the session only.

### Rules no role can override
- Reviewer cannot review own submission (`CHECK reviewed_by <> submitted_by`). A task assigned to a Dept Head is reviewed by Super Admin.
- Dept Head assigns tasks and builds teams only in departments they head.
- Only Super Admin assigns roles (`role.manage`) or sets a department head; nobody changes own roles; every role change audited.
- HR cannot create, change or deactivate users holding HR Manager, Dept Head or Super Admin roles.
- Nobody changes own department, designation or employment status.
- Department head cannot be deactivated until replaced (409 `DEPARTMENT_HEAD_REQUIRED`).
- System roles cannot be deleted/renamed. Last active Super Admin cannot be disabled (409 `LAST_SUPER_ADMIN`).

## 2. Workflows

Each critical step is one DB transaction. Duplicate guards listed.

### 2.1 Login and session
1. `POST /auth/login` (email, password, optional `organizationSlug`).
2. Check lockout, verify Argon2id, create `user_sessions` row, set access cookie (15 min) and refresh cookie (12 h idle, 7 d absolute).
3. `POST /auth/refresh` rotates token; reuse of a used token revokes the family.
4. `GET /auth/me` returns roles, permissions with scopes, employee id. UI builds navigation from it; backend re-checks every request.
Guards: unique session token hash; 5 failures in 5 min lock for 15 min.

### 2.2 Forgot password (OTP)
See SAD.md section 3. Always 202; identical `OTP_INVALID`; single-use conditional updates; email job singleton key per challenge.

### 2.3 Create employee / HR Manager / Department Head
1. HR or Super Admin `POST /employees` with `Idempotency-Key`: name, work email, department, designation, joining date, employment type, optional personal profile.
2. One transaction: increment `organizations.last_employee_number` under row lock (code BST-00124), create employees + employee_profiles, `hired` history, `users` row status `invited` with Employee role, hashed single-use invite token, audit record.
3. After commit the worker emails the invite; retries with backoff; `POST /employees/{id}/invite` resends.
4. Employee calls `POST /auth/accept-invite` to set password; account becomes active.
5. HR Manager: Super Admin sends `roles` in step 1 (only accepted with `role.manage`) or later `PUT /users/{id}/roles`.
6. Department Head: Super Admin `PUT /departments/{id}/head`; one transaction sets `head_employee_id` and grants Department Head role. Removing/replacing a head revokes the role if the person heads no other department.
Guards: unique (org, employee_code), unique work email per org, idempotency key.

### 2.4 Change department or designation
1. `PATCH /employees/{id}` with departmentId or designationId, optional effectiveDate, reason (required).
2. One transaction: update employee, append `department_change`/`designation_change` history row (old/new), audit. Cannot target own record.
3. Department change: remove from old department's teams; open personal assignments stay; open team-task assignments from old teams cancelled and creators notified.
4. If the employee heads the old department: 409 `DEPARTMENT_HEAD_REQUIRED`.

### 2.5 Attendance (check-in only)
1. `POST /attendance/check-in`: server clock, `work_date` in org timezone, `late_minutes` against start + grace, status `present` or `late`. Second call same day: 409 `ALREADY_CHECKED_IN`. Client time ignored.
2. **Absence is derived, never stored.** Absent when all hold: employee active and already joined; date is a working day (not weekend/holiday); no attendance record; work-day end time has passed (today) or date is in the past. Before end time today: "not checked in yet".
3. HR correction `POST /attendance/corrections` (employeeId, workDate, checkInAt, status, reason 10 to 500). One transaction: store `original_snapshot`, upsert record with `source = hr_correction`, recalc `late_minutes`, audit. A correction on a day with no record creates one (forgotten check-in, approved leave per A11). Status `absent` through a correction stores an absent record that overrides check-in.
Guard: unique (employee_id, work_date). No job writes attendance rows. No check-out route (`POST /attendance/check-out` is 404).

### 2.6 Team creation
1. Dept Head (or Super Admin) `POST /teams`: department they head, name, initial members.
2. Server verifies all members are active employees of that department; inserts team + team_members; notifies; audits.
3. `POST /teams/{id}/members` adds; `DELETE /teams/{id}/members/{employeeId}` sets `removed_at`. Membership changes never alter existing assignments.
Guards: unique active team name per department; unique active membership per team+employee.

### 2.7 Task creation
`POST /tasks` with `Idempotency-Key`, `assignmentType`:
- `self`: any user; assignee is creator; review off by default.
- `individual`: Dept Head (managed) or Super Admin picks one active employee.
- `team`: Dept Head or Super Admin picks a team; fans out to every current member.
One transaction: task, one `task_assignments` row per assignee (status `todo`), first status event each, notifications, audit. Empty team: 422 `TEAM_EMPTY`; inactive assignee: 422 `ASSIGNEE_INACTIVE`. `requires_review` defaults true for individual/team, false for self; creator may change at creation. Task's department = team's or assignee's department at creation.
Guards: idempotency key; unique (task_id, employee_id).

### 2.8 Task state machine (per assignment)
Every change appends a `task_status_events` row.

| From | To | Who | Trigger |
|---|---|---|---|
| todo | in_progress | Assignee | `PATCH /task-assignments/{id}/status` |
| in_progress | todo | Assignee | same |
| todo, in_progress, changes_requested | in_review | Assignee | `POST /task-assignments/{id}/submissions` when `requires_review` |
| todo, in_progress, changes_requested | done | Assignee | same submission when review not required |
| in_review | done | Reviewer | `PATCH /task-submissions/{id}/review` approved |
| in_review | changes_requested | Reviewer | same, with required note |
| changes_requested | in_progress | Assignee | status endpoint (rework) |
| todo, in_progress, in_review, changes_requested | cancelled | Creator, Dept Head, Super Admin | `POST /tasks/{id}/cancel` or assignee deactivation |

Illegal moves: 409 `INVALID_TASK_TRANSITION`.

Submission and review:
1. Assignee submits note + up to 5 https links; server creates `task_submissions` version n+1 with `review_status = pending`, assignment to `in_review`. Earlier versions stay.
2. Reviewer (Dept Head of the department, or Super Admin) gets a notification and uses `GET /task-submissions?reviewStatus=pending`.
3. Review in one transaction: `UPDATE submission WHERE review_status = 'pending'` (0 rows: 409 `ALREADY_REVIEWED`), set assignment status, append event, notify assignee. Own submission: 422 `SELF_REVIEW_NOT_ALLOWED`.
4. Assignee sees review status, reviewer, time, note; after changes_requested edits and resubmits.
5. Status and comment endpoints limited to people who can act on the task (assignee, creator, reviewers in scope). Board viewers see status only.
A team task is complete when every non-cancelled assignment is `done`; detail returns `progress {done, total}`.

### 2.9 Issues and suggestions
1. Any user `POST /feedback` (kind issue|suggestion, category, subject, body) with `Idempotency-Key`.
2. Row `open`; Super Admins notified.
3. Super Admin `PATCH /feedback/{id}` to `in_review`, `resolved` or `closed` with resolution note; submitter notified and sees status.
Guards: idempotency key; conditional status updates.

### 2.10 Deactivate / reactivate
1. `POST /employees/{id}/deactivate` (effectiveDate, reason). Dept heads: 409 `DEPARTMENT_HEAD_REQUIRED`.
2. One transaction: status `inactive` + `exit_date`, history row, end team memberships, cancel open assignments (creators notified), disable user and revoke sessions if date is today or earlier (scheduled job for future dates), audit.
3. Nothing hard-deleted.
4. `POST /employees/{id}/reactivate` restores status and user; user must reset password via OTP flow.

## 3. API conventions

Base `/api/v1` (global prefix). JSON, camelCase. UUID ids. Dates `YYYY-MM-DD`; instants ISO 8601 UTC; server decides `work_date`.

Success: `{ "success": true, "message": "...", "data": ..., "meta": null }`
Error: `{ "success": false, "error": { "code", "message", "details": [{ "field", "message" }] }, "requestId" }`

- Pagination: offset (`page` from 1, `limit` default 20 max 100; meta page/limit/total/totalPages); cursor for notifications, comments, audit logs (`cursor`, `limit`; meta nextCursor/hasMore).
- Sorting: `sort=field` or `-field` from per-endpoint allow-list; unknown field 422. Filters are query params named after the field.
- Idempotency-Key (UUID) required on `POST /employees`, `POST /tasks`, `POST /task-assignments/{id}/submissions`, `POST /feedback`. Same key + body replays for 24 h; same key + different body 422 `IDEMPOTENCY_KEY_REUSED`.
- Every response carries `X-Request-Id`.
- Static routes (`/me`, `/summary`, `/board/...`) declared before `/{id}` routes in controllers.
- Creator-or-permission checks (e.g. `task.manage` or creator) are service-level ownership checks.

### Status and error codes
| HTTP | error.code | When |
|---|---|---|
| 200/201/202/204 | none | success, created, accepted, no body |
| 400 | BAD_REQUEST | malformed JSON/request |
| 401 | UNAUTHENTICATED, TOKEN_EXPIRED, INVALID_CREDENTIALS | missing/expired/invalid credentials (login message identical for unknown user and wrong password) |
| 403 | FORBIDDEN, ACCOUNT_LOCKED, ACCOUNT_DISABLED, CSRF_FAILED, SELF_MODIFICATION_NOT_ALLOWED | not allowed |
| 404 | NOT_FOUND | missing or out of scope |
| 409 | CONFLICT, DUPLICATE_RESOURCE, ALREADY_CHECKED_IN, INVALID_TASK_TRANSITION, ALREADY_REVIEWED, DEPARTMENT_HEAD_REQUIRED, LAST_SUPER_ADMIN | state conflicts |
| 422 | VALIDATION_ERROR, OTP_INVALID, SELF_REVIEW_NOT_ALLOWED, TEAM_EMPTY, ASSIGNEE_INACTIVE, IDEMPOTENCY_KEY_REUSED | invalid content/rule |
| 429 | RATE_LIMITED | with Retry-After |
| 500/503 | INTERNAL_ERROR, SERVICE_UNAVAILABLE | no internals in body |

Clients branch on `error.code`, never message text.

## 4. Endpoint catalogue

### Authentication and profile
| Method | Endpoint | Perm | Notes |
|---|---|---|---|
| POST | /auth/login | Public | email, password, optional organizationSlug; sets cookies |
| POST | /auth/refresh | Cookie | rotate; reuse revokes family |
| POST | /auth/logout | Session | revoke current session |
| GET | /auth/me | Session | user, roles, permissions+scopes, employeeId |
| POST | /auth/accept-invite | Public (token) | set first password |
| POST | /auth/forgot-password | Public | always 202 |
| POST | /auth/verify-otp | Public | email, otp; sets reset cookie |
| POST | /auth/reset-password | Public (reset cookie) | newPassword |
| POST | /auth/change-password | Session | requires current password; revokes other sessions |
| GET | /auth/sessions | Session | own active sessions |
| DELETE | /auth/sessions/{id} | Session | revoke own session |
| GET, PATCH | /me/profile | Session | PATCH only phone, address, personal and emergency contact |

### Employees
| Method | Endpoint | Perm | Notes |
|---|---|---|---|
| GET | /employees | employee.read | filters q, departmentId, designationId, status, employmentType, joinedFrom, joinedTo; sort employeeCode, lastName, joiningDate, status |
| POST | /employees | employee.create | Idempotency-Key; roles only with role.manage |
| GET | /employees/{id} | employee.read | work profile only |
| PATCH | /employees/{id} | employee.update | appends history; 403 on own record |
| GET | /employees/{id}/profile | employee.read.sensitive | non-owner reads audited |
| PATCH | /employees/{id}/profile | employee.update | HR edits personal data |
| GET | /employees/{id}/history | employee.history.read | newest first |
| POST | /employees/{id}/invite | employee.create | resend |
| POST | /employees/{id}/deactivate | employee.status.manage | effective date, reason |
| POST | /employees/{id}/reactivate | employee.status.manage | |

No `DELETE /employees/{id}`.

### Organization setup
| Method | Endpoint | Perm |
|---|---|---|
| GET, POST | /departments | org.structure.read / manage |
| GET, PATCH | /departments/{id} | read / manage |
| PUT | /departments/{id}/head | department.head.assign (employeeId or null; syncs role) |
| DELETE | /departments/{id} | org.structure.manage (archives; 409 while active employees) |
| GET, POST | /designations | read / manage |
| PATCH, DELETE | /designations/{id} | manage (DELETE archives) |
| GET, POST | /holidays | read / manage (filter year) |
| DELETE | /holidays/{id} | manage |
| GET, PATCH | /organization | org.settings.manage (name, timezone, work start, grace, work end, weekend days, employee code prefix) |

### Users, roles, audit (Super Admin)
| Method | Endpoint | Perm | Notes |
|---|---|---|---|
| GET, POST | /users | user.read / manage | POST creates accounts without employee profile and invites |
| GET, PATCH | /users/{id} | read / manage | accountStatus active/suspended/disabled; disabling revokes sessions |
| PUT | /users/{id}/roles | role.manage | replaces role set; audited; not on self |
| POST | /users/{id}/unlock | user.manage | |
| GET | /roles, /permissions | user.read | system roles fixed |
| GET | /audit-logs | audit.read | filters actorUserId, entityType, entityId, action, from, to; cursor; viewer audited |

### Attendance
| Method | Endpoint | Perm | Notes |
|---|---|---|---|
| POST | /attendance/check-in | attendance.self | server time only; 409 ALREADY_CHECKED_IN |
| GET | /attendance/me | attendance.self | from, to; past working days without a record returned as derived absent (`isDerived: true`) |
| GET | /attendance | attendance.read | employeeId, departmentId, from, to, status; absent includes derived |
| GET | /attendance/summary | attendance.read | groupBy day or month |
| GET | /attendance/{id} | attendance.read | stored records only |
| POST | /attendance/corrections | attendance.correct | snapshot stored |
| GET | /attendance/{id}/corrections | attendance.correct | |

### Teams
| Method | Endpoint | Perm |
|---|---|---|
| GET | /teams | team.read |
| POST | /teams | team.manage (departmentId, name, description, memberIds) |
| GET, PATCH | /teams/{id} | read / manage |
| DELETE | /teams/{id} | team.manage (archives) |
| POST | /teams/{id}/members | team.manage (employeeIds) |
| DELETE | /teams/{id}/members/{employeeId} | team.manage |

### Tasks
| Method | Endpoint | Perm | Notes |
|---|---|---|---|
| POST | /tasks | task.create.self or task.assign | Idempotency-Key |
| GET | /tasks | task.read | filters status, priority, assigneeId, teamId, departmentId, createdBy, dueFrom, dueTo, overdue; sort dueDate, priority, createdAt |
| GET | /tasks/me | task.work | own assignments with review status |
| GET | /tasks/board/team | task.board.team | teamId; reduced cards |
| GET | /tasks/board/department | task.board.department | reduced cards; Dept Head/Super Admin may pass departmentId |
| GET | /tasks/{id} | task.read | with progress |
| PATCH | /tasks/{id} | task.manage or creator | requiresReview only before any submission |
| POST | /tasks/{id}/cancel | task.manage or creator | reason required |
| GET, POST | /tasks/{id}/comments | task.comment or task.work | cursor; hidden from board-only |
| GET | /task-assignments/{id} | task.work or task.read | |
| PATCH | /task-assignments/{id}/status | task.work | in_progress or todo only |
| POST | /task-assignments/{id}/submissions | task.work | Idempotency-Key |
| GET | /task-submissions | task.review | review queue |
| PATCH | /task-submissions/{id}/review | task.review | decision, note |

### Notifications, feedback, dashboards, platform
| Method | Endpoint | Perm |
|---|---|---|
| GET | /notifications | Session (cursor; `unread=true`; UI polls 30 to 60 s) |
| GET | /notifications/unread-count | Session |
| PATCH | /notifications/{id}/read, POST /notifications/read-all | Session |
| POST | /feedback | feedback.submit (Idempotency-Key) |
| GET | /feedback, /feedback/{id} | feedback.read (own for all; all for Super Admin) |
| PATCH | /feedback/{id} | feedback.manage (status, resolutionNote) |
| GET | /dashboard/me | dashboard.read (own) |
| GET | /dashboard/team | dashboard.read (managed) |
| GET | /dashboard/hr | dashboard.read (org) |
| GET | /dashboard/company | dashboard.read (org) + task.manage (org) |
| GET | /dashboard/summary | dashboard.read |
| GET | /health | Public (liveness `{"status":"ok"}`) |
| GET | /ready | internal network only |

## 5. Request validation (Zod, from `packages/contracts`)

Unknown body fields rejected (422 `VALIDATION_ERROR` with per-field details).

| Endpoint | Rules |
|---|---|
| POST /auth/login | email valid max 254; password 1 to 128; optional organizationSlug lowercase-hyphen |
| POST /auth/forgot-password | email valid max 254 |
| POST /auth/verify-otp | email valid; otp exactly 6 digits |
| accept-invite, reset-password, change-password | token opaque 43 chars (invite); password 12 to 128, not compromised, not equal to email/name |
| POST /employees | firstName, lastName 1 to 80; workEmail valid, unique in org; departmentId, designationId exist in org; joiningDate not > 1 year ahead; employmentType in vocabulary; phone E.164; roles only with role.manage |
| PATCH /employees/{id} | partial; reason required (max 500) for department/designation change; effectiveDate not before joining date |
| POST /employees/{id}/deactivate | effectiveDate required; reason 1 to 500 |
| POST /attendance/check-in | no time field; optional note max 200 |
| POST /attendance/corrections | workDate not future, not older than 31 days (configurable); checkInAt ISO instant on workDate, required unless status absent; status present/late/absent; reason 10 to 500 |
| POST /teams | name 2 to 80; departmentId headed by caller (Super Admin any); memberIds unique active employees of that department, max 50 |
| POST /tasks | title 1 to 150; description max 4000; priority in vocabulary; dueDate not past, not > 2 years ahead; assigneeId only for individual, teamId only for team, neither for self; requiresReview boolean |
| POST submissions | note 1 to 2000; links up to 5 https URLs, each max 500 chars |
| PATCH review | decision approved/changes_requested; note required for changes_requested, max 500 |
| POST comments | body 1 to 2000 |
| POST /feedback | kind, category in vocabulary; subject 5 to 150; body 10 to 4000 |
| All lists | page >= 1; limit 1 to 100; sort from allow-list; from <= to; ids UUID |

## 6. Dashboard metric definitions

Counts filtered by caller scope; "today" uses org timezone; one shared implementation in DashboardModule; aggregate SQL, uncached at launch.

| Metric | Definition |
|---|---|
| Total employees | in scope, `employment_status = active` (inactive shown separately) |
| Joiners this month | `joining_date` in current calendar month |
| Department summary | active employees per department |
| Present today | attendance row today with status present or late |
| Late today | `check_in_at` after start + grace; `late_minutes` is the difference |
| Not checked in yet | active, joined employees on a working day, no row, before work-day end |
| Absent today | same population after work-day end, plus stored absent records |
| Monthly attendance summary | per employee: present, late, absent days over expected working days; excludes days not yet ended; no worked minutes |
| Task counts by status | assignments by status in scope, excluding cancelled |
| Overdue | assignment not done/cancelled with task `due_date` before today |
| Due soon | open assignments due within 3 days |
| Pending reviews | submissions `pending` in caller's review scope, excluding own |
| Completion rate | done / (done + open) for tasks created in the period |
| Open feedback | status open or in_review |

## 7. Data vocabularies (used identically in DB checks, API enums, UI)

| Field | Values |
|---|---|
| users.account_status | invited, active, suspended, disabled |
| employees.employment_status | active, inactive |
| employees.employment_type | full_time, part_time, contract, intern |
| attendance_records.status | present, late, absent |
| attendance_records.source | web, hr_correction |
| tasks.status | active, cancelled |
| tasks.priority | low, medium, high, urgent |
| tasks.assignment_type | self, individual, team |
| task_assignments.status | todo, in_progress, in_review, changes_requested, done, cancelled |
| task_submissions.review_status | pending, approved, changes_requested |
| feedback_items.kind | issue, suggestion |
| feedback_items.status | open, in_review, resolved, closed |
| feedback_items.category | general, attendance, tasks, system, workplace, other |
| role_permissions.scope | own, team, department, managed, org |
| employee_employment_history.event_type | hired, department_change, designation_change, status_change, reactivated |

## 8. Data dictionary (key columns and constraints)

| Table | Key columns | Constraints and notes |
|---|---|---|
| organizations | id, name, slug, timezone, settings JSONB, employee_code_prefix, last_employee_number | unique slug; settings: work start, grace, work end, weekend days; counter incremented under row lock |
| users | id, organization_id, email, display_name, password_hash, account_status, failed_login_count, locked_until, last_login_at | unique (org, lower(email)); active requires hash |
| roles | id, organization_id, name, is_system | unique (org, name); 4 seeded |
| permissions | id, key, description | global; 32 rows |
| role_permissions | role_id, permission_id, scope | PK (role_id, permission_id) |
| user_roles | user_id, role_id, organization_id, assigned_by, assigned_at | PK (user_id, role_id); FK (org) |
| user_sessions | id, user_id, family_id, refresh_token_hash, user_agent, ip_address, expires_at, revoked_at | unique hash |
| auth_tokens | id, user_id, purpose, token_hash, expires_at, used_at | purpose invite or password_reset; hashed, single use |
| otp_challenges | id, organization_id, user_id, purpose, code_hash, attempts, max_attempts, sent_at, expires_at, consumed_at | CHECK attempts <= max_attempts (5); partial unique (user_id, purpose) WHERE consumed_at IS NULL |
| departments | id, organization_id, name, description, head_employee_id, archived_at | flat; unique (org, name); head FK (org) nullable |
| designations | id, organization_id, title, archived_at | unique (org, title) |
| holidays | id, organization_id, holiday_date, name | unique (org, holiday_date) |
| employees | id, organization_id, user_id, employee_code, first_name, last_name, work_email, phone, department_id, designation_id, employment_type, employment_status, joining_date, exit_date | unique (org, employee_code) and (org, lower(work_email)); unique user_id; inactive requires exit_date >= joining_date; no manager_id |
| employee_profiles | employee_id, date_of_birth, personal_email, personal_phone, address_line, city, country_code, emergency_contact_* | one row per employee; sensitive |
| employee_employment_history | id, employee_id, event_type, effective_date, old_value, new_value, reason, changed_by | append-only |
| attendance_records | id, employee_id, work_date, check_in_at, status, source, late_minutes | unique (employee_id, work_date); no check_out/worked_minutes |
| attendance_corrections | id, employee_id, attendance_record_id (nullable), work_date, corrected_check_in_at, corrected_status, reason, original_snapshot JSONB, corrected_by | append-only; reason 10 to 500 |
| teams | id, organization_id, department_id, name, description, created_by, archived_at | unique (department_id, lower(name)) where not archived |
| team_members | id, organization_id, team_id, employee_id, added_by, added_at, removed_at | partial unique (team_id, employee_id) WHERE removed_at IS NULL; trigger: employee dept = team dept |
| tasks | id, organization_id, title, description, priority, due_date, assignment_type, team_id, department_id, requires_review, status, created_by, cancelled_at | CHECK ((assignment_type='team') = (team_id IS NOT NULL)); title 1 to 150 |
| task_assignments | id, organization_id, task_id, employee_id, status, started_at, submitted_at, completed_at | unique (task_id, employee_id) |
| task_submissions | id, organization_id, assignment_id, version, note, links JSONB, submitted_by, submitted_at, review_status, reviewed_by, reviewed_at, review_note | unique (assignment_id, version); one pending per assignment; CHECK reviewed_by <> submitted_by; links <= 5 URLs |
| task_comments | id, organization_id, task_id, author_user_id, body, created_at | body 1 to 2000; immutable |
| task_status_events | id, organization_id, assignment_id, from_status, to_status, actor_user_id, created_at | append-only (trigger) |
| feedback_items | id, organization_id, submitted_by, kind, category, subject, body, status, resolution_note, handled_by, handled_at | subject 5 to 150; body 10 to 4000 |
| notifications | id, organization_id, user_id, type, title, body, payload, dedupe_key, read_at | unique (user_id, dedupe_key) |
| audit_logs | id, organization_id, actor_user_id, action, entity_type, entity_id, metadata, ip_address, user_agent, request_id | append-only; INSERT+SELECT only; entity_id polymorphic |
| idempotency_keys | organization_id, user_id, key, request_hash, response_status, response_body, expires_at | replay on same key+body |

## 9. Indexes (confirm with EXPLAIN ANALYZE before adding more)

High: users (org, lower(email)) unique; employees (org, employment_status); employees (org, department_id, employment_status); employees (org, lower(last_name), lower(first_name)); attendance (employee_id, work_date) unique; attendance (org, work_date, status); task_assignments (employee_id, status); task_assignments (task_id); tasks (org, department_id, status, due_date); task_submissions (org, submitted_at) partial on pending; team_members (employee_id) partial active; notifications (user_id, created_at DESC) + partial unread.
Medium: tasks (team_id) and (created_by); task_comments (task_id, created_at); feedback_items (org, status, created_at DESC); audit_logs (org, created_at DESC) and (org, entity_type, entity_id, created_at DESC).
ILIKE `'%x%'` is not served; add pg_trgm only if slow.

## 10. Transactions and concurrency

| Workflow | Atomic operations | Concurrency control |
|---|---|---|
| Employee creation | counter, employee, profile, history, user, role, invite token, audit | row lock on org counter; unique constraints; idempotency |
| Department head change | head, role grant/revoke, audit | lock department row |
| Department/designation change | employee, history, end memberships, cancel assignments, audit | lock employee row |
| Check-in | insert row | unique (employee_id, work_date); conflict 409 |
| HR correction | snapshot, upsert, correction row, audit | lock attendance row or insert conflict |
| Task creation | task, assignments, events, notifications, audit | idempotency; unique assignment; lock team row |
| Submission | next version, assignment in_review | lock assignment; partial unique pending |
| Review | submission, assignment, event, audit | `UPDATE ... WHERE review_status='pending'` |
| OTP verify | attempts, compare, consume, issue reset token | conditional update |
| Deactivation | status, history, memberships, assignments, user, sessions | one transaction; job for future date |

## 11. Notification events (in-app)
task assigned, submitted, reviewed, commented, cancelled; team member added; feedback submitted (to Super Admins) and handled (to submitter). Unique `(user_id, dedupe_key)` prevents duplicates.

## 12. Required test cases (IDs referenced by SAD.md and FTL.md)

| ID | Test | Level |
|---|---|---|
| T-01 | Argon2id format; plaintext never stored/logged; rehash after param change | Integration |
| T-02 | Short/common/compromised password on invite, reset, change gives 422 | API |
| T-03 | Unknown user vs wrong password identical 401; lock on 5th failure; unlock works | API |
| T-04 | Tokens only in HttpOnly cookies | API, E2E |
| T-05 | Replaying a used refresh token gives 401 and revokes family | API |
| T-06 | Logout, password change, reset, disable, deactivation revoke sessions | Workflow |
| T-07 | Invite token reuse/expiry fails | API |
| T-08 | State change without CSRF token or with foreign Origin gives 403 CSRF_FAILED | API |
| T-09 | OTP: 5 wrong then right fails; expired fails; second code kills first; stored as HMAC | API, DB |
| T-10 | OTP limits: cooldown and 4th request in an hour; always 202 | API |
| T-11 | forgot-password/verify-otp identical for known and unknown email incl. timing | API |
| T-12 | Reset token single use and 15 min; reset revokes sessions, clears lockout, queues notice | API |
| T-13 | TOTP (later) | API |
| T-14 | Route-table scan: all routes declare permission or public | CI |
| T-15 | Permission matrix: each permission x role | Authorization |
| T-16 | Employee requesting another's profile/attendance/assignment/comments gets 404; no list leakage | Authorization |
| T-17 | Dept Head cross-department gets 404; board-only viewers cannot open comments/submissions | Authorization |
| T-18 | Self-review gives 422; DB check rejects direct write | API, DB |
| T-19 | Role/HR/head/last-Super-Admin/system-role rules rejected with right codes | API |
| T-20 | Org A cannot list/read/modify/export B; cross-tenant FK insert fails | Authorization, DB |
| T-21 | Sensitive profile access; HR read writes audit row | Authorization |
| T-22 | No passwordHash/tokens/OTP in any response | API |
| T-23 | HTTPS redirect and HSTS | Security |
| T-24 | Logs contain no passwords/tokens/OTP/personal fields | Integration |
| T-25 | Retention cleanup removes only expired rows | Integration |
| T-26 | Invalid dates, unknown fields, duplicates, bad enum, long strings, bad sort, past due date | API |
| T-27 | SQL metacharacters treated as data | API, lint |
| T-28 | Headers, CORS, oversized body 413, javascript: link rejected | Security, API |
| T-29 | Internal error returns envelope with request id, no stack | API |
| T-30 | Each rate-limit class returns 429 with Retry-After | API |
| T-31 | ZAP baseline + ASVS review, no high findings | Security |
| T-32 | UPDATE/DELETE/TRUNCATE on audit_logs and task_status_events rejected; audit row only for committed changes | DB, integration |
| T-33 | Each security alert fires in staging | Manual |
| T-34 | Backup restore drill within RTO | Recovery |
| T-35 | Two concurrent hires get distinct codes; idempotency replay | Integration |
| T-36 | Failure mid-onboarding leaves no partial rows; email down then invite retries/resend | Integration |
| T-37 | Deactivating a department head gives 409, then success after reassign | Workflow |
| T-38 | Department change: history, memberships ended, team assignments cancelled, creators notified | Workflow |
| T-39 | Double check-in 409; client time ignored; weekend/holiday; no check-out route (404) | API |
| T-40 | HR correction (add check-in, set absent); Dept Head correction gives 403 | API, workflow |
| T-41 | Derived absence incl. weekend, holiday, inactive, not-yet-joined, today before/after end, corrected day; no row inserted by read or job | Integration |
| T-42 | Team with member from another department gives 422; other-department head gives 404 | API |
| T-43 | Self/individual/team task creation; TEAM_EMPTY; ASSIGNEE_INACTIVE; Employee assigning gives 403 | Workflow |
| T-44 | Every legal and illegal transition in 2.8 | Unit, API |
| T-45 | Submit, resubmit, concurrent double submit | Integration |
| T-46 | Two reviewers at once: one 200, one 409 ALREADY_REVIEWED | Integration |
| T-47 | Board visibility per department/team; assignee sees review status | Authorization, API |
| T-48 | Feedback idempotency; Employee PATCH 403; Super Admin resolve notifies submitter | API |
| T-49 | Dashboard figures against fixed fixture per scope incl. boundaries and derived absence | Integration |
| T-50 | Deactivation with open assignments and sessions | Workflow |
| T-51 | Email/worker failures; job crash and rerun; no duplicate notifications | Integration |

Test infrastructure: tests override email provider and clock with fakes; each test in its own transaction or schema; fixtures include two orgs, four roles, three departments with heads, varied teams, multi-role users.
