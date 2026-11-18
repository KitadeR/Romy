import { describe, expect, it, vi } from "vitest";
import { decideHours, parsePreferences, parseScene, runScene, type SceneDeps } from "../src/scene";
import { SearchPipelineError } from "../src/searchReader";
import { MemoryStore } from "./memoryStore";
const session = "781D55EC-250B-4C69-9B03-213BE189C6D6";
const now = new Date("2026-11-17T03:00:00Z");
const url = "https://cafe.example.jp/kobe";
const shop = { operation: "hours" as const, session, name: "神戸カフェ", address: "兵庫県神戸市中央区1-1",
  date: "2026-11-17", timeZone: "Asia/Tokyo" };
const official = { ...shop, conflicting: false, closed: false, windows: [{ start: 600, end: 1200, lastOrder: 1140 }],
  sources: [{ url, title: "神戸店", official: true }] };
function makeDeps(text = JSON.stringify(official)) {
  const store = new MemoryStore();
  let searches = 0, intakes = 0;
  const counts = new Map<string, number>();
  const deps: SceneDeps = {
    store, limits: { deviceDaily: 15, globalUSD: 0.5, reserveUSD: 0.02 }, now: () => now,
    search: async () => { searches++; return { text, urls: [url], costUSD: 0.01 }; },
    interpret: async () => { intakes++; return { text, urls: [], costUSD: 0.001 }; },
    takeSession: async (id, operation) => {
      const key = id + operation, count = counts.get(key) ?? 0;
      if (count >= (operation === "interpret" ? 1 : 3)) return false;
      counts.set(key, count + 1); return true;
    },
  };
  return { deps, store, searches: () => searches, intakes: () => intakes };
}
describe("一言と営業時間の入力境界", () => {
  it("日付・タイムゾーン・セッション・空の一言を検証する", () => {
    expect(parseScene(shop)).not.toBeNull();
    for (const patch of [{ date: "2026-02-30" }, { date: "9999-99-99" }, { timeZone: "invalid" }, { session: "invalid" }]) {
      expect(parseScene({ ...shop, ...patch })).toBeNull();
    }
    expect(parseScene({ operation: "interpret", session, text: " " })).toBeNull();
    expect(parseScene({ operation: "interpret", session, text: "a".repeat(301) })).toBeNull();
  });
  it("休む時間と全体の時間を別々に受け取り、範囲外の値を採用しない", () => {
    expect(parsePreferences({ restMinutes: 30, totalMinutes: 60, walkMinutes: 5, unhandled: ["静かな席"] }))
      .toMatchObject({ restMinutes: 30, totalMinutes: 60, walkMinutes: 5, unhandled: ["静かな席"] });
    expect(parsePreferences({ walkMinutes: 999, unhandled: [] })).toBeNull();
    expect(parsePreferences({ restMinutes: 3.5, unhandled: [] })).toBeNull();
  });
});
describe("公式営業時間の判定", () => {
  it("同じ支店の公式ページと、翌日に続く営業区間・休業日を採用する", () => {
    expect(decideHours(shop, official, [url], now).status).toBe("official");
    expect(decideHours(shop, { ...official, windows: [{ start: 1080, end: 1560, lastOrder: 1500 }] }, [url], now).windows[0].end).toBe(1560);
    expect(decideHours(shop, { ...official, closed: true, windows: [] }, [url], now).closed).toBe(true);
  });
  it("別支店・別日・出典不一致・矛盾・不正時刻は未確認にとどめる", () => {
    for (const patch of [{ name: "大阪店" }, { address: "大阪市1-1" }, { date: "2026-11-18" },
      { conflicting: true }, { windows: [{ start: 1200, end: 600 }] },
      { windows: [{ start: 600, end: 1200, lastOrder: 1300 }] }, { closed: true }]) {
      expect(decideHours(shop, { ...official, ...patch }, [url], now).status).toBe("unknown");
    }
    expect(decideHours(shop, official, [], now).status).toBe("unknown");
  });
});
describe("検索と解釈の上限・保存", () => {
  it("一言は1回だけ解釈し、希望文も結果も共有保存しない", async () => {
    const d = makeDeps(JSON.stringify({ query: "甘いもの", walkMinutes: 5, restMinutes: 30, unhandled: [] }));
    const request = { operation: "interpret" as const, session, text: "甘いもので30分休みたい" };
    expect((await runScene(request, "deviceAAAA", d.deps)).preferences?.restMinutes).toBe(30);
    expect(await runScene(request, "deviceAAAA", d.deps)).toEqual({ reason: "limit" });
    expect(d.intakes()).toBe(1); expect(d.searches()).toBe(0); expect(d.store.checks.size).toBe(0);
    expect(d.store.spend.get("2026-11-17")).toEqual({ spent: 0.001, reserved: 0 });
  });
  it("共有結果には検索回数を使わず、日付違いは再確認する", async () => {
    const d = makeDeps();
    expect((await runScene(shop, "deviceAAAA", d.deps)).hours?.status).toBe("official");
    await runScene(shop, "deviceBBBB", d.deps);
    expect(d.searches()).toBe(1); expect(d.store.usage.has("deviceBBBB|2026-11-17")).toBe(false);
    await runScene({ ...shop, date: "2026-11-18" }, "deviceAAAA", d.deps);
    expect(d.searches()).toBe(2);
  });
  it("3回を超える確認と予算上限ではAIを呼ばず、予約額を解放する", async () => {
    const d = makeDeps();
    for (let i = 0; i < 4; i++) await runScene({ ...shop, name: "店" + i }, "deviceAAAA", d.deps);
    expect(d.searches()).toBe(3); expect(d.store.usage.get("deviceAAAA|2026-11-17")).toBe(3);
    expect(d.store.spend.get("2026-11-17")?.reserved).toBe(0);
    d.store.spend.set("2026-11-17", { spent: 0.49, reserved: 0 });
    expect(await runScene({ ...shop, session: crypto.randomUUID() }, "deviceAAAA", d.deps)).toEqual({ reason: "limit", diagnostic: { code: "budget_limit" } });
    expect(d.searches()).toBe(3);
  });
  it("通信失敗でも予約を解放し、不確かな情報を保存しない", async () => {
    const d = makeDeps(); d.deps.search = async () => { throw new SearchPipelineError("search_failed"); };
    expect(await runScene(shop, "deviceAAAA", d.deps)).toEqual({ reason: "error", diagnostic: { code: "search_failed" } });
    expect(d.store.checks.size).toBe(0);
    expect(d.store.spend.get("2026-11-17")).toEqual({ spent: 0.02, reserved: 0 });
  });
});


