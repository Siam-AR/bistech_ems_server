-- 0005_teams_tasks.sql : teams, tasks, assignments, submissions, comments, status events

CREATE TABLE teams (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  department_id   uuid NOT NULL,
  name            text NOT NULL CHECK (char_length(name) BETWEEN 2 AND 80),
  description     text CHECK (char_length(description) <= 500),
  created_by      uuid NOT NULL,
  archived_at     timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT teams_org_id_key UNIQUE (organization_id, id),
  CONSTRAINT teams_department_fk FOREIGN KEY (organization_id, department_id) REFERENCES departments (organization_id, id),
  CONSTRAINT teams_created_by_fk FOREIGN KEY (organization_id, created_by)    REFERENCES users (organization_id, id)
);
CREATE UNIQUE INDEX teams_dept_name_active_key ON teams (department_id, lower(name)) WHERE archived_at IS NULL;
CREATE INDEX teams_org_dept_idx ON teams (organization_id, department_id) WHERE archived_at IS NULL;

CREATE TABLE team_members (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  team_id         uuid NOT NULL,
  employee_id     uuid NOT NULL,
  added_by        uuid NOT NULL,
  added_at        timestamptz NOT NULL DEFAULT now(),
  removed_at      timestamptz,
  CONSTRAINT team_members_team_fk     FOREIGN KEY (organization_id, team_id)     REFERENCES teams (organization_id, id),
  CONSTRAINT team_members_employee_fk FOREIGN KEY (organization_id, employee_id) REFERENCES employees (organization_id, id),
  CONSTRAINT team_members_added_by_fk FOREIGN KEY (organization_id, added_by)    REFERENCES users (organization_id, id),
  CONSTRAINT team_members_removed_chk CHECK (removed_at IS NULL OR removed_at >= added_at)
);
CREATE UNIQUE INDEX team_members_active_key ON team_members (team_id, employee_id) WHERE removed_at IS NULL;
CREATE INDEX team_members_employee_active_idx ON team_members (employee_id) WHERE removed_at IS NULL;

CREATE FUNCTION team_members_check_department() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  emp_dept  uuid;
  team_dept uuid;
BEGIN
  SELECT department_id INTO emp_dept  FROM employees WHERE organization_id = NEW.organization_id AND id = NEW.employee_id;
  SELECT department_id INTO team_dept FROM teams     WHERE organization_id = NEW.organization_id AND id = NEW.team_id;
  IF emp_dept IS DISTINCT FROM team_dept THEN
    RAISE EXCEPTION 'employee % is not in the department of team %', NEW.employee_id, NEW.team_id
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER team_members_department_chk BEFORE INSERT ON team_members
  FOR EACH ROW EXECUTE FUNCTION team_members_check_department();

CREATE TABLE tasks (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  title           text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 150),
  description     text CHECK (char_length(description) <= 4000),
  priority        text NOT NULL DEFAULT 'medium' CHECK (priority IN ('low','medium','high','urgent')),
  due_date        date,
  assignment_type text NOT NULL CHECK (assignment_type IN ('self','individual','team')),
  team_id         uuid,
  department_id   uuid NOT NULL,                        -- fixed at creation (FSD 2.7)
  requires_review boolean NOT NULL,
  status          text NOT NULL DEFAULT 'active' CHECK (status IN ('active','cancelled')),
  created_by      uuid NOT NULL,
  cancelled_at    timestamptz,
  cancel_reason   text CHECK (char_length(cancel_reason) <= 500),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT tasks_org_id_key UNIQUE (organization_id, id),
  CONSTRAINT tasks_team_fk       FOREIGN KEY (organization_id, team_id)       REFERENCES teams (organization_id, id),
  CONSTRAINT tasks_department_fk FOREIGN KEY (organization_id, department_id) REFERENCES departments (organization_id, id),
  CONSTRAINT tasks_created_by_fk FOREIGN KEY (organization_id, created_by)    REFERENCES users (organization_id, id),
  CONSTRAINT tasks_team_iff_team_type CHECK ((assignment_type = 'team') = (team_id IS NOT NULL)),
  CONSTRAINT tasks_cancel_shape CHECK ((status = 'cancelled') = (cancelled_at IS NOT NULL))
);
CREATE INDEX tasks_org_dept_status_due_idx ON tasks (organization_id, department_id, status, due_date);
CREATE INDEX tasks_team_idx       ON tasks (team_id) WHERE team_id IS NOT NULL;
CREATE INDEX tasks_created_by_idx ON tasks (created_by);

