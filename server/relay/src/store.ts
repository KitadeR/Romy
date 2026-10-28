import type { CheckResult } from "./types";

/// Where the relay keeps the shared results and the counts for the caps. D1 in the Worker, memory in tests.
export interface Store {
  getCheck(key: string, nowMs: number): Promise<CheckResult | null>;
  putCheck(key: string, kind: string, result: CheckResult, expiresAtMs: number): Promise<void>;
  /// Counts one search for the device today, unless it already reached `limit`. False when it had.
  takeSearch(device: string, day: string, limit: number): Promise<boolean>;
  giveBackSearch(device: string, day: string): Promise<void>;
  /// Holds `amount` of today's money, unless spent + held + amount would pass `cap`. False when it would.
  reserve(day: string, amount: number, cap: number): Promise<boolean>;
  /// Lets go of what was held and adds what the call really cost.
  settle(day: string, reserved: number, spent: number): Promise<void>;
  /// Deletes counts from before `oldestDay` and results past their date.
  sweep(oldestDay: string, nowMs: number): Promise<void>;
}

export class D1Store implements Store {
  constructor(private readonly db: D1Database) {}

  async getCheck(key: string, nowMs: number): Promise<CheckResult | null> {
    const row = await this.db
      .prepare("SELECT result FROM checks WHERE key = ?1 AND expires_at > ?2")
      .bind(key, nowMs)
      .first<{ result: string }>();
    return row ? (JSON.parse(row.result) as CheckResult) : null;
  }

  async putCheck(key: string, kind: string, result: CheckResult, expiresAtMs: number): Promise<void> {
    await this.db
      .prepare(
        "INSERT INTO checks (key, kind, result, checked_at, expires_at) VALUES (?1, ?2, ?3, ?4, ?5) " +
          "ON CONFLICT (key) DO UPDATE SET result = ?3, checked_at = ?4, expires_at = ?5"
      )
      .bind(key, kind, JSON.stringify(result), result.checkedAt, expiresAtMs)
      .run();
  }

  async takeSearch(device: string, day: string, limit: number): Promise<boolean> {
    const [, update] = await this.db.batch([
      this.db.prepare("INSERT INTO usage (device, day) VALUES (?1, ?2) ON CONFLICT DO NOTHING").bind(device, day),
      this.db
        .prepare("UPDATE usage SET searches = searches + 1 WHERE device = ?1 AND day = ?2 AND searches < ?3")
        .bind(device, day, limit),
    ]);
    return update.meta.changes === 1;
  }

  async giveBackSearch(device: string, day: string): Promise<void> {
    await this.db
      .prepare("UPDATE usage SET searches = MAX(0, searches - 1) WHERE device = ?1 AND day = ?2")
      .bind(device, day)
      .run();
  }

  async reserve(day: string, amount: number, cap: number): Promise<boolean> {
    const [, update] = await this.db.batch([
      this.db.prepare("INSERT INTO spend (day) VALUES (?1) ON CONFLICT DO NOTHING").bind(day),
      this.db
        .prepare(
          "UPDATE spend SET reserved_usd = reserved_usd + ?2 WHERE day = ?1 AND spent_usd + reserved_usd + ?2 <= ?3"
        )
        .bind(day, amount, cap),
    ]);
    return update.meta.changes === 1;
  }

  async settle(day: string, reserved: number, spent: number): Promise<void> {
    await this.db
      .prepare("UPDATE spend SET reserved_usd = MAX(0, reserved_usd - ?2), spent_usd = spent_usd + ?3 WHERE day = ?1")
      .bind(day, reserved, spent)
      .run();
  }

  async sweep(oldestDay: string, nowMs: number): Promise<void> {
    await this.db.batch([
      this.db.prepare("DELETE FROM usage WHERE day < ?1").bind(oldestDay),
      this.db.prepare("DELETE FROM checks WHERE expires_at <= ?1").bind(nowMs),
    ]);
  }
}
