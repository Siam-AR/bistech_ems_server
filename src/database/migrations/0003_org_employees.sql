-- 0003_org_employees.sql : organization structure, employees, history

CREATE TABLE departments (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  uuid NOT NULL REFERENCES organizations (id),
  name             text NOT NULL CHECK (char_length(name) BETWEEN 2 AND 100),
  description      text CHECK (char_length(description) <= 500),
  head_employee_id uuid,                               -- FK added after employees exists
  archived_at      timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT departments_org_id_key UNIQUE (organization_id, id),
  CONSTRAINT departments_org_name_key UNIQUE (organization_id, name)
);
CREATE INDEX departments_head_idx ON departments (organization_id, head_employee_id)
  WHERE head_employee_id IS NOT NULL;

CREATE TABLE designations (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations (id),
  title           text NOT NULL CHECK (char_length(title) BETWEEN 2 AND 100),
  archived_at     timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT designations_org_id_key UNIQUE (organization_id, id),
  CONSTRAINT designations_org_title_key UNIQUE (organization_id, title)
);

CREATE TABLE holidays (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations (id),
  holiday_date    date NOT NULL,
  name            text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 100),
  created_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT holidays_org_date_key UNIQUE (organization_id, holiday_date)
);

CREATE TABLE employees (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES organizations (id),
  user_id           uuid NOT NULL,
  employee_code     text NOT NULL CHECK (employee_code ~ '^[A-Z]{2,6}-[0-9]{5,}$'),
  first_name        text NOT NULL CHECK (char_length(first_name) BETWEEN 1 AND 80),
  last_name         text NOT NULL CHECK (char_length(last_name) BETWEEN 1 AND 80),
  work_email        text NOT NULL CHECK (char_length(work_email) BETWEEN 3 AND 254),
  phone             text CHECK (phone ~ '^\+[1-9][0-9]{6,14}$'),
  department_id     uuid NOT NULL,
  designation_id    uuid NOT NULL,
  employment_type   text NOT NULL CHECK (employment_type IN ('full_time','part_time','contract','intern')),
  employment_status text NOT NULL DEFAULT 'active' CHECK (employment_status IN ('active','inactive')),
  joining_date      date NOT NULL,
  exit_date         date,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT employees_org_id_key UNIQUE (organization_id, id),
  CONSTRAINT employees_user_key UNIQUE (user_id),
  CONSTRAINT employees_user_fk        FOREIGN KEY (organization_id, user_id)        REFERENCES users (organization_id, id),
  CONSTRAINT employees_department_fk  FOREIGN KEY (organization_id, department_id)  REFERENCES departments (organization_id, id),
  CONSTRAINT employees_designation_fk FOREIGN KEY (organization_id, designation_id) REFERENCES designations (organization_id, id),
  CONSTRAINT employees_exit_chk CHECK (exit_date IS NULL OR exit_date >= joining_date),
  CONSTRAINT employees_inactive_requires_exit CHECK (employment_status = 'active' OR exit_date IS NOT NULL)
);
CREATE UNIQUE INDEX employees_org_code_key  ON employees (organization_id, employee_code);
CREATE UNIQUE INDEX employees_org_email_key ON employees (organization_id, lower(work_email));
CREATE INDEX employees_org_status_idx      ON employees (organization_id, employment_status);
CREATE INDEX employees_org_dept_status_idx ON employees (organization_id, department_id, employment_status);
CREATE INDEX employees_org_name_idx        ON employees (organization_id, lower(last_name), lower(first_name));

ALTER TABLE departments
  ADD CONSTRAINT departments_head_fk
  FOREIGN KEY (organization_id, head_employee_id) REFERENCES employees (organization_id, id);

CREATE TABLE employee_profiles (
  employee_id               uuid PRIMARY KEY,
  organization_id           uuid NOT NULL,
  date_of_birth             date CHECK (date_of_birth < CURRENT_DATE),
  personal_email            text CHECK (char_length(personal_email) <= 254),
  personal_phone            text CHECK (personal_phone ~ '^\+[1-9][0-9]{6,14}$'),
  address_line              text CHECK (char_length(address_line) <= 300),
  city                      text CHECK (char_length(city) <= 100),
  country_code              char(2) CHECK (country_code ~ '^[A-Z]{2}$'),
  emergency_contact_name    text CHECK (char_length(emergency_contact_name) <= 120),
  emergency_contact_phone   text CHECK (emergency_contact_phone ~ '^\+[1-9][0-9]{6,14}$'),
  emergency_contact_relation text CHECK (char_length(emergency_contact_relation) <= 60),
  created_at                timestamptz NOT NULL DEFAULT now(),
  updated_at                timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT employee_profiles_employee_fk FOREIGN KEY (organization_id, employee_id)
    REFERENCES employees (organization_id, id)
);

CREATE TABLE employee_employment_history (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  employee_id     uuid NOT NULL,
  event_type      text NOT NULL CHECK (event_type IN
                    ('hired','department_change','designation_change','status_change','reactivated')),
  effective_date  date NOT NULL,
  old_value       jsonb,
  new_value       jsonb,
  reason          text CHECK (char_length(reason) <= 500),
  changed_by      uuid NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT history_employee_fk   FOREIGN KEY (organization_id, employee_id) REFERENCES employees (organization_id, id),
  CONSTRAINT history_changed_by_fk FOREIGN KEY (organization_id, changed_by)  REFERENCES users (organization_id, id)
);
CREATE INDEX history_employee_idx ON employee_employment_history (employee_id, effective_date DESC, created_at DESC);

