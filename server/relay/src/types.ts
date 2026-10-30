/// One kind of fact the relay checks. Only the stay's luggage before check-in for now
/// (Notion 02 §6-4「決定（2026-10-29）｜事実の確認⑤」); free text (③) adds more kinds later.
export type CheckKind = "luggage_before_checkin";

/// ✓ 公式 / 紹介されています / ？ / ✗, the same four as the app's `CheckResult`.
export type Status = "official" | "introduced" | "unknown" | "contradicted";

/// What the app sends: public facts about a place only, never where the person is or what they wrote
/// (Notion 04「2026-10-29｜各社のデータの扱い」①).
export interface PlaceInput {
  /// MapKit place ID, when the place has one.
  id?: string;
  name: string;
  address?: string;
}

export interface CheckRequest {
  kind: CheckKind;
  place: PlaceInput;
}

export interface Source {
  url: string;
  title?: string;
  official: boolean;
}

/// What is cached and shared between people.
export interface CheckResult {
  status: Status;
  /// Conditions as the source writes them (「当日の朝から」); only with a yes.
  conditions: string[];
  sources: Source[];
  /// The stay's own lockers, apart from the front desk (「宿のロッカーあり（空きは分かりません）」).
  /// Only from pages the search returned for the same stay; free space is never known.
  locker: "yes" | "no" | "unknown";
  /// The name the source used, to show which place was checked.
  foundName?: string;
  /// When Romy checked, shown as 「10/20に確認」; a cached result keeps its own date.
  checkedAt: string;
}

export interface CheckResponse extends CheckResult {
  cached: boolean;
  /// Why there is no answer: the caps were reached, or the search failed. Neither is cached.
  reason?: "limit" | "error";
}
