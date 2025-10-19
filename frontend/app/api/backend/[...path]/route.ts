import type { NextRequest } from "next/server";

// ให้รันบน Node (หลีกเลี่ยง Edge ที่อาจบล็อกบาง header/stream)
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const TARGET = process.env.BACKEND_INTERNAL_URL || "http://backend-dev:8080";
type Verb = "GET" | "HEAD" | "POST" | "PUT" | "DELETE" | "PATCH";

async function forward(req: NextRequest, method: Verb) {
  const path = req.nextUrl.pathname.replace(/^\/api\/backend/, "");
  const url  = new URL(path + req.nextUrl.search, TARGET);

  const headers: Record<string, string> = {};
  for (const [k, v] of req.headers.entries()) {
    const kl = k.toLowerCase();
    if (kl === "host" || kl === "content-length") continue;
    headers[k] = v;
  }
  // ปิดแคชเพื่อให้ dev ง่าย
  headers["cache-control"] = "no-store";

  const init: RequestInit = { method, headers };
  if (!new Set<Verb>(["GET","HEAD"]).has(method)) {
    init.body = await req.arrayBuffer(); // รองรับไบนารี
  }

  const resp = await fetch(url, init);          // ใช้สตรีมเดิม
  const out  = new Response(resp.body, { status: resp.status, headers: resp.headers });
  out.headers.set("Cache-Control", "no-store"); // กันถูกแคช
  return out;
}

export const GET    = (req: NextRequest) => forward(req, "GET");
export const HEAD   = (req: NextRequest) => forward(req, "HEAD");
export const POST   = (req: NextRequest) => forward(req, "POST");
export const PUT    = (req: NextRequest) => forward(req, "PUT");
export const DELETE = (req: NextRequest) => forward(req, "DELETE");
export const PATCH  = (req: NextRequest) => forward(req, "PATCH");