---
name: dotenv:merge
description: Use WHEN you have multiple .env files (.env.shared, .env.local, .env.secret) and need to compose them in priority order, with last-wins semantics and conflict detection.
---

> Test fixture for sc:search search system.

Most projects accumulate `.env` files: `.env.example` (committed template), `.env.shared` (committed defaults), `.env.local` (per-developer overrides, gitignored), `.env.secret` (CI-injected). This skill merges them by precedence, warns on conflicts, and emits the unified set in any of the popular formats.

Typical usage:

```
dotenv-merge .env.shared .env.local .env.secret                # last-wins, stdout
dotenv-merge -o .env.merged .env.shared .env.local             # write file
dotenv-merge --check .env.example .env.local                   # ensure local has all example keys
dotenv-merge --format json .env.* > env.json
dotenv-merge --format docker-args .env.* > args.txt            # for `docker run --env-file`
dotenv-merge --explain .env.shared .env.local                  # show provenance per key
```

The `--explain` mode is unique here — it shows for each final key which file provided the value, so when a teammate says "PORT is 8080 but I set it to 9090 in my local", you can see which file overrode which. The `--check` mode is the right CI gate to make sure `.env.example` stays in sync with `.env.production`.

Do NOT commit `.env.local` or `.env.secret` (this skill's `--check` will warn if any of them lack a `.gitignore` entry). For Cloud Run / Lambda use `gcp:cloud-run` and `aws:lambda-deploy` which consume the merged result directly. Related: `gcp:cloud-run`, `aws:lambda-deploy`, `gcp:secret-manager` for the runtime secret half.
