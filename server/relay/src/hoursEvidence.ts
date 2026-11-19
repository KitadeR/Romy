import type { Page } from "./searchReader";
import { normalize } from "./verdict";

export interface HoursWindow { start: number; end: number; lastOrder?: number }

// 全角・空白・Markdownの太字記号だけをそろえる。原文の言い換えや、別の時刻への読み替えはしない。
const compact = (value: string) => value.normalize("NFKC").replace(/\*\*/g, "").replace(/\s+/gu, "");

function containsLiteral(context: string, literal: string): boolean {
  const text = compact(context), wanted = compact(literal);
  if (!wanted) return false;
  let from = 0;
  while (from <= text.length - wanted.length) {
    const index = text.indexOf(wanted, from);
    if (index < 0) return false;
    const before = text.slice(0, index), after = text.slice(index + wanted.length);
    // 17:00の中の7:00、午後・翌を外した時刻、末尾のpm・分を落とした時刻には一致させない。
    const croppedStart = /^\d/.test(wanted) && /(?:\d:?|午前|午後|前日|翌日?|am|pm)$/i.test(before);
    const croppedEnd = /[\d時]$/.test(wanted) && /^(?:[\d:]|時|分|半|am|pm)/i.test(after);
    if (!croppedStart && !croppedEnd) return true;
    from = index + 1;
  }
  return false;
}

function citedQuote(value: unknown, name: string, officialURLs: string[], pages: Page[]): string | null {
  if (!value || typeof value !== "object") return null;
  const { url, quote } = value as Record<string, unknown>;
  if (typeof url !== "string" || !officialURLs.includes(url) || typeof quote !== "string"
      || quote.length > 800 || !quote.trim()) return null;
  const page = pages.find(page => page.url === url && containsLiteral(page.snippet, quote));
  if (!page) return null;
  // 複数店舗の一覧では、ページのどこかではなく、引用部分かタイトルに指定店舗の名前が必要。
  if (!normalize(page.title).includes(normalize(name)) && !normalize(quote).includes(normalize(name))) return null;
  return compact(quote);
}

/** 原文の時刻を分に変換する。前日からの営業は「前日」の明記が必要。日付をまたぐ閉店は26:00・翌2:00と書ける。 */
function clock(value: string): number | null {
  const text = compact(value);
  const match = /^(前日|翌日|翌)?(午前|午後|am|pm)?(\d{1,2})(?::(\d{2})|時(?:(\d{1,2})分|(半))?)?(am|pm)?$/i.exec(text);
  if (!match) return null;
  const [, day, prefix, h, colonMinutes, japaneseMinutes, half, suffix] = match;
  let hour = Number(h);
  const minutes = Number(colonMinutes ?? japaneseMinutes ?? (half ? 30 : 0));
  if (minutes > 59 || hour > 47 || (prefix && suffix)) return null;
  const meridiem = (prefix ?? suffix)?.toLowerCase();
  if (meridiem) {
    if (hour < 1 || hour > 12) return null;
    hour = hour % 12 + (["午後", "pm"].includes(meridiem) ? 12 : 0);
  }
  if (day && hour >= 24) return null;
  return hour * 60 + minutes + (day === "前日" ? -1440 : day ? 1440 : 0);
}

function range(text: string): HoursWindow | null {
  if (compact(text) === "24時間営業") return { start: 0, end: 1440 };
  const parts = text.split(/[〜~～\-–—−]/u);
  if (parts.length !== 2) return null;
  const from = clock(parts[0]), to = clock(parts[1]);
  if (from === null || to === null) return null;
  // 「翌」「26時」の明記がない日付またぎは、閉店が早朝（6時まで）の場合だけ認める。10:00〜9:00などは推測しない。
  if (to < from && to > 360) return null;
  const end = to < from ? to + 1440 : to;
  if (from >= 1440 || end > 2880 || end <= 0 || from >= end) return null;
  return { start: Math.max(0, from), end };
}

