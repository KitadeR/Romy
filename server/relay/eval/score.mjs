// 保存した検索結果で宿の荷物預かりの判定を採点する。先に `npx wrangler dev -c eval/wrangler.toml --port 8797` を起動する。
// 使い方: node eval/score.mjs [回数]   （同じ抜粋でも読み取りが揺れるため、既定で各宿3回読む）
import { readFileSync } from "node:fs";

const runs = Number(process.argv[2] ?? 3);
const base = new URL("./luggage/", import.meta.url);
const places = JSON.parse(readFileSync(new URL("places.json", base)));
const { cases } = JSON.parse(readFileSync(new URL("expected.json", base)));
const label = { official: "✓公式", introduced: "紹介", unknown: "？", contradicted: "✗", none: "答えなし" };

let correct = 0, dangerous = 0, total = 0;
for (const place of places) {
  const expected = cases[place.id];
  const pages = JSON.parse(readFileSync(new URL(`search/${place.id}.json`, base))).results
    .map(({ url, title, snippet }) => ({ url, title: title ?? "", snippet }));
  const marks = [];
  for (let i = 0; i < runs; i++) {
    const response = await fetch("http://localhost:8797", {
      method: "POST", body: JSON.stringify({ place: { name: place.name, address: place.address }, pages }),
    });
    const { verdict } = await response.json();
    const status = verdict?.status ?? "none";
    const lockerOk = !expected.locker || verdict?.locker === expected.locker;
    const ok = expected.accept.includes(status) && lockerOk;
    const bad = (expected.never ?? []).includes(status);
    total += 1; if (ok) correct += 1; if (bad) dangerous += 1;
    marks.push(`${label[status]}${expected.locker ? `/ロッカー${verdict?.locker ?? "-"}` : ""}${ok ? "○" : bad ? "✕危険" : "×"}`);
  }
  console.log(`${place.name.padEnd(18, "　")} 正解:${expected.accept.map((s) => label[s]).join("か")}${expected.locker ? "/ロッカーyes" : ""}  結果: ${marks.join(" ")}`);
}
console.log(`\n正解 ${correct}/${total}（${Math.round((correct / total) * 100)}%）  危険な誤り ${dangerous}件（出してはいけない✓・✗など）`);
