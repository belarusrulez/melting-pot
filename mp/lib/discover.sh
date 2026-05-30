# melting-pot shared helpers — POSIX sh. Sourced by every mp/*/action and by
# sibling lib files (tier.sh, patch.sh, compose.sh). No `set -eu` here — the
# sourcing script owns that.
#
# Reads ONLY $MP_PATTERNS (default ~/.melt/repos.patterns). There is NO
# runtime fallback to any other path.

# ----- output helpers -----
mp_warn() { printf 'WARN: %s\n' "$*" >&2; }
mp_err()  { printf 'ERROR: %s\n' "$*" >&2; }

# Leveled logging — emits to stderr if MP_LOG_LEVEL <= level.
# Levels: verbose=0 debug=1 info=2 warning=3 error=4 critical=5
mp_log_level_num() {
  case "${MP_LOG_LEVEL:-info}" in
    verbose|0)  printf 0 ;;
    debug|1)    printf 1 ;;
    info|2)     printf 2 ;;
    warning|3)  printf 3 ;;
    error|4)    printf 4 ;;
    critical|5) printf 5 ;;
    *)          printf 2 ;;
  esac
}
mp_log() {
  lvl="$1"; shift
  case "$lvl" in
    verbose)  n=0 ;;
    debug)    n=1 ;;
    info)     n=2 ;;
    warning)  n=3 ;;
    error)    n=4 ;;
    critical) n=5 ;;
    *) n=2 ;;
  esac
  cur=$(mp_log_level_num)
  [ "$n" -ge "$cur" ] && printf '[%s] %s\n' "$lvl" "$*" >&2
  return 0
}

# ----- SQL escape (single → doubled) -----
mp_sql_esc() {
  sed "s/'/''/g"
}

# ----- JSON escape: stdin → stdout, escape for JSON string value -----
mp_json_escape() {
  sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# ----- expand leading ~ in a path -----
mp_expand_root() {
  case "$1" in
    "~")   printf "%s\n" "$HOME" ;;
    "~/"*) printf "%s/%s\n" "$HOME" "${1#~/}" ;;
    *)     printf "%s\n" "$1" ;;
  esac
}

# ----- parse_patterns: emit "<root>\t<pattern>" per line -----
# Skip blank lines and # comments. Default pattern = "*"; "re:" prefix = regex.
mp_parse_patterns() {
  if [ ! -f "$MP_PATTERNS" ]; then
    return 0
  fi
  awk '
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*#/ { next }
    {
      sub(/\r$/, "")
      line = $0
      tab = index(line, "\t")
      if (tab > 0) {
        root = substr(line, 1, tab - 1)
        pat  = substr(line, tab + 1)
      } else {
        match(line, /[[:space:]]+/)
        if (RSTART > 0) {
          root = substr(line, 1, RSTART - 1)
          pat  = substr(line, RSTART + RLENGTH)
        } else {
          root = line; pat = ""
        }
      }
      sub(/^[[:space:]]+/, "", root); sub(/[[:space:]]+$/, "", root)
      sub(/^[[:space:]]+/, "", pat);  sub(/[[:space:]]+$/, "", pat)
      if (root == "") next
      if (pat  == "") pat = "*"
      printf "%s\t%s\n", root, pat
    }
  ' "$MP_PATTERNS"
}

# ----- fm_field <key> <path>: emit frontmatter value (one line, trimmed, unquoted) -----
mp_fm_field() {
  awk -v key="$1" '
    BEGIN { in_fm = 0; seen_open = 0 }
    /^---[[:space:]]*$/ {
      if (!seen_open) { seen_open = 1; in_fm = 1; next }
      else            { in_fm = 0; exit }
    }
    in_fm {
      kp = key ":"
      if (index($0, kp) == 1) {
        v = substr($0, length(kp) + 1)
        sub(/^[[:space:]]+/, "", v)
        sub(/[[:space:]]+$/, "", v)
        if (length(v) >= 2) {
          first = substr(v, 1, 1)
          last  = substr(v, length(v), 1)
          if ((first == "\"" && last == "\"") || (first == "'\''" && last == "'\''")) {
            v = substr(v, 2, length(v) - 2)
          }
        }
        print v
        exit
      }
    }
  ' "$2"
}

# ----- body_after_fm <path>: emit content after the closing `---` -----
mp_body_after_fm() {
  awk '
    BEGIN { seen_open = 0; past = 0 }
    {
      if (past) { print; next }
      if ($0 ~ /^---[[:space:]]*$/) {
        if (!seen_open) { seen_open = 1; next }
        else            { past = 1; next }
      }
      if (!seen_open) {
        past = 1
        print
      }
    }
  ' "$1"
}

# ----- has_frontmatter <path>: 0 if file has a frontmatter block, 1 otherwise -----
mp_has_frontmatter() {
  awk '
    BEGIN { seen_open = 0; ok = 1 }
    NR == 1 && /^---[[:space:]]*$/ { seen_open = 1; next }
    seen_open && /^---[[:space:]]*$/ { ok = 0; exit }
    END { exit ok }
  ' "$1"
}

