# -----------------------
# Builder stage
# -----------------------
FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    wget \
    ca-certificates \
    libboost-all-dev \
    libpqxx-dev \
    libpq-dev \
    libssl-dev \
    libsodium-dev \
    libhiredis-dev \
    libcurl4-openssl-dev \
    pkg-config \
    nlohmann-json3-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# copy project into container
COPY .. /app

# remove pre-copied host build artifacts if any
RUN rm -rf /app/build

# Install jwt-cpp (header) for build
COPY third_party/jwt-cpp /tmp/jwt-cpp
RUN set -eux; \
    mkdir -p /tmp/jwt-cpp/build; \
    cd /tmp/jwt-cpp/build; \
    cmake -DBUILD_TESTS=OFF -DCPPJWT_USE_PICOJSON=ON -DCMAKE_BUILD_TYPE=Release ..; \
    make -j"$(nproc)"; \
    make install

# Build the project
RUN mkdir -p /app/build \
 && cd /app/build \
 && cmake .. \
 && make -j"$(nproc)"

# Locate libpqxx shared objects for copying (if present)
# We'll canonicalize their paths into /tmp/libcopy for later COPY from builder->runtime
RUN set -eux; \
    mkdir -p /tmp/libcopy; \
    for f in $(ldconfig -p | awk '/libpqxx/ {print $4}' | sort -u); do \
      if [ -f "$f" ]; then cp -v "$f" /tmp/libcopy/ || true; fi; \
    done || true; \
    # also copy common candidate locations just in case
    for p in /usr/lib/x86_64-linux-gnu/libpqxx* /usr/local/lib/libpqxx*; do \
      if [ -f "$p" ]; then cp -v "$p" /tmp/libcopy/ || true; fi; \
    done || true; \
    ls -la /tmp/libcopy || true

# -----------------------
# Runtime stage
# -----------------------
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install runtime dependencies (including libpq runtime lib)
RUN apt-get update && apt-get install -y \
    libpq5 \
    libpq-dev \
    libpqxx-dev \
    libsodium23 \
    libhiredis-dev \
    libssl3 \
    python3 \
    openssl \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*
# Copy compiled binary & keys from builder
COPY --from=builder /app/build/user_management_service /usr/local/bin/user_management_service
COPY --from=builder /app/build/user_management_tests /usr/local/bin/user_management_tests

# Generate RSA keypair for JWT signing inside the container
RUN mkdir -p /usr/local/bin/keys \
    && openssl genrsa -out /usr/local/bin/keys/private.pem 2048 \
    && openssl rsa -in /usr/local/bin/keys/private.pem -pubout -out /usr/local/bin/keys/public.pem \
    && chmod 600 /usr/local/bin/keys/private.pem \
    && chmod 644 /usr/local/bin/keys/public.pem

# Copy any libpqxx shared libs found in the builder into runtime library dir,
# then run ldconfig so the runtime loader can find them.
COPY --from=builder /tmp/libcopy/ /usr/local/lib/
RUN chmod +x /usr/local/bin/user_management_service || true && ldconfig

WORKDIR /usr/local/bin

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/user_management_service"]
