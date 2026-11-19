import { describe, expect, it } from "vitest";
import { decideHours } from "../src/scene";
import { hoursCandidates, withHoursCandidates } from "../src/hoursEvidence";

const request = { name: "駅前喫茶 中央口店", address: "京都市下京区公開町1-1", date: "2026-11-18", timeZone: "Asia/Tokyo" };
const now = new Date("2026-11-18T03:00:00Z");
const url = "https://cafe.example.jp/central";
const snippet = "駅前喫茶 中央口店 営業時間：7:00〜21:00（ラストオーダー：20:30）";
const pages = [{ url, title: request.name, snippet }];
const selected = { hoursID: "p1-w1" };
const answer = { ...request, closed: false, conflicting: false, sources: [{ url, title: request.name, official: true }], windows: [selected] };

function check(text: string, windows: unknown[] = [selected]) {
  return decideHours(request, { ...answer, windows }, [url], now, [{ ...pages[0], snippet: `${request.name} ${text}` }]);
}

describe("営業時間の原文照合", () => {
  it("0時という生成値を採用せず、元の7:00を420分に計算する", () => {
    const body = { ...answer, windows: [{ ...selected, start: 0, end: 1260, lastOrder: 1230 }] };
    expect(decideHours(request, body, [url], now, pages).windows).toEqual([{ start: 420, end: 1260, lastOrder: 1230 }]);
  });
  it("7〜20時を0〜22時にした誤読も生成値を無視する", () => {
    expect(check("7:00-20:00 (L.O.19:30)", [{ ...selected, start: 0, end: 1320 }]).windows)
      .toEqual([{ start: 420, end: 1200, lastOrder: 1170 }]);
  });
  it("架空の候補IDと数値だけの旧出力を採用しない", () => {
    for (const window of [{ hoursID: "p99-w1" }, { start: 0, end: 1260 }]) {
      expect(decideHours(request, { ...answer, windows: [window] }, [url], now, pages).status).toBe("unknown");
    }
  });
  it("候補は同じ店名を含む実際の検索ページから選ぶ", () => {
    const other = [{ url, title: "別の店", snippet: "別の店 7:00〜21:00 LO20:30" }];
    expect(decideHours(request, answer, [url], now, other).status).toBe("unknown");
    expect(decideHours(request, answer, [], now, pages).status).toBe("unknown");
    expect(decideHours(request, { ...answer, sources: [{ url, official: false }] }, [url], now, pages).status).toBe("unknown");
  });
  it("AIへは原文候補を送り、生成した分数を選択肢にしない", () => {
    const input = withHoursCandidates("店舗の指定", pages);
    expect(input).toContain("p1-w1");
    expect(input).toContain("7:00〜21:00");
    expect(input).not.toContain('"start"');
    expect(input).not.toContain('"end"');
  });
});

describe("時刻表記の変換", () => {
  it.each([
    ["７：００〜２１：００", 420, 1260], ["午前10時〜午後8時", 600, 1200],
    ["7:00am-9:00pm", 420, 1260], ["午前12時〜午後12時", 0, 720],
    ["0:00〜5:00", 0, 300], ["18:00〜翌2:00", 1080, 1560],
    ["18:00〜2:00", 1080, 1560], ["18:00〜26:00", 1080, 1560],
    ["前日18:00〜2:00", 0, 120], ["24時間営業", 0, 1440],
    ["9時半〜17時30分", 570, 1050], ["10:00〜24:00", 600, 1440],
    ["17:00〜21:00", 1020, 1260], ["午後7:00〜午後9:00", 1140, 1260],
    ["7am-9pm", 420, 1260],
  ])("原文%sを計算する", (text, start, end) => {
    expect(check(text).windows).toEqual([{ start, end, lastOrder: undefined }]);
  });
  it.each(["7:90〜21:00", "7:00〜48:00", "7:00〜7:00", "9am〜13pm", "7-21", "7:00", "翌24:00〜翌26:00", "117:00〜21:00", "10:00〜9:00"])("曖昧・不正な%sを補わない", text => {
    expect(check(text).status).toBe("unknown");
  });
  it("昼夜の別の営業区間と翌日のLOを計算する", () => {
    expect(check("11:00〜14:00 LO13:30 / 18:00〜翌2:00 LO翌1:30", [
      { hoursID: "p1-w1" }, { hoursID: "p1-w2" },
    ]).windows).toEqual([{ start: 660, end: 840, lastOrder: 810 }, { start: 1080, end: 1560, lastOrder: 1530 }]);
  });
  it("LOは同じ区間の原文から対応付け、AIが付け足したLOの値は使わない。営業区間外のLOは未確認にする", () => {
    expect(check("11:00〜14:00 LO13:30 / 18:00〜22:00 LO21:30", [selected]).windows)
      .toEqual([{ start: 660, end: 840, lastOrder: 810 }]);
    expect(check("7:00〜21:00 LO22:00", [selected]).status).toBe("unknown");
    expect(check(snippet, [{ hoursID: "p1-w1", lastOrder: 0 }]).windows)
      .toEqual([{ start: 420, end: 1260, lastOrder: 1230 }]);
  });
  it("Markdownの表や強調でも原文時刻をそのまま使う", () => {
    expect(check("|営業時間|**7:00〜21:00（LO20:30）**|", [selected]).windows)
      .toEqual([{ start: 420, end: 1260, lastOrder: 1230 }]);
  });
  it("同じ区間の重複はまとめ、異なるLO・重なった区間は矛盾にする", () => {
    expect(check(snippet, [selected, selected]).windows).toHaveLength(1);
    expect(check("7:00〜21:00 LO20:00 / 7:00〜21:00 LO20:30", [selected, { hoursID: "p1-w2" }]).diagnostic).toBe("conflicting");
    expect(check("7:00〜21:00 / 8:00〜22:00", [selected, { hoursID: "p1-w2" }]).diagnostic).toBe("conflicting");
  });
  it("候補の番号は抽出された原文と対応する", () => {
    const found = hoursCandidates(pages);
    expect(found.windows[0]).toMatchObject({ id: "p1-w1", text: "7:00〜21:00", start: 420, end: 1260 });
    expect(found.lastOrders[0]).toMatchObject({ id: "p1-lo1", minutes: 1230 });
  });
});

