/// The app's passphrase (Notion 04「2026-10-29｜段階3 公開」): until App Attest can be used (it needs the paid
/// Apple Developer Program), the published relay answers only requests that carry it in `X-Romy-Token`.
/// It only keeps casual callers out — it ships inside the app — so the spending caps stay the real guard.
/// Without `APP_TOKEN` (the relay on the Mac, `wrangler dev`), nothing is asked.
export function tokenAllows(expected: string | undefined, given: string | null): boolean {
  if (!expected) return true;
  if (given === null) return false;
  const a = new TextEncoder().encode(expected);
  const b = new TextEncoder().encode(given);
  // Compared in full whatever the first difference, so the time taken does not tell how much was right.
  let difference = a.length ^ b.length;
  for (let i = 0; i < a.length; i++) difference |= a[i] ^ (b[i] ?? 0);
  return difference === 0;
}
