import { describe, expect, it } from "vitest";
import { assess } from "../eval/hours/assessment.mjs";
const reference = { expectation: "regular_reference", windows: [{ start: 600, end: 1200, lastOrder: 1170 }], sources: ["https://cafe.example.jp/shop"] };
const hours = { status: "official", closed: false, windows: reference.windows, sources: [{ url: reference.sources[0], official: true }] };
describe("営業時間の評価", () => {
  it("通常時間との一致は対象日の正解とは呼ばない", () => {
    expect(assess(reference, { hours })).toBe("matches_regular_reference");
    expect(assess(reference, {})).toBe("unconfirmed");
  });
  it("矛盾がある店舗の確認済み表示を危険な確認として数える", () => {
    const unknown = { ...reference, expectation: "unknown" };
    expect(assess(unknown, { hours })).toBe("unsafe_confirmation");
    expect(assess(unknown, { hours: { status: "unknown" } })).toBe("expected_unknown");
  });
  it("終了時刻・LO・休業・出典を別々に検証する", () => {
    expect(assess(reference, { hours: { ...hours, closed: true } })).toBe("reference_mismatch");
    expect(assess(reference, { hours: { ...hours, windows: [{ start: 600, end: 1200, lastOrder: 1190 }] } })).toBe("reference_mismatch");
    expect(assess(reference, { hours: { ...hours, sources: [{ url: "https://other.example.jp", official: true }] } })).toBe("source_review_needed");
  });
});
