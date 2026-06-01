# melting-pot tier helpers — POSIX sh. Recognises ONLY N-melting-pot/ dirs
# (where N ∈ 0..5) as native tier content. Bare N/ dirs are deliberately
# ignored (Q-007) to avoid colliding with random numbered subdirectories in
# third-party repos.
#
# SKILL.md is treated as tier-5 content alongside any 5-melting-pot/*.md files
# at the same tier — they merge alphabetically, neither shadows the other.
#
# Sourced after discover.sh (depends on mp_warn / mp_log / mp_has_tier_dirs).

# ----- walk_tier_dirs <skill-dir>: emit TSV `<tier>\t<chunk-path>` per chunk -----
# Walks all six possible tier dirs in numeric order; within each tier emits
# chunks alphabetically by basename. The SKILL.md (if present at the skill
# root) is emitted under tier 5 alongside any 5-melting-pot/*.md files.
#
# Symlinked tier dirs (Q-007 upstream linkage) work transparently — `find -L`
# follows links so the chunks under upstream/N-melting-pot/ are walked.
mp_walk_tier_dirs() {
  d="$1"
  [ -d "$d" ] || return 0
  for n in 0 1 2 3 4 5; do
    td="$d/${n}-melting-pot"
    [ -d "$td" ] || continue
    # `find -L` follows symlinks so symlinked upstream tier dirs work.
    find -L "$td" -maxdepth 1 -type f -name '*.md' 2>/dev/null \
      | sort \
      | while IFS= read -r f; do
          printf "%s\t%s\n" "$n" "$f"
        done
  done
  # SKILL.md merges into tier 5 (alongside any 5-melting-pot/*.md). Emit it
  # AFTER 5-melting-pot/*.md so the alphabetical sort happens at the caller's
  # discretion if it cares — we keep the emission ordered by tier first.
  if [ -f "$d/SKILL.md" ]; then
    printf "5\t%s\n" "$d/SKILL.md"
  fi
}

# ----- list_tiers_present <skill-dir>: emit comma-joined sorted tier list -----
# e.g. "0,2,5" for a skill with chunks at tier 0, 2, 5 (no 1,3,4).
# Returns empty string if no tier dirs and no SKILL.md.
mp_list_tiers_present() {
  d="$1"
  tmp=$(mktemp -t mp_tiers.XXXXXX)
  : > "$tmp"
  for n in 0 1 2 3 4 5; do
    td="$d/${n}-melting-pot"
    if [ -d "$td" ]; then
      # Count chunks under this tier (follow symlinks).
      cnt=$(find -L "$td" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
      if [ "$cnt" -gt 0 ]; then
        printf "%s\n" "$n" >> "$tmp"
      fi
    fi
  done
  if [ -f "$d/SKILL.md" ]; then
    printf "5\n" >> "$tmp"
  fi
  sort -u "$tmp" | awk '{a=a","$0} END{print substr(a,2)}'
  rm -f "$tmp"
}

# ----- count_chunks <skill-dir>: total .md chunks across all tiers -----
# Counts SKILL.md as +1 only if present (independent of any 5-melting-pot/*.md).
mp_count_chunks() {
  d="$1"
  c=0
  for n in 0 1 2 3 4 5; do
    td="$d/${n}-melting-pot"
    [ -d "$td" ] || continue
    cnt=$(find -L "$td" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
    c=$((c + cnt))
  done
  if [ -f "$d/SKILL.md" ]; then
    c=$((c + 1))
  fi
  printf "%s\n" "$c"
}

# ----- avg_tier <skill-dir>: emit weighted-average tier with 1-decimal precision -----
# Weight = number of chunks at that tier. SKILL.md contributes 1 chunk at tier 5.
# Empty skill (no chunks anywhere) → empty string.
mp_avg_tier() {
  d="$1"
  total=0
  weighted=0
  for n in 0 1 2 3 4 5; do
    td="$d/${n}-melting-pot"
    [ -d "$td" ] || continue
    cnt=$(find -L "$td" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
    total=$((total + cnt))
    weighted=$((weighted + cnt * n))
  done
  if [ -f "$d/SKILL.md" ]; then
    total=$((total + 1))
    weighted=$((weighted + 5))
  fi
  if [ "$total" -eq 0 ]; then
    printf ""
    return 0
  fi
  # awk for fractional division (POSIX sh has no float arithmetic).
  awk -v w="$weighted" -v t="$total" 'BEGIN{ printf "%.1f", w / t }'
}

# ----- hits_summary <skill-dir>: emit `[t:n, t:n, ...]` of (tier, chunk-count) -----
# Only tiers with chunks are included. SKILL.md counts as one chunk at tier 5.
mp_hits_summary() {
  d="$1"
  parts=""
  for n in 0 1 2 3 4 5; do
    cnt=0
    td="$d/${n}-melting-pot"
    if [ -d "$td" ]; then
      cnt=$(find -L "$td" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
    fi
    if [ "$n" -eq 5 ] && [ -f "$d/SKILL.md" ]; then
      cnt=$((cnt + 1))
    fi
    if [ "$cnt" -gt 0 ]; then
      if [ -z "$parts" ]; then
        parts="${n}:${cnt}"
      else
        parts="${parts}, ${n}:${cnt}"
      fi
    fi
  done
  printf "[%s]\n" "$parts"
}

# ----- resolve_chunk_path <skill-dir> <chunk-name>: print highest-tier copy -----
# Searches tier 5 down to tier 0 for `<chunk-name>.md` (or exact-match if the
# caller passed `.md` already). Returns path of the highest-tier match; exits
# 0 on hit, 1 on miss.
mp_resolve_chunk_path() {
  d="$1"; name="$2"
  case "$name" in
    *.md) fname="$name" ;;
    *)    fname="${name}.md" ;;
  esac
  for n in 5 4 3 2 1 0; do
    p="$d/${n}-melting-pot/$fname"
    if [ -f "$p" ]; then
      printf "%s\n" "$p"
      return 0
    fi
  done
  # SKILL.md fallback only when caller asked for it by name.
  if [ "$fname" = "SKILL.md" ] && [ -f "$d/SKILL.md" ]; then
    printf "%s\n" "$d/SKILL.md"
    return 0
  fi
  return 1
}

# ----- tier_of_chunk <chunk-path>: print the tier number (0..5) or empty -----
# Extracts the N from the parent dir name `N-melting-pot`. SKILL.md → 5.
mp_tier_of_chunk() {
  p="$1"
  case "$(basename "$p")" in
    SKILL.md)
      printf "5\n"
      return 0
      ;;
  esac
  parent=$(basename "$(dirname "$p")")
  case "$parent" in
    0-melting-pot) printf "0\n" ;;
    1-melting-pot) printf "1\n" ;;
    2-melting-pot) printf "2\n" ;;
    3-melting-pot) printf "3\n" ;;
    4-melting-pot) printf "4\n" ;;
    5-melting-pot) printf "5\n" ;;
    *) return 1 ;;
  esac
}

