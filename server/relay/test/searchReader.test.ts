import { describe, expect, it } from "vitest";
import { isNeverOfficial } from "../src/official";
import { answerText, pagesAbout, READER_MODEL, SEARCH_COST_USD, searchAndRead, type Reader } from "../src/searchReader";
import { decideLuggage } from "../src/verdict";

const pages = {
  results: [
    { title: "ご滞在時のサービス｜ホテル京都駅前【公式】", url: "https://hotel-kyoto.example.jp/service", snippet: "チェックイン前でもお荷物をお預かりします。" },
    { title: "ホテル京都駅前 - 楽天トラベル", url: "https://travel.rakuten.co.jp/HOTEL/1/1.html", snippet: "荷物預かりあり" },
  ],
};

function fakeSearch(body: unknown, status = 200) {
  const sent: { url: string; body: Record<string, unknown> }[] = [];
  const send = (async (url: string, init: RequestInit) => {
    sent.push({ url, body: JSON.parse(String(init.body)) });
    return new Response(JSON.stringify(body), { status });
  }) as unknown as typeof fetch;
  return { send, sent };
}

function fakeReader(reply: unknown) {
  const calls: { model: string; input: Record<string, unknown> }[] = [];
  const reader: Reader = { run: async (model, input) => { calls.push({ model, input }); return reply; } };
  return { reader, calls };
}

describe("searchAndRead", () => {
  it("searches with the query, reads only the excerpts, and returns the searched pages", async () => {
    const search = fakeSearch(pages);
    const read = fakeReader({ choices: [{ message: { content: "{\"front_desk\":\"yes\"}" } }] });
    const answer = await searchAndRead("key", read.reader, search.send)("指示", "宿の名前：ホテル京都駅前", { type: "object" },
      { query: "ホテル京都駅前 チェックイン前 荷物 預かり", mention: "ホテル京都駅前" });
    expect(search.sent[0].url).toBe("https://api.perplexity.ai/search");
    expect(search.sent[0].body).toMatchObject({ query: "ホテル京都駅前 チェックイン前 荷物 預かり", country: "JP", max_results: 5 });
    expect(read.calls[0].model).toBe(READER_MODEL);
    expect(read.calls[0].input.chat_template_kwargs).toEqual({ enable_thinking: false });
    const user = (read.calls[0].input.messages as { content: string }[])[1].content;
    expect(user).toContain("チェックイン前でもお荷物をお預かりします。");
    expect(answer).toEqual({
      text: "{\"front_desk\":\"yes\"}",
      urls: ["https://hotel-kyoto.example.jp/service", "https://travel.rakuten.co.jp/HOTEL/1/1.html"],
      pages: pages.results,
      costUSD: SEARCH_COST_USD,
      diagnostic: { code: "read", foundPages: 2, matchedPages: 2 },
    });
  });

  it("does not call the reader when the search finds nothing", async () => {
    const read = fakeReader({});
    const answer = await searchAndRead("key", read.reader, fakeSearch({ results: [] }).send)("指示", "入力", {});
    expect(read.calls).toHaveLength(0);
    expect(answer.text).toBe("");
    expect(answer.diagnostic).toEqual({ code: "search_empty", foundPages: 0, matchedPages: 0 });
  });

  it("fails like the Agent API did when the search is refused, so the check stays ？", async () => {
    await expect(searchAndRead("key", fakeReader({}).reader, fakeSearch({}, 403).send)("指示", "入力", {}))
      .rejects.toThrow("perplexity 403");
  });

  it("distinguishes reader failures from search failures without leaking provider errors", async () => {
    const reader: Reader = { run: async () => { throw new Error("secret response body"); } };
    await expect(searchAndRead("key", reader, fakeSearch(pages).send)("指示", "入力", {}))
      .rejects.toMatchObject({ code: "reader_failed", message: "reader_failed" });
    const answer = await searchAndRead("key", fakeReader({}).reader, fakeSearch(pages).send)("指示", "入力", {});
    expect(answer.diagnostic?.code).toBe("reader_empty");
  });

  it("reads both reply shapes of Workers AI", () => {
    expect(answerText({ response: "{}" })).toBe("{}");
    expect(answerText({ response: { a: 1 } })).toBe("{\"a\":1}");
    expect(answerText({ choices: [{ message: { content: "{\"b\":2}" } }] })).toBe("{\"b\":2}");
    expect(answerText({ choices: [{ message: { content: "" } }] })).toBe("");
  });
});

