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
