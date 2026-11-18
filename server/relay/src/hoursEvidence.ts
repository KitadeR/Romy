import type { Page } from "./searchReader";
import { normalize } from "./verdict";

export interface HoursWindow { start: number; end: number; lastOrder?: number }

// Normalize width, whitespace and Markdown bold markers only; do not paraphrase evidence or turn one clock time into another.
const compact = (value: string) => value.normalize("NFKC").replace(/\*\*/g, "").replace(/\s+/gu, "");

function containsLiteral(context: string, literal: string): boolean {
  const text = compact(context), wanted = compact(literal);
  if (!wanted) return false;
  let from = 0;
  while (from <= text.length - wanted.length) {
    const index = text.indexOf(wanted, from);
    if (index < 0) return false;
    const before = text.slice(0, index), after = text.slice(index + wanted.length);
    // Do not match 7:00 inside 17:00, strip 午後/翌, or omit a trailing pm or minute unit.
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
  // A list of multiple shops needs the requested shop's name in the quoted context, not just elsewhere on the page.
  if (!normalize(page.title).includes(normalize(name)) && !normalize(quote).includes(normalize(name))) return null;
  return compact(quote);
}

/** Parses source clock text. A previous-day start requires an explicit 前日; an overnight closing can use 26:00 or 翌2:00. */
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

/** Candidates come from the saved excerpt, never from generated quotes or generated minute values. */
export function hoursCandidates(pages: Page[]): { windows: WindowCandidate[]; lastOrders: LastOrderCandidate[] } {
  const windows: WindowCandidate[] = [], lastOrders: LastOrderCandidate[] = [];
  const token = String.raw`(?:(?:前日|翌日|翌)\s*)?(?:(?:午前|午後|am|pm)\s*)?\d{1,2}(?::\d{2}|時(?:\d{1,2}分|半)?)(?:\s*(?:am|pm))?`;
  const time = `(?:${token}|\\d{1,2}\\s*(?:am|pm))`;
  for (const [pageIndex, page] of pages.entries()) {
    const text = page.snippet.normalize("NFKC").replace(/\*\*/g, "");
    const ranges = new RegExp(`(?<!\\d)(?<!\\d:)(?:${time}\\s*[〜~～\\-–—−]\\s*${time}|24時間営業)(?![\\d:])`, "giu");
    const orders = new RegExp(`(?:ラストオーダー|L\\.?O\\.?|Last\\s*Order|Last\\s*Call)\\s*[:：]?\\s*(${time})(?![\\d:])`, "giu");
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

export function withHoursCandidates(input: string, pages: Page[]): string {
  const candidates = hoursCandidates(pages);
  const fields = ({ id, url, text, context }: ClockCandidate) => ({ id, url, text, context });
  return input + "\n\n原文の時刻候補（idだけを選ぶ。値を書き換えない）:\n" + JSON.stringify({
    windows: candidates.windows.map(fields),
  });
}

export function evidenceWindow(value: unknown, name: string, officialURLs: string[], pages: Page[]): HoursWindow | null {
  if (!value || typeof value !== "object") return null;
  const { hoursID } = value as Record<string, unknown>;
  if (typeof hoursID !== "string") return null;
  const candidates = hoursCandidates(pages);
  const selected = candidates.windows.find(value => value.id === hoursID && officialURLs.includes(value.url));
  if (!selected) return null;
  const page = pages[selected.pageIndex];
  if (!normalize(page.title + page.snippet).includes(normalize(name))) return null;
  const orders = candidates.lastOrders.filter(order => adjacentOrder(selected, order, candidates.windows));
  const minutes = orders.map(order => order.minutes < selected.start && selected.end > 1440 ? order.minutes + 1440 : order.minutes);
  if (minutes.some(value => value < selected.start || value > selected.end)) return null;
  // More than one distinct LO can be menu-dependent. Do not pick one without a matching menu.
  const distinct = [...new Set(minutes)];
  const lastOrder = distinct.length === 1 ? distinct[0] : undefined;
  return { start: selected.start, end: selected.end, lastOrder };
}

export function evidenceClosure(value: unknown, name: string, date: string, officialURLs: string[], pages: Page[]): boolean {
  const quote = citedQuote(value, name, officialURLs, pages);
  if (!quote || !/休業|休み|店休|closed/i.test(quote)) return false;
  const [year, month, day] = date.split("-").map(Number);
  // A generic closing day or an old announcement does not prove this particular date is closed.
  return [date, `${year}/${month}/${day}`, `${year}年${month}月${day}日`].some(value => quote.includes(value));
}
