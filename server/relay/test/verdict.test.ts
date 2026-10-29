import { describe, expect, it } from "vitest";
import { decideLuggage } from "../src/verdict";

const place = { name: "ホテル京都駅前", address: "京都府京都市下京区東塩小路町1" };
const official = "https://hotel-kyoto.example.jp/faq";
const blog = "https://travel-blog.example.com/kyoto";
const yes = {
  found_name: "ホテル京都駅前",
  found_address: "京都府京都市下京区東塩小路町1",
  applies_to_this_hotel: "yes",
  front_desk: "yes",
  conditions: ["当日の朝7:00から", "貴重品は預けられません"],
  conflicting: false,
  evidence: [{ url: official, title: "よくある質問", official: true }],
};

describe("decideLuggage", () => {
  it("is ✓ with an official page the search returned, for the same stay", () => {
    const result = decideLuggage(place, yes, [official]);
    expect(result.status).toBe("official");
    expect(result.conditions).toEqual(["当日の朝7:00から", "貴重品は預けられません"]);
    expect(result.sources).toEqual([{ url: official, title: "よくある質問", official: true }]);
  });

  it("does not believe a page the search never returned", () => {
    expect(decideLuggage(place, yes, ["https://other.example.org/"]).status).toBe("unknown");
  });

  it("is 紹介 when only other sites say yes", () => {
    const answer = { ...yes, evidence: [{ url: blog, official: false }] };
    expect(decideLuggage(place, answer, [blog]).status).toBe("introduced");
  });

  it("is ✗ only when an official page says no, and gives no conditions", () => {
    const answer = { ...yes, front_desk: "no" };
    expect(decideLuggage(place, answer, [official])).toMatchObject({ status: "contradicted", conditions: [] });
    const fromBlog = { ...answer, evidence: [{ url: blog, official: false }] };
    expect(decideLuggage(place, fromBlog, [blog]).status).toBe("unknown");
  });

  it("is not ✗ when there is no front desk but the stay has its own lockers, and says so", () => {
    const answer = { ...yes, front_desk: "no", locker: "yes" };
    expect(decideLuggage(place, answer, [official])).toMatchObject({ status: "unknown", locker: "yes" });
  });

  it("tells the lockers only for the same stay from a searched page", () => {
    expect(decideLuggage(place, { ...yes, locker: "yes" }, [official])).toMatchObject({ status: "official", locker: "yes" });
    expect(decideLuggage(place, { ...yes, locker: "yes" }, []).locker).toBe("unknown");
    expect(decideLuggage(place, { ...yes, locker: "yes", found_name: "ホテル大阪梅田" }, [official]).locker).toBe("unknown");
    expect(decideLuggage(place, { ...yes, locker: "maybe" }, [official]).locker).toBe("unknown");
  });

  it("keeps the long vowel when it compares names", () => {
    const east = { name: "ホテルイースト", address: place.address };
    expect(decideLuggage(east, { ...yes, found_name: "ホテルイースト" }, [official]).status).toBe("official");
    expect(decideLuggage(east, { ...yes, found_name: "ホテルイスト" }, [official]).status).toBe("unknown");
  });

  it("is ？ for another branch, another town, a chain-wide page or a conflict", () => {
    expect(decideLuggage(place, { ...yes, found_name: "ホテル大阪梅田" }, [official]).status).toBe("unknown");
    expect(decideLuggage(place, { ...yes, found_address: "大阪府大阪市北区1" }, [official]).status).toBe("unknown");
    expect(decideLuggage(place, { ...yes, applies_to_this_hotel: "unknown" }, [official]).status).toBe("unknown");
    expect(decideLuggage(place, { ...yes, conflicting: true }, [official]).status).toBe("unknown");
  });

  it("takes back a yes whose conditions doubt it", () => {
    const answer = { ...yes, conditions: ["預かりの可否は確認できない"] };
    expect(decideLuggage(place, answer, [official]).status).toBe("unknown");
  });

  it("matches names written a little differently", () => {
    const answer = { ...yes, found_name: "ホテル 京都駅前（公式サイト）" };
    expect(decideLuggage(place, answer, [official]).status).toBe("official");
  });

  it("is ？ for a broken answer", () => {
    expect(decideLuggage(place, {}, []).status).toBe("unknown");
    expect(decideLuggage(place, { ...yes, evidence: "x", conditions: 3 }, [official]).status).toBe("unknown");
  });
});
