/// Sites that are never a place's own official page: booking sites, travel agencies, reviews and tourism guides.
/// The reader decides `official`, but a ✓ must not rest on its word alone (2026-11-17: Qwen3 marked AsiaYo,
/// 楽天トラベル and ANA official). The list only takes "official" away; it never grants it.
const notOfficialHosts = [
  "asiayo.com", "agoda.com", "booking.com", "expedia.co.jp", "expedia.com", "hotels.com", "trip.com",
  "tripadvisor.jp", "tripadvisor.com", "travel.rakuten.co.jp", "jalan.net", "ikyu.com", "rurubu.travel",
  "knt.co.jp", "jtb.co.jp", "ana.co.jp", "jal.co.jp", "travel.yahoo.co.jp", "newt.net", "relux.jp",
  "yukoyuko.net", "tabelog.com", "retty.me", "hotpepper.jp", "gnavi.co.jp", "google.com", "instagram.com",
  "x.com", "twitter.com", "facebook.com", "kyoto-kankou.or.jp",
  // 個人ブログ・地図・まとめ記事（2026-11-19：note.comのブログやナビタイムが公式と判定された）。
  "note.com", "ameblo.jp", "hatenablog.com", "hatenablog.jp", "hatena.ne.jp", "navitime.co.jp", "mapion.co.jp",
  "map.yahoo.co.jp", "loco.yahoo.co.jp", "rurubu.jp", "co-trip.jp", "icotto.jp", "kinarino.jp", "aumo.jp",
  "walkerplus.com", "gltjp.com", "hitosara.com", "ekiten.jp", "epark.jp", "macaro-ni.jp", "timeout.jp", "ozmall.co.jp",
];

/// True when the URL belongs to one of the sites above (or a subdomain such as yado.knt.co.jp).
export function isNeverOfficial(url: string): boolean {
  let host: string;
  try {
    host = new URL(url).host.replace(/^www\./, "").toLowerCase();
  } catch {
    return true;
  }
  return notOfficialHosts.some((site) => host === site || host.endsWith("." + site));
}
