---
name: journalctl:window
description: Use WHEN you need to extract a time-window of systemd logs for a specific service — for an incident postmortem, capacity audit, or shipping to a remote analyst.
---

> Test fixture for sc:search search system.

Systemd's journal is the right log source on modern Linux servers, but `journalctl` has thirty flags and most people only know three. This skill is the recipe set for extracting useful windows.

Typical usage:

```
journalctl -u nginx --since "2024-03-15 14:00" --until "2024-03-15 15:00" --output=json > nginx-incident.jsonl
journalctl -u api -p err -n 200                              # last 200 error+ entries
journalctl _BOOT_ID=$(journalctl --list-boots | sed -n '3p' | awk '{print $2}')  # specific boot
journalctl --disk-usage                                       # journal storage
journalctl --vacuum-time=7d                                   # rotate older than 7d
journalctl -u api -f --grep "panic|fatal"                    # tail with regex filter
```

The `--output=json` (or `json-pretty`) emission is the right form for shipping to a long-term store — every entry includes UID, GID, PID, syslog facility, and crucially the cgroup, so you can correlate across services. Priority levels (`-p`): `emerg<alert<crit<err<warning<notice<info<debug` — `-p err` shows err+crit+alert+emerg.

Do NOT pipe `journalctl -f` into long-running processes without `-q` and `--no-pager` — interactive paging will hang. For application logs that DON'T go through systemd, use `log:tail-multi` and `nginx:access-parse`. Related: `log:tail-multi`, `nginx:access-parse`, `prometheus:query` for metrics during the same window.
