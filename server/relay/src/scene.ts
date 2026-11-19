import { evidenceClosure, evidenceWindow, hoursCandidates } from "./hoursEvidence";
import type { Page } from "./searchReader";
import { SearchPipelineError } from "./searchReader";
import { isNeverOfficial } from "./official";
import { japanDay, type Deps } from "./check";
import { jsonIn, type SearchAI } from "./perplexity";
import { normalize } from "./verdict";
import type { Source } from "./types";

export interface Preferences {
  query?: string;
  category?: string;
  walkMinutes?: number;
  restMinutes?: number;
  totalMinutes?: number;
  unhandled: string[];
}
export interface Hours {
  status: "official" | "unknown";
  date: string;
  timeZone: string;
  windows: { start: number; end: number; lastOrder?: number }[];
  closed: boolean;
  sources: Source[];
  checkedAt: string;
  diagnostic?: HoursDecisionCode;
}
type SceneRequest = { session: string } & (
  { operation: "interpret"; text: string } |
  { operation: "hours"; name: string; address: string; date: string; timeZone: string }
);
export interface SceneDeps extends Omit<Deps, "takeSession"> {
  interpret: SearchAI;
  takeSession: (session: string, operation: "interpret" | "hours") => Promise<boolean>;
}
export type HoursDecisionCode = "confirmed" | "name_mismatch" | "address_mismatch" | "date_mismatch"
  | "conflicting" | "no_official_source" | "invalid_hours" | "no_hours";
export type HoursDiagnosticCode = HoursDecisionCode | "device_limit" | "budget_limit" | "session_limit"
  | "search_empty" | "place_not_matched" | "reader_empty" | "reader_invalid_json"
  | "search_failed" | "reader_failed" | "internal_error" | "cached_unknown" | "api_unconfigured";
export interface HoursDiagnostic {
  code: HoursDiagnosticCode;
  cached?: boolean;
  foundPages?: number;
  matchedPages?: number;
}
export interface SceneReply {
  preferences?: Preferences;
  hours?: Hours;
  reason?: "limit" | "error";
  diagnostic?: HoursDiagnostic;
}

export function parseScene(value: unknown): SceneRequest | null {
  if (!value || typeof value !== "object") return null;
  const body = value as Record<string, unknown>;
  if (typeof body.session !== "string" || !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(body.session)) return null;
  if (body.operation === "interpret" && typeof body.text === "string"
      && body.text.trim().length > 0 && body.text.length <= 300) {
    return { session: body.session, operation: "interpret", text: body.text.trim() };
  }
  if (body.operation !== "hours" || typeof body.name !== "string" || !body.name.trim() || body.name.length > 100
      || typeof body.address !== "string" || body.address.length < 5 || body.address.length > 200
      || typeof body.date !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(body.date)
      || !Number.isFinite(Date.parse(body.date)) || new Date(body.date).toISOString().slice(0, 10) !== body.date
      || typeof body.timeZone !== "string" || body.timeZone.length > 80) return null;
  try { new Intl.DateTimeFormat("en", { timeZone: body.timeZone }); } catch { return null; }
  return { session: body.session, operation: "hours", name: body.name, address: body.address,
    date: body.date, timeZone: body.timeZone };
}

export async function runScene(request: SceneRequest, device: string, deps: SceneDeps): Promise<SceneReply> {
  const started = Date.now();
  const reply = await runSceneRequest(request, device, deps);
  if (request.operation === "hours") {
    // 決まった判定コードと件数だけを残す。入力・URL・ID・AIの応答はログに出さない。
    console.log(JSON.stringify({ event: "hours_result", code: reply.diagnostic?.code ?? "internal_error",
      cached: reply.diagnostic?.cached ?? false, foundPages: reply.diagnostic?.foundPages,
      matchedPages: reply.diagnostic?.matchedPages, ms: Date.now() - started }));
  }
  return reply;
}

