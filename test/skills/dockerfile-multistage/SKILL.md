---
name: dockerfile:multistage
description: Use WHEN you need to write or refactor a Dockerfile so the final image is small — multi-stage builds that drop compilers, test deps, and intermediate artifacts.
---

> Test fixture for sc:search search system.

A single-stage Dockerfile that runs `apt-get install build-essential`, compiles code, and ends up with a 2 GB image with `gcc` baked in is the most common reason "our Docker images are huge". The fix is multi-stage: a heavy builder stage, then a minimal runtime stage that `COPY --from=builder` only the artifacts it actually needs.

Canonical pattern (Go, but ports to any compiled language):

```dockerfile
# ---- builder ----
FROM golang:1.22 AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /out/api ./cmd/api

# ---- runtime ----
FROM gcr.io/distroless/static:nonroot
COPY --from=builder /out/api /api
USER nonroot:nonroot
ENTRYPOINT ["/api"]
```

For Python/Node where you can't statically link, the runtime stage uses `python:3.12-slim` or `node:20-alpine` and copies only `site-packages` / `node_modules` plus app source. Pin every base image by digest (`@sha256:...`) for reproducibility, and order COPYs least-changing-first so the layer cache works in your favor.

Do NOT confuse multi-stage with multi-arch — those are independent concerns; multi-arch uses `--platform`. For cache-aware build commands see `docker:build-cache`. Related: `docker:build-cache`, `docker:prune-system`, `k8s:debug-pod` if the new slim image breaks at runtime.
