use actix_cors::Cors;
use actix_web::{
    body::{BoxBody, EitherBody},
    dev::{ServiceRequest, ServiceResponse},
    http::header::{CONTENT_TYPE, RETRY_AFTER},
    middleware::Logger,
    web::{self, Data, Json, Bytes},
    App, HttpRequest, HttpResponse, HttpServer, Responder, Result,
};
use chrono::Utc;
use futures_util::Stream;
use rand::{thread_rng, Rng};
use serde::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    net::IpAddr,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

#[derive(Clone)]
struct RateCfg { max: usize, window: Duration }
#[derive(Clone)]
struct AppState {
    hits: Arc<Mutex<HashMap<IpAddr, Vec<Instant>>>>,
    cfg: RateCfg,
    api_key: String,
}

fn client_ip(req: &HttpRequest) -> Option<IpAddr> {
    req.peer_addr().map(|s| s.ip())
}

#[actix_web::get("/healthz")]
async fn healthz() -> impl Responder { HttpResponse::Ok().body("ok") }

#[derive(Deserialize)]
struct HelloQ { name: Option<String> }

#[actix_web::get("/api/hello")]
async fn hello(q: web::Query<HelloQ>) -> impl Responder {
    let who = q.name.clone().unwrap_or_else(|| "World".into());
    HttpResponse::Ok().body(format!("Hello, {who}!"))
}

#[derive(Deserialize)]
struct AddQ { a: i64, b: i64 }

#[actix_web::get("/api/add")]
async fn add(q: web::Query<AddQ>) -> impl Responder {
    HttpResponse::Ok().json(serde_json::json!({ "a": q.a, "b": q.b, "sum": q.a + q.b }))
}

#[derive(Serialize)]
struct UserResp { id: i64, name: String, at: String }

#[actix_web::get("/api/user/{id}")]
async fn user(path: web::Path<(i64,)>) -> impl Responder {
    let (id,) = path.into_inner();
    HttpResponse::Ok().json(UserResp {
        id,
        name: format!("User #{id}"),
        at: Utc::now().to_rfc3339(),
    })
}

#[actix_web::get("/api/time")]
async fn time_now() -> impl Responder {
    HttpResponse::Ok().body(format!("{}", chrono::Utc::now().timestamp()))
}

#[actix_web::post("/api/echo")]
async fn echo_txt(body: String) -> impl Responder {
    HttpResponse::Ok().body(format!("ECHO: {body}"))
}

