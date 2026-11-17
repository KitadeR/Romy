-- 一連の検索の上限を中継側で共有する。希望の文や旅程は記録しない。
CREATE TABLE scene_sessions (
  device TEXT NOT NULL,
  session TEXT NOT NULL,
  day TEXT NOT NULL,
  searches INTEGER NOT NULL DEFAULT 0,
  intakes INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY(device, session)
);