describe("pagesAbout", () => {
  it("drops a sister hotel's FAQ and chain-wide pages that do not name the place", () => {
    const pages = [
      { url: "https://fav-hotels.com/hotels/lux/hidatakayama/faq/", title: "【公式】FAV LUX 飛騨高山｜よくいただく質問", snippet: "館内の無料手荷物ロッカー" },
      { url: "https://fav-hotels.com/faq-takayama/?hotel=takayama", title: "FAQ - 【公式】fav | FAV LUX", snippet: "お荷物預かりは行っておりません。" },
      { url: "https://www.toyoko-inn.com/faq/", title: "よくあるご質問 東横INN", snippet: "当日の朝からお荷物のお預けが可能" },
    ];
    expect(pagesAbout(pages, "FAV LUX 飛騨高山").map((page) => page.url)).toEqual(["https://fav-hotels.com/hotels/lux/hidatakayama/faq/"]);
    expect(pagesAbout(pages, "東横INN京都五条烏丸")).toEqual([]);
  });

  it("does not read at all when no excerpt names the place", async () => {
    const read = fakeReader({});
    const answer = await searchAndRead("key", read.reader, fakeSearch(pages).send)("指示", "入力", {}, { mention: "別のホテル" });
    expect(read.calls).toHaveLength(0);
    expect(answer.urls).toEqual([]);
    expect(answer.diagnostic).toEqual({ code: "place_not_matched", foundPages: 2, matchedPages: 0 });
  });
});

describe("isNeverOfficial", () => {
  it("takes official away from booking and travel sites, also on subdomains", () => {
    expect(isNeverOfficial("https://travel.rakuten.co.jp/HOTEL/4979/4979.html")).toBe(true);
    expect(isNeverOfficial("https://yado.knt.co.jp/st/S260006/")).toBe(true);
    expect(isNeverOfficial("https://www.asiayo.com/ja-jp/view/")).toBe(true);
    expect(isNeverOfficial("https://www.hotelkeihan.co.jp/kyoto/facilities/")).toBe(false);
    expect(isNeverOfficial("not a url")).toBe(true);
  });

  it("keeps a ✓ from resting on a booking site the reader called official", () => {
    const place = { name: "ホテル京都駅前", address: "京都府京都市下京区" };
    const answer = {
      found_name: "ホテル京都駅前", applies_to_this_hotel: "yes", front_desk: "yes", conflicting: false,
      conditions: [], evidence: [{ url: "https://travel.rakuten.co.jp/HOTEL/1/1.html", official: true }],
    };
    const decided = decideLuggage(place, answer, ["https://travel.rakuten.co.jp/HOTEL/1/1.html"]);
    expect(decided.status).toBe("introduced");
    expect(decided.sources[0].official).toBe(false);
  });
});


it("営業時間だけ抜粋に候補idを埋め込み、判定には元の抜粋を使う", async () => {
  const page = { url: "https://cafe.example.jp/shop", title: "駅前喫茶", snippet: "駅前喫茶 営業時間7:00〜21:00 LO20:30" };
  const read = fakeReader({ response: "{}" });
  const answer = await searchAndRead("key", read.reader, fakeSearch({ results: [page] }).send)("指示", "対象店舗", {},
    { mention: "駅前喫茶", hoursEvidence: true });
  const user = (read.calls[0].input.messages as { content: string }[])[1].content;
  expect(user).toContain("駅前喫茶 営業時間[p1-w1]7:00〜21:00 LO20:30");
  expect(user).not.toContain("p1-lo1");
  expect(answer.pages).toEqual([page]);
});
