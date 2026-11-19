// Run from server/relay. Captures contain public third-party excerpts and stay outside Git.
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { assess } from "./assessment.mjs";

const base = new URL("./", import.meta.url);
const cases = JSON.parse(await readFile(new URL("cases.json", base), "utf8"));
const [mode, runArg = "1"] = process.argv.slice(2);
if (!["capture", "score"].includes(mode)) throw new Error("Use: node eval/hours/run.mjs capture|score [runs:1-3]");
const runs = Number(runArg);
if (!Number.isInteger(runs) || runs < 1 || runs > 3) throw new Error("runs must be 1-3");
if (cases.length > 15) throw new Error("Review the evaluation budget before adding more than 15 cases");
await mkdir(new URL("search/", base), { recursive: true });
const readJSON = async url => JSON.parse(await readFile(url, "utf8"));

if (mode === "capture") {
  const key = process.env.PERPLEXITY_API_KEY;
  if (!key) throw new Error("Set PERPLEXITY_API_KEY with node --env-file=.dev.vars");
  for (const item of cases) {
    const file = new URL(`search/${item.id}.json`, base);
    try { await readJSON(file); console.log(`${item.id}: saved (skip)`); continue; }
    catch (error) { if (error.code !== "ENOENT") throw error; }
    const query = `${item.request.name} ${item.request.address} 営業時間`;
    const start = Date.now();
    const response = await fetch("https://api.perplexity.ai/search", {
      method: "POST", headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json", "User-Agent": "Romy-Hours-Evaluation/1.0" },
      body: JSON.stringify({ query, max_results: 5, max_tokens_per_page: 512, country: "JP" }),
      signal: AbortSignal.timeout(30_000),
    });
    if (!response.ok) throw new Error(`${item.id}: search HTTP ${response.status}`);
    const body = await response.json();
    if (!Array.isArray(body.results)) throw new Error(`${item.id}: invalid search response`);
    const results = body.results.filter(page => typeof page.url === "string" && typeof page.snippet === "string")
      .map(page => ({ url: page.url, title: typeof page.title === "string" ? page.title : "", snippet: page.snippet }));
    await writeFile(file, JSON.stringify({ capturedAt: new Date().toISOString(), query, searchMs: Date.now() - start, results }, null, 2) + "\n");
    console.log(`${item.id}: ${results.length} pages saved`);
  }
} else {
  const rows = [];
  for (const item of cases) {
    const capture = await readJSON(new URL(`search/${item.id}.json`, base));
    for (let run = 1; run <= runs; run++) {
      const started = Date.now();
      const response = await fetch("http://localhost:8797/hours", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ request: { ...item.request, session: "781D55EC-250B-4C69-9B03-213BE189C6D6" }, pages: capture.results }),
        signal: AbortSignal.timeout(70_000),
      });
      if (!response.ok) throw new Error(`${item.id}: evaluator HTTP ${response.status}`);
      const reply = await response.json();
      const row = { id: item.id, run, captureDate: capture.capturedAt, searchMs: capture.searchMs,
        readerMs: Date.now() - started, assessment: assess(item.reference, reply), ...reply };
      rows.push(row);
      console.log(`${item.id} #${run}: ${reply.diagnostic?.code} ${row.assessment} (${reply.diagnostic?.matchedPages}/${reply.diagnostic?.foundPages} pages)`);
    }
  }
  const counts = {};
  for (const row of rows) counts[row.assessment] = (counts[row.assessment] ?? 0) + 1;
  const confirmed = rows.filter(row => row.hours?.status === "official").length;
  const report = { evaluatedAt: new Date().toISOString(), runs, cases: cases.length, confirmed, total: rows.length, counts, rows };
  await mkdir(new URL("results/", base), { recursive: true });
  await writeFile(new URL("results/latest.json", base), JSON.stringify(report, null, 2) + "\n");
  console.log(JSON.stringify({ confirmed, total: rows.length, counts }));
}
