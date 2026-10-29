import { describe, expect, it } from "vitest";
import { jsonIn, perplexity, read } from "../src/perplexity";

const reply = {
  output: [
    { type: "search_results", results: [{ url: "https://a.example.jp/faq", title: "FAQ" }] },
    { type: "message", content: [{ type: "output_text", text: "{\"front_desk\":\"yes\"}" }] },
  ],
  usage: { input_tokens: 100, output_tokens: 20, cost: { total_cost: 0.0071 } },
};

describe("perplexity", () => {
  it("reads the text, the searched pages and the cost", () => {
    expect(read(reply)).toEqual({ text: "{\"front_desk\":\"yes\"}", urls: ["https://a.example.jp/faq"], costUSD: 0.0071 });
  });

  it("asks once more without the schema when it is refused, and sends no location but the country", async () => {
    const bodies: Record<string, unknown>[] = [];
    const send = (async (_url: string, init: RequestInit) => {
      bodies.push(JSON.parse(String(init.body)));
      return bodies.length === 1 ? new Response("bad", { status: 400 }) : Response.json(reply);
    }) as typeof fetch;
    const answer = await perplexity("test-key", send)("指示", "宿の名前：A", { type: "object" });
    expect(answer.costUSD).toBe(0.0071);
    expect(bodies[0].response_format).toBeDefined();
    expect(bodies[1].response_format).toBeUndefined();
    expect(bodies[0].tools).toEqual([{ type: "web_search", search_type: "web", user_location: { country: "JP" } }]);
  });

  it("finds JSON inside a fence or after a sentence", () => {
    expect(jsonIn("結果です。\n```json\n{\"a\":1}\n```")).toEqual({ a: 1 });
    expect(jsonIn("なし")).toBeNull();
  });
});