#[derive(Deserialize, Serialize)]
struct EchoJson { message: String, tags: Option<Vec<String>>, #[serde(default)] urgent: bool }

#[actix_web::post("/api/json")]
async fn echo_json(Json(p): Json<EchoJson>) -> impl Responder {
    HttpResponse::Ok().json(serde_json::json!({
        "received": p,
        "at": Utc::now().to_rfc3339()
    }))
}

// Bytes streaming: ต้องเป็น Stream<Item=Result<Bytes, E>>
#[actix_web::get("/api/bytes")]
async fn bytes_stream(q: web::Query<HashMap<String, String>>) -> impl Responder {
    let kb: usize = q.get("kb").and_then(|s| s.parse().ok()).unwrap_or(1);
    let total = kb * 1024;
    let chunk = vec![b'X'; 1024];

    let stream = futures_util::stream::unfold((0usize, total, chunk), |(mut sent, total, chunk)| async move {
        if sent >= total { return None; }
        let left = (total - sent).min(1024);
        sent += left;
        actix_web::rt::time::sleep(Duration::from_millis(30)).await;
        let bytes = Bytes::copy_from_slice(&chunk[..left]);
        Some((Ok::<Bytes, std::io::Error>(bytes), (sent, total, chunk)))
    });

    HttpResponse::Ok()
        .insert_header((CONTENT_TYPE, "application/octet-stream"))
        .insert_header(("Content-Disposition", format!("attachment; filename=sample_{kb}KB.bin")))
        .streaming(stream)
}

#[actix_web::get("/api/slow")]
async fn slow(q: web::Query<HashMap<String, String>>) -> impl Responder {
    let ms: u64 = q.get("ms").and_then(|s| s.parse().ok()).unwrap_or(1500);
    actix_web::rt::time::sleep(Duration::from_millis(ms)).await;
    HttpResponse::Ok().json(serde_json::json!({"slept_ms": ms}))
}

#[actix_web::get("/api/flaky")]
async fn flaky() -> impl Responder {
    let mut rng = thread_rng();
    let ok: bool = rng.gen_bool(0.5);
    if ok {
        HttpResponse::Ok().json(serde_json::json!({"ok": true}))
    } else {
        HttpResponse::InternalServerError().json(serde_json::json!({"ok": false, "err": "random fail"}))
    }
}

// SSE: Stream<Item=Result<Bytes, _>>
#[actix_web::get("/api/sse")]
async fn sse() -> Result<HttpResponse> {
    let mut i = 0usize;
    let stream = futures_util::stream::unfold((), move |_| async move {
        if i >= 10 { return None; }
        i += 1;
        actix_web::rt::time::sleep(Duration::from_secs(1)).await;
        let msg = format!("data: hello {i}\n\nevent: tick\ndata: {i}\n\n");
        Some((Ok::<Bytes, std::io::Error>(Bytes::from(msg)), ()))
    });

    Ok(HttpResponse::Ok()
        .append_header((CONTENT_TYPE, "text/event-stream"))
        .append_header(("Cache-Control", "no-store"))
        .streaming(stream))
}

// Secure route
#[actix_web::get("/api/secure/ping")]
async fn secure_ping() -> impl Responder {
    HttpResponse::Ok().json(serde_json::json!({"secure": true, "msg": "pong"}))
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    std::env::set_var("RUST_LOG", std::env::var("RUST_LOG").unwrap_or_else(|_| "info,actix_web=info".into()));
    std::env::set_var("RUST_BACKTRACE", "1");
    env_logger::init();

    let state = AppState{
        hits: Arc::new(Mutex::new(HashMap::new())),
        cfg: RateCfg { max: 10, window: Duration::from_secs(10) },
        api_key: std::env::var("API_KEY").unwrap_or_else(|_| "dev123".into()),
    };

    println!("===> Actix listening on 0.0.0.0:8080");

    HttpServer::new(move || {
        App::new()
            .wrap(Logger::default())
            .wrap(Cors::permissive())
            .app_data(Data::new(state.clone()))
            // ---- Rate Limit (wrap_fn) ----
            .wrap_fn(|mut req, srv| {
                let state = req.app_data::<Data<AppState>>().cloned();
                async move {
                    if let Some(state) = state {
                        if let Some(ip) = client_ip(req.head()) {
                            let mut map = state.hits.lock().unwrap();
                            let now = Instant::now();
                            let window = state.cfg.window;
                            let v = map.entry(ip).or_default();
                            v.retain(|t| now.duration_since(*t) < window);
                            if v.len() >= state.cfg.max {
                                let mut resp = HttpResponse::TooManyRequests().body("rate limit exceeded");
                                resp.headers_mut().insert(RETRY_AFTER, "2".parse().unwrap());
                                return Ok(ServiceResponse::new(req.into_parts().0, resp.map_into_right_body()));
                            }
                            v.push(now);
                        }
                    }
                    let res = srv.call(req).await?;
                    Ok(res.map_into_left_body())
                }
            })
            // ---- Secure header check (wrap_fn) ----
            .wrap_fn(|mut req, srv| {
                let need_check = req.path().starts_with("/api/secure/");
                let api_key = req.app_data::<Data<AppState>>().map(|d| d.api_key.clone());
                async move {
                    if need_check {
                        let ok = req.headers()
                            .get("x-api-key")
                            .and_then(|v| v.to_str().ok())
                            .map(|v| Some(v.to_string()) == api_key)
                            .unwrap_or(false);
                        if !ok {
                            let resp = HttpResponse::Unauthorized().body("missing/invalid x-api-key");
                            return Ok(ServiceResponse::new(req.into_parts().0, resp.map_into_right_body()));
                        }
                    }
                    let res = srv.call(req).await?;
                    Ok(res.map_into_left_body())
                }
            })
            .service(healthz)
            .service(hello)
            .service(add)
            .service(user)
            .service(time_now)
            .service(echo_txt)
            .service(echo_json)
            .service(bytes_stream)
            .service(slow)
            .service(flaky)
            .service(sse)
            .service(secure_ping)
    })
    .workers(12)
    .bind(("0.0.0.0", 8080))?
    .run().await
}