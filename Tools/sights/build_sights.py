#!/usr/bin/env python3
"""Builds Romy/Resources/Data/sights.json: famous sights in Japan for the destination search.

Sources (Issue #2, decided 2026-10-15):
- Wikidata (CC0): sights by type, Japanese label, aliases, kana (P1814), place (P131), location (P625).
- Japanese Wikipedia pageviews (MediaWiki API prop=pageviews, 50 titles per request): fame = views over
  the last 60 days. Per-article yearly counts were tried first but hit HTTP 429 for 12,000 titles.
- Japanese Wikipedia intro: reading in the first parentheses, e.g. 「清水寺（きよみずでら）」, when P1814 is missing.
- macOS reading guess (reading.swift) as the last fallback.

Run once a year:  python3 -I Tools/sights/build_sights.py
Only the Python standard library is used.
"""

import json
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
import urllib.parse
import urllib.request
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "Romy" / "Resources" / "Data" / "sights.json"
REPORT = Path(__file__).resolve().parent / "last_build_report.txt"
CACHE = Path(__file__).resolve().parent / ".cache"
UA = "RomyBuild/0.1 (https://github.com/KitadeR/Romy)"

# Wikidata type -> label shown in the app. Types were taken from famous examples (2026-10-15).
TYPES = {
    "Q2416723": "テーマパーク", "Q194195": "テーマパーク",
    "Q43501": "動物園", "Q2281788": "水族館",
    "Q46169": "国立公園", "Q1071482": "国立公園",
    "Q23413": "城", "Q92026": "城",
    "Q5393308": "寺",
    "Q845945": "神社", "Q514480": "神社", "Q1190456": "神社",
    "Q34038": "滝",
    "Q1107656": "庭園", "Q15835": "庭園", "Q11433351": "庭園", "Q11420231": "庭園",
    "Q33506": "博物館", "Q17431399": "博物館",
    "Q207694": "美術館", "Q1007870": "美術館", "Q108860927": "美術館",
    "Q1440300": "タワー",
    "Q655311": "温泉",
    "Q130003": "スキー場",
    "Q8502": "山",
    "Q23442": "島",
    "Q23397": "湖",
    "Q25391": "砂丘",
    "Q12323": "ダム",
    "Q5003624": "名所", "Q2319498": "名所",
}
FACILITIES = {"テーマパーク", "動物園", "水族館", "博物館", "美術館", "タワー", "スキー場"}
MIN_SITELINKS = 2          # has an article in at least one other language
KEEP = 2500                # most-viewed sights kept


def get_json(url, params=None, data=None, tries=4):
    if params:
        url += "?" + urllib.parse.urlencode(params)
    body = urllib.parse.urlencode(data).encode() if data else None
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url, data=body, headers={"User-Agent": UA, "Accept": "application/json"})
            with urllib.request.urlopen(req, timeout=90) as res:
                return json.load(res)
        except Exception as error:  # noqa: BLE001 - retry any network error
            if attempt == tries - 1:
                raise
            time.sleep(2 * (attempt + 1))
            print(f"  retry {url[:60]}… ({error})", file=sys.stderr)
    return None


def sparql(query):
    data = get_json("https://query.wikidata.org/sparql", data={"query": query, "format": "json"})
    return data["results"]["bindings"]


def qid(uri):
    return uri.rsplit("/", 1)[-1]


def candidates():
    items = {}
    for type_id in TYPES:
        rows = sparql(f"""
SELECT ?item ?label ?title ?links ?coord WHERE {{
  ?item wdt:P31 wd:{type_id} ; wdt:P17 wd:Q17 ; wikibase:sitelinks ?links ; wdt:P625 ?coord .
  FILTER(?links >= {MIN_SITELINKS})
  ?article schema:about ?item ; schema:isPartOf <https://ja.wikipedia.org/> ; schema:name ?title .
  ?item rdfs:label ?label FILTER(LANG(?label) = "ja")
}}""")
        print(f"{type_id} {TYPES[type_id]}: {len(rows)}", file=sys.stderr)
        for row in rows:
            key = qid(row["item"]["value"])
            entry = items.setdefault(key, {
                "id": key,
                "name": row["label"]["value"],
                "title": row["title"]["value"],
                "kinds": [],
                "coord": row["coord"]["value"],
            })
            if TYPES[type_id] not in entry["kinds"]:
                entry["kinds"].append(TYPES[type_id])
    return items


def batch_views(batch):
    """Views over the last 60 days for up to 50 titles. The API returns views for only part of a
    batch at a time and asks to continue for the rest."""
    views = {}
    params = {"action": "query", "prop": "pageviews", "pvipdays": 60, "format": "json",
              "formatversion": 2, "titles": "|".join(batch)}
    while True:
        data = get_json("https://ja.wikipedia.org/w/api.php", params=params)
        query = data.get("query", {})
        back = {n["to"]: n["from"] for n in query.get("normalized", [])}
        for page in query.get("pages", []):
            if "pageviews" in page:
                views[back.get(page["title"], page["title"])] = sum(v or 0 for v in page["pageviews"].values())
        time.sleep(0.3)
        if "continue" not in data:
            return views
        params = {**params, **data["continue"]}