async function runSceneRequest(request: SceneRequest, device: string, deps: SceneDeps): Promise<SceneReply> {
  const fail = (reason: "limit" | "error", code: HoursDiagnosticCode): SceneReply =>
    request.operation === "hours" ? { reason, diagnostic: { code } } : { reason };
  const now = deps.now();
  const day = japanDay(now);
  // 営業時間は当日・店舗・タイムゾーン単位。希望文の解釈は共有保存しない。
  const key = request.operation === "hours"
    ? "hours:evidence-v1:" + normalize(request.name + "|" + request.address) + "|" + request.date + "|" + request.timeZone : null;
  if (key) {
    const cached = await deps.store.getCheck(key, now.getTime());
    if (cached?.hours) return { hours: cached.hours, diagnostic: {
      code: cached.hours.diagnostic ?? (cached.hours.status === "official" ? "confirmed" : "cached_unknown"), cached: true,
    } };
  }
  const search = request.operation === "hours";
  if (search && !await deps.store.takeSearch(device, day, deps.limits.deviceDaily)) return fail("limit", "device_limit");
  if (!await deps.store.reserve(day, deps.limits.reserveUSD, deps.limits.globalUSD)) {
    if (search) await deps.store.giveBackSearch(device, day);
    return fail("limit", "budget_limit");
  }
  let spent = 0;
  try {
    if (!await deps.takeSession(request.session, request.operation)) {
      if (search) await deps.store.giveBackSearch(device, day);
      return fail("limit", "session_limit");
    }
    spent = deps.limits.reserveUSD;
    const answer = request.operation === "interpret"
      ? await deps.interpret(intakeInstructions, request.text, intakeSchema)
      : await deps.search(hoursInstructions, JSON.stringify({
          name: request.name, address: request.address, date: request.date, timeZone: request.timeZone,
        }), hoursSchema, { query: `${request.name} ${request.address} 営業時間`, mention: request.name, hoursEvidence: true });
    spent = answer.costUSD ?? deps.limits.reserveUSD;
    const json = jsonIn(answer.text);
    const counts = answer.diagnostic ? {
      foundPages: answer.diagnostic.foundPages, matchedPages: answer.diagnostic.matchedPages,
    } : {};
    if (!json) {
      const code = answer.diagnostic?.code;
      const reply = fail("error", code && code !== "read" ? code : "reader_invalid_json");
      if (reply.diagnostic) Object.assign(reply.diagnostic, counts);
      return reply;
    }
    if (request.operation === "interpret") {
      const preferences = parsePreferences(json);
      return preferences ? { preferences } : { reason: "error" };
    }
    const hours = decideHours(request, json, answer.urls, now, answer.pages ?? []);
    if (key) {
      // 同じ日の店舗情報だけを短時間共有する。臨時休業・日付またぎを別日の結果で埋めない。
      await deps.store.putCheck(key, "hours", {
        status: hours.status, conditions: [], locker: "unknown", sources: hours.sources,
        checkedAt: hours.checkedAt, hours,
      }, now.getTime() + (hours.status === "official" ? 3_600_000 : 300_000));
    }
    return { hours, diagnostic: { code: hours.diagnostic ?? "internal_error", ...counts, cached: false } };
  } catch (error) {
    // HTTP状態などの失敗種別だけを残す。希望文・店名・住所・応答本文はログに出さない。
    const kind = error instanceof Error && /^perplexity \d{3}$/.test(error.message)
      ? error.message : error instanceof Error && ["Error", "TypeError", "TimeoutError", "AbortError"].includes(error.name) ? error.name : "unknown";
    console.log(JSON.stringify({ event: "scene_failed", operation: request.operation, error: kind }));
    return fail("error", error instanceof SearchPipelineError ? error.code : "internal_error");
  } finally {
    await deps.store.settle(day, deps.limits.reserveUSD, spent);
    await deps.store.sweep(japanDay(new Date(now.getTime() - 7 * 86_400_000)), now.getTime());
  }
}

export function parsePreferences(body: Record<string, unknown>): Preferences | null {
  const result: Preferences = { unhandled: [] };
  if (body.query !== null && body.query !== undefined) {
    if (typeof body.query !== "string" || body.query.length > 50 || !body.query.trim()) return null;
    result.query = body.query.trim();
  }
  if (body.category !== null && body.category !== undefined) {
    if (!["cafe", "restaurant", "bakery"].includes(String(body.category))) return null;
    result.category = String(body.category);
  }
  for (const [field, min, max] of [["walkMinutes", 1, 30], ["restMinutes", 5, 240],
    ["totalMinutes", 5, 300]] as const) {
    const value = body[field];
    if (value !== null && value !== undefined) {
      if (!Number.isInteger(value) || Number(value) < min || Number(value) > max) return null;
      result[field] = Number(value);
    }
  }
  if (!Array.isArray(body.unhandled) || body.unhandled.some(value => typeof value !== "string")) return null;
  result.unhandled = body.unhandled.slice(0, 8).map(value => String(value).slice(0, 100));
  return result;
}

