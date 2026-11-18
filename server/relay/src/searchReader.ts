import { withHoursCandidates } from "./hoursEvidence";
import type { SearchAI } from "./perplexity";
import { normalize } from "./verdict";

/// Perplexity Search API: one paid request returns pages and their excerpts, without an AI answer.
/// The Agent API (search + answer) needs paid credits that this project does not buy (2026-11-17 check),
/// so the excerpts are read by a Workers AI model instead.
const searchEndpoint = "https://api.perplexity.ai/search";
/// $5 per 1,000 requests (Perplexity pricing, checked 2026-11-17). Workers AI stays within its free daily Neurons.
export const SEARCH_COST_USD = 0.005;
/// Gemma 4 marked official pages correctly where Qwen3 also marked booking sites official (2026-11-17 comparison).
export const READER_MODEL = "@cf/google/gemma-4-26b-a4b-it";

/// The Workers AI binding, narrowed to the one call this file makes.
export interface Reader {
  run(model: string, input: Record<string, unknown>): Promise<unknown>;
}

export interface Page {
  url: string;
  title: string;
  snippet: string;
}

/// Searches with the query, then has the reader answer only from the returned excerpts.
/// `urls` are the pages the search really returned, so the verdict can drop any page the reader invents.
/// No location is sent: only the place's name and address in the query, and the country for Japanese pages
/// (Notion 04「2026-10-29｜各社のデータの扱い」①).
export function searchAndRead(key: string, reader: Reader, send: typeof fetch = fetch): SearchAI {
  return async (instructions, input, schema, options = {}) => {
    let found: Page[];
    try { found = await search(send, key, options.query ?? input); }
    catch (error) { throw new SearchPipelineError("search_failed", error); }
    const pages = options.mention ? pagesAbout(found, options.mention) : found;
    const counts = { foundPages: found.length, matchedPages: pages.length };
    if (pages.length === 0) return { text: "", urls: [], pages: [], costUSD: SEARCH_COST_USD,
      diagnostic: { ...counts, code: found.length ? "place_not_matched" : "search_empty" } };
    let text: string;
    try { text = await readExcerpts(reader, instructions, options.hoursEvidence ? withHoursCandidates(input, pages) : input, schema, pages); }
    catch { throw new SearchPipelineError("reader_failed"); }
    return { text, urls: pages.map((page) => page.url), pages, costUSD: SEARCH_COST_USD,
      diagnostic: { ...counts, code: text.trim() ? "read" : "reader_empty" } };
  };
}

export class SearchPipelineError extends Error {
  constructor(readonly code: "search_failed" | "reader_failed", cause?: unknown) {
    super(cause instanceof Error && /^perplexity \d{3}$/.test(cause.message) ? cause.message : code);
  }
}

/// Only the pages whose title or excerpt names the place. A sister hotel's FAQ or a chain-wide page otherwise
/// reads as a contradiction or as this hotel's rule (FAV LUX 飛騨高山 and FAV TAKAYAMA, 2026-11-17 evaluation).
export function pagesAbout(pages: Page[], name: string): Page[] {
  const wanted = normalize(name);
  if (!wanted) return [];
  return pages.filter((page) => normalize(page.title + page.snippet).includes(wanted));
}

/// Has the reader answer from the excerpts only. Separate from the search so saved results can be read again
/// for evaluation without paying for the search (server/relay/eval).
export async function readExcerpts(reader: Reader, instructions: string, input: string,
  schema: Record<string, unknown>, pages: Page[]): Promise<string> {
  const excerpts = pages.map((page, index) => `[${index + 1}] ${page.title}\nURL: ${page.url}\n${page.snippet}`).join("\n\n");
  const output = await reader.run(READER_MODEL, {
    messages: [
      { role: "system", content: instructions + "\n" + readingRules },
      { role: "user", content: input + "\n\n検索結果:\n" + excerpts },
    ],
    response_format: { type: "json_schema", json_schema: schema },
    max_tokens: 1200,
    temperature: 0,
    // 考える過程を英語で長く書くと出力の上限で答えが切れるため、答えだけを書かせる（2026-11-17の比較）。
    chat_template_kwargs: { enable_thinking: false },
  });
  return answerText(output);
}

/// Added to every kind's instructions: the reader sees excerpts, not whole pages.
const readingRules = [
  "下の検索結果の抜粋だけを根拠にし、それ以外の知識で補わない。",
  "名前の違う別の宿・別の店舗・別の支店のページは根拠にしない。",
  "evidence や sources には、根拠にした検索結果のURLだけをそのまま入れる。",
  "予約サイト・旅行会社・口コミ・観光案内のページは公式ではない（official は false）。",
].join("\n");

async function search(send: typeof fetch, key: string, query: string): Promise<Page[]> {
  const response = await send(searchEndpoint, {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ query, max_results: 5, max_tokens_per_page: 512, country: "JP" }),
    signal: AbortSignal.timeout(30_000),
  });
  if (!response.ok) throw new Error(`perplexity ${response.status}`);
  const body = (await response.json()) as { results?: unknown };
  if (!Array.isArray(body.results)) return [];
  return body.results.flatMap((value) => {
    const item = (value ?? {}) as Record<string, unknown>;
    if (typeof item.url !== "string" || typeof item.snippet !== "string") return [];
    return [{ url: item.url, title: typeof item.title === "string" ? item.title : "", snippet: item.snippet }];
  });
}

/// The reader's reply text. Workers AI returns either `{response}` or the chat-completions shape.
export function answerText(output: unknown): string {
  const object = (output ?? {}) as Record<string, unknown>;
  if (typeof object.response === "string") return object.response;
  if (object.response && typeof object.response === "object") return JSON.stringify(object.response);
  const choices = Array.isArray(object.choices) ? (object.choices as Record<string, unknown>[]) : [];
  const message = (choices[0]?.message ?? {}) as Record<string, unknown>;
  return typeof message.content === "string" ? message.content : "";
}

