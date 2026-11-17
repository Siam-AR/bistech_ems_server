-- 0007_triggers.sql : updated_at maintenance and append-only enforcement

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'organizations','users','roles','departments','designations','employees','employee_profiles',
    'attendance_records','teams','tasks','task_assignments','feedback_items'
  ] LOOP
    EXECUTE format(
      'CREATE TRIGGER %I BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION set_updated_at()',
      t || '_set_updated_at', t);
  END LOOP;

  -- Append-only tables: block UPDATE/DELETE per row and TRUNCATE per statement.
  FOREACH t IN ARRAY ARRAY[
    'audit_logs','task_status_events','employee_employment_history','attendance_corrections','task_comments'
  ] LOOP
    EXECUTE format(
      'CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION block_mutation()',
      t || '_append_only_row', t);
    EXECUTE format(
      'CREATE TRIGGER %I BEFORE TRUNCATE ON %I FOR EACH STATEMENT EXECUTE FUNCTION block_mutation()',
      t || '_append_only_truncate', t);
  END LOOP;
END $$;

