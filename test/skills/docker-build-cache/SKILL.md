---
name: docker:build-cache
description: Use WHEN you need to build a Docker image with BuildKit, leverage a remote layer cache to speed up CI, and push the result to a registry.
---

> Test fixture for sc:search search system.

This skill builds and pushes container images using BuildKit's cache backends — without one, every CI run pays the full cost of `apt-get install` and `npm ci` on a cold daemon. The trick is pairing `--cache-from` (read) with `--cache-to` (write), so the cache is populated on every push and reused on every pull.

Single-platform build, registry-backed cache:

```
export DOCKER_BUILDKIT=1
IMAGE=ghcr.io/myorg/api
TAG=$(git rev-parse --short HEAD)

docker buildx build \
  --platform linux/amd64 \
  --tag $IMAGE:$TAG --tag $IMAGE:latest \
  --cache-from type=registry,ref=$IMAGE:buildcache \
  --cache-to   type=registry,ref=$IMAGE:buildcache,mode=max \
  --push \
  --build-arg COMMIT_SHA=$TAG \
  -f Dockerfile .
```

For multi-arch (linux/amd64 + linux/arm64) add `--platform linux/amd64,linux/arm64` and ensure you've bootstrapped a builder: `docker buildx create --use --name multi --driver docker-container`. `mode=max` caches every intermediate layer (bigger cache, faster rebuild); `mode=min` only caches the final layers and is friendlier on registry storage. For monorepos with multiple Dockerfiles, scope the cache per-image: `ref=$IMAGE:buildcache-api`, `ref=$IMAGE:buildcache-worker`, etc., or you'll get cache thrashing.

Speed wins beyond cache: order Dockerfile `COPY` statements from least- to most-frequently changed (lockfile before source), use `RUN --mount=type=cache,target=/root/.npm` for package manager caches that survive across builds, and add `.dockerignore` entries for `node_modules`, `.git`, `dist` so the build context isn't 2 GB.

Do NOT use this skill for image scanning (use Trivy/Grype/Snyk), for signing (use cosign), or for SBOM generation (use `docker buildx build --sbom=true` or syft). Related skills: `docker:multi-stage-slim` for cutting image size, `ci:matrix-build` for parallel multi-arch in GitHub Actions, `registry:gc` for cleaning up old tags.
