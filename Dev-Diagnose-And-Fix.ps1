# Dev-Fix-LiteralPath.ps1
$ErrorActionPreference = "Stop"

function New-LiteralDir {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -LiteralPath $Path -Force | Out-Null
  }
}

function Write-TextLiteral {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Text
  )
  $parent = Split-Path -Parent $Path
  if ($parent) { New-LiteralDir -Path $parent }
  # ใช้ Set-Content หรือ Out-File ก็ได้ แต่ต้องเป็น -LiteralPath
  Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
  # หรือ: $Text | Out-File -LiteralPath $Path -Encoding utf8
}

# ---------- (1) ตรวจ Actix main.rs ว่ามี bind/run/health ----------
$main = ".\backend\src\main.rs"
if (!(Test-Path -LiteralPath $main)) { throw "ไม่พบ $main" }
$code = Get-Content -LiteralPath $main -Raw

$hasBind = ($code -match '\.bind\(\(\s*"0\.0\.0\.0"\s*,\s*8080\s*\)\)') -or
           ($code -match '\.bind\(\s*"0\.0\.0\.0:8080"\s*\)')
$hasRunAwait    = $code -match '\.run\(\)\s*\.await'
$hasHealthRoute = $code -match '"/healthz"'

if ($hasBind) { Write-Host "✅ bind 0.0.0.0:8080" -ForegroundColor Green } else { Write-Host "❌ ขาด bind 0.0.0.0:8080" -ForegroundColor Red }
if ($hasRunAwait) { Write-Host "✅ .run().await" -ForegroundColor Green } else { Write-Host "❌ ขาด .run().await" -ForegroundColor Red }
if ($hasHealthRoute) { Write-Host "✅ พบ /healthz" -ForegroundColor Green } else { Write-Host "❌ ยังไม่พบ /healthz (จะมีตัวอย่างให้ด้านล่าง)" -ForegroundColor Yellow }

# ---------- (2) เขียน Next proxy route แบบ literal ----------
$ProxyDir = ".\frontend\app\api\backend\[...path]"
$Proxy    = Join-Path $ProxyDir "route.ts"

$ProxyCode = @'
import type { NextRequest } from "next/server";

const TARGET = process.env.BACKEND_INTERNAL_URL || "http://backend-dev:8080";

async function forward(req: NextRequest, method: "GET"|"POST"|"PUT"|"DELETE"|"PATCH") {
  const path = req.nextUrl.pathname.replace(/^\/api\/backend/, "");
  const url = new URL(path + req.nextUrl.search, TARGET);
  const headers: Record<string, string> = {};
  req.headers.forEach((v, k) => (headers[k] = v));

  console.log(`[Next proxy] --> ${method} ${url.toString()}`);
  const init: RequestInit = { method, headers };

  if (method !== "GET") {
    const body = await req.text();
    init.body = body;
    const preview = body.length > 400 ? body.slice(0, 400) + "...(trimmed)" : body;
    console.log(`[Next proxy] body: ${preview}`);
  }

  const resp = await fetch(url.toString(), init);
  const buff = Buffer.from(await resp.arrayBuffer());
  console.log(`[Next proxy] <-- ${resp.status} (${buff.length} bytes) for ${url.toString()}`);

  return new Response(buff, { status: resp.status, headers: resp.headers });
}

export const GET = (req: NextRequest) => forward(req, "GET");
export const POST = (req: NextRequest) => forward(req, "POST");
export const PUT = (req: NextRequest) => forward(req, "PUT");
export const DELETE = (req: NextRequest) => forward(req, "DELETE");
export const PATCH = (req: NextRequest) => forward(req, "PATCH");
'@

New-LiteralDir -Path $ProxyDir
Write-TextLiteral -Path $Proxy -Text $ProxyCode
Write-Host "✅ เขียนไฟล์ (literal) $Proxy เรียบร้อย" -ForegroundColor Green

Write-Host "`n🎯 เสร็จสิ้นขั้นตอน literal-path. ต่อไปให้ลอง build อีกครั้ง:"
Write-Host "   docker compose -f docker-compose.dev.yml up --build" -ForegroundColor Cyan
