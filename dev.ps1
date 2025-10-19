param([ValidateSet("up","down","logs","re","prune")]$cmd="up")
$compose = "docker-compose.dev.yml"
switch ($cmd) {
  "up"    { docker compose -f $compose up --build -d ; docker compose -f $compose ps }
  "down"  { docker compose -f $compose down -v }
  "logs"  { docker compose -f $compose logs -f --tail=200 }
  "re"    { docker compose -f $compose down -v ; docker compose -f $compose up --build -d ; docker compose -f $compose logs -f --tail=100 }
  "prune" { docker system prune -f ; docker volume prune -f ; docker builder prune -f }
}