interface ClockCandidate {
  id: string;
  url: string;
  text: string;
  context: string;
  pageIndex: number;
  offset: number;
}
interface WindowCandidate extends ClockCandidate { start: number; end: number }
interface LastOrderCandidate extends ClockCandidate { minutes: number }

// 候補の位置（offset）はこの表記を基準にする。AIへの埋め込みも同じ表記に対して行う。
const readable = (snippet: string) => snippet.normalize("NFKC").replace(/\*\*/g, "");

/** 候補は検索抜粋の原文から作る。AIが生成した引用や分数は使わない。 */
export function hoursCandidates(pages: Page[]): { windows: WindowCandidate[]; lastOrders: LastOrderCandidate[] } {
  const windows: WindowCandidate[] = [], lastOrders: LastOrderCandidate[] = [];
  const token = String.raw`(?:(?:前日|翌日|翌)\s*)?(?:(?:午前|午後|am|pm)\s*)?\d{1,2}(?::\d{2}|時(?:\d{1,2}分|半)?)(?:\s*(?:am|pm))?`;
  const time = `(?:${token}|\\d{1,2}\\s*(?:am|pm))`;
  for (const [pageIndex, page] of pages.entries()) {
    const text = readable(page.snippet);
    const ranges = new RegExp(`(?<!\\d)(?<!\\d:)(?:${time}\\s*[〜~～\\-–—−]\\s*${time}|24時間営業)(?![\\d:])`, "giu");
    // 「Polo」「LOCATION」など英単語の一部は拾わない。
    const orders = new RegExp(`(?<![A-Za-z])(?:ラストオーダー|L\\.?O\\.?(?![A-Za-z])|Last\\s*Order|Last\\s*Call)\\s*[:：]?\\s*(${time})(?![\\d:])`, "giu");
    const context = (offset: number, length: number) => text.slice(Math.max(0, offset - 100), offset + length + 100);
    let index = 0;
    for (const match of text.matchAll(ranges)) {
      const parsed = range(match[0]);
      if (!parsed) continue;
      windows.push({ id: `p${pageIndex + 1}-w${++index}`, url: page.url, text: match[0],
        context: context(match.index, match[0].length), pageIndex, offset: match.index, ...parsed });
    }
    index = 0;
    for (const match of text.matchAll(orders)) {
      const minutes = clock(match[1]);
      if (minutes === null) continue;
      lastOrders.push({ id: `p${pageIndex + 1}-lo${++index}`, url: page.url, text: match[0],
        context: context(match.index, match[0].length), pageIndex, offset: match.index, minutes });
    }
  }
  return { windows, lastOrders };
}

function adjacentOrder(window: WindowCandidate, order: LastOrderCandidate, windows: WindowCandidate[]): boolean {
  if (order.pageIndex !== window.pageIndex || order.offset < window.offset || order.offset - window.offset > 200) return false;
  if (windows.some(value => value.pageIndex === window.pageIndex && value.offset > window.offset && value.offset < order.offset)) return false;
  return true;
}

/**
 * AIへ渡す入力。候補idを抜粋の該当箇所に埋め込み、候補の前後の文は別に送らない。
 * 前後の文を別に送ると抜粋の3〜5倍に入力が膨らみ、JSONの崩れや待ち時間の増加につながった（2026-11-19の確認）。
 */
export function hoursReaderInput(input: string, pages: Page[]): { input: string; pages: Page[] } {
  const { windows } = hoursCandidates(pages);
  const marked = pages.map((page, pageIndex) => {
    let text = readable(page.snippet);
    for (const window of windows.filter(value => value.pageIndex === pageIndex).sort((a, b) => b.offset - a.offset)) {
      text = text.slice(0, window.offset) + `[${window.id}]` + text.slice(window.offset);
    }
    return { ...page, snippet: text };
  });
  // idと原文の時刻だけの短い一覧も添える。埋め込みだけではAIが候補を見落とし、空のidを返した（2026-11-19の評価）。
  return {
    input: input + "\n\n原文の時刻候補（p1は検索結果[1]。抜粋中の[p1-w1]の位置にある。idだけを選び、値を書き換えない）:\n"
      + JSON.stringify(windows.map(({ id, text }) => ({ id, text }))),
    pages: marked,
  };
}

