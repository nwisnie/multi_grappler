-- Keep each player's personal best, including players outside the public top 10.
CREATE TABLE level_times (
  level_id TEXT NOT NULL REFERENCES levels(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  time_ms INTEGER NOT NULL CHECK(typeof(time_ms) = 'integer' AND time_ms BETWEEN 1 AND 86400000),
  achieved_at TEXT NOT NULL,
  PRIMARY KEY (level_id, user_id)
);

CREATE INDEX level_times_ranking ON level_times(level_id, time_ms, achieved_at, user_id);