# ----- name_from_dirname <dirname>: first '-' → ':' only, rest unchanged -----
# my-cool-tool → my:cool-tool ; foo → foo ; mp → mp
mp_name_from_dirname() {
  printf "%s\n" "$1" | awk '
    {
      i = index($0, "-")
      if (i == 0) print $0
      else        printf "%s:%s\n", substr($0, 1, i-1), substr($0, i+1)
    }
  '
}

# ----- manifest_path <skill-dir>: print "meta.md" if present, else "SKILL.md" if present, else empty -----
# meta.md is the native overlay format; SKILL.md is the legacy single-file format.
# Both are first-class. Native takes precedence when both exist.
mp_manifest_path() {
  d="$1"
  if [ -f "$d/meta.md" ]; then
    printf "%s\n" "$d/meta.md"
  elif [ -f "$d/SKILL.md" ]; then
    printf "%s\n" "$d/SKILL.md"
  fi
}

# ----- has_tier_dirs <skill-dir>: return 0 if any N-melting-pot/ dir exists -----
mp_has_tier_dirs() {
  d="$1"
  for n in 0 1 2 3 4 5; do
    if [ -d "$d/${n}-melting-pot" ]; then
      return 0
    fi
  done
  return 1
}

# ----- overlay_dir_for <skill-basename>: print path under $MP_HOME -----
# Overlay layout: $MP_HOME/<skill-basename>/{meta.md, N-melting-pot/, patches/}
mp_overlay_dir_for() {
  printf "%s/%s\n" "${MP_HOME%/}" "$1"
}

# ----- symlink_upstream_tiers <upstream-skill-dir> <overlay-skill-dir> -----
# Q-007: when an upstream registered repo contains N-melting-pot/ dirs, the
# overlay owns the entire tier stack for that skill ("full-overlay mode"). We
# create symlinks `<overlay>/N-melting-pot/ → <upstream>/N-melting-pot/` for
# whichever N exist upstream, so the search/load pipeline reads everything
# uniformly through the overlay path.
#
# Idempotent: existing symlinks pointing at the right target are left alone;
# wrong-target symlinks are replaced; existing non-symlink dirs/files are NOT
# touched (overlay-authored content wins — log a warning).
mp_symlink_upstream_tiers() {
  ups="$1"; ovl="$2"
  [ -d "$ups" ] || return 0
  [ -n "$ovl" ] || return 1
  mkdir -p "$ovl"
  for n in 0 1 2 3 4 5; do
    src="$ups/${n}-melting-pot"
    dst="$ovl/${n}-melting-pot"
    [ -d "$src" ] || continue
    if [ -L "$dst" ]; then
      cur=$(readlink "$dst")
      if [ "$cur" = "$src" ]; then
        continue
      fi
      rm -f "$dst"
      ln -s "$src" "$dst"
      mp_log debug "re-pointed symlink $dst -> $src"
    elif [ -e "$dst" ]; then
      mp_warn "overlay has non-symlink at $dst; upstream $src not linked (overlay wins)"
    else
      ln -s "$src" "$dst"
      mp_log debug "linked $dst -> $src"
    fi
  done
  return 0
}

