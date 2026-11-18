import { expect, it, vi } from "vitest";
import worker, { type Env } from "../src/index";

it("APIキー未設定を診断し、検索やDB操作をしない", async () => {
  const log = vi.spyOn(console, "log").mockImplementation(() => {});
  try {
    const env = { DB: {}, AI: { run: vi.fn() }, DEVICE_DAILY_SEARCHES: "15", GLOBAL_DAILY_USD: "0.5", RESERVE_USD: "0.02" } as unknown as Env;
    const response = await worker.fetch(new Request("https://relay.example.jp/v1/scene", {
      method: "POST", headers: { "X-Romy-Device": "deviceAAAA" },
      body: JSON.stringify({ operation: "hours", session: "781D55EC-250B-4C69-9B03-213BE189C6D6",
        name: "公開店舗", address: "京都市下京区1-1", date: "2026-11-18", timeZone: "Asia/Tokyo" }),
    }), env);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ reason: "error", diagnostic: { code: "api_unconfigured" } });
    expect(env.AI.run).not.toHaveBeenCalled();
    expect(log).toHaveBeenCalledWith(JSON.stringify({ event: "hours_result", code: "api_unconfigured", cached: false }));
  } finally { log.mockRestore(); }
});
