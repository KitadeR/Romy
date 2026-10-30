import { runCheck } from "./check";
import { isKind } from "./kinds";
import { perplexity } from "./perplexity";
import { D1Store } from "./store";
import { tokenAllows } from "./token";
import type { CheckRequest, CheckResponse } from "./types";

export interface Env {
  DB: D1Database;
  PERPLEXITY_API_KEY?: string;
  /// The app's passphrase on the published relay (a secret); unset on the Mac.
  APP_TOKEN?: string;
  DEVICE_DAILY_SEARCHES: string;
  GLOBAL_DAILY_USD: string;
  RESERVE_USD: string;
}

/// POST /v1/check with {kind, place:{id?, name, address?}}, the device in `X-Romy-Device` and, on the published
/// relay, the app's passphrase in `X-Romy-Token`. The device is an opaque ID for the daily cap; it becomes the
/// App Attest key ID once the paid Apple Developer Program is there (Notion 04「2026-10-29｜段階3 公開」).
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname !== "/v1/check") return new Response("Not found", { status: 404 });
    if (request.method !== "POST") return new Response("Method not allowed", { status: 405 });
    if (!tokenAllows(env.APP_TOKEN, request.headers.get("X-Romy-Token"))) {
      return new Response("Forbidden", { status: 403 });
    }

    const device = request.headers.get("X-Romy-Device") ?? "";
    if (!/^[A-Za-z0-9_\-=+/]{8,128}$/.test(device)) return new Response("Bad device", { status: 400 });
    const body = parse(await request.json().catch(() => null));
    if (!body) return new Response("Bad request", { status: 400 });

    const started = Date.now();
    const result: CheckResponse = env.PERPLEXITY_API_KEY
      ? await runCheck(body, device, {
          store: new D1Store(env.DB),
          search: perplexity(env.PERPLEXITY_API_KEY),
          limits: {
            deviceDaily: Number(env.DEVICE_DAILY_SEARCHES),
            globalUSD: Number(env.GLOBAL_DAILY_USD),
            reserveUSD: Number(env.RESERVE_USD),
          },
          now: () => new Date(),
        })
      : { status: "unknown", conditions: [], sources: [], locker: "unknown", checkedAt: new Date().toISOString(), cached: false, reason: "error" };
    // Counts and time only, never the place or the device (Notion 04「2026-10-29｜各社のデータの扱い」④).
    console.log(JSON.stringify({
      event: "check", kind: body.kind, status: result.status, cached: result.cached, reason: result.reason ?? null,
      ms: Date.now() - started,
    }));
    return Response.json(result);
  },
};

function parse(value: unknown): CheckRequest | null {
  if (typeof value !== "object" || value === null) return null;
  const { kind, place } = value as Record<string, unknown>;
  if (!isKind(kind) || typeof place !== "object" || place === null) return null;
  const { id, name, address } = place as Record<string, unknown>;
  if (typeof name !== "string" || name.trim() === "" || name.length > 100) return null;
  if (address !== undefined && (typeof address !== "string" || address.length > 200)) return null;
  if (id !== undefined && (typeof id !== "string" || id.length > 200)) return null;
  return {
    kind,
    place: { id: id || undefined, name: name.trim(), address: (address as string | undefined)?.trim() || undefined },
  };
}
