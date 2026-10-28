import type { Store } from "../src/store";
import type { CheckResult } from "../src/types";

/// The `Store` in memory, with the same rules as the D1 one, for tests.
export class MemoryStore implements Store {
  checks = new Map<string, { result: CheckResult; expiresAtMs: number }>();
  usage = new Map<string, number>();
  spend = new Map<string, { spent: number; reserved: number }>();

  async getCheck(key: string, nowMs: number) {
    const row = this.checks.get(key);
    return row && row.expiresAtMs > nowMs ? row.result : null;
  }

  async putCheck(key: string, _kind: string, result: CheckResult, expiresAtMs: number) {
    this.checks.set(key, { result, expiresAtMs });
  }

  async takeSearch(device: string, day: string, limit: number) {
    const key = `${device}|${day}`;
    const count = this.usage.get(key) ?? 0;
    if (count >= limit) return false;
    this.usage.set(key, count + 1);
    return true;
  }

  async giveBackSearch(device: string, day: string) {
    const key = `${device}|${day}`;
    this.usage.set(key, Math.max(0, (this.usage.get(key) ?? 0) - 1));
  }

  async reserve(day: string, amount: number, cap: number) {
    const row = this.spend.get(day) ?? { spent: 0, reserved: 0 };
    if (row.spent + row.reserved + amount > cap + 1e-9) return false;
    this.spend.set(day, { ...row, reserved: row.reserved + amount });
    return true;
  }

  async settle(day: string, reserved: number, spent: number) {
    const row = this.spend.get(day) ?? { spent: 0, reserved: 0 };
    this.spend.set(day, { spent: row.spent + spent, reserved: Math.max(0, row.reserved - reserved) });
  }

  async sweep(oldestDay: string, nowMs: number) {
    for (const key of [...this.usage.keys()]) if (key.split("|")[1] < oldestDay) this.usage.delete(key);
    for (const [key, row] of [...this.checks]) if (row.expiresAtMs <= nowMs) this.checks.delete(key);
  }
}
