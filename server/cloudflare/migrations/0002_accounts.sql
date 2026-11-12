CREATE TABLE users (
  id TEXT PRIMARY KEY NOT NULL,
  username TEXT NOT NULL CHECK(length(username) BETWEEN 3 AND 24),
  username_key TEXT NOT NULL UNIQUE,
  password_salt TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  password_scheme TEXT NOT NULL DEFAULT 'scrypt-v1',
  created_at TEXT NOT NULL
);

CREATE TABLE account_sessions (
  token_hash TEXT PRIMARY KEY NOT NULL,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at INTEGER NOT NULL
);

CREATE INDEX account_session_expiry ON account_sessions(expires_at);
CREATE INDEX account_session_user ON account_sessions(user_id, expires_at DESC);

-- Existing published levels keep their original attribution.
ALTER TABLE levels ADD COLUMN author_id TEXT REFERENCES users(id);