# ----- detect_full_overlay_mode <skill-basename>: 0 if overlay owns whole stack -----
# Q-007 partial-coverage rule: if the upstream registered repo has ANY
# N-melting-pot/ dirs, then the overlay owns the entire tier stack for that
# skill (we don't mix-and-match partial upstream tiers with overlay tiers).
# This function answers "is this skill in full-overlay mode?" by checking the
# overlay dir's contents — if symlinks to upstream tier dirs exist, mode is on.
#
# Exit 0 = full-overlay-mode active (upstream supplied at least one tier dir,
# which discover.sh symlinked into the overlay).
# Exit 1 = no upstream tier-dir symlinks present (skill is either pure overlay
# or pure registered-legacy).
mp_detect_full_overlay_mode() {
  basename_v="$1"
  ovl="${MP_HOME%/}/$basename_v"
  [ -d "$ovl" ] || return 1
  for n in 0 1 2 3 4 5; do
    td="$ovl/${n}-melting-pot"
    if [ -L "$td" ]; then
      return 0
    fi
  done
  return 1
}

# ----- append_status_history <chunk-path> <tier> <reason> -----
# Appends a new entry to the chunk frontmatter's `status_history:` block:
#     - { tier: <tier>, at: <YYYY-MM-DD>, reason: "<reason>" }
# If no `status_history:` key exists in the frontmatter, one is created.
# Writes atomically via tmp-file + rename.
#
# Quoting: the reason string is wrapped in double quotes; any embedded
# double-quote is escaped with a backslash for YAML round-trip safety.
mp_append_status_history() {
  p="$1"; tier="$2"; reason="$3"
  [ -f "$p" ] || { mp_err "no such chunk: $p"; return 1; }
  if ! mp_has_frontmatter "$p"; then
    mp_err "chunk lacks frontmatter: $p"
    return 1
  fi
  # ISO-8601 date (UTC).
  today=$(date -u +%Y-%m-%d)
  # Escape embedded double quotes and backslashes in the reason (YAML-safe).
  reason_esc=$(printf "%s" "$reason" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')

  tmp="${p}.mp-tmp.$$"
  # Three cases for appending into the frontmatter:
  #   (a) No `status_history:` key exists  → synthesise a fresh block right
  #       before the closing `---`.
  #   (b) `status_history:` key exists and is followed by more top-level keys
  #       → append our entry as the block's final list item, then carry on
  #       printing the trailing keys.
  #   (c) `status_history:` is the LAST key (block extends to the closing
  #       `---`) → append our entry just before the closing `---`.
  #
  # `seen_block` records that we entered an existing block at any point; that
  # disables the "synthesise fresh block" branch. `sh_block` tracks whether
  # we're CURRENTLY inside the list (so the closing-`---` rule knows whether
  # to flush our entry as a list continuation or not).
  awk -v t="$tier" -v at="$today" -v rs="$reason_esc" '
    BEGIN { in_fm = 0; seen_open = 0; sh_block = 0; seen_block = 0; emitted = 0 }
    /^---[[:space:]]*$/ {
      if (!seen_open) {
        seen_open = 1; in_fm = 1
        print; next
      } else {
        # Closing frontmatter delimiter.
        if (!emitted) {
          if (seen_block) {
            # Case (c): status_history was the last key, extending up to here.
            # Append our entry as a final list item before the close.
            printf "  - { tier: %s, at: %s, reason: \"%s\" }\n", t, at, rs
          } else {
            # Case (a): no status_history block existed — synthesise one.
            printf "status_history:\n"
            printf "  - { tier: %s, at: %s, reason: \"%s\" }\n", t, at, rs
          }
          emitted = 1
        }
        in_fm = 0; sh_block = 0
        print; next
      }
    }
    in_fm && /^status_history:[[:space:]]*$/ {
      print
      sh_block = 1
      seen_block = 1
      next
    }
    in_fm && sh_block {
      # Inside status_history list — entries indented with "  -" or "- ".
      if ($0 ~ /^[[:space:]]+-/) {
        print; next
      } else {
        # Case (b): we hit the next top-level key while still inside the
        # list. Flush our entry, then print this line.
        printf "  - { tier: %s, at: %s, reason: \"%s\" }\n", t, at, rs
        emitted = 1
        sh_block = 0
        print; next
      }
    }
    { print }
  ' "$p" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$p"
  return 0
}

# ----- read_tier_meta <chunk-path>: emit TSV of structured frontmatter keys -----
# One line: `tier\tuse_count\tlast_used\tlast_validated\tdays_since_last_use\tdays_since_validated`
# Empty values left as empty strings. Days are computed against today UTC; if
# the date field is missing or unparseable, the days field is empty.
mp_read_tier_meta() {
  p="$1"
  [ -f "$p" ] || return 1
  tier=$(mp_tier_of_chunk "$p")
  uc=$(mp_fm_field use_count "$p")
  lu=$(mp_fm_field last_used "$p")
  lv=$(mp_fm_field last_validated "$p")
  dlu=$(mp_days_since "$lu")
  dlv=$(mp_days_since "$lv")
  printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$tier" "$uc" "$lu" "$lv" "$dlu" "$dlv"
}

# ----- days_since <YYYY-MM-DD>: integer days from given date to today UTC -----
# Empty / unparseable input → empty output. POSIX-portable epoch math via awk.
mp_days_since() {
  d="$1"
  case "$d" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) : ;;
    *) return 0 ;;
  esac
  today=$(date -u +%Y-%m-%d)
  awk -v a="$d" -v b="$today" '
    function ymd_to_days(s,    y, m, dd, days, i, dim, leap) {
      y = substr(s, 1, 4) + 0
      m = substr(s, 6, 2) + 0
      dd = substr(s, 9, 2) + 0
      days = 0
      for (i = 1970; i < y; i++) {
        leap = (i % 4 == 0 && (i % 100 != 0 || i % 400 == 0))
        days += leap ? 366 : 365
      }
      split("31,28,31,30,31,30,31,31,30,31,30,31", dim, ",")
      leap = (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0))
      if (leap) dim[2] = 29
      for (i = 1; i < m; i++) days += dim[i]
      days += dd - 1
      return days
    }
    BEGIN {
      da = ymd_to_days(a)
      db = ymd_to_days(b)
      diff = db - da
      if (diff < 0) diff = 0
      print diff
    }
  '
}

# ----- new_chunk_frontmatter <title> <session-id>: emit a fresh tier-0 frontmatter block -----
# Used by mp-learn harvest when scaffolding a new chunk. The block lands at
# tier 0 (scrap) per the "born at 0" invariant. Caller is responsible for
# writing the body after.
mp_new_chunk_frontmatter() {
  title="$1"; session="${2:-unknown}"
  today=$(date -u +%Y-%m-%d)
  # Escape embedded double-quotes / backslashes in title.
  t_esc=$(printf "%s" "$title" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
  cat <<EOF
---
title: "$t_esc"
created: $today
last_used: $today
use_count: 0
provenance:
  - session: $session
  - source: live-context
depends_on: []
status_history:
  - { tier: 0, at: $today, reason: "born from session $session" }
---
EOF
}
