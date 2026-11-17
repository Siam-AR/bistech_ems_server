-- 0002_identity.sql : tenant root, users, RBAC, sessions, tokens, OTP

CREATE TABLE organizations (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name                 text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 150),
  slug                 text NOT NULL CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  timezone             text NOT NULL DEFAULT 'Asia/Dhaka',
  settings             jsonb NOT NULL DEFAULT
    '{"workStart":"10:00","graceMinutes":15,"workEnd":"18:30","weekendDays":[5,6]}'::jsonb
    CHECK (jsonb_typeof(settings) = 'object'),            -- weekendDays: ISO (1=Mon..7=Sun)
  employee_code_prefix text NOT NULL DEFAULT 'BST' CHECK (employee_code_prefix ~ '^[A-Z]{2,6}$'),
  last_employee_number integer NOT NULL DEFAULT 0 CHECK (last_employee_number >= 0),
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT organizations_slug_key UNIQUE (slug)
);

CREATE TABLE users (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id    uuid NOT NULL REFERENCES organizations (id),
  email              text NOT NULL CHECK (char_length(email) BETWEEN 3 AND 254),
  display_name       text NOT NULL CHECK (char_length(display_name) BETWEEN 1 AND 160),
  password_hash      text,
  account_status     text NOT NULL DEFAULT 'invited'
    CHECK (account_status IN ('invited','active','suspended','disabled')),
  failed_login_count integer NOT NULL DEFAULT 0 CHECK (failed_login_count >= 0),
  locked_until       timestamptz,
  last_login_at      timestamptz,
  password_changed_at timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT users_org_id_key UNIQUE (organization_id, id),
  CONSTRAINT users_active_requires_hash CHECK (account_status <> 'active' OR password_hash IS NOT NULL)
);
CREATE UNIQUE INDEX users_org_email_key ON users (organization_id, lower(email));

CREATE TABLE roles (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations (id),
  name            text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 60),
  description     text,
  is_system       boolean NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT roles_org_id_key UNIQUE (organization_id, id),
  CONSTRAINT roles_org_name_key UNIQUE (organization_id, name)
);

CREATE TABLE permissions (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key         text NOT NULL CHECK (key ~ '^[a-z]+(\.[a-z]+)+$'),
  description text NOT NULL,
  CONSTRAINT permissions_key_key UNIQUE (key)
);

CREATE TABLE role_permissions (
  role_id       uuid NOT NULL REFERENCES roles (id),
  permission_id uuid NOT NULL REFERENCES permissions (id),
  scope         text NOT NULL CHECK (scope IN ('own','team','department','managed','org')),
  PRIMARY KEY (role_id, permission_id)
);
CREATE INDEX role_permissions_permission_idx ON role_permissions (permission_id);

CREATE TABLE user_roles (
  user_id         uuid NOT NULL,
  role_id         uuid NOT NULL,
  organization_id uuid NOT NULL,
  assigned_by     uuid,
  assigned_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, role_id),
  CONSTRAINT user_roles_user_fk     FOREIGN KEY (organization_id, user_id)     REFERENCES users (organization_id, id),
  CONSTRAINT user_roles_role_fk     FOREIGN KEY (organization_id, role_id)     REFERENCES roles (organization_id, id),
  CONSTRAINT user_roles_assigner_fk FOREIGN KEY (organization_id, assigned_by) REFERENCES users (organization_id, id)
);
CREATE INDEX user_roles_role_idx ON user_roles (organization_id, role_id);

-- One row per refresh token. A rotation inserts a new row in the same family and sets rotated_at on the old one.
-- family_id is the session id exposed to the API and carried in the access-token (sid).
CREATE TABLE user_sessions (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id     uuid NOT NULL,
  user_id             uuid NOT NULL,
  family_id           uuid NOT NULL,
  refresh_token_hash  text NOT NULL,
  user_agent          text CHECK (char_length(user_agent) <= 512),
  ip_address          inet,
  created_at          timestamptz NOT NULL DEFAULT now(),
  last_used_at        timestamptz NOT NULL DEFAULT now(),
  rotated_at          timestamptz,
  expires_at          timestamptz NOT NULL,            -- idle expiry (12 h), slides on rotation
  absolute_expires_at timestamptz NOT NULL,            -- 7 d from login, never extended
  revoked_at          timestamptz,
  revoked_reason      text CHECK (revoked_reason IN ('logout','password_change','password_reset',
                        'account_disabled','deactivated','role_removed','reuse_detected','user_revoke','admin_revoke')),
  CONSTRAINT user_sessions_hash_key UNIQUE (refresh_token_hash),
  CONSTRAINT user_sessions_user_fk FOREIGN KEY (organization_id, user_id) REFERENCES users (organization_id, id),
  CONSTRAINT user_sessions_expiry_chk CHECK (expires_at <= absolute_expires_at),
  CONSTRAINT user_sessions_revoke_chk CHECK ((revoked_at IS NULL) = (revoked_reason IS NULL))
);
CREATE INDEX user_sessions_family_idx ON user_sessions (family_id);
CREATE INDEX user_sessions_user_live_idx ON user_sessions (user_id)
  WHERE revoked_at IS NULL AND rotated_at IS NULL;
CREATE INDEX user_sessions_cleanup_idx ON user_sessions (absolute_expires_at);

CREATE TABLE auth_tokens (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  user_id         uuid NOT NULL,
  purpose         text NOT NULL CHECK (purpose IN ('invite','password_reset')),
  token_hash      text NOT NULL,
  expires_at      timestamptz NOT NULL,
  used_at         timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT auth_tokens_hash_key UNIQUE (token_hash),
  CONSTRAINT auth_tokens_user_fk FOREIGN KEY (organization_id, user_id) REFERENCES users (organization_id, id)
);
CREATE INDEX auth_tokens_user_purpose_idx ON auth_tokens (user_id, purpose) WHERE used_at IS NULL;
CREATE INDEX auth_tokens_cleanup_idx ON auth_tokens (expires_at);

CREATE TABLE otp_challenges (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  user_id         uuid NOT NULL,
  purpose         text NOT NULL CHECK (purpose IN ('password_reset')),
  code_hash       text NOT NULL,                       -- HMAC-SHA256(challengeId:code), never a plain hash
  hmac_key_id     text NOT NULL,                       -- which HMAC secret version produced it (rotation grace)
  attempts        smallint NOT NULL DEFAULT 0,
  max_attempts    smallint NOT NULL DEFAULT 5,
  sent_at         timestamptz NOT NULL DEFAULT now(),
  expires_at      timestamptz NOT NULL,
  consumed_at     timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT otp_attempts_chk CHECK (attempts >= 0 AND attempts <= max_attempts),
  CONSTRAINT otp_max_attempts_chk CHECK (max_attempts BETWEEN 1 AND 5),
  CONSTRAINT otp_user_fk FOREIGN KEY (organization_id, user_id) REFERENCES users (organization_id, id)
);
CREATE UNIQUE INDEX otp_one_live_per_user_purpose ON otp_challenges (user_id, purpose) WHERE consumed_at IS NULL;
CREATE INDEX otp_rate_idx ON otp_challenges (user_id, created_at DESC);
CREATE INDEX otp_cleanup_idx ON otp_challenges (expires_at);