export function decideHours(request: { name: string; address: string; date: string; timeZone: string },
  body: Record<string, unknown>, searchedUrls: string[], now: Date, pages: Page[] = []): Hours {
  const sources: Source[] = Array.isArray(body.sources) ? body.sources.flatMap(source => {
    if (!source || typeof source !== "object") return [];
    const item = source as Record<string, unknown>;
    if (item.official !== true || typeof item.url !== "string" || !searchedUrls.includes(item.url)
        || isNeverOfficial(item.url)) return [];
    try { if (!["https:", "http:"].includes(new URL(item.url).protocol)) return []; } catch { return []; }
    return [{ url: item.url, official: true, title: typeof item.title === "string" ? item.title.slice(0, 100) : undefined }];
  }).slice(0, 3) : [];
  const result: Hours = { status: "unknown", date: request.date, timeZone: request.timeZone,
    windows: [], closed: false, sources, checkedAt: now.toISOString() };
  const unknown = (diagnostic: HoursDecisionCode): Hours => ({ ...result, windows: [], diagnostic });
  // 採用の基準は従来どおり。診断コードは最初に満たさなかった条件を示す。
  if (normalize(String(body.name ?? "")) !== normalize(request.name)) return unknown("name_mismatch");
  if (normalize(String(body.address ?? "")) !== normalize(request.address)) return unknown("address_mismatch");
  if (body.date !== request.date) return unknown("date_mismatch");
  if (body.conflicting !== false) return unknown("conflicting");
  if (!sources.length) return unknown("no_official_source");
  if (typeof body.closed !== "boolean" || !Array.isArray(body.windows)) return unknown("invalid_hours");
  if (body.closed && !evidenceClosure(body.closureEvidence, request.name, request.date, sources.map(source => source.url), pages)) {
    return unknown("invalid_hours");
  }
  const candidates = hoursCandidates(pages);
  for (const value of body.windows) {
    const candidate = value && typeof value === "object"
      ? candidates.windows.find(item => item.id === (value as Record<string, unknown>).hoursID) : undefined;
    // 出典と同じく、非公式ページの候補は捨て、確認できた公式の営業区間は残す。
    if (candidate && !sources.some(source => source.url === candidate.url)) continue;
    const window = evidenceWindow(value, request.name, request.address, sources.map(source => source.url), pages);
    if (!window) return unknown("invalid_hours");
    const existing = result.windows.find(value => value.start === window.start && value.end === window.end);
    if (existing) {
      if (existing.lastOrder !== undefined && window.lastOrder !== undefined && existing.lastOrder !== window.lastOrder) return unknown("conflicting");
      existing.lastOrder ??= window.lastOrder;
    } else {
      if (result.windows.some(value => window.start < value.end && window.end > value.start)) return unknown("conflicting");
      result.windows.push(window);
    }
  }
  if (body.closed ? result.windows.length !== 0 : result.windows.length === 0) return unknown(body.closed ? "invalid_hours" : "no_hours");
  return { ...result, status: "official", closed: body.closed, diagnostic: "confirmed" };
}

const intakeInstructions = [
  "旅行中の短い希望から検索条件を抽出し、JSONだけを返す。場所・経路・所要時間の推測はしない。",
  "queryは食べたいものや店の種類の短い日本語、categoryはcafe/restaurant/bakery。不明ならnull。",
  "walkMinutesは最初の店まで歩ける分数、restMinutesはその店で休む分数、totalMinutesは移動込みで使える全体の分数。",
  "『30分休みたい』はrestMinutes=30、『30分しかない』はtotalMinutes=30。明記のない数字はnull。",
  "静かさ・安さなど扱えない希望、範囲外の数字、曖昧な希望はunhandledに原文の該当部分を残す。勝手に補わない。",
].join("\n");
const nullableNumber = { type: ["integer", "null"] };
const intakeSchema = { type: "object", properties: {
  query: { type: ["string", "null"] }, category: { type: ["string", "null"] },
  walkMinutes: nullableNumber, restMinutes: nullableNumber, totalMinutes: nullableNumber,
  unhandled: { type: "array", items: { type: "string" } },
}, required: ["query", "category", "walkMinutes", "restMinutes", "totalMinutes", "unhandled"] };
export const hoursInstructions = [
  "指定店舗の対象日の営業時間を公式ページの検索抜粋だけから確かめる。別支店の案内、通常時間だけで祝日・臨時休業を判断しない。",
  "JSONのname/address/dateは照合できた店舗と対象日。確認できなければ空文字にし、conflicting=true。",
  "windowsでは、指定店舗・対象日に当てはまる公式ページの原文時刻候補のidだけをhoursIDに入れる。非公式ページの候補を選ばない。",
  "ラストオーダーは同じ営業区間の原文からコードが対応付ける。LOの候補や値を出力しない。",
  "時刻候補には計算済みの番号がある。候補以外の時刻・番号を作らない。分数や引用を書き直さない。適切な候補がなければwindows=[]。",
  "同じ営業区間を複数の出典で確認してもwindowsには1回だけ入れる。昼と夜など別の営業区間は別々に入れる。",
  "closedは対象日が休業と分かるときだけtrue。closureEvidenceに、対象日の日付（年か曜日つき）または対象日の曜日の定休日を書いた休業案内の原文quoteと公式urlをコピーする。営業ならclosureEvidence=null。",
  "情報がない場合はwindows=[]、closed=false、closureEvidence=null。出典が食い違う場合はconflicting=true。",
  "sourcesには根拠にした検索結果の公式ページのurl/title/officialを入れる。空席・当日の受付を保証しない。",
].join("\n");
const hoursEvidenceSchema = { type: "object", properties: {
  url: { type: "string" }, quote: { type: "string", maxLength: 800 },
}, required: ["url", "quote"] };
export const hoursSchema = { type: "object", properties: {
  name: { type: "string" }, address: { type: "string" }, date: { type: "string" },
  closed: { type: "boolean" }, conflicting: { type: "boolean" },
  closureEvidence: { ...hoursEvidenceSchema, type: ["object", "null"] },
  windows: { type: "array", items: { type: "object", properties: {
    hoursID: { type: "string" },
  }, required: ["hoursID"] } },
  sources: { type: "array", items: { type: "object", properties: {
    url: { type: "string" }, title: { type: "string" }, official: { type: "boolean" },
  }, required: ["url", "title", "official"] } },
}, required: ["name", "address", "date", "closed", "conflicting", "windows", "closureEvidence", "sources"] };
