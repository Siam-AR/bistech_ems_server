# SAD: Security Architecture Document, BisTech EMS

Version: 1.0 | Date: 2026-11-17
Scope: security and privacy controls, mapped to NestJS building blocks. Values marked "proposal" need confirmation.
Test IDs (T-xx) are defined in FSD.md section 12 and used by FTL.md.

---

## 1. Threats and main controls

| Threat | Main controls |
|---|---|
| Broken access control | Global permissions guard; record-level scope in services returning 404; composite tenant FKs; authorization tests generated from the matrix; undeclared routes denied |
| Credential attacks | Argon2id; lockout; rate limits; compromised-password check; generic login errors; TOTP later |
| OTP abuse | 5 attempts; HMAC storage; one live code; cooldown + hourly cap; identical responses; IP + email rate limits |
| Token theft | HttpOnly cookies, nothing in browser storage; 15-min access token; refresh rotation with reuse detection |
| CSRF | SameSite cookies; X-CSRF-Token + Origin check in a global guard |
| Injection / XSS | Parameterized queries; Zod validation pipe; React output encoding; https-only links; CSP + headers |
| Sensitive data exposure | Separate sensitive table + permission; explicit response DTOs; log redaction; encrypted backups |
| Insider misuse | DB-enforced reviewer check; self-modification bans; append-only audit; audited role changes |
| Abuse / DoS | Edge/WAF; per-route throttling; body size and statement timeouts |
| Supply chain / config | Dependency audit in CI; secret scanning; secret manager; separate environments |
| Data loss | PITR, encrypted off-site backups, tested restores |

## 2. Authentication

| Topic | Decision |
|---|---|
| Password hash | Argon2id. Start at OWASP minimum (~19 MiB, 2 iterations, 1 lane), tune to ~250 ms on prod host; params stored in hash; rehash on login when changed. bcrypt not used |
| Password policy | 08 to 32 chars, any characters, no composition rules, no forced rotation, reject compromised passwords, not equal to email/name; never logged or returned |
| Access token | JWT, 15 min, HttpOnly Secure SameSite=Lax cookie; verify signature, issuer, audience, expiry; carries user id, org id, session id only. Permissions loaded from DB per request so role changes apply immediately. Signing keys carry a key id for rotation |
| Refresh token | Opaque 256-bit, separate HttpOnly cookie scoped `/api/v1/auth`; stored hashed in `user_sessions`; rotated on every use; reuse revokes whole `family_id`. 12 h idle, 7 days absolute |
| Revocation | Logout, password change, reset, account disable, deactivation, role removal revoke sessions. Users can list/revoke own sessions |
| Lockout | 5 failed logins in 5 min lock account 15 min; identical message for unknown user and wrong password; Super Admin unlock |
| Account creation | No self-registration. Invite token single use, 72 h, stored hashed; active only after password set |
| Cookies | HttpOnly; Secure; SameSite=Lax; `__Host-` prefix where path allows |
| CSRF | Double-submit `X-CSRF-Token` bound to session + Origin match, global guard; GET never changes state |
| MFA | TOTP for Super Admin and HR Manager later (S-12). Until then compensating controls and alerts (K3) |

## 3. Forgot-password with OTP

1. `POST /auth/forgot-password`: always 202, same body whether or not the account exists.
2. Active account: one transaction invalidates earlier OTP, creates `otp_challenges` row, queues email. No new code within 60 s; max 3 per account per hour; 10 per hour per IP.
3. `POST /auth/verify-otp`: wrong code increments attempts atomically; after 5 the challenge is dead. Unknown email, wrong, expired, exhausted all return identical 422 `OTP_INVALID`. Keep response time similar by running the same work for unknown accounts.
4. Success: challenge consumed; single-use reset token (15 min) in HttpOnly cookie scoped `/api/v1/auth/reset-password`.
5. `POST /auth/reset-password`: check policy, store hash, consume token, revoke all sessions, clear lockout, send "password changed" email.

OTP details: 6 digits from a CSPRNG (never `Math.random`); stored as HMAC-SHA256 of `challengeId:code` with a secret from the secret manager (a plain hash is reversible in seconds); valid 10 min; the code is never in logs/audit; job payload encrypted AES-256-GCM and deleted on completion; HMAC secret rotated with a grace period for live challenges. Single use enforced by conditional update `WHERE consumed_at IS NULL AND attempts < max_attempts`.

## 4. Authorization and tenant isolation

