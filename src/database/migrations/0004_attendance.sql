-- 0004_attendance.sql : check-in only attendance (A5, A14)

CREATE TABLE attendance_records (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  employee_id     uuid NOT NULL,
  work_date       date NOT NULL,                        -- calendar day in the organization's timezone
  check_in_at     timestamptz,
  status          text NOT NULL CHECK (status IN ('present','late','absent')),
  source          text NOT NULL CHECK (source IN ('web','hr_correction')),
  late_minutes    integer NOT NULL DEFAULT 0 CHECK (late_minutes >= 0),
  note            text CHECK (char_length(note) <= 200),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT attendance_org_id_key UNIQUE (organization_id, id),
  CONSTRAINT attendance_employee_day_key UNIQUE (employee_id, work_date),
  CONSTRAINT attendance_employee_fk FOREIGN KEY (organization_id, employee_id) REFERENCES employees (organization_id, id),
  CONSTRAINT attendance_checkin_required CHECK (status = 'absent' OR check_in_at IS NOT NULL),
  CONSTRAINT attendance_absent_shape CHECK (status <> 'absent' OR (late_minutes = 0 AND source = 'hr_correction')),
  CONSTRAINT attendance_late_shape CHECK (status = 'late' OR late_minutes = 0)
);
CREATE INDEX attendance_org_date_status_idx ON attendance_records (organization_id, work_date, status);

CREATE TABLE attendance_corrections (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id       uuid NOT NULL,
  employee_id           uuid NOT NULL,
  attendance_record_id  uuid,                           -- null when the day had no row
  work_date             date NOT NULL,
  corrected_check_in_at timestamptz,
  corrected_status      text NOT NULL CHECK (corrected_status IN ('present','late','absent')),
  reason                text NOT NULL CHECK (char_length(reason) BETWEEN 10 AND 500),
  original_snapshot     jsonb,                          -- null when there was no original row
  corrected_by          uuid NOT NULL,
  created_at            timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT corrections_employee_fk FOREIGN KEY (organization_id, employee_id) REFERENCES employees (organization_id, id),
  CONSTRAINT corrections_record_fk   FOREIGN KEY (organization_id, attendance_record_id) REFERENCES attendance_records (organization_id, id),
  CONSTRAINT corrections_user_fk     FOREIGN KEY (organization_id, corrected_by) REFERENCES users (organization_id, id),
  CONSTRAINT corrections_checkin_chk CHECK (corrected_status = 'absent' OR corrected_check_in_at IS NOT NULL)
);
CREATE INDEX corrections_record_idx ON attendance_corrections (attendance_record_id, created_at DESC);
CREATE INDEX corrections_employee_day_idx ON attendance_corrections (employee_id, work_date);
