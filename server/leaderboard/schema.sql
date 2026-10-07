-- 미니게임 순위. 앱에서 순위 참여를 켠 사람의 무작위 설치 ID, 닉네임, 점수만 둔다.
CREATE TABLE IF NOT EXISTS players (
  id TEXT PRIMARY KEY,
  nickname TEXT NOT NULL,
  best INTEGER NOT NULL DEFAULT 0,
  best_at INTEGER,
  last_submit INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS runs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  player_id TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  score INTEGER NOT NULL,
  coins INTEGER NOT NULL,
  duration_ms INTEGER NOT NULL,
  app_version TEXT,
  created_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS players_best ON players (best DESC);
CREATE INDEX IF NOT EXISTS runs_recent ON runs (created_at, player_id, score);

-- 제출 횟수 (해시한 IP, 1분 단위). 예약 작업이 1시간 지난 것을 지운다.
CREATE TABLE IF NOT EXISTS submit_hits (
  key TEXT NOT NULL,
  minute INTEGER NOT NULL,
  count INTEGER NOT NULL,
  PRIMARY KEY (key, minute)
);
