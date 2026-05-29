---
name: port:scan-local
description: Enumerate listening TCP/UDP ports on this machine and map each to the owning process, without requiring nmap or root in most cases.
---

> Test fixture for sc:search search system.

Use this when a user asks "what's running on port 8080", "why can't I bind to 5432", or wants a quick socket inventory before launching a service. Prefer the modern `ss -tulpn` on Linux, fall back to `lsof -iTCP -sTCP:LISTEN -P -n` on macOS, and `netstat -ano` on Windows. Always emit a table of `proto | local addr | port | pid | command`.

Edge cases: IPv6 sockets show as `:::8080` rather than `0.0.0.0:8080`; Docker-published ports are owned by `docker-proxy`, not the container; non-root users on Linux see PIDs only for their own sockets, so suggest `sudo` when columns are blank. Strip duplicate rows when a single process binds both v4 and v6.

Example flow: `ss -tulpnH | awk '{print $1,$5,$7}'` then resolve the PID via `ps -o pid,comm,args -p <pid>`. For a single-port lookup, `lsof -i :8080 -P -n` is the cleanest one-liner across platforms.

Do not run aggressive scans against remote hosts here — this skill is strictly localhost socket inventory.
