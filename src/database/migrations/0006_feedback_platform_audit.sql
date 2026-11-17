-- 0006_feedback_platform_audit.sql

CREATE TABLE feedback_items (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  submitted_by    uuid NOT NULL,
  kind            text NOT NULL CHECK (kind IN ('issue','suggestion')),
  category        text NOT NULL CHECK (category IN ('general','attendance','tasks','system','workplace','other')),
  subject         text NOT NULL CHECK (char_length(subject) BETWEEN 5 AND 150),
  body            text NOT NULL CHECK (char_length(body) BETWEEN 10 AND 4000),
  status          text NOT NULL DEFAULT 'open' CHECK (status IN ('open','in_review','resolved','closed')),
  resolution_note text CHECK (char_length(resolution_note) <= 2000),
  handled_by      uuid,
  handled_at      timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT feedback_submitter_fk FOREIGN KEY (organization_id, submitted_by) REFERENCES users (organization_id, id),
  CONSTRAINT feedback_handler_fk   FOREIGN KEY (organization_id, handled_by)   REFERENCES users (organization_id, id),
  CONSTRAINT feedback_handled_shape CHECK (status = 'open' OR (handled_by IS NOT NULL AND handled_at IS NOT NULL))
);
CREATE INDEX feedback_org_status_created_idx ON feedback_items (organization_id, status, created_at DESC);
CREATE INDEX feedback_submitter_idx ON feedback_items (submitted_by, created_at DESC);

CREATE TABLE notifications (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  user_id         uuid NOT NULL,
  type            text NOT NULL CHECK (char_length(type) BETWEEN 1 AND 60),
  title           text NOT NULL CHECK (char_length(title) <= 150),
  body            text CHECK (char_length(body) <= 500),
  payload         jsonb NOT NULL DEFAULT '{}'::jsonb,   -- deep-link ids only
  dedupe_key      text NOT NULL CHECK (char_length(dedupe_key) <= 200),
  read_at         timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT notifications_user_fk FOREIGN KEY (organization_id, user_id) REFERENCES users (organization_id, id),
  CONSTRAINT notifications_dedupe_key UNIQUE (user_id, dedupe_key)
);
CREATE INDEX notifications_user_created_idx ON notifications (user_id, created_at DESC, id DESC);
CREATE INDEX notifications_user_unread_idx  ON notifications (user_id, created_at DESC) WHERE read_at IS NULL;
CREATE INDEX notifications_cleanup_idx      ON notifications (read_at) WHERE read_at IS NOT NULL;

CREATE TABLE audit_logs (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations (id),
  actor_user_id   uuid,                                 -- null for unauthenticated events (failed login, OTP)
  action          text NOT NULL CHECK (char_length(action) BETWEEN 1 AND 80),
  entity_type     text NOT NULL CHECK (char_length(entity_type) BETWEEN 1 AND 60),
  entity_id       uuid,                                 -- deliberate polymorphic reference, no FK
  metadata        jsonb NOT NULL DEFAULT '{}'::jsonb,   -- changed fields; never secrets or personal values
  ip_address      inet,
  user_agent      text CHECK (char_length(user_agent) <= 512),
  request_id      text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT audit_actor_fk FOREIGN KEY (organization_id, actor_user_id) REFERENCES users (organization_id, id)
);
CREATE INDEX audit_org_created_idx ON audit_logs (organization_id, created_at DESC, id DESC);
CREATE INDEX audit_entity_idx ON audit_logs (organization_id, entity_type, entity_id, created_at DESC);

CREATE TABLE idempotency_keys (
  organization_id uuid NOT NULL,
  user_id         uuid NOT NULL,
  key             uuid NOT NULL,
  request_hash    text NOT NULL,                        -- sha256(method + path + canonical body)
  response_status integer,                              -- null while the first request is in flight
  response_body   jsonb,
  created_at      timestamptz NOT NULL DEFAULT now(),
  expires_at      timestamptz NOT NULL,                 -- replay window 24 h
  PRIMARY KEY (organization_id, user_id, key),
  CONSTRAINT idempotency_user_fk FOREIGN KEY (organization_id, user_id) REFERENCES users (organization_id, id)
);
CREATE INDEX idempotency_cleanup_idx ON idempotency_keys (created_at);