// 住所の比較用。全角・空白・ハイフンの種類だけをそろえる。番地の区切りは残す（1-11と11-1を区別する）。
const addressText = (value: string) => value.normalize("NFKC").toLowerCase().replace(/\s+/gu, "").replace(/[‐‑–—−ー](?=\d)/gu, "-");

/** 住所の照合に使う部分。都道府県と、番地より後ろ（建物名・階）は表記がゆれるので外す。 */
function addressCore(address: string): string {
  const value = addressText(address).replace(/^(?:東京都|北海道|(?:京都|大阪)府|.{2,3}県)/u, "");
  const match = /^\D{4,}\d+(?:-\d+)*/u.exec(value);
  return match ? match[0] : "";
}

function containsAddress(text: string, core: string): boolean {
  const value = addressText(text);
  for (let index = value.indexOf(core); index >= 0; index = value.indexOf(core, index + 1)) {
    if (!/^[\d-]/.test(value.slice(index + core.length, index + core.length + 1))) return true;
  }
  return false;
}

/**
 * 支店の一覧ページで別支店の時間を選ばないよう、その営業時間の区切り（一つ前の営業時間の後ろから、最大400文字前まで）に
 * 店名・支店名・住所のどれかを求める。公式の一覧は「## 店名 → 説明 → 住所 → 営業時間」の順が多く、
 * 営業時間の後ろには次の店の見出しが続くため、後ろの文は見ない。タイトルに正式名があればそのページの営業時間とみなす。
 */
function namesWindow(name: string, address: string, page: Page, window: WindowCandidate, windows: WindowCandidate[]): boolean {
  const full = normalize(name);
  if (normalize(page.title).includes(full)) return true;
  const previous = windows.filter(value => value.pageIndex === window.pageIndex && value.offset < window.offset).at(-1);
  const from = Math.max(previous ? previous.offset + previous.text.length : 0, window.offset - 400);
  const raw = readable(page.snippet).slice(from, window.offset);
  const block = normalize(raw);
  const parts = name.normalize("NFKC").trim().split(/\s+/u);
  // 末尾の支店名（「清水店」「本店」）。公式の一覧はブランド名を省いて支店名だけで書くことが多い。
  const branch = parts.length > 1 ? normalize(parts[parts.length - 1]) : "";
  const core = addressCore(address);
  return block.includes(full) || (branch.length >= 2 && block.includes(branch)) || (core !== "" && containsAddress(raw, core));
}

export function evidenceWindow(value: unknown, name: string, address: string, officialURLs: string[], pages: Page[]): HoursWindow | null {
  if (!value || typeof value !== "object") return null;
  const { hoursID } = value as Record<string, unknown>;
  if (typeof hoursID !== "string") return null;
  const candidates = hoursCandidates(pages);
  const selected = candidates.windows.find(value => value.id === hoursID && officialURLs.includes(value.url));
  if (!selected) return null;
  const page = pages[selected.pageIndex];
  if (!namesWindow(name, address, page, selected, candidates.windows)) return null;
  const orders = candidates.lastOrders.filter(order => adjacentOrder(selected, order, candidates.windows));
  const minutes = orders.map(order => order.minutes < selected.start && selected.end > 1440 ? order.minutes + 1440 : order.minutes);
  if (minutes.some(value => value < selected.start || value > selected.end)) return null;
  // 異なるLOが複数あるのはメニュー別の可能性がある。対応するメニューが分からないので選ばない。
  const distinct = [...new Set(minutes)];
  const lastOrder = distinct.length === 1 ? distinct[0] : undefined;
  return { start: selected.start, end: selected.end, lastOrder };
}

const WEEKDAYS = "日月火水木金土";

interface DateMention { index: number; end: number; year?: number; month: number; day: number; weekday?: string }

// 「26/10」を26月10日と読まないよう、月日として成り立つものだけを日付とみなす。
const validDay = (month: number, day: number) => month >= 1 && month <= 12 && day >= 1 && day <= 31;

