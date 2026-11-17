import { KINDS } from "../src/kinds";
import { jsonIn } from "../src/perplexity";
import { pagesAbout, readExcerpts, type Page, type Reader } from "../src/searchReader";
import { decideLuggage } from "../src/verdict";
import type { PlaceInput } from "../src/types";

/// POST {place, pages} → 本番と同じ指示文・読み取り・判定ルールを通した結果。検索はしない（費用なし）。
export default {
  async fetch(request: Request, env: { AI: Reader }): Promise<Response> {
    const body = (await request.json()) as { place: PlaceInput; pages: Page[] };
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