CREATE TABLE task_assignments (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  task_id         uuid NOT NULL,
  employee_id     uuid NOT NULL,
  status          text NOT NULL DEFAULT 'todo' CHECK (status IN
                    ('todo','in_progress','in_review','changes_requested','done','cancelled')),
  started_at      timestamptz,
  submitted_at    timestamptz,
  completed_at    timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT task_assignments_org_id_key UNIQUE (organization_id, id),
  CONSTRAINT task_assignments_task_employee_key UNIQUE (task_id, employee_id),
  CONSTRAINT task_assignments_task_fk     FOREIGN KEY (organization_id, task_id)     REFERENCES tasks (organization_id, id),
  CONSTRAINT task_assignments_employee_fk FOREIGN KEY (organization_id, employee_id) REFERENCES employees (organization_id, id),
  CONSTRAINT task_assignments_completed_chk CHECK (status = 'done' OR completed_at IS NULL)
);
CREATE INDEX task_assignments_employee_status_idx ON task_assignments (employee_id, status);
CREATE INDEX task_assignments_task_idx ON task_assignments (task_id);

CREATE TABLE task_submissions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  assignment_id   uuid NOT NULL,
  version         integer NOT NULL CHECK (version >= 1),
  note            text NOT NULL CHECK (char_length(note) BETWEEN 1 AND 2000),
  links           jsonb NOT NULL DEFAULT '[]'::jsonb
                  CHECK (jsonb_typeof(links) = 'array' AND jsonb_array_length(links) <= 5),
  submitted_by    uuid NOT NULL,
  submitted_at    timestamptz NOT NULL DEFAULT now(),
  review_status   text NOT NULL DEFAULT 'pending'
                  CHECK (review_status IN ('pending','approved','changes_requested','not_required')),
  reviewed_by     uuid,
  reviewed_at     timestamptz,
  review_note     text CHECK (char_length(review_note) <= 500),
  CONSTRAINT task_submissions_assignment_fk FOREIGN KEY (organization_id, assignment_id) REFERENCES task_assignments (organization_id, id),
  CONSTRAINT task_submissions_submitter_fk  FOREIGN KEY (organization_id, submitted_by)  REFERENCES users (organization_id, id),
  CONSTRAINT task_submissions_reviewer_fk   FOREIGN KEY (organization_id, reviewed_by)   REFERENCES users (organization_id, id),
  CONSTRAINT task_submissions_version_key UNIQUE (assignment_id, version),
  CONSTRAINT task_submissions_no_self_review CHECK (reviewed_by <> submitted_by),
  CONSTRAINT task_submissions_review_shape CHECK (
    (review_status IN ('approved','changes_requested')) = (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)),
  CONSTRAINT task_submissions_changes_need_note CHECK (review_status <> 'changes_requested' OR review_note IS NOT NULL)
);
CREATE UNIQUE INDEX task_submissions_one_pending_key ON task_submissions (assignment_id) WHERE review_status = 'pending';
CREATE INDEX task_submissions_review_queue_idx ON task_submissions (organization_id, submitted_at) WHERE review_status = 'pending';

CREATE TABLE task_comments (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  task_id         uuid NOT NULL,
  author_user_id  uuid NOT NULL,
  body            text NOT NULL CHECK (char_length(body) BETWEEN 1 AND 2000),
  created_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT task_comments_task_fk   FOREIGN KEY (organization_id, task_id)        REFERENCES tasks (organization_id, id),
  CONSTRAINT task_comments_author_fk FOREIGN KEY (organization_id, author_user_id) REFERENCES users (organization_id, id)
);
CREATE INDEX task_comments_thread_idx ON task_comments (task_id, created_at, id);

CREATE TABLE task_status_events (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  assignment_id   uuid NOT NULL,
  from_status     text CHECK (from_status IN ('todo','in_progress','in_review','changes_requested','done','cancelled')),
  to_status       text NOT NULL CHECK (to_status IN ('todo','in_progress','in_review','changes_requested','done','cancelled')),
  actor_user_id   uuid,                                 -- null for system-driven cancellation by job
  created_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT task_events_assignment_fk FOREIGN KEY (organization_id, assignment_id) REFERENCES task_assignments (organization_id, id),
  CONSTRAINT task_events_actor_fk      FOREIGN KEY (organization_id, actor_user_id) REFERENCES users (organization_id, id)
);
CREATE INDEX task_events_assignment_idx ON task_status_events (assignment_id, created_at, id);
