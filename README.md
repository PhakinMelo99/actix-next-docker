# Actix (Rust) + Next.js (Docker Dev Stack)

## โครงสร้าง
- \ackend\ — Actix-web (Rust) + healthcheck + ตัวอย่าง endpoint (hello/add/user/time/bytes/sse/secure)
- \rontend\ — Next.js App Router พร้อม proxy API \/api/backend/*\ ไป \http://backend-dev:8080\ (ภายใน docker network)
- \docker-compose.dev.yml\ — dev stack (backend-dev, frontend-dev, network \ppnet\)

## รัน dev
\\\ash
docker compose -f docker-compose.dev.yml up --build
# เปิด http://localhost:3000
# Backend health: http://localhost:8080/healthz
\\\

## ตัวแปรสำคัญ (ฝั่ง frontend)
- \NEXT_PUBLIC_API_URL=/api/backend\ (เรียกผ่าน Next API proxy)
- \BACKEND_INTERNAL_URL=http://backend-dev:8080\ (วิ่งภายใน network ของ Docker)

## ตัวแปรสำคัญ (ฝั่ง backend)
- \RUST_LOG\, \RUST_BACKTRACE\, \API_KEY\ (เช่น \dev123\)

## โปรดอ่าน
- ใน dev เรา proxy ผ่าน \/api/backend/*\ เพื่อให้ client-side ทำงานแม้ backend จะอยู่ใน container
- สำหรับ production แนะนำแยก compose/traefik/nginx หรือปรับ NEXT_PUBLIC_* ให้ชี้ domain จริง
