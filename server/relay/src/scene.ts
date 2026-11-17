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
}
type SceneRequest = { session: string } & (
  { operation: "interpret"; text: string } |
  { operation: "hours"; name: string; address: string; date: string; timeZone: string }
);
export interface SceneDeps extends Omit<Deps, "takeSession"> {
  interpret: SearchAI;
  takeSession: (session: string, operation: "interpret" | "hours") => Promise<boolean>;
}
export interface SceneReply {
  preferences?: Preferences;
  hours?: Hours;
  reason?: "limit" | "error";
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
  const now = deps.now();
  const day = japanDay(now);
  // 営業時間は当日・店舗・タイムゾーン単位。希望文の解釈は共有保存しない。
  const key = request.operation === "hours"
    ? "hours:" + normalize(request.name + "|" + request.address) + "|" + request.date + "|" + request.timeZone : null;
  if (key) {
    const cached = await deps.store.getCheck(key, now.getTime());
    if (cached) return { hours: (cached as unknown as { hours: Hours }).hours };
  }
  const search = request.operation === "hours";
  if (search && !await deps.store.takeSearch(device, day, deps.limits.deviceDaily)) return { reason: "limit" };
  if (!await deps.store.reserve(day, deps.limits.reserveUSD, deps.limits.globalUSD)) {
    if (search) await deps.store.giveBackSearch(device, day);
    return { reason: "limit" };
  }
  let spent = 0;
  try {
    if (!await deps.takeSession(request.session, request.operation)) {
      if (search) await deps.store.giveBackSearch(device, day);
      return { reason: "limit" };
    }
    spent = deps.limits.reserveUSD;
    const answer = request.operation === "interpret"
      ? await deps.interpret(intakeInstructions, request.text, intakeSchema)
      : await deps.search(hoursInstructions, JSON.stringify({
          name: request.name, address: request.address, date: request.date, timeZone: request.timeZone,
        }), hoursSchema, { query: `${request.name} ${request.address} 営業時間`, mention: request.name });
    spent = answer.costUSD ?? deps.limits.reserveUSD;
    const json = jsonIn(answer.text);
    if (!json) return { reason: "error" };
    if (request.operation === "interpret") {
      const preferences = parsePreferences(json);
      return preferences ? { preferences } : { reason: "error" };
    }
    const hours = decideHours(request, json, answer.urls, now);
    if (key) {
      // 同じ日の店舗情報だけを短時間共有する。臨時休業・日付またぎを別日の結果で埋めない。
      await deps.store.putCheck(key, "hours", {
        status: hours.status, conditions: [], locker: "unknown", sources: hours.sources,
        checkedAt: hours.checkedAt, hours,
      }, now.getTime() + (hours.status === "official" ? 3_600_000 : 300_000));
    }
    return { hours };
  } catch (error) {
    // HTTP状態などの失敗種別だけを残す。希望文・店名・住所・応答本文はログに出さない。
    const kind = error instanceof Error && /^perplexity \d{3}$/.test(error.message)
      ? error.message : error instanceof Error ? error.name : "unknown";
    console.log(JSON.stringify({ event: "scene_failed", operation: request.operation, error: kind }));
    return { reason: "error" };
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
  body: Record<string, unknown>, searchedUrls: string[], now: Date): Hours {
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
  // 同じ支店・対象日の公式情報と照合できた場合だけ、時刻の判定に使う。
  if (normalize(String(body.name ?? "")) !== normalize(request.name)
      || normalize(String(body.address ?? "")) !== normalize(request.address)
      || body.date !== request.date || body.conflicting !== false || !sources.length
      || typeof body.closed !== "boolean" || !Array.isArray(body.windows)) return result;
  for (const value of body.windows) {
    if (!value || typeof value !== "object") return result;
    const { start, end, lastOrder } = value as Record<string, unknown>;
    if (!Number.isInteger(start) || !Number.isInteger(end) || Number(start) < 0
        || Number(end) > 2880 || Number(start) >= Number(end)) return result;
    if (lastOrder != null && (!Number.isInteger(lastOrder) || Number(lastOrder) < Number(start)
        || Number(lastOrder) > Number(end))) return result;
    result.windows.push({ start: Number(start), end: Number(end),
      lastOrder: lastOrder == null ? undefined : Number(lastOrder) });
  }
  if (body.closed ? result.windows.length !== 0 : result.windows.length === 0) return { ...result, windows: [] };
  return { ...result, status: "official", closed: body.closed };
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
const hoursInstructions = [
  "指定店舗の対象日の営業時間を公式ページから確かめる。別支店の案内、通常時間だけで祝日・臨時休業を判断しない。",
  "JSONのname/address/dateは照合できた店舗と対象日。確認できなければ空文字にし、conflicting=true。",
  "windowsは対象日の0時からの営業区間（分）。翌日2時は1560。前日から続く営業も対象日の0時をstart=0とする。",
  "ラストオーダーが分かればlastOrder（分）、不明はnull。closedは対象日の休業が公式に分かるときだけtrue。",
  "情報がない場合はwindows=[]、closed=false。出典が食い違う場合はconflicting=true。",
  "sourcesには実際に検索・閲覧した公式ページのurl/title/officialを入れる。空席・当日の受付を保証しない。",
].join("\n");
const hoursSchema = { type: "object", properties: {
  name: { type: "string" }, address: { type: "string" }, date: { type: "string" },
  closed: { type: "boolean" }, conflicting: { type: "boolean" },
  windows: { type: "array", items: { type: "object", properties: {
    start: { type: "integer" }, end: { type: "integer" }, lastOrder: nullableNumber,
  }, required: ["start", "end", "lastOrder"] } },
  sources: { type: "array", items: { type: "object", properties: {
    url: { type: "string" }, title: { type: "string" }, official: { type: "boolean" },
  }, required: ["url", "title", "official"] } },
}, required: ["name", "address", "date", "closed", "conflicting", "windows", "sources"] };
