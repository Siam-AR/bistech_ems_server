# PRD: BisTech EMS (Reduced MVP)

Version: 1.0 | Date: 2026-11-17 | Owner: @Siam
Source: "BisTech EMS: Reduced MVP Design & Architecture (NestJS edition)" plus frontend/email addendum.
Status: Assumptions below need stakeholder confirmation. Nothing in the schema has been executed or tested yet.

---

## 1. Purpose

Give BisTech one place to manage employees and attendance, assign and review work through teams and tasks, and collect issues and suggestions. Confidential data is protected and important actions are recorded.

## 2. Goals and non-goals

### Goals
- Four roles: Super Admin, HR Manager, Department Head, Employee.
- Three working modules: attendance (check-in only), teams and tasks, issues and suggestions.
- Invite-only accounts with email/password login and OTP password reset.
- Server-enforced permission + scope authorization on every request.
- Auditable critical actions; no hard deletes of business records.

### Non-goals (explicitly out of this release)
Leave, payroll, documents/object storage, performance, reports/exports, Auditor role, check-out and worked hours, nightly absent-marking job, TOTP/SSO, custom roles, department hierarchy, CSV import, task reassignment/subtasks/recurring/attachments, email digests, push/real-time, anonymous feedback, native mobile.

## 3. Users and roles

| Role | Purpose | Notable limits |
|---|---|---|
| Super Admin | Every permission at org scope; creates HR Managers and Department Heads; audit, settings, triage feedback | Cannot disable/demote last active Super Admin; cannot change own roles |
| HR Manager | Creates/manages employees and designations, views all attendance, corrects attendance, HR dashboard | Cannot create/change HR Manager, Dept Head or Super Admin accounts; cannot change own department/designation/status; no task management beyond own |
| Department Head | Team attendance, team creation, task assignment and review, team dashboard for departments they head | Limited to managed departments; cannot review own submission |
| Employee | Own profile, attendance, tasks, department/team boards, comments, submissions, feedback | Own records only |

Roles are additive: HR Managers and Department Heads also hold Employee.

## 4. Assumptions (A1 to A14)

| ID | Assumption |
|---|---|
| A1 | One organization (BisTech) at launch; schema is multi-tenant ready |
| A2 | Up to ~100 employees, 50 concurrent users in year one |
| A3 | Timezone Asia/Dhaka; weekend days configurable (default Fri, Sat) |
| A4 | Responsive web & mobile both (web first approach);  |
| A5 | Check-in only, one record per employee per day; no check-out, no worked time |
| A6 | Defaults: work start 10:00, grace 15 min, work day end 18:30 (org settings). End time only decides when a missing check-in counts as absent |
| A7 | Each employee in exactly one department; may be in several teams inside it |
| A8 | Each department has at most one head; one person may head several departments |
| A9 | OTP delivered by email (Nodemailer + Gmail) in the MVP |
| A10 | Task submission = note + up to 5 links; no file uploads |
| A11 | No leave module: approved leave shows absent until HR adds a correction |
| A12 | Retention proposal: employee/attendance 7y after exit; tasks/comments/feedback 3y after closure; audit logs 3y. Legal review required before any hard deletion |
| A13 | Everyone can create tasks for themselves; only Department Heads (own departments) and Super Admin assign to others |
| A14 | Absence is computed at read time, never stored (except HR-set absent correction) |

## 5. Features

### 5.1 Identity and access
Login, logout, refresh, invite-only accounts (accept-invite), forgot password with email OTP, change password, session list and revoke, RBAC with scopes, Super Admin creates HR Managers and Department Heads.

### 5.2 Employees and organization
Create profile (HR), list/search, change department/designation (with history), deactivate/reactivate, departments (flat), designations, holidays, org settings, department head assignment.

### 5.3 Attendance
Check-in (server clock), daily records, history, HR correction with mandatory reason and original snapshot, daily and monthly summaries with derived absence.

### 5.4 Teams and tasks
Department Head creates teams and manages members. Tasks: self, individual, team (fans out to one assignment per member). Per-assignment status, comments, submission (note + links), review (approve / changes requested), department and team read-only boards, personal tasks.

