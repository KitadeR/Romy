import { describe, expect, it } from "vitest";
import { cacheKey, japanDay, runCheck, type Deps } from "../src/check";
import type { SearchAI } from "../src/perplexity";
import type { CheckRequest } from "../src/types";
import { MemoryStore } from "./memoryStore";

const official = "https://hotel-kyoto.example.jp/faq";
const request: CheckRequest = {
  kind: "luggage_before_checkin",
  place: { id: "I123", name: "ホテル京都駅前", address: "京都府京都市下京区東塩小路町1" },
};
const yesText = JSON.stringify({
  found_name: "ホテル京都駅前", found_address: "京都府京都市下京区東塩小路町1", applies_to_this_hotel: "yes",
  front_desk: "yes", conditions: ["当日の朝7:00から"], conflicting: false,
  evidence: [{ url: official, official: true }],
});

function deps(search: SearchAI, store = new MemoryStore(), now = new Date("2026-10-29T03:00:00Z")) {
  let calls = 0;
  const counted: SearchAI = async (...args) => { calls += 1; return search(...args); };
  const value: Deps = { store, search: counted, limits: { deviceDaily: 15, globalUSD: 0.5, reserveUSD: 0.02 }, now: () => now };
  return { value, store, calls: () => calls };
}

describe("runCheck", () => {
  it("searches once, shares the result, and does not count a shared result", async () => {
    const d = deps(async () => ({ text: "```json\n" + yesText + "\n```", urls: [official], costUSD: 0.009 }));
    const first = await runCheck(request, "deviceAAAA", d.value);
    expect(first).toMatchObject({ status: "official", cached: false, checkedAt: "2026-10-29T03:00:00.000Z" });
    const second = await runCheck(request, "deviceBBBB", d.value);
    expect(second).toMatchObject({ status: "official", cached: true, checkedAt: "2026-10-29T03:00:00.000Z" });
    expect(d.calls()).toBe(1);
    expect(d.store.usage.get("deviceBBBB|2026-10-29")).toBeUndefined();
    expect(d.store.spend.get("2026-10-29")).toEqual({ spent: 0.009, reserved: 0 });
  });

  it("keeps ✓ for 30 days and ？ for 3", async () => {
    const d = deps(async () => ({ text: yesText, urls: [official] }));
    await runCheck(request, "deviceAAAA", d.value);
    expect(d.store.checks.get(cacheKey(request))!.expiresAtMs - Date.parse("2026-10-29T03:00:00Z")).toBe(30 * 86_400_000);
    const unknownText = JSON.stringify({ found_name: "ホテル京都駅前", applies_to_this_hotel: "unknown", front_desk: "unknown", conditions: [], conflicting: false, evidence: [] });
    const other = { ...request, place: { ...request.place, id: "I999" } };
    const e = deps(async () => ({ text: unknownText, urls: [] }));
    await runCheck(other, "deviceAAAA", e.value);
    expect(e.store.checks.get(cacheKey(other))!.expiresAtMs - Date.parse("2026-10-29T03:00:00Z")).toBe(3 * 86_400_000);
  });

  it("stops at 15 searches a device a day, as ？ with a reason", async () => {
    const store = new MemoryStore();
    store.usage.set("deviceAAAA|2026-10-29", 15);
    const d = deps(async () => ({ text: yesText, urls: [official] }), store);
    expect(await runCheck(request, "deviceAAAA", d.value)).toMatchObject({ status: "unknown", reason: "limit", cached: false });
    expect(d.calls()).toBe(0);
  });

  it("stops at $0.5 a day for everyone and gives the device its search back", async () => {
    const store = new MemoryStore();
    store.spend.set("2026-10-29", { spent: 0.49, reserved: 0 });
    const d = deps(async () => ({ text: yesText, urls: [official] }), store);
    expect(await runCheck(request, "deviceAAAA", d.value)).toMatchObject({ reason: "limit" });
    expect(store.usage.get("deviceAAAA|2026-10-29")).toBe(0);
    expect(d.calls()).toBe(0);
  });

  it("does not cache a failed search and still lets go of the held money", async () => {
    const d = deps(async () => { throw new Error("timeout"); });
    expect(await runCheck(request, "deviceAAAA", d.value)).toMatchObject({ status: "unknown", reason: "error" });
    expect(d.store.checks.size).toBe(0);
    expect(d.store.spend.get("2026-10-29")).toEqual({ spent: 0.02, reserved: 0 });
  });

  it("does not cache an answer without JSON", async () => {
    const d = deps(async () => ({ text: "分かりませんでした。", urls: [], costUSD: 0.004 }));
    expect(await runCheck(request, "deviceAAAA", d.value)).toMatchObject({ reason: "error" });
    expect(d.store.checks.size).toBe(0);
  });

  it("deletes counts older than 7 days", async () => {
    const store = new MemoryStore();
    store.usage.set("deviceOLD0|2026-10-21", 3);
    store.usage.set("deviceNEW0|2026-10-22", 3);
    const d = deps(async () => ({ text: yesText, urls: [official] }), store);
    await runCheck(request, "deviceAAAA", d.value);
    expect([...store.usage.keys()].sort()).toEqual(["deviceAAAA|2026-10-29", "deviceNEW0|2026-10-22"]);
  });
});

describe("cacheKey and japanDay", () => {
  it("uses the place ID, or the name and address written the same way", () => {
    expect(cacheKey(request)).toBe("luggage_before_checkin:id:I123");
    const a = cacheKey({ ...request, place: { name: "ホテル 京都駅前", address: "京都市下京区" } });
    const b = cacheKey({ ...request, place: { name: "ホテル京都駅前", address: "京都市 下京区" } });
    expect(a).toBe(b);
  });

  it("changes the day at midnight in Japan", () => {
    expect(japanDay(new Date("2026-10-28T14:59:59Z"))).toBe("2026-10-28");
    expect(japanDay(new Date("2026-10-28T15:00:00Z"))).toBe("2026-10-29");
  });
});