def recent_views(titles):
    """Views per title, cached in .cache/views.json so a failed run resumes where it stopped."""
    cache_file = CACHE / "views.json"
    views = json.loads(cache_file.read_text()) if cache_file.exists() else {}
    todo = [t for t in titles if t not in views]
    batches = [todo[i:i + 50] for i in range(0, len(todo), 50)]
    with ThreadPoolExecutor(max_workers=4) as pool:
        for done, result in enumerate(pool.map(batch_views, batches), start=1):
            views.update(result)
            for title in batches[done - 1]:
                views.setdefault(title, 0)
            if done % 20 == 0 or done == len(batches):
                cache_file.write_text(json.dumps(views, ensure_ascii=False))
                print(f"  views {done}/{len(batches)} batches", file=sys.stderr)
    return views


MUNICIPALITIES = {e["code"]: e for e in json.loads((ROOT / "Romy/Resources/Data/municipalities.json").read_text())}


def details(ids):
    """Aliases, kana, municipality and closure for the kept items.
    The place is named after the bundled municipality list (MIC codes, P429), so it reads the same
    as the town list in the app: 京都市, 浦安市, 箱根町 (wards fall back to their city)."""
    cache_file = CACHE / "details.json"
    cached = json.loads(cache_file.read_text()) if cache_file.exists() else {}
    out = {key: {"aliases": [], "kana": [], "codes": set(), "closed": False} for key in ids}
    for key, value in cached.items():
        if key in out:
            out[key] = {**value, "codes": set(value["codes"])}
    todo = [key for key in ids if key not in cached]
    for start in range(0, len(todo), 40):
        batch = todo[start:start + 40]
        values = " ".join(f"wd:{key}" for key in batch)
        for row in sparql(f"""
SELECT DISTINCT ?item ?alias ?kana WHERE {{
  VALUES ?item {{ {values} }}
  {{ ?item skos:altLabel ?alias FILTER(LANG(?alias) = "ja") }} UNION {{ ?item wdt:P1814 ?kana }}
}}"""):
            entry = out[qid(row["item"]["value"])]
            for field, target in (("alias", "aliases"), ("kana", "kana")):
                value = row.get(field, {}).get("value")
                if value and value not in entry[target]:
                    entry[target].append(value)
        for row in sparql(f"""
SELECT DISTINCT ?item ?code WHERE {{
  VALUES ?item {{ {values} }}
  ?item wdt:P131+ ?place . ?place wdt:P429 ?code .
}}"""):
            out[qid(row["item"]["value"])]["codes"].add(row["code"]["value"])
        for row in sparql(f"""
SELECT DISTINCT ?item WHERE {{
  VALUES ?item {{ {values} }}
  {{ ?item wdt:P576 ?end }} UNION {{ ?item wdt:P3999 ?end }}
}}"""):
            out[qid(row["item"]["value"])]["closed"] = True
        for key in batch:
            cached[key] = {**out[key], "codes": sorted(out[key]["codes"])}
        cache_file.write_text(json.dumps(cached, ensure_ascii=False))
        print(f"  details {start + len(batch)}/{len(todo)}", file=sys.stderr)
    for entry in out.values():
        known = [MUNICIPALITIES[c] for c in entry["codes"] if c in MUNICIPALITIES]
        towns = [m for m in known if not m["isPrefecture"]]
        prefectures = [m for m in known if m["isPrefecture"]]
        entry["town"] = towns[0]["name"] if len(towns) == 1 else None
        entry["prefecture"] = (prefectures[0]["name"] if prefectures
                               else towns[0]["prefecture"] if towns else None)
    return out


KANA_ONLY = re.compile(r"[ぁ-ゖァ-ヺー・･゛゜ 　]+")
KANA_IN_PARENS = re.compile(r"[（(]([ぁ-ゖァ-ヺー・゛゜ 　]+?)[、,，）)]")


def intro_readings(titles):
    """Reading from the first parentheses of the Japanese Wikipedia intro."""
    readings = {}
    for start in range(0, len(titles), 20):
        batch = titles[start:start + 20]
        data = get_json("https://ja.wikipedia.org/w/api.php", params={
            "action": "query", "prop": "extracts", "exintro": 1, "explaintext": 1, "exsentences": 1,
            "exlimit": 20, "format": "json", "titles": "|".join(batch),
        })
        for page in data["query"]["pages"].values():
            match = KANA_IN_PARENS.search(page.get("extract", "")[:200])
            if match:
                readings[page["title"]] = match.group(1).replace(" ", "").replace("　", "")
    return readings