### 5.5 Issues and suggestions
Every role submits; Super Admin triages (open, in_review, resolved, closed) with resolution note; submitter sees status.

### 5.6 Notifications
In-app, polled every 30 to 60 s, for task and feedback events.

### 5.7 Dashboards
Employee, Department Head (team), HR (employee overview), Super Admin (company), plus summary.

### 5.8 Administration
User and role assignment, audit log viewer, org settings, backup and monitoring plan.

### 5.9 UI/UX requirements
- Dark theme by default (next-themes); light theme optional later.
- shadcn/ui (Radix + Tailwind), lucide-react icons, Google Sans (fallback DM Sans or Figtree if not licensed for web).
- Key forms meet WCAG 2.1 AA, including dark-mode contrast.
- Readable, code-driven error messages; responsive layout.

## 6. Non-functional requirements (proposed targets)

| Area | Target |
|---|---|
| Security | 100% of endpoints authenticated except login, refresh, accept-invite, forgot-password, verify-otp, reset-password; every route declares a permission or is `@Public()` |
| Privacy | Sensitive profile in own table; readable only with `employee.read.sensitive` |
| Reliability | Idempotency keys and unique constraints on retry-prone creates |
| Performance | p95 < 500 ms list/detail; check-in p95 < 300 ms |
| Scalability | Stateless app; add instances without code change |
| Availability | 99.5% business hours; RPO 15 min; RTO 4 h |
| Accessibility | WCAG 2.1 AA on key forms |

## 7. Success criteria for the MVP
- All milestone exit criteria in FTL.md met (M0 to M6).
- Authorization test matrix (32 permissions x 4 roles) passes.
- Performance criteria in TAD.md section 12 met.
- Restore drill passed within RTO.
- Stakeholder sign-off on open questions.

## 8. Open questions (needed-by milestone)

| ID | Question | By |
|---|---|---|
| Q1 | Employees/HR create only personal tasks; Dept Heads assign in their departments; Super Admin assigns anyone? | M4 |
| Q2 | Should every employee see department-wide and team-wide boards? | M4 |
| Q3 | Should Super Admin and HR both read sensitive profiles? (current: yes) | M1 |
| Q4 | Who triages feedback: Super Admin only or HR for workplace items? | M5 |
| Q5 | Is review required for every assigned task? May the employee's Dept Head review Super Admin tasks? | M4 |
| Q6 | One department per employee; may teams cross departments? | M2 |
| Q7 | Working week, hours, grace, shifts? | M3 |
| Q8 | Handling of approved leave until a leave module exists? | M3 |
| Q9 | OTP email only or SMS too? Sending address/domain (Gmail vs Workspace)? | M0 |
| Q10 | Does Super Admin have an employee profile/attendance? Does HR have a Dept Head? | M2 |
| Q11 | Retention periods, erasure rules, data-access requests? | M5 |
| Q12 | Hosting provider, region, budget, data residency? | M0 |
| Q13 | MFA required in MVP for Super Admin/HR? | M1 |
| Q14 | Reassignment, attachments, recurring tasks at launch? | M4 |
| Q15 | On-call/security contact and breach process? | M5 |
| Q16 | Is check-in-only attendance acceptable for HR reporting? | M3 |
| Q17 | OK that past absences change when holidays/settings are edited? | M3 |

## 9. Risks (summary)
Scope growth (K1), module boundary erosion (K2), no MFA initially (K3), authorization gaps (K4), OTP deliverability (K5), leave counted as absent (K6), team new to NestJS (K17), derived absence correctness/performance (K18), no worked-hours data (K19), Gmail sending limits (new, see TAD.md). Full list in the source report section 12.1.

## 10. Later work
Check-out and worked hours; nightly absent marking or monthly lock; leave; payroll; documents; performance; TOTP/SSO; custom roles; task reassignment/subtasks/recurring/attachments; email digests; real-time; department hierarchy; CSV import/export; anonymous feedback; analytics.
