-- 0009_grants.sql : least-privilege grants for the runtime role.
-- Roles themselves are created by infra/db/bootstrap-roles.sql (superuser), not by migrations.
--   ems_migrator : owns the schema, runs migrations, no login from the app
--   ems_app      : runtime role used by API and worker, no DDL

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO ems_app;

-- Read/write tables (no hard delete)
GRANT SELECT, INSERT, UPDATE ON
  organizations, users, roles, role_permissions, departments, designations, employees,
  employee_profiles, attendance_records, teams, team_members, tasks, task_assignments,
  task_submissions, feedback_items
TO ems_app;

-- Append-only tables: INSERT + SELECT only (triggers are the second line of defence)
GRANT SELECT, INSERT ON
  audit_logs, task_status_events, employee_employment_history, attendance_corrections, task_comments
TO ems_app;

-- Short-lived or configuration tables that the application may delete from
GRANT SELECT, INSERT, UPDATE, DELETE ON
  user_sessions, auth_tokens, otp_challenges, notifications, idempotency_keys
TO ems_app;
GRANT SELECT, INSERT, DELETE ON user_roles, holidays TO ems_app;

-- Global catalogue: read only (changed by migrations or the seed role)
GRANT SELECT ON permissions TO ems_app;

GRANT EXECUTE ON FUNCTION managed_employee_ids(uuid, uuid) TO ems_app;