- Access = permission + scope (`own`, `team`, `department`, `managed`, `org`). Union of scopes across multiple roles.
- Global permissions guard reads `@RequirePermission()`; service then checks the specific record (guards run before the record loads).
- Deny by default: a handler with neither `@RequirePermission()` nor `@Public()` returns 403 and fails the CI route scan.
- Out-of-scope record returns **404**, not 403.
- Organization id comes only from the session; every repository function takes it as a required argument; jobs carry it in payload.
- Composite FKs block cross-tenant references. Row-Level Security is a later defence in depth.
- Board-only task views return reduced cards; comments and submission text need a task-level permission.
- The permission matrix and seed come from one definition (in `packages/contracts`), which also types decorator keys.
- Rules no role can override: reviewer is never the submitter (DB CHECK + API); Dept Head acts only in departments they head; only Super Admin assigns roles or heads; nobody changes own roles/department/designation/status; HR cannot touch HR/Dept Head/Super Admin accounts; department head cannot be deactivated until replaced; last Super Admin protected; seeded system roles cannot be deleted or renamed.

## 5. Data classification

| Class | Examples | Who may read | Protection |
|---|---|---|---|
| Restricted | Password hashes, session/reset tokens, OTP hashes | Server only | Never returned or logged; hashed/HMAC |
| Confidential | employee_profiles; feedback; comments; submission text | Profiles: `employee.read.sensitive` + owner. Feedback: submitter + Super Admin. Comments/submissions: people who can act on the task | Separate table + permission; non-owner reads audited; field allow-lists |
| Internal | Work profile, attendance, task titles/status | Scope rules | Scope filtering, pagination |
| Public to staff | Holidays, department names, designations | Authenticated users | Authentication only |

- In transit: HTTPS only, HSTS, TLS 1.2+; DB over TLS on private network.
- At rest: encrypted managed DB and backups. Add external-key column encryption if identity numbers are ever collected.
- Minimisation: no identity numbers, bank details, photos.
- Responses built from explicit response DTOs; nestjs-pino redacts password, token, authorization, cookie, refresh, OTP and personal fields; bodies not logged.
- Staging/dev use synthetic data only.

### Retention (proposal, A12; legal review before hard deletion)
Employee/history/attendance 7 y after exit; tasks/submissions/comments/feedback 3 y after closure; audit logs 3 y online then archived; notifications 90 d after read; sessions/tokens/OTP 30 d after expiry; idempotency keys 7 d; backups expire per 8.6 below.

## 6. Application and infrastructure controls

- Input: Zod pipe on every route; parameterized queries only; sort allow-lists; 1 MB body limit; lint rule against string-built SQL.
- Output/browser: no `dangerouslySetInnerHTML` on user content; submission links only `https://` with `rel="noopener noreferrer"`; CSP without inline scripts where Next.js allows; X-Content-Type-Options, Referrer-Policy, `frame-ancestors 'none'`; Helmet in `main.ts`.
- CORS: strict allow-list (none needed behind the proxy).
- Errors: one global filter; stack traces/SQL logged with request id, never returned.
- Secrets: host secret manager, validated at boot, rotated on staff change, secret scanning in CI + pre-commit, per-environment. **Gmail credentials (app password or OAuth2 refresh token) live here and are never logged.**
- Dependencies: lockfile, `npm audit`, scheduled updates, block merges on critical findings.
- Database: app role has no DDL; migrations use a separate role; INSERT+SELECT only on `audit_logs` and `task_status_events`; statement timeout; no public DB endpoint.
- Network: edge/WAF; origin accepts only edge traffic where supported; admin access via VPN or provider console with MFA.
- `/health` returns only `{"status":"ok"}`; `/ready` internal; Swagger disabled in production.
- Frontend: dark-theme contrast checked against WCAG AA; axe runs in dark mode.

## 7. Rate limits (proposal, `@nestjs/throttler`)

| Route class | Limit | Key |
|---|---|---|
| `/auth/login` | 5 failed per 5 min | IP + email |
| `/auth/forgot-password` | 3 per 15 min; 10/h per IP | IP + email |
| `/auth/verify-otp` | 10 per 15 min | IP + email |
| accept-invite, reset-password, refresh | 10 per 15 min; refresh 30 per 15 min | IP; session for refresh |
| General authenticated | 100/min | user |
| Task and comment creation | 30/min | user |
| `POST /feedback` | 5/h | user |

429 `RATE_LIMITED` with `Retry-After`. Counters in process at launch; move to a shared store before a second API instance. Lockout/OTP state is in the DB so it works across instances.

## 8. Audit and monitoring

Audit rows are written by `AuditService` **inside the same transaction** as the change (not via events). Fields: actor, action, entity type/id, changed fields (before/after for non-sensitive, field names only for sensitive), IP, user agent, request id. No passwords, OTPs, tokens or personal profile values.

- Always audited: login, failed login, lockout, logout, password change, OTP requested/verified, password reset, session revocation; user creation/status/role changes; department head changes; employee create/update/department or designation change/deactivate/reactivate; attendance corrections; task creation by Dept Head/Super Admin, cancellation, review decisions; feedback handling; org settings changes.
- Also: non-owner reads of sensitive profiles; audit viewer reads (viewer is itself audited). Failed authorization on sensitive routes and OTP verification failures are counted and alerted, not stored per attempt.
- Alerts to a named on-call: login failures above threshold; repeated lockouts; refresh-token reuse; OTP request/failure limits exceeded; role change granting HR Manager or Super Admin; any update attempt on `audit_logs`.

