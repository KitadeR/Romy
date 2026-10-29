import type { CheckKind, PlaceInput, Status } from "./types";

const DAY_MS = 86_400_000;

/// The fixed question for one kind. It is fixed here, not sent by the app, so one answer can serve everyone
/// who asks about the same place (Notion 04「2026-10-28｜結果の保存（キャッシュ）」見分け方).
export interface KindSpec {
  instructions: string;
  input(place: PlaceInput): string;
  schema: Record<string, unknown>;
  /// How long a result is used again. ✓・✗ last long; ？ and 紹介 are checked again soon.
  ttlMs: Record<Status, number>;
}

const yesNoUnknown = { type: "string", enum: ["yes", "no", "unknown"] };

export const KINDS: Record<CheckKind, KindSpec> = {
  luggage_before_checkin: {
    instructions: [
      "あなたは宿の公式の案内を確かめる調査係です。",
      "指定された宿で、チェックイン前にフロントで荷物を預かってもらえるかを調べます。",
      "宿や運営会社の公式サイト・公式FAQを優先し、予約サイトやブログなど公式以外の情報は official を false にして分けます。",
      "別の店舗やチェーン全体の案内しか見つからないときは、その宿に当てはまるか分からないので applies_to_this_hotel を unknown にします。",
      "セルフのロッカーはフロントでの預かりとは別に locker に書きます。ロッカーの空きは分からないものとして扱います。",
      "見つからない・書いていないことは推測せず unknown にします。食い違う情報があれば conflicting を true にします。",
      "conditions には、出典に書いてある条件（受付の時間・料金・預けられない物・事前の連絡など）だけを短い日本語で入れます。",
      "分からないこと（当日の受付状況など）は conditions に入れず unknowns に入れます。",
      "evidence には実際に読んだページのURLだけを入れます。JSONだけで答えます。",
    ].join("\n"),
    input: (place) => [`宿の名前：${place.name}`, place.address ? `住所：${place.address}` : null].filter(Boolean).join("\n"),
    schema: {
      type: "object",
      properties: {
        found_name: { type: "string" },
        found_address: { type: "string" },
        applies_to_this_hotel: yesNoUnknown,
        front_desk: yesNoUnknown,
        locker: yesNoUnknown,
        conditions: { type: "array", items: { type: "string" } },
        unknowns: { type: "array", items: { type: "string" } },
        conflicting: { type: "boolean" },
        evidence: {
          type: "array",
          items: {
            type: "object",
            properties: { url: { type: "string" }, title: { type: "string" }, official: { type: "boolean" } },
            required: ["url", "official"],
          },
        },
      },
      required: ["found_name", "applies_to_this_hotel", "front_desk", "conditions", "conflicting", "evidence"],
    },
    ttlMs: { official: 30 * DAY_MS, contradicted: 30 * DAY_MS, introduced: 3 * DAY_MS, unknown: 3 * DAY_MS },
  },
};

export function isKind(value: unknown): value is CheckKind {
  return typeof value === "string" && value in KINDS;
}
