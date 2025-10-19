param(
  [string]$RepoPath = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Folder($p) { if (-not (Test-Path $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null } }

# 0) ตรวจเครื่องมือ + เข้าโฟลเดอร์โปรเจกต์
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  throw "ไม่พบ 'git' ใน PATH — ติดตั้ง Git ก่อนแล้วลองใหม่"
}
Set-Location -Path $RepoPath

# 1) เตรียมข้อมูล owner/repo จาก remote origin (เพื่อทำ badge)
$originUrl = ""
$owner = ""
$repo  = ""
try {
  $originUrl = (git remote get-url origin).Trim()
  if ($originUrl -match "github\.com[:/](?<owner>[^/]+)/(?<repo>[^/.]+)"){
    $owner = $Matches['owner']
    $repo  = $Matches['repo']
  }
} catch {}

# 2) สร้างไฟล์ LICENSE (MIT)
$year = (Get-Date).Year
$author = "Phakin Khammawong"  # ปรับได้ตามต้องการ
$licensePath = Join-Path $RepoPath "LICENSE"
$mit = @"
MIT License

Copyright (c) $year $author

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"@
$mit | Out-File -Encoding utf8 $licensePath

# 3) สร้าง .env.example (ถ้ายังไม่มี)
Ensure-Folder "frontend"
$feEnv = @'
# Frontend (Next.js)
NODE_ENV=development
PORT=3000
NEXT_PUBLIC_API_URL=/api/backend
BACKEND_INTERNAL_URL=http://backend-dev:8080
'@
$feEnvPath = "frontend\.env.example"
if (-not (Test-Path $feEnvPath)) { $feEnv | Out-File -Encoding utf8 $feEnvPath }

Ensure-Folder "backend"
$beEnv = @'
# Backend (Actix)
RUST_LOG=info,actix_web=info
RUST_BACKTRACE=1
API_KEY=dev123
'@
$beEnvPath = "backend\.env.example"
if (-not (Test-Path $beEnvPath)) { $beEnv | Out-File -Encoding utf8 $beEnvPath }

# 4) สร้าง GitHub Actions CI
Ensure-Folder ".github"
Ensure-Folder ".github/workflows"
$ciPath = ".github/workflows/ci.yml"
$ciYml = @"
name: CI

on:
  push:
    branches: [ "main" ]
  pull_request:
    branches: [ "main" ]

jobs:
  backend:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: backend
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - name: Cargo check
        run: cargo check --locked
      - name: Cargo build (release)
        run: cargo build --release --locked

  frontend:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: frontend
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 'current'
          cache: 'npm'
          cache-dependency-path: 'frontend/package-lock.json'
      - name: Install
        run: npm ci
      - name: Type check
        run: npx tsc --noEmit
      - name: Next build
        run: npm run build

  docker-dev-build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Docker build (dev compose)
        run: docker compose -f docker-compose.dev.yml build
"@
$ciYml | Out-File -Encoding utf8 $ciPath -Force

# 5) ลบไฟล์สำรองที่ไม่จำเป็นถ้ามี
$junk = @(
  "docker-compose.yml.bak",
  ".DS_Store",
  "Thumbs.db"
)
$deleted = @()
foreach($f in $junk){
  if (Test-Path $f) { Remove-Item -Force $f; $deleted += $f }
}

# 6) แทรก Badges ลง README (เฉพาะถ้ารู้ owner/repo และยังไม่มี badge)
$readme = "README.md"
if (Test-Path $readme) {
  $content = Get-Content $readme -Raw
  $badgeMarker = "<!-- badges -->"
  if ($owner -and $repo -and ($content -notmatch [regex]::Escape($badgeMarker))) {
    $badges = @"
$badgeMarker
[![CI](https://github.com/$owner/$repo/actions/workflows/ci.yml/badge.svg)](https://github.com/$owner/$repo/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

"@
    # แทรก badges ไว้บนสุดของ README (backup ไฟล์เดิมก่อน)
    Copy-Item $readme "$readme.bak" -Force
    ($badges + $content) | Out-File -Encoding utf8 $readme
  }
}

# 7) ตั้งค่า Git เบื้องต้น + เปลี่ยน branch เป็น main
git config core.autocrlf true | Out-Null
git config core.longpaths true | Out-Null

# ถ้ายังไม่ได้ commit เริ่มต้น ให้ add ไฟล์ด้วย
git add -A
try { git commit -m "chore: repo hardening (MIT LICENSE, env examples, CI, cleanup, badges)" | Out-Null } catch {}

# สลับ/บังคับชื่อสาขาเป็น main
$cur = (git branch --show-current)
if (-not $cur) { git checkout -b main | Out-Null }
elseif ($cur -ne "main") { git branch -M main | Out-Null }

# 8) push ขึ้น origin/main (ถ้ามี remote)
$hasRemote = git remote | Select-String -Quiet "^origin$"
if ($hasRemote) {
  git push -u origin main
  Write-Host "`n✅ สำเร็จ: อัปเดตไฟล์ + push ขึ้น origin/main แล้ว" -ForegroundColor Green
  if ($deleted.Count -gt 0) {
    Write-Host ("   (ลบไฟล์: " + ($deleted -join ", ") + ")")
  }
} else {
  Write-Host "`nℹ️ ยังไม่ได้ push เพราะไม่มี remote 'origin' — ให้ตั้ง remote ก่อนแล้วรันสคริปต์ซ้ำ" -ForegroundColor Yellow
}