/** 引用中の日付。年付き（2026/11/8・2026年11月8日・2026-11-08・'26/11/8）と年なし（11/18・11月18日）を、書かれていれば曜日とともに拾う。 */
function datesIn(text: string): DateMention[] {
  const weekday = "(?:[(（]([日月火水木金土])(?:曜日?)?[)）])?";
  const found: DateMention[] = [];
  // 年は4桁か、「'26」のようにアポストロフィつきの2桁（2000年代として読む）。
  for (const match of text.matchAll(new RegExp(`(?<!\\d)(?:(\\d{4})|['’](\\d{2}))[/.\\-年](\\d{1,2})[/.\\-月](\\d{1,2})日?(?!\\d)${weekday}`, "g"))) {
    const month = Number(match[3]), day = Number(match[4]);
    if (!validDay(month, day)) continue;
    found.push({ index: match.index, end: match.index + match[0].length,
      year: match[1] ? Number(match[1]) : 2000 + Number(match[2]), month, day, weekday: match[5] });
  }
  for (const match of text.matchAll(new RegExp(`(?<![\\d/.\\-年'’])(\\d{1,2})[/月](\\d{1,2})日?(?!\\d)${weekday}`, "g"))) {
    const end = match.index + match[0].length;
    const month = Number(match[1]), day = Number(match[2]);
    if (!validDay(month, day) || found.some(item => match.index < item.end && end > item.index)) continue;
    found.push({ index: match.index, end, month, day, weekday: match[3] });
  }
  return found.sort((a, b) => a.index - b.index);
}

/** 対象日の臨時休業。年が一致するか、年がなければ曜日が書かれていて対象日と一致する場合だけ認める。 */
function closedOnDate(quote: string, year: number, month: number, day: number, weekday: string): boolean {
  const dates = datesIn(quote);
  return dates.some((item, index) => {
    if (item.month !== month || item.day !== day) return false;
    if (item.weekday !== undefined && item.weekday !== weekday) return false;
    if (item.year === undefined ? item.weekday === undefined : item.year !== year) return false;
    // 次の日付までの文に休業があるか、直前が「休業日：」などの見出しなら、この日付の休業とみなす。
    const after = quote.slice(item.end, dates[index + 1]?.index ?? quote.length);
    const before = quote.slice(dates[index - 1]?.end ?? 0, item.index);
    // 「11/18は通常営業。臨時休業のお知らせ」のように営業とも読める文は推測しない。
    if (after.replace(/休業/g, "").includes("営業")) return false;
    return /休業|休み|店休|closed/i.test(after) || /(?:休業日|店休日|臨時休業|休み)[:：]?$/.test(before);
  });
}

/** 毎週の定休日。祝日の扱い・第何週・不定休など、対象日に当てはまるか分からない書き方は認めない。 */
function regularClosure(quote: string, month: number, day: number, weekday: string): boolean {
  if (/祝|不定休|第\d|隔週|月\d回/.test(quote)) return false;
  // 対象日そのものの案内（「11/18(水)は営業」など）があれば、そちらを優先し定休日では判断しない。
  if (datesIn(quote).some(item => item.month === month && item.day === day)) return false;
  return [...quote.matchAll(/定休日?[:：]?([日月火水木金土曜・、,と]+)|([日月火水木金土曜・、,と]+)定休/g)]
    .some(match => (match[1] ?? match[2]).replace(/曜日?/g, "").includes(weekday));
}

export function evidenceClosure(value: unknown, name: string, date: string, officialURLs: string[], pages: Page[]): boolean {
  const quote = citedQuote(value, name, officialURLs, pages);
  if (!quote) return false;
  const [year, month, day] = date.split("-").map(Number);
  const weekday = WEEKDAYS[new Date(Date.UTC(year, month - 1, day)).getUTCDay()];
  // 一般的な休業の案内や古いお知らせでは、対象日の休業とは言えない。分からなければ未確認にする。
  return closedOnDate(quote, year, month, day, weekday) || regularClosure(quote, month, day, weekday);
}
