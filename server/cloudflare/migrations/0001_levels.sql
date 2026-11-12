CREATE TABLE levels (
  id TEXT PRIMARY KEY NOT NULL CHECK(length(id) = 64),
  title TEXT NOT NULL CHECK(length(title) BETWEEN 1 AND 64),
  author TEXT NOT NULL CHECK(length(author) BETWEEN 1 AND 32),
  created_at TEXT NOT NULL,
  level_code TEXT NOT NULL CHECK(length(level_code) BETWEEN 8 AND 16384)
);

CREATE INDEX levels_newest ON levels(created_at DESC, id);

-- Also enforce the cap for writes outside the API. Duplicate retries are harmless.
CREATE TRIGGER levels_capacity BEFORE INSERT ON levels
WHEN (SELECT COUNT(*) FROM levels) >= 100
  AND NOT EXISTS (SELECT 1 FROM levels WHERE id = NEW.id)
BEGIN
  SELECT RAISE(ABORT, 'level_library_full');
END;