def guessed_readings(names):
    if not names:
        return {}
    script = Path(__file__).resolve().parent / "reading.swift"
    result = subprocess.run(["swift", str(script)], input="\n".join(names), capture_output=True, text=True, check=True)
    return dict(zip(names, result.stdout.splitlines()))


def hiragana(text):
    return "".join(chr(ord(ch) - 0x60) if "ァ" <= ch <= "ヶ" else ch for ch in text).replace("・", "").replace("･", "")


def main():
    CACHE.mkdir(exist_ok=True)
    cached = CACHE / "candidates.json"
    if cached.exists():
        items = json.loads(cached.read_text())
    else:
        items = candidates()
        cached.write_text(json.dumps(items, ensure_ascii=False))
    print(f"candidates: {len(items)}", file=sys.stderr)

    entries = list(items.values())
    views = recent_views([e["title"] for e in entries])
    for entry in entries:
        entry["views"] = views.get(entry["title"], 0)
    entries.sort(key=lambda e: e["views"], reverse=True)
    viewed = [e for e in entries if e["views"] > 0][:KEEP + 300]
    info = details([e["id"] for e in viewed])
    # A closing date only means "gone" for facilities. Castles, temples and the like carry the date
    # they were destroyed even when rebuilt and open (大坂城, 熊本城).
    def is_gone(entry):
        return info[entry["id"]]["closed"] and entry["kinds"][0] in FACILITIES
    closed = [e["name"] for e in viewed if is_gone(e)]
    kept = [e for e in viewed if not is_gone(e)][:KEEP]
    # Wikidata aliases mix readings in (「はこねじんじゃ」「にうつひめじんじゃ、にふつひめじんじゃ」):
    # pure-kana aliases become readings, and other aliases get a guessed reading (金閣寺→きんかくじ).
    for entry in kept:
        extra = info[entry["id"]]
        parts = [p.strip() for a in extra["aliases"] for p in re.split("[、,，]", a) if p.strip()]
        extra["kana"] += [p for p in parts if KANA_ONLY.fullmatch(p)]
        extra["aliases"] = [p for p in parts if not KANA_ONLY.fullmatch(p) and p != entry["name"]][:5]
    # Registered readings are sometimes partial (東京スカイツリー → 「スカイツリー」), so every name also
    # gets a guessed reading. Latin-only aliases (TDL) get none: the guess turns them into nonsense.
    japanese = re.compile(r"[ぁ-ゖァ-ヺ一-龯々]")
    alias_readings = guessed_readings(sorted({
        a for e in kept for a in info[e["id"]]["aliases"] if japanese.search(a)
    } | {e["name"] for e in kept}))

    missing = [e["title"] for e in kept if not info[e["id"]]["kana"]]
    from_intro = intro_readings(missing)
    still = [e["name"] for e in kept if not info[e["id"]]["kana"] and e["title"] not in from_intro]
    guessed = guessed_readings(still)

    sources = {"wikidata": 0, "wikipedia": 0, "guess": 0}
    output = []
    for entry in kept:
        extra = info[entry["id"]]
        if extra["kana"]:
            kana, sources["wikidata"] = extra["kana"], sources["wikidata"] + 1
        elif entry["title"] in from_intro:
            kana, sources["wikipedia"] = [from_intro[entry["title"]]], sources["wikipedia"] + 1
        else:
            kana, sources["guess"] = [guessed.get(entry["name"], "")], sources["guess"] + 1
        lon, lat = (float(v) for v in re.findall(r"-?\d+(?:\.\d+)?", entry["coord"])[:2])
        output.append({
            "id": entry["id"],
            "name": entry["name"],
            "aliases": extra["aliases"],
            "kana": sorted({hiragana(k) for k in kana + [alias_readings.get(entry["name"], "")] if k}),
            "aliasKana": [hiragana(alias_readings.get(a, "")) for a in extra["aliases"]],
            "kind": entry["kinds"][0],
            "town": extra["town"],
            "prefecture": extra["prefecture"],
            "lat": round(lat, 5),
            "lon": round(lon, 5),
            "views": entry["views"],
        })

    OUT.write_text(json.dumps(output, ensure_ascii=False, separators=(",", ":")) + "\n")
    lines = [
        f"built {date.today()}: candidates {len(items)}, with views {sum(1 for e in entries if e['views'])}, kept {len(output)}",
        f"dropped as closed ({len(closed)}): {'、'.join(closed[:30])}",
        f"no single town ({sum(1 for o in output if not o['town'])}): {'、'.join(o['name'] for o in output if not o['town'])[:300]}",
        f"readings: wikidata {sources['wikidata']}, wikipedia intro {sources['wikipedia']}, guessed {sources['guess']}",
        "top 40:",
        *(f"  {o['views']:>9,}  {o['name']} [{o['kind']}] {o['prefecture'] or ''}{o['town'] or ''} {o['kana']}" for o in output[:40]),
        "last 10:",
        *(f"  {o['views']:>9,}  {o['name']} [{o['kind']}]" for o in output[-10:]),
    ]
    REPORT.write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
