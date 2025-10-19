# --- Builder: build a fully-static binary with MUSL ---
FROM rust:1.82-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    musl-tools pkg-config build-essential ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# add musl target
RUN rustup target add x86_64-unknown-linux-musl

WORKDIR /app

# cache deps
COPY Cargo.toml Cargo.lock ./
RUN mkdir -p src && echo "fn main() {}" > src/main.rs && \
    cargo build --release --target x86_64-unknown-linux-musl || true

# real source
COPY src ./src

# build static binary
ENV RUSTFLAGS="-C target-feature=+crt-static"
RUN cargo build --release --target x86_64-unknown-linux-musl

# --- Runtime: distroless static (nonroot) ---
FROM gcr.io/distroless/static:nonroot

# app dir (not strictly needed, but tidy)
WORKDIR /app

# copy static binary
COPY --from=builder /app/target/x86_64-unknown-linux-musl/release/backend /usr/local/bin/backend

# nonroot user is default in this image; expose port
EXPOSE 8080

# health by compose (optional)
ENTRYPOINT ["/usr/local/bin/backend"]