# ----- discover_skills: emit TSV `<path>\t<origin>\t<kind>` per skill (deduped, sorted) -----
#   path   = absolute path to the canonical skill directory (overlay path when
#            overlay contributes; upstream path when only upstream contributes)
#   origin = `reg`  (only registered upstream contributes)
#          | `ovl`  (only overlay contributes — overlay-born skill)
#          | `mix`  (both layers contribute — overlay holds patches and/or
#                    overlay-authored chunks alongside upstream content)
#   kind   = `legacy` (SKILL.md-only, no N-melting-pot/ tier dirs anywhere)
#          | `native` (at least one N-melting-pot/ tier dir present somewhere)
#
# Side effect (Q-007): for any upstream skill containing N-melting-pot/ dirs,
# the function creates symlinks into $MP_HOME/<dirname>/N-melting-pot/ so
# downstream consumers (search reindex, compose) read uniformly through the
# overlay path. The emitted `path` is the overlay path in that case.
#
# Pattern semantics: registered roots filtered by glob /
# regex via $MP_PATTERNS. Overlay roots are walked unconditionally.
mp_discover_skills() {
  [ -n "${MP_HOME:-}" ] || { mp_err "MP_HOME unset"; return 1; }
  [ -n "${MP_PATTERNS:-}" ] || MP_PATTERNS="$MP_HOME/repos.patterns"

  # --- collect registered-layer skill paths from $MP_PATTERNS roots ---
  reg_raw=$(mktemp -t mp_disc_reg.XXXXXX)
  : > "$reg_raw"
  mp_parse_patterns | while IFS=$(printf '\t') read -r root pat; do
    [ -n "$root" ] || continue
    root_e=$(mp_expand_root "$root")
    if [ ! -d "$root_e" ]; then
      mp_warn "skipping root (not a directory): $root_e"
      continue
    fi
    case "$pat" in
      re:*)
        regex="${pat#re:}"
        # A skill is "any directory containing meta.md or SKILL.md".
        find "$root_e" -type f \( -name SKILL.md -o -name meta.md \) 2>/dev/null | while read -r p; do
          d=$(dirname "$p")
          b=$(basename "$d")
          if printf "%s\n" "$b" | grep -E -q -- "$regex"; then printf "%s\n" "$d"; fi
        done
        ;;
      "*")
        find "$root_e" -type f \( -name SKILL.md -o -name meta.md \) 2>/dev/null | while read -r p; do
          printf "%s\n" "$(dirname "$p")"
        done
        ;;
      *)
        find "$root_e" -type f \( -name SKILL.md -o -name meta.md \) 2>/dev/null | while read -r p; do
          d=$(dirname "$p")
          b=$(basename "$d")
          # shellcheck disable=SC2254
          case "$b" in
            $pat) printf "%s\n" "$d" ;;
          esac
        done
        ;;
    esac
  done | sort -u >> "$reg_raw"

  # --- collect overlay-layer skill paths from $MP_HOME ---
  ovl_raw=$(mktemp -t mp_disc_ovl.XXXXXX)
  : > "$ovl_raw"
  if [ -d "$MP_HOME" ]; then
    # Overlay skills are direct children of $MP_HOME that contain meta.md OR
    # SKILL.md OR any N-melting-pot/ dir OR a patches/ dir. We must NOT descend
    # into ~/.melt internals (search/, trash/, learn/, hooks/).
    for d in "$MP_HOME"/*/; do
      [ -d "$d" ] || continue
      d="${d%/}"
      b=$(basename "$d")
      case "$b" in
        search|trash|learn|hooks) continue ;;
      esac
      if [ -f "$d/meta.md" ] || [ -f "$d/SKILL.md" ] || mp_has_tier_dirs "$d" || [ -d "$d/patches" ]; then
        printf "%s\n" "$d" >> "$ovl_raw"
      fi
    done
  fi

  # --- union: keyed by basename. For each basename we know which layers contribute. ---
  # We emit one row per basename, using the overlay path when overlay contributes
  # (because Q-007 symlinks bring upstream content under the overlay path).
  union_raw=$(mktemp -t mp_disc_union.XXXXXX)
  : > "$union_raw"

  # Index basename -> upstream path
  reg_idx=$(mktemp -t mp_disc_regidx.XXXXXX)
  : > "$reg_idx"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    printf "%s\t%s\n" "$(basename "$p")" "$p" >> "$reg_idx"
  done < "$reg_raw"

  # Track basenames we've emitted (to dedupe across layers).
  seen=$(mktemp -t mp_disc_seen.XXXXXX)
  : > "$seen"

  # Pass 1: overlay-rooted skills (origin includes ovl).
  while IFS= read -r ovl_path; do
    [ -n "$ovl_path" ] || continue
    b=$(basename "$ovl_path")
    grep -Fxq -- "$b" "$seen" 2>/dev/null && continue
    printf "%s\n" "$b" >> "$seen"

    ups_path=$(awk -F'\t' -v k="$b" '$1==k {print $2; exit}' "$reg_idx")
    if [ -n "$ups_path" ]; then
      origin=mix
      # Q-007: if upstream has tier dirs, symlink them in.
      if mp_has_tier_dirs "$ups_path"; then
        mp_symlink_upstream_tiers "$ups_path" "$ovl_path"
      fi
    else
      origin=ovl
    fi

    if mp_has_tier_dirs "$ovl_path"; then
      kind=native
    elif [ -n "$ups_path" ] && mp_has_tier_dirs "$ups_path"; then
      kind=native
    else
      kind=legacy
    fi
    printf "%s\t%s\t%s\n" "$ovl_path" "$origin" "$kind" >> "$union_raw"
  done < "$ovl_raw"

  # Pass 2: registered-only skills (no overlay basename seen).
  while IFS= read -r ups_path; do
    [ -n "$ups_path" ] || continue
    b=$(basename "$ups_path")
    grep -Fxq -- "$b" "$seen" 2>/dev/null && continue
    printf "%s\n" "$b" >> "$seen"

    if mp_has_tier_dirs "$ups_path"; then
      # Q-007: ensure overlay dir exists and contains symlinks; rewrite emitted
      # path to the overlay so downstream consumers see content uniformly.
      ovl_path=$(mp_overlay_dir_for "$b")
      mp_symlink_upstream_tiers "$ups_path" "$ovl_path"
      printf "%s\t%s\t%s\n" "$ovl_path" "reg" "native" >> "$union_raw"
    else
      printf "%s\t%s\t%s\n" "$ups_path" "reg" "legacy" >> "$union_raw"
    fi
  done < "$reg_raw"

  sort -u "$union_raw"

  rm -f "$reg_raw" "$ovl_raw" "$union_raw" "$reg_idx" "$seen"
}

# ----- discover_skill_paths: legacy convenience — paths only, one per line -----
# Use mp_discover_skills directly when origin/kind are needed.
mp_discover_skill_paths() {
  mp_discover_skills | awk -F'\t' '{print $1}'
}
