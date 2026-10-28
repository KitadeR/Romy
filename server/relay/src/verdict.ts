import type { CheckResult, PlaceInput, Source, Status } from "./types";

/// What the search AI answered for 「チェックイン前の荷物預かり」, as asked in `KINDS`.
export interface LuggageAnswer {
  found_name?: string;
  found_address?: string;
  applies_to_this_hotel?: string;
  front_desk?: string;
  locker?: string;
  conditions?: unknown;
  conflicting?: boolean;
  evidence?: unknown;
}

/// Words that take back a yes (the app's `CheckResult.doubtWords`).
const doubtWords = ["確証はな", "確証がな", "確認できな", "確認できず", "見つから", "不明", "分から", "特定できな"];

/// Turns an answer into ✓ / 紹介 / ？ / ✗ by the rules in Notion 04「2026-10-28｜Romy Now｜荷物預かりの情報確認」:
/// ✓ only for the same stay with an official page; ✗ only when an official page says no; everything else ？.
/// A page counts only when the search really returned it, so an invented URL never makes a ✓.
export function decideLuggage(
  place: PlaceInput, answer: LuggageAnswer, searchedUrls: string[]
): Omit<CheckResult, "checkedAt"> {
  const sources = evidence(answer.evidence).filter((source) => searched(source.url, searchedUrls)).slice(0, 3);
  const foundName = text(answer.found_name);
  const samePlace = answer.applies_to_this_hotel === "yes"
    && sameName(place.name, foundName)
    && sameArea(place.address, text(answer.found_address));
  const trusted = samePlace && answer.conflicting !== true && sources.length > 0;
  const locker: CheckResult["locker"] =
    trusted && (answer.locker === "yes" || answer.locker === "no") ? answer.locker : "unknown";
  const unknown = { status: "unknown" as Status, conditions: [], sources, locker, foundName };
  if (!trusted) return unknown;

  const official = sources.some((source) => source.official);
  const conditions = strings(answer.conditions).slice(0, 4).map((line) => line.slice(0, 80));
  if (answer.front_desk === "yes") {
    if (conditions.some((line) => doubtWords.some((word) => line.includes(word)))) return unknown;
    return { status: official ? "official" : "introduced", conditions, sources, locker, foundName };
  }
  // No front desk but the stay's own lockers: the luggage can still be left there, so it is not ✗
  // (FAV LUX 飛騨高山, 2026-10-29 live check). The app then says 「宿のロッカーあり（空きは分かりません）」.
  if (answer.front_desk === "no" && locker !== "yes" && official) {
    return { status: "contradicted", conditions: [], sources, locker, foundName };
  }
  return unknown;
}

export function normalize(value: string): string {
  // 「ー」 is a long vowel (イースト), not a dash, so it stays.
  return value.normalize("NFKC").toLowerCase().replace(/[\s・\-‐（）()「」]/g, "");
}

/// One name holds the other: 「ホテル京都駅前」 and 「ホテル京都駅前（公式）」.
function sameName(asked: string, found?: string): boolean {
  if (!found) return false;
  const a = normalize(asked);
  const b = normalize(found);
  return a.length > 0 && b.length > 0 && (a.includes(b) || b.includes(a));
}

/// When both addresses are known, the found one has the asked one's town (up to 市・区・町・村).
function sameArea(asked?: string, found?: string): boolean {
  if (!asked || !found) return true;
  const town = normalize(asked).match(/^.*?[市区町村]/)?.[0];
  return !town || normalize(found).includes(town);
}

function searched(url: string, searchedUrls: string[]): boolean {
  const host = hostOf(url);
  return host !== null && searchedUrls.some((other) => other === url || hostOf(other) === host);
}

function hostOf(url: string): string | null {
  try {
    return new URL(url).host.replace(/^www\./, "");
  } catch {
    return null;
  }
}

function evidence(value: unknown): Source[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    if (typeof item !== "object" || item === null) return [];
    const { url, title, official } = item as Record<string, unknown>;
    if (typeof url !== "string" || hostOf(url) === null) return [];
    return [{ url, title: typeof title === "string" ? title.slice(0, 120) : undefined, official: official === true }];
  });
}

function strings(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((line): line is string => typeof line === "string" && line.trim() !== "") : [];
}

function text(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() !== "" ? value.trim() : undefined;
}
