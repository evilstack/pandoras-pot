# syntax=docker/dockerfile:1
# Keep in sync with DEBIAN_RELEASE in the workflow; the builder and runtime
# must share a Debian release so the binary never needs a newer glibc than
# the runtime image provides.
ARG DEBIAN_RELEASE=trixie

# --- Stage 1: cargo-chef base (tooling layer, cached) ---
FROM rust:1-${DEBIAN_RELEASE} AS chef
RUN cargo install cargo-chef --locked
WORKDIR /usr/src/pandoras_pot

# --- Stage 2: compute the dependency recipe ---
FROM chef AS planner
COPY upstream/Cargo.toml upstream/Cargo.lock ./
COPY upstream/src ./src
RUN cargo chef prepare --recipe-path recipe.json

# --- Stage 3: build deps (cached), then the binary ---
FROM chef AS builder
# Smaller, faster binary without modifying upstream's Cargo.toml
ENV CARGO_PROFILE_RELEASE_LTO=true \
    CARGO_PROFILE_RELEASE_STRIP=true \
    CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1

# Dependencies only: this layer is reused until Cargo.toml/Cargo.lock change
COPY --from=planner /usr/src/pandoras_pot/recipe.json recipe.json
RUN cargo chef cook --release --locked --recipe-path recipe.json

# Copy source
COPY upstream/Cargo.toml upstream/Cargo.lock ./
COPY upstream/src ./src

# Copy config and markov corpus
COPY config/config.toml ./
COPY markov/liber.txt ./

# Set build args
ARG CONFIG="config.toml"
ARG DATA="liber.txt"

RUN cargo build --release --locked

# --- Stage 4: Debian runtime image ---
FROM debian:${DEBIAN_RELEASE}-slim

RUN groupadd --system -g 10666 satan \
    && useradd --system -u 10666 --gid satan \
        --shell /usr/sbin/nologin --no-create-home satan

WORKDIR /hell

COPY --link --from=builder /usr/src/pandoras_pot/target/release/pandoras_pot /hell/pandoras_pot
COPY --link config/config.toml /hell/config.toml
COPY --link markov/ /hell/

USER 10666:10666

EXPOSE 8080

CMD ["./pandoras_pot", "--config", "config.toml"]
