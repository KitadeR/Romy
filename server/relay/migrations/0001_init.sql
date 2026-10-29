-- Shared results of fact checks (Notion 04「2026-10-28｜結果の保存（キャッシュ）」).
-- Public facts about places only: no device, location, request text or itinerary.
CREATE TABLE checks (
  key TEXT PRIMARY KEY,          -- kind + place (MapKit place ID, or name + address)
  kind TEXT NOT NULL,
  result TEXT NOT NULL,          -- JSON of the result returned to the app
  checked_at TEXT NOT NULL,      -- ISO 8601, shown as 「10/20に確認」
  expires_at INTEGER NOT NULL    -- epoch milliseconds
);
CREATE INDEX checks_expires ON checks (expires_at);

-- Searches per device per day (Japan date), only to keep the cap; rows older than 7 days are deleted
-- (Notion 04「2026-10-29｜各社のデータの扱い」③).
CREATE TABLE usage (
  device TEXT NOT NULL,
  day TEXT NOT NULL,             -- YYYY-MM-DD in Japan time
  searches INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (device, day)
);

-- Money for the whole service per day. `reserved` holds the worst case of calls still running.
CREATE TABLE spend (
  day TEXT PRIMARY KEY,
  spent_usd REAL NOT NULL DEFAULT 0,
  reserved_usd REAL NOT NULL DEFAULT 0
);
