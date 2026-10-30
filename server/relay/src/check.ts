import { KINDS } from "./kinds";
import { jsonIn, type SearchAI } from "./perplexity";
import type { Store } from "./store";
import type { CheckRequest, CheckResponse, CheckResult } from "./types";
import { decideLuggage, normalize, type LuggageAnswer } from "./verdict";

export interface Limits {
  /// Searches one device may start a day (Notion 04「2026-10-28｜費用の上限」②).
  deviceDaily: number;
  /// Dollars for the whole service a day (③).
  globalUSD: number;
  /// The worst case of one search, held before it starts so calls at the same time cannot pass the cap.
  reserveUSD: number;
}

export interface Deps {
  store: Store;
  search: SearchAI;
  limits: Limits;
  now: () => Date;
}

const DAY_MS = 86_400_000;
/// Usage rows are kept this many days (Notion 04「2026-10-29｜各社のデータの扱い」③).
const KEEP_USAGE_DAYS = 7;

/// One fact check: a shared result when there is one, otherwise a search within the caps.
/// Never an error to the app: a reached cap or a failed search comes back as ？ with a reason, and is not cached.
export async function runCheck(request: CheckRequest, device: string, deps: Deps): Promise<CheckResponse> {
  const now = deps.now();
  const nowMs = now.getTime();
  const key = cacheKey(request);
  const shared = await deps.store.getCheck(key, nowMs);
  if (shared) return { ...shared, cached: true };

  const day = japanDay(now);
  const nothing = (reason: "limit" | "error"): CheckResponse => ({
    status: "unknown", conditions: [], sources: [], locker: "unknown", checkedAt: now.toISOString(), cached: false, reason,
  });
  if (!(await deps.store.takeSearch(device, day, deps.limits.deviceDaily))) return nothing("limit");
  if (!(await deps.store.reserve(day, deps.limits.reserveUSD, deps.limits.globalUSD))) {
    await deps.store.giveBackSearch(device, day);
    return nothing("limit");
  }

  const spec = KINDS[request.kind];
  let spent = deps.limits.reserveUSD;
  try {
    const answer = await deps.search(spec.instructions, spec.input(request.place), spec.schema);
    spent = answer.costUSD ?? deps.limits.reserveUSD;
    const json = jsonIn(answer.text);
    if (!json) {
      console.log(JSON.stringify({ event: "check_failed", error: "no json in the answer" }));
      return nothing("error");
    }
    const decided = decideLuggage(request.place, json as LuggageAnswer, answer.urls);
    const result: CheckResult = { ...decided, checkedAt: now.toISOString() };
    await deps.store.putCheck(key, request.kind, result, nowMs + spec.ttlMs[result.status]);
    return { ...result, cached: false };
  } catch (error) {
    // The kind of failure only (an HTTP status, a D1 message), never the place (Notion 04「各社のデータの扱い」④).
    console.log(JSON.stringify({ event: "check_failed", error: String(error).slice(0, 120) }));
    return nothing("error");
  } finally {
    await deps.store.settle(day, deps.limits.reserveUSD, spent);
    await deps.store.sweep(japanDay(new Date(nowMs - KEEP_USAGE_DAYS * DAY_MS)), nowMs);
  }
}

/// The same place and question give the same key: the MapKit place ID when there is one, otherwise name + address.
export function cacheKey(request: CheckRequest): string {
  const { id, name, address } = request.place;
  const place = id ? `id:${id}` : `na:${normalize(name)}|${normalize(address ?? "")}`;
  return `${request.kind}:${place}`;
}

/// Days change at midnight in Japan (Notion 04「2026-10-28｜費用の上限」数え方).
export function japanDay(date: Date): string {
  return new Date(date.getTime() + 9 * 3_600_000).toISOString().slice(0, 10);
}