## 9. Backup and recovery

| Topic | Plan |
|---|---|
| Scope | PostgreSQL (includes job queue). Code/config in Git; secrets in secret manager with documented recovery path |
| Method | Managed daily base backup + continuous WAL archiving (PITR). Fallback: pg_basebackup or pgBackRest to a separate account |
| Retention (proposal) | PITR window 7 d; daily snapshots 35 d; monthly 12 months |
| Protection | Encrypted at rest/in transit; separate account/project; two named roles; deletion needs second approver; access logged |
| Restore | Declare incident, freeze writes; restore to new instance at chosen time; integrity checks; repoint API/worker via secret manager; re-run migrations if needed; re-enable worker; record data window lost |
| Testing | Before go-live, quarterly, and after major changes; measure against RTO 4 h. Untested backup = unverified |
| Alerts | Backup failure; WAL lag > 10 min; latest backup > 26 h old |

RPO 15 min, RTO 4 h. Incident response contacts and a breach procedure (who decides, who is notified, within what time) are required before go-live (S-39).

## 10. Security checklist

Phase is MVP unless marked Later. Mark done when implemented **and** when its test passes.

| ID | Control | Test |
|---|---|---|
| S-01 | Argon2id; configurable params; rehash on login | T-01 |
| S-02 | 12-char minimum + compromised check on invite/reset/change | T-02 |
| S-03 | Generic login failure; lockout after 5; Super Admin unlock | T-03 |
| S-04 | Tokens only in HttpOnly Secure SameSite cookies; none in localStorage/URLs | T-04 |
| S-05 | Refresh rotation with reuse detection revoking family | T-05 |
| S-06 | Sessions revoked on logout, password change, reset, disable, deactivation | T-06 |
| S-07 | Invite-only; single-use hashed invite tokens with expiry | T-07 |
| S-08 | CSRF token + Origin check (global guard) | T-08 |
| S-09 | OTP: CSPRNG 6 digits, HMAC, 10 min, 5 attempts, one live code, 60 s cooldown, 3/h | T-09, T-10 |
| S-10 | forgot-password and verify-otp reveal nothing (body and timing) | T-11 |
| S-11 | Reset token single use, 15 min, path-scoped; reset revokes sessions, sends notice | T-12 |
| S-12 | TOTP for Super Admin and HR Manager (Later) | T-13 |
| S-13 | Every route declares permission or `@Public()`; deny-by-default; CI fails on undeclared | T-14 |
| S-14 | Server-side permission, scope, record checks; 404 out of scope | T-15, T-16 |
| S-15 | Dept Heads limited to managed departments; board-only views hide comments/submissions | T-17 |
| S-16 | No self-review (API + DB) | T-18 |
| S-17 | Role change rules; HR limits; last Super Admin; head assignment syncs role | T-19 |
| S-18 | Org id from session only; composite FKs; cross-tenant test | T-20 |
| S-19 | Sensitive profile permission; non-owner reads audited | T-21 |
| S-20 | Response DTO allow-lists; no hash/token/OTP in any response | T-22 |
| S-21 | HTTPS + HSTS; TLS on DB connections | T-23 |
| S-22 | Encrypted DB and backups | Config review |
| S-23 | Logs redact secrets, OTP, personal fields; bodies not logged | T-24 |
| S-24 | Retention approved; cleanup jobs running; erasure needs legal sign-off | T-25 |
| S-25 | Staging/dev synthetic data | Config review |
| S-26 | Zod pipe on all inputs; unknown fields rejected; sort allow-lists | T-26 |
| S-27 | Parameterized queries only; lint rule | T-27 |
| S-28 | Security headers, CSP, strict CORS, size limits, https-only links | T-28 |
| S-29 | Global exception filter; no stack/SQL in responses | T-29 |
| S-30 | Throttler on all route classes with 429 + Retry-After | T-30 |
| S-31 | Edge/WAF DDoS protection | Config review |
| S-32 | Secrets in secret manager; scanning; per-env; rotation procedure | CI check |
| S-33 | Dependency audit in CI + scheduled updates | CI check |
| S-34 | ZAP baseline + manual OWASP ASVS L2 review before go-live | T-31 |
| S-35 | Audit in same transaction; append-only by trigger + grants | T-32 |
| S-36 | Alerts for login anomalies, OTP abuse, session reuse, privileged role changes, audit tampering | T-33 |
| S-37 | Encrypted off-account backups with PITR; failure alerts | T-34 |
| S-38 | Restore tested before go-live and quarterly vs RTO | T-34 |
| S-39 | Incident contact list + breach procedure | Review |

## 11. Open security items
Gmail OAuth2 vs app password and sender domain (Q9); MFA timing (Q13); on-call and breach contacts (Q15); retention/legal review (Q11, K12); OTP, lockout and rate-limit values are proposals, unmeasured.
