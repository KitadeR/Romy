/// One search with the search AI: the text it wrote, the pages its search returned, and what it cost.
export interface SearchAnswer {
  text: string;
  urls: string[];
  costUSD?: number;
  diagnostic?: { code: "read" | "search_empty" | "place_not_matched" | "reader_empty"; foundPages: number; matchedPages: number };
}

/// For the Search API + Workers AI reader: `query` is what to search for, and `mention` is the place's name,
/// which an excerpt must contain to be read at all.
export interface SearchOptions {
  query?: string;
  mention?: string;
}

export type SearchAI = (instructions: string, input: string, schema: Record<string, unknown>,
  options?: SearchOptions) => Promise<SearchAnswer>;

const endpoint = "https://api.perplexity.ai/v1/agent";

/// Perplexity's Agent API with Sonar and web search, as in the 2026-10-19 probe (Romy-probe `ProbeClients.swift`).
/// No location is sent (Notion 04「2026-10-29｜各社のデータの扱い」①): only the country, so Japanese pages come first.
/// When the API refuses the JSON schema, it is asked once more without it, as the probe did.
export function perplexity(key: string, send: typeof fetch = fetch,
  options: { intake?: boolean; retrySchema?: boolean } = {}): SearchAI {
  return async (instructions, input, schema) => {
    const body: Record<string, unknown> = {
      model: options.intake ? "openai/gpt-6-luna" : "perplexity/sonar",
      instructions,
      input,
      max_output_tokens: 2000,
      response_format: { type: "json_schema", json_schema: { name: "answer", schema } },
      tools: options.intake ? [] : [{ type: "web_search", search_type: "web", user_location: { country: "JP" } }],
      max_steps: 3,
    };
    let response = await post(send, key, body);
    if (response.status === 400 && options.retrySchema !== false) {
      delete body.response_format;
      response = await post(send, key, body);
    }
    if (!response.ok) throw new Error(`perplexity ${response.status}`);
    return read(await response.json());
  };
}

function post(send: typeof fetch, key: string, body: Record<string, unknown>): Promise<Response> {
  return send(endpoint, {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(60_000),
  });
}

export function read(response: unknown): SearchAnswer {
  const object = (response ?? {}) as Record<string, unknown>;
  const output = Array.isArray(object.output) ? (object.output as Record<string, unknown>[]) : [];
  let text = "";
  const urls: string[] = [];
  for (const item of output) {
    for (const result of Array.isArray(item.results) ? (item.results as Record<string, unknown>[]) : []) {
      if (typeof result.url === "string") urls.push(result.url);
    }
    for (const part of Array.isArray(item.content) ? (item.content as Record<string, unknown>[]) : []) {
      if (typeof part.text === "string") text += part.text;
    }
  }
  return { text, urls, costUSD: totalCost(object.usage) };
}

/// `usage.total_cost`, also when it sits one level deeper.
function totalCost(usage: unknown): number | undefined {
  if (typeof usage !== "object" || usage === null) return undefined;
  for (const [key, value] of Object.entries(usage)) {
    if (key === "total_cost" && typeof value === "number") return value;
    const nested = totalCost(value);
    if (nested !== undefined) return nested;
  }
  return undefined;
}

/// The JSON object in a reply, also when it sits inside a code fence or after a sentence.
export function jsonIn(text: string): Record<string, unknown> | null {
  const open = text.indexOf("{");
  const close = text.lastIndexOf("}");
  if (open < 0 || close <= open) return null;
  try {
    const value = JSON.parse(text.slice(open, close + 1));
    return typeof value === "object" && value !== null ? value : null;
  } catch {
    return null;
  }
}