describe("営業時間の失敗診断", () => {
  it.each([
    [{ name: "別の店" }, "name_mismatch"], [{ address: "別の住所" }, "address_mismatch"],
    [{ date: "2026-11-18" }, "date_mismatch"], [{ conflicting: true }, "conflicting"],
    [{ sources: [] }, "no_official_source"], [{ windows: [] }, "no_hours"],
    [{ windows: [{ start: 1200, end: 600 }] }, "invalid_hours"],
  ])("未確認の理由を区別する: %s", (patch, code) => {
    const hours = decideHours(shop, { ...official, ...patch }, [url], now);
    expect(hours.status).toBe("unknown");
    expect(hours.diagnostic).toBe(code);
    expect(hours.windows).toEqual([]);
  });

  it("検索未実行の上限を区別する", async () => {
    const daily = makeDeps(); daily.deps.limits.deviceDaily = 0;
    expect((await runScene(shop, "deviceAAAA", daily.deps)).diagnostic?.code).toBe("device_limit");
    const session = makeDeps(); session.deps.takeSession = async () => false;
    expect((await runScene(shop, "deviceAAAA", session.deps)).diagnostic?.code).toBe("session_limit");
    expect(session.searches()).toBe(0);
    expect(session.store.spend.get("2026-11-17")?.reserved).toBe(0);
  });

  it("古いキャッシュには不明、新しいキャッシュには保存時の判定理由を返す", async () => {
    const d = makeDeps(JSON.stringify({ ...official, address: "別の住所" }));
    const first = await runScene(shop, "deviceAAAA", d.deps);
    expect(first.diagnostic?.code).toBe("address_mismatch");
    const second = await runScene(shop, "deviceAAAA", d.deps);
    expect(second.diagnostic).toEqual({ code: "address_mismatch", cached: true });
    for (const row of d.store.checks.values()) delete row.result.hours!.diagnostic;
    expect((await runScene(shop, "deviceAAAA", d.deps)).diagnostic).toEqual({ code: "cached_unknown", cached: true });
    expect(d.searches()).toBe(1);
  });

  it.each(["search_empty", "place_not_matched", "reader_empty", "read"] as const)("読み取り前後の失敗を識別する: %s", async (code) => {
    const d = makeDeps();
    d.deps.search = async () => ({ text: "not json", urls: [], costUSD: 0.005,
      diagnostic: { code, foundPages: 5, matchedPages: 2 } });
    const reply = await runScene(shop, "deviceAAAA", d.deps);
    expect(reply.diagnostic).toEqual({ code: code === "read" ? "reader_invalid_json" : code, foundPages: 5, matchedPages: 2 });
    expect(d.store.checks.size).toBe(0);
  });

  it("ログには固定の理由と件数だけを残し、入力やAI応答の文字列を残さない", async () => {
    const log = vi.spyOn(console, "log").mockImplementation(() => {});
    try {
      const d = makeDeps();
      d.deps.search = async () => { throw Object.assign(new Error("secret-provider-body"), { name: "secret-provider-name" }); };
      await runScene(shop, "private-device", d.deps);
      const messages = log.mock.calls.map(([value]) => String(value)).join("\n");
      for (const value of [shop.name, shop.address, shop.session, "private-device", "secret-provider-body", "secret-provider-name", url]) {
        expect(messages).not.toContain(value);
      }
      const result = log.mock.calls.map(([value]) => JSON.parse(String(value))).find(value => value.event === "hours_result");
      expect(result).toMatchObject({ code: "internal_error", cached: false });
    } finally { log.mockRestore(); }
  });
});
