param(
  [string]$ProjectPath = (Get-Location).Path,     # ปกติใช้โฟลเดอร์ปัจจุบัน
  [string]$RepoName = "",                         # ตั้งชื่อ repo ถ้าจะให้ gh สร้าง (เว้นค่าว่างถ้าใช้ RemoteUrl)
  [switch]$Private,                               # ใช้คู่กับ RepoName; ถ้าใส่จะสร้างแบบ private
  [string]$RemoteUrl = ""                         # ใส่ URL ถ้าจะผูกกับ repo ที่มีอยู่แล้ว
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# 0) ตรวจเครื่องมือ
function Test-Exists($name){ (Get-Command $name -ErrorAction SilentlyContinue) -ne $null }
if (-not (Test-Exists git)) { throw "ไม่พบ 'git' ใน PATH — ติดตั้ง Git ก่อนแล้วลองใหม่" }

$HasGh = Test-Exists gh

# 1) ไปยังโฟลเดอร์โปรเจกต์
Set-Location -Path $ProjectPath

# 2) เขียนไฟล์สำคัญ (.gitignore / .gitattributes / .dockerignore / README.md) ถ้ายังไม่มี
#    ครอบคลุม Next.js + Node, Rust/Actix, Docker, และสิ่งแวดล้อม dev บน Windows
if (-not (Test-Path ".gitignore")) {
@'
# ===== Global OS / Editor =====
.DS_Store
Thumbs.db
*.log
*.tmp
*.swp
*.swo
.npmrc
.vscode/
.idea/

# ===== Node / Next.js =====
frontend/node_modules/
frontend/.next/
frontend/.turbo/
frontend/.vercel/
frontend/.cache/
frontend/dist/
frontend/coverage/

# env
frontend/.env.local
frontend/.env.development.local
frontend/.env.test.local
frontend/.env.production.local
frontend/.env

# ===== Rust / Cargo =====
backend/target/
backend/.cargo/
**/*.rs.bk

# ===== Docker =====
*.env
**/.env
**/.env.*
docker-compose.override.yml

# ===== OS-specific =====
*.orig
*.rej

# ===== Misc build =====
**/build/
**/dist/
**/tmp/
**/coverage/
'@ | Out-File -Encoding utf8 .gitignore
}

if (-not (Test-Path ".gitattributes")) {
@'
# บังคับ normalize เป็น LF ใน repo (Windows จะ checkout เป็น CRLF ตาม core.autocrlf)
* text=auto

# บางไฟล์ให้เก็บเป็น binary
*.png binary
*.jpg binary
*.jpeg binary
*.gif binary
*.ico binary
*.pdf binary
'@ | Out-File -Encoding utf8 .gitattributes
}

if (-not (Test-Path ".dockerignore")) {
@'
# ไม่ให้ Docker context บวม
.git
.gitignore
.gitattributes
**/node_modules
**/target
**/dist
**/.next
**/.env
**/.env.*
Dockerfile*
docker-compose*.yml
README.md
'@ | Out-File -Encoding utf8 .dockerignore
}

if (-not (Test-Path "README.md")) {
@"
# Actix (Rust) + Next.js (Docker Dev Stack)

## โครงสร้าง
- \`backend\` — Actix-web (Rust) + healthcheck + ตัวอย่าง endpoint (hello/add/user/time/bytes/sse/secure)
- \`frontend\` — Next.js App Router พร้อม proxy API \`/api/backend/*\` ไป \`http://backend-dev:8080\` (ภายใน docker network)
- \`docker-compose.dev.yml\` — dev stack (backend-dev, frontend-dev, network \`appnet\`)

## รัน dev
\`\`\`bash
docker compose -f docker-compose.dev.yml up --build
# เปิด http://localhost:3000
# Backend health: http://localhost:8080/healthz
\`\`\`

## ตัวแปรสำคัญ (ฝั่ง frontend)
- \`NEXT_PUBLIC_API_URL=/api/backend\` (เรียกผ่าน Next API proxy)
- \`BACKEND_INTERNAL_URL=http://backend-dev:8080\` (วิ่งภายใน network ของ Docker)

## ตัวแปรสำคัญ (ฝั่ง backend)
- \`RUST_LOG\`, \`RUST_BACKTRACE\`, \`API_KEY\` (เช่น \`dev123\`)

## โปรดอ่าน
- ใน dev เรา proxy ผ่าน \`/api/backend/*\` เพื่อให้ client-side ทำงานแม้ backend จะอยู่ใน container
- สำหรับ production แนะนำแยก compose/traefik/nginx หรือปรับ NEXT_PUBLIC_* ให้ชี้ domain จริง
"@ | Out-File -Encoding utf8 README.md
}

# 3) git init + config เบื้องต้น
if (-not (Test-Path ".git")) {
  git init | Out-Null
}

# ตั้งค่าเพื่อกันปัญหา CRLF
git config core.autocrlf true | Out-Null
git config core.longpaths true | Out-Null

# 4) สร้าง commit แรก (idempotent: ถ้าไม่มีอะไรเปลี่ยน จะไม่ล้ม)
git add -A
try {
  git commit -m "Initial commit: Actix + Next dev stack (Docker dev)" | Out-Null
} catch {
  Write-Host "ไม่มีไฟล์ใหม่ให้ commit (อาจเคย commit แล้ว)" -ForegroundColor Yellow
}

# 5) สร้าง/ผูก remote
$hasRemote = git remote | Select-String -Quiet "origin"

if ($RemoteUrl -and -not $hasRemote) {
  git remote add origin $RemoteUrl
} elseif ($RepoName -and $HasGh -and -not $hasRemote) {
  # ใช้ gh สร้าง repo แล้วผูกอัตโนมัติ
  $visibility = $(if ($Private) { "private" } else { "public" })
  # ถ้ายังไม่ได้ login: gh auth login
  gh repo create $RepoName --$visibility --source "$ProjectPath" --remote origin --push
} elseif (-not $hasRemote -and -not $RemoteUrl -and -not $RepoName) {
  Write-Host "`n[คำแนะนำ] ยังไม่ได้ตั้ง remote: ใส่ -RemoteUrl หรือ -RepoName เพื่อให้สคริปต์ push ให้ได้เลย" -ForegroundColor Yellow
}

# 6) push (ถ้ามี remote แล้ว)
$hasRemote = git remote | Select-String -Quiet "origin"
if ($hasRemote) {
  # ตั้งชื่อ branch main ถ้ายังไม่ใช่
  $curBranch = (git branch --show-current)
  if (-not $curBranch) { git checkout -b main | Out-Null }
  elseif ($curBranch -ne "main") { git branch -M main | Out-Null }

  git push -u origin main
  Write-Host "`n✅ สำเร็จ: push ขึ้น origin/main แล้ว" -ForegroundColor Green
} else {
  Write-Host "`nℹ️ ยังไม่ได้ push เพราะไม่มี remote origin — ระบุ -RemoteUrl หรือ -RepoName แล้วรันใหม่" -ForegroundColor Yellow
}

# 7) แถม: สร้าง .env.example (ช่วย onboard ทีม)
if (-not (Test-Path "frontend\.env.example")) {
@'
# Frontend (Next.js)
NODE_ENV=development
PORT=3000
NEXT_PUBLIC_API_URL=/api/backend
BACKEND_INTERNAL_URL=http://backend-dev:8080
'@ | Out-File -Encoding utf8 "frontend\.env.example"
}

if (-not (Test-Path "backend\.env.example")) {
@'
# Backend (Actix)
RUST_LOG=info,actix_web=info
RUST_BACKTRACE=1
API_KEY=dev123
'@ | Out-File -Encoding utf8 "backend\.env.example"
}

Write-Host "`n🎉 เสร็จสิ้นสคริปต์ตั้งค่า Git/GitHub + ไฟล์ ignore/attrs/dockerignore + README" -ForegroundColor Green
