CREATE TABLE IF NOT EXISTS qq_accounts_users (
  id uuid PRIMARY KEY,
  username varchar(20),
  username_key varchar(80) UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((username IS NULL) = (username_key IS NULL))
);
CREATE TABLE IF NOT EXISTS qq_accounts_identities (
  provider varchar(16) NOT NULL CHECK (provider IN ('google', 'github')),
  subject varchar(255) NOT NULL,
  user_id uuid NOT NULL REFERENCES qq_accounts_users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (provider, subject)
);
CREATE TABLE IF NOT EXISTS qq_accounts_sessions (
  token_hash char(64) PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES qq_accounts_users(id),
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS qq_accounts_sessions_expiry ON qq_accounts_sessions(expires_at);
CREATE TABLE IF NOT EXISTS qq_accounts_oauth_attempts (
  state_hash char(64) PRIMARY KEY,
  binding_hash char(64) NOT NULL,
  provider varchar(16) NOT NULL CHECK (provider IN ('google', 'github')),
  verifier varchar(128) NOT NULL,
  nonce varchar(128) NOT NULL,
  language varchar(2) NOT NULL CHECK (language IN ('ja', 'en')),
  expires_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS qq_accounts_attempts_expiry ON qq_accounts_oauth_attempts(expires_at);

CREATE TABLE IF NOT EXISTS qq_ranked_seasons (
  id text PRIMARY KEY, ruleset text NOT NULL, starts_at timestamptz NOT NULL, ends_at timestamptz NOT NULL
);
CREATE TABLE IF NOT EXISTS qq_ranked_runs (
  id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES qq_accounts_users(id),
  season_id text NOT NULL REFERENCES qq_ranked_seasons(id), ruleset text NOT NULL,
  seed integer NOT NULL, starter_id text NOT NULL, next_sequence integer NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'active' CHECK(status IN ('active','pending','verifying','verified','rejected','disqualified','unverified')),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz, result jsonb, reason text, attempts integer NOT NULL DEFAULT 0,
  lease_until timestamptz, locked_by uuid
);
CREATE INDEX IF NOT EXISTS qq_ranked_owner ON qq_ranked_runs(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS qq_ranked_queue ON qq_ranked_runs(status, updated_at);
CREATE INDEX IF NOT EXISTS qq_ranked_board ON qq_ranked_runs(season_id, status);
CREATE TABLE IF NOT EXISTS qq_ranked_commands (
  run_id uuid NOT NULL REFERENCES qq_ranked_runs(id), sequence integer NOT NULL,
  command jsonb NOT NULL, PRIMARY KEY(run_id, sequence)
);