describe("休業の判定（分からなければ未確認）", () => {
  // 2026-11-18は水曜日。
  const closure = (text: string, date = request.date) => {
    const quote = `${request.name} ${text}`;
    return decideHours({ ...request, date }, { ...answer, date, closed: true, windows: [], closureEvidence: { url, quote } },
      [url], now, [{ ...pages[0], snippet: quote }]).status;
  };
  it("対象日を示す原文がある場合だけ採用する", () => {
    expect(closure("2026年11月18日は休業します。")).toBe("official");
    const quote = `${request.name} 2026年11月18日は休業します。`;
    const body = { ...answer, closed: true, windows: [], closureEvidence: null };
    expect(decideHours(request, body, [url], now, [{ ...pages[0], snippet: quote }]).status).toBe("unknown");
    expect(closure("2026年11月19日は休業します。")).toBe("unknown");
  });
  it.each(["2026/11/18は臨時休業", "2026-11-18(水)は店休日", "2026/11/08は休業"].map(text => [text]))("年つきの日付%sを読む", text => {
    expect(closure(text, text.includes("11/08") ? "2026-11-08" : request.date)).toBe("official");
  });
  it("日付の一部だけの一致では休業にしない", () => {
    expect(closure("2026/11/18は休業します", "2026-11-01")).toBe("unknown");
    expect(closure("2027/1/20は休業", "2027-01-02")).toBe("unknown");
  });
  it("年のない日付は、書かれた曜日が対象日と合う場合だけ採用する", () => {
    expect(closure("11月18日(水)は臨時休業いたします")).toBe("official");
    expect(closure("11/18（水曜日）休業")).toBe("official");
    expect(closure("11月18日(木)は臨時休業")).toBe("unknown");
    expect(closure("11月18日は臨時休業")).toBe("unknown");
    expect(closure("2026/11/18(木)は休業")).toBe("unknown");
  });
  it("対象日が営業とも読める案内では休業にしない", () => {
    expect(closure("11/18(水)は通常営業。臨時休業のお知らせ")).toBe("unknown");
    expect(closure("11/18(水)は営業、11/19(木)は休業")).toBe("unknown");
    expect(closure("休業日：11/18(水)")).toBe("official");
  });
  it("定休日は対象日の曜日が書かれていれば採用し、祝日などの例外があれば未確認にする", () => {
    expect(closure("定休日：水曜日")).toBe("official");
    expect(closure("毎週水曜日定休")).toBe("official");
    expect(closure("定休日 火・水曜")).toBe("official");
    expect(closure("定休日：木曜日")).toBe("unknown");
    expect(closure("定休日：水曜日（祝日の場合は営業）")).toBe("unknown");
    expect(closure("定休日：第2・第4水曜日")).toBe("unknown");
    expect(closure("不定休")).toBe("unknown");
    expect(closure("定休日：水曜日。11/18(水)は営業します")).toBe("unknown");
  });
});


it("英単語の中の「lo」をLOとして拾わない", () => {
  expect(hoursCandidates([{ url, title: request.name, snippet: "7:00〜21:00 Cafe Polo 20:00" }]).lastOrders).toEqual([]);
  expect(check("7:00〜21:00 L.O.20:30", [selected]).windows).toEqual([{ start: 420, end: 1260, lastOrder: 1230 }]);
});

it("支店の一覧では、タイトルか営業時間の前後に店名がある区間だけ採用する", () => {
  const list = `イノダ 本店 7:00〜18:00 ${"・".repeat(120)} ${request.name}のお知らせ`;
  const other = [{ url, title: "店舗一覧", snippet: `別の店 8:00〜20:00 ${"・".repeat(120)} ${request.name}` }];
  expect(decideHours(request, answer, [url], now, other).status).toBe("unknown");
  expect(decideHours(request, answer, [url], now, [{ url, title: "店舗一覧", snippet: list }]).status).toBe("unknown");
  expect(decideHours(request, answer, [url], now, [{ url, title: "店舗一覧", snippet: `${request.name} 7:00〜21:00` }]).status).toBe("official");
});

it("別の区間のLOは自動的に流用せず、区間内で複数なら推測しない", () => {
  expect(check("7:00〜20:00 / 別の店 7:00〜19:00 LO18:30").windows)
    .toEqual([{ start: 420, end: 1200, lastOrder: undefined }]);
  expect(check("7:00〜20:00 LO19:00 LO19:30").windows)
    .toEqual([{ start: 420, end: 1200, lastOrder: undefined }]);
});

it("非公式の候補は公式の候補に混ぜても採用せず、存在しないIDは拒否する", () => {
  const other = { url: "https://review.example.jp", title: request.name, snippet: `${request.name} 0:00〜23:00` };
  const body = { ...answer, windows: [{ hoursID: "p1-w1" }, { hoursID: "p2-w1" }] };
  expect(decideHours(request, body, [url, other.url], now, [...pages, other]).windows)
    .toEqual([{ start: 420, end: 1260, lastOrder: 1230 }]);
  expect(decideHours(request, { ...body, windows: [{ hoursID: "p1-w1" }, { hoursID: "p99-w1" }] }, [url], now, pages).status).toBe("unknown");
});
