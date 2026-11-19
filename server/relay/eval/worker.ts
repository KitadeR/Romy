import { hoursReaderInput } from "../src/hoursEvidence";
import { decideHours, hoursInstructions, hoursSchema, parseScene } from "../src/scene";
import { KINDS } from "../src/kinds";
import { jsonIn } from "../src/perplexity";
import { pagesAbout, readExcerpts, type Page, type Reader } from "../src/searchReader";
import { decideLuggage } from "../src/verdict";
import type { PlaceInput } from "../src/types";

/// POST {place, pages} → 本番と同じ指示文・読み取り・判定ルールを通した結果。検索はしない（費用なし）。
export default {
  async fetch(request: Request, env: { AI: Reader }): Promise<Response> {
    const body = (await request.json()) as { place: PlaceInput; pages: Page[]; request?: unknown };
    if (new URL(request.url).pathname === "/hours") {
      const input = parseScene(body.request);
      if (!input || input.operation !== "hours" || !Array.isArray(body.pages)) return new Response("Bad request", { status: 400 });
      const pages = pagesAbout(body.pages, input.name);
      const counts = { foundPages: body.pages.length, matchedPages: pages.length };
      if (!pages.length) return Response.json({ diagnostic: {
        code: body.pages.length ? "place_not_matched" : "search_empty", ...counts,
      } });
      try {
        const read = hoursReaderInput(JSON.stringify({
          name: input.name, address: input.address, date: input.date, timeZone: input.timeZone,
        }), pages);
        const text = await readExcerpts(env.AI, hoursInstructions, read.input, hoursSchema, read.pages);
        const answer = jsonIn(text);
        if (!answer) return Response.json({ diagnostic: { code: text.trim() ? "reader_invalid_json" : "reader_empty", ...counts } });
        const hours = decideHours(input, answer, pages.map(page => page.url), new Date(), pages);
        return Response.json({ answer, hours, diagnostic: { code: hours.diagnostic, ...counts } });
      } catch { return Response.json({ diagnostic: { code: "reader_failed", ...counts } }); }
    }
    const { place } = body;
    // 本番の searchAndRead と同じく、宿名を含まない抜粋は読ませない。
    const pages = pagesAbout(body.pages, place.name);
    if (pages.length === 0) return Response.json({ answer: null, verdict: { status: "unknown", locker: "unknown" } });
    const spec = KINDS.luggage_before_checkin;
    const text = await readExcerpts(env.AI, spec.instructions, spec.input(place), spec.schema, pages);
    const answer = jsonIn(text);
    const verdict = answer ? decideLuggage(place, answer, pages.map((page) => page.url)) : null;
    return Response.json({ answer, verdict });
  },
};
