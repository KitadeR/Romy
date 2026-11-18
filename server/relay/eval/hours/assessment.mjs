// Regular hours are a reference, not proof that a particular day has no temporary changes.
export function assess(reference, reply) {
  if (reply.hours?.status !== "official") return reference.expectation === "unknown" ? "expected_unknown" : "unconfirmed";
  if (reference.expectation === "unknown") return "unsafe_confirmation";
  const actual = reply.hours;
  if (actual.closed || actual.windows.length !== reference.windows.length) return "reference_mismatch";
  const matches = reference.windows.every((window, index) => {
    const value = actual.windows[index];
    return value.start === window.start && value.end === window.end
      && (window.lastOrder === undefined || value.lastOrder === window.lastOrder);
  });
  if (!matches) return "reference_mismatch";
  const hosts = new Set(reference.sources.map(url => new URL(url).hostname.replace(/^www\./, "")));
  const knownSource = actual.sources.some(source => {
    try { return source.official && hosts.has(new URL(source.url).hostname.replace(/^www\./, "")); }
    catch { return false; }
  });
  return knownSource ? "matches_regular_reference" : "source_review_needed";
}
