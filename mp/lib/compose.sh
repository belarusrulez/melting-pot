# melting-pot compose helpers — POSIX sh.
#
# Composes a fully-rendered skill (manifest + all chunks across all tiers +
# applied patches) as one document for `mp-load`'s use. Markdown is default;
# JSON for programmatic consumers.
#
# Sourced after discover.sh + tier.sh + patch.sh.

# ----- tier_label <N>: human-friendly tier name (matches the pitch's table) -----
mp_tier_label() {
  case "$1" in
    5) printf "Pure alloy" ;;
    4) printf "Refined" ;;
    3) printf "Mixed-in" ;;
    2) printf "Melted" ;;
    1) printf "Heating" ;;
    0) printf "Scrap" ;;
    *) printf "?" ;;
  esac
}

# ----- _filter_has_tier <comma-list> <N>: 0 if N is in the comma-separated list -----
# Empty list = match-all (returns 0).
_mp_filter_has_tier() {
  list="$1"; n="$2"
  [ -z "$list" ] && return 0
  case ",${list}," in
    *,${n},*) return 0 ;;
    *) return 1 ;;
  esac
}

# ----- compose_skill <skill-basename> [flags] -----
# Flags:
#   --format md|json     output format (default: md)
#   --tiers a,b,c        only emit listed tiers (e.g. 5,3 — default: all six)
#   --no-patches         show raw upstream content without your patches applied
#   --with-history       include each chunk's status_history block in the output
#
# Resolution:
#   1. Skill basename = directory name under $MP_HOME (overlay path is canonical
#      once discover.sh has run — upstream tier dirs are symlinked in).
#   2. If the overlay dir doesn't exist, fall back to discovering via
#      mp_discover_skills and matching basename against the emitted paths.
#
# Side effect (only when --no-patches is NOT set): patches that fail to apply
# are recorded to ~/.melt/<skill>/patches/.failed/ via mp_apply_in_memory.
mp_compose_skill() {
  skill="$1"; shift

  format=md
  tiers=""
  apply_patches=1
  with_history=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --format)      format="${2:?--format needs value}"; shift 2 ;;
      --format=*)    format="${1#--format=}"; shift ;;
      --tiers)       tiers="${2:?--tiers needs value}"; shift 2 ;;
      --tiers=*)     tiers="${1#--tiers=}"; shift ;;
      --no-patches)  apply_patches=0; shift ;;
      --with-history) with_history=1; shift ;;
      *) mp_err "compose_skill: unknown flag: $1"; return 2 ;;
    esac
  done

  case "$format" in md|markdown) format=md ;; json) ;; *) mp_err "unknown format: $format"; return 2 ;; esac

  # Resolve content source. First, run discovery once and cache the row for
  # this basename — that gives us the canonical path (which may be either an
  # overlay path OR an upstream path, depending on origin/kind). Then, fall
  # back to walking individual locations if discovery didn't catch the skill.
  disc_row=$(mp_discover_skills 2>/dev/null | awk -F'\t' -v b="$skill" '
    { n = split($1, parts, "/"); if (parts[n] == b) { print; exit } }
  ')
  src=""
  origin=""
  if [ -n "$disc_row" ]; then
    src=$(printf "%s\n" "$disc_row" | awk -F'\t' '{print $1}')
    origin=$(printf "%s\n" "$disc_row" | awk -F'\t' '{print $2}')
  else
    # Discovery missed it — try overlay then bail.
    ovl=$(mp_overlay_dir_for "$skill")
    if [ -d "$ovl" ]; then
      src="$ovl"
      origin=ovl
    fi
  fi
  if [ -z "$src" ] || [ ! -d "$src" ]; then
    mp_err "no such skill: $skill"
    return 1
  fi

  # Manifest may live at $src OR — for a mix-origin legacy skill where the
  # overlay only carries patches — at the upstream registered path.
  manifest=$(mp_manifest_path "$src")
  if [ -z "$manifest" ] && { [ "$origin" = "mix" ] || [ "$origin" = "reg" ]; }; then
    # Look the upstream path up via discovery against registered roots.
    ups=$(mp_parse_patterns | while IFS=$(printf '\t') read -r root pat; do
      root_e=$(mp_expand_root "$root")
      [ -d "$root_e/$skill" ] || continue
      printf "%s\n" "$root_e/$skill"
      break
    done)
    if [ -n "$ups" ]; then
      cand=$(mp_manifest_path "$ups")
      if [ -n "$cand" ]; then
        manifest="$cand"
      fi
    fi
  fi
  name_v=""
  desc_v=""
  if [ -n "$manifest" ] && [ -f "$manifest" ]; then
    name_v=$(mp_fm_field name "$manifest")
    desc_v=$(mp_fm_field description "$manifest")
  fi
  [ -z "$name_v" ] && name_v=$(mp_name_from_dirname "$skill")
  [ -z "$origin" ] && origin=ovl

  # Compute applied / failed patch lists once (so we can print the count line).
  # We apply against the manifest's `SKILL.md` body if the manifest IS a
  # SKILL.md (legacy upstream content); native overlays don't typically carry
  # patches against their own meta.md, but we honour the same flow either way.
  patches_applied_n=0
  patches_failed_n=0
  patched_manifest_body=""
  if [ "$apply_patches" -eq 1 ] && [ -n "$manifest" ]; then
    # Apply patches against the manifest body. We feed mp_apply_in_memory the
    # full manifest file so patches can target any line within it.
    tmp_out=$(mktemp -t mp_comp.XXXXXX)
    mp_apply_in_memory "$skill" "$manifest" > "$tmp_out" 2>/dev/null
    patched_manifest_body=$(cat "$tmp_out")
    rm -f "$tmp_out"
    # Translate space-separated env vars into counts.
    set -- $MP_PATCH_APPLIED
    patches_applied_n=$#
    set -- $MP_PATCH_FAILED
    patches_failed_n=$#
  else
    [ -f "$manifest" ] && patched_manifest_body=$(cat "$manifest")
  fi

  # Determine whether the manifest is a SKILL.md (legacy upstream content the
  # composer should render under tier 5) or a meta.md (native — separate from
  # tier content).
  manifest_is_skill_md=0
  case "$manifest" in
    */SKILL.md) manifest_is_skill_md=1 ;;
  esac

  case "$format" in
    md)   _mp_compose_md   "$skill" "$name_v" "$desc_v" "$origin" "$src" "$tiers" "$with_history" "$patches_applied_n" "$patches_failed_n" "$patched_manifest_body" "$manifest_is_skill_md" ;;
    json) _mp_compose_json "$skill" "$name_v" "$desc_v" "$origin" "$src" "$tiers" "$with_history" "$patches_applied_n" "$patches_failed_n" "$patched_manifest_body" "$manifest_is_skill_md" ;;
  esac
}

# ----- _mp_compose_md ... — internal markdown emitter -----
_mp_compose_md() {
  skill="$1"; name_v="$2"; desc_v="$3"; origin="$4"; src="$5"; tiers="$6"; with_history="$7"
  pa_n="$8"; pf_n="$9"; manifest_body="${10}"; manifest_is_skill_md="${11:-0}"

  # tiers_present reflects what's at $src + (SKILL.md if the manifest IS one).
  tiers_present=$(mp_list_tiers_present "$src")
  if [ "$manifest_is_skill_md" = "1" ] && [ ! -f "$src/SKILL.md" ]; then
    # Add tier 5 to the list (deduped + sorted by awk).
    tiers_present=$(printf "%s\n5" "$tiers_present" | tr ',' '\n' | grep -v '^$' | sort -u | tr '\n' ',' | sed 's/,$//')
  fi

  printf "# %s\n\n" "$name_v"
  [ -n "$desc_v" ] && printf "> %s\n\n" "$desc_v"
  printf "origin=%s | tiers present: [%s] | patches applied: %s | patches failed: %s\n\n" \
    "$origin" "$tiers_present" "$pa_n" "$pf_n"

  # Iterate tiers 5 → 0, alphabetical within tier.
  history_buf=$(mktemp -t mp_hist.XXXXXX)
  : > "$history_buf"

  for n in 5 4 3 2 1 0; do
    _mp_filter_has_tier "$tiers" "$n" || continue
    td="$src/${n}-melting-pot"
    has_dir=0
    [ -d "$td" ] && has_dir=1
    inc_skill_md=0
    if [ "$n" -eq 5 ]; then
      if [ -f "$src/SKILL.md" ] || [ "$manifest_is_skill_md" = "1" ]; then
        inc_skill_md=1
      fi
    fi
    if [ "$has_dir" -eq 0 ] && [ "$inc_skill_md" -eq 0 ]; then
      continue
    fi
    # Skip tier section if no files (the dir may exist but be empty).
    nfiles=0
    if [ "$has_dir" -eq 1 ]; then
      nfiles=$(find -L "$td" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
    fi
    if [ "$nfiles" -eq 0 ] && [ "$inc_skill_md" -eq 0 ]; then
      continue
    fi

    label=$(mp_tier_label "$n")
    printf "## Tier %s — %s\n\n" "$n" "$label"

    # Build the alphabetical list (chunks + maybe SKILL.md). We mark the
    # SKILL.md entry with the literal token `__SKILL_MD__` so the renderer
    # can use $manifest_body (which may carry applied patches) instead of
    # re-reading from disk.
    list_file=$(mktemp -t mp_list.XXXXXX)
    : > "$list_file"
    if [ "$has_dir" -eq 1 ]; then
      find -L "$td" -maxdepth 1 -type f -name '*.md' 2>/dev/null \
        | sort >> "$list_file"
    fi
    if [ "$inc_skill_md" -eq 1 ]; then
      printf "__SKILL_MD__\n" >> "$list_file"
    fi

    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if [ "$f" = "__SKILL_MD__" ]; then
        tag=""
        if [ "$pa_n" -gt 0 ] || [ "$pf_n" -gt 0 ]; then
          tag=" (patches applied: $pa_n, failed: $pf_n)"
        fi
        printf "### SKILL.md%s\n\n" "$tag"
        if [ -n "$manifest_body" ]; then
          printf "%s\n" "$manifest_body" | mp_body_after_fm /dev/stdin
        elif [ -f "$src/SKILL.md" ]; then
          mp_body_after_fm "$src/SKILL.md"
        fi
        printf "\n"
        continue
      fi
      bn=$(basename "$f")
      title=$(mp_fm_field title "$f")
      if [ -n "$title" ]; then
        printf "### %s — %s\n\n" "$bn" "$title"
      else
        printf "### %s\n\n" "$bn"
      fi
      mp_body_after_fm "$f"
      if [ "$with_history" -eq 1 ]; then
        _mp_extract_history "$f" >> "$history_buf"
      fi
      printf "\n"
    done < "$list_file"
    rm -f "$list_file"
  done

  if [ "$with_history" -eq 1 ] && [ -s "$history_buf" ]; then
    printf "## Status history (across all chunks)\n\n"
    # Sort entries by date descending.
    sort -r "$history_buf"
    printf "\n"
  fi
  rm -f "$history_buf"
}

# ----- _mp_extract_history <chunk-path>: emit "<date>: <chunk-name> <reason>" per history entry -----
_mp_extract_history() {
  p="$1"
  bn=$(basename "$p")
  awk -v bn="$bn" '
    BEGIN { in_fm = 0; seen_open = 0; sh_block = 0 }
    /^---[[:space:]]*$/ {
      if (!seen_open) { seen_open = 1; in_fm = 1; next }
      else            { in_fm = 0; exit }
    }
    in_fm && /^status_history:/ { sh_block = 1; next }
    in_fm && sh_block {
      if ($0 ~ /^[[:space:]]+-/) {
        # Match `- { tier: N, at: YYYY-MM-DD, reason: "..." }`
        line = $0
        at = ""
        reason = ""
        if (match(line, /at:[[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2}/)) {
          at = substr(line, RSTART + 3, RLENGTH - 3)
          sub(/^[[:space:]]+/, "", at)
        }
        if (match(line, /reason:[[:space:]]*"[^"]*"/)) {
          reason = substr(line, RSTART, RLENGTH)
          sub(/^reason:[[:space:]]*"/, "", reason)
          sub(/"$/, "", reason)
        }
        if (at != "") printf "- %s: %s %s\n", at, bn, reason
      } else {
        sh_block = 0
      }
    }
  ' "$p"
}

# ----- _mp_compose_json ... — internal JSON emitter (hand-rolled, no jq) -----
_mp_compose_json() {
  skill="$1"; name_v="$2"; desc_v="$3"; origin="$4"; src="$5"; tiers="$6"; with_history="$7"
  pa_n="$8"; pf_n="$9"; manifest_body="${10}"; manifest_is_skill_md="${11:-0}"

  tiers_present=$(mp_list_tiers_present "$src")
  if [ "$manifest_is_skill_md" = "1" ] && [ ! -f "$src/SKILL.md" ]; then
    tiers_present=$(printf "%s\n5" "$tiers_present" | tr ',' '\n' | grep -v '^$' | sort -u | tr '\n' ',' | sed 's/,$//')
  fi
  n_e=$(printf "%s" "$name_v" | mp_json_escape)
  d_e=$(printf "%s" "$desc_v" | mp_json_escape)
  s_e=$(printf "%s" "$skill"  | mp_json_escape)

  printf '{'
  printf '"name":"%s",' "$n_e"
  printf '"basename":"%s",' "$s_e"
  printf '"description":"%s",' "$d_e"
  printf '"origin":"%s",' "$origin"
  printf '"tiers_present":"%s",' "$tiers_present"
  printf '"patches_applied":%s,' "$pa_n"
  printf '"patches_failed":%s,' "$pf_n"
  printf '"tiers":['

  first_tier=1
  for n in 5 4 3 2 1 0; do
    _mp_filter_has_tier "$tiers" "$n" || continue
    td="$src/${n}-melting-pot"
    has_dir=0
    [ -d "$td" ] && has_dir=1
    inc_skill_md=0
    if [ "$n" -eq 5 ]; then
      if [ -f "$src/SKILL.md" ] || [ "$manifest_is_skill_md" = "1" ]; then
        inc_skill_md=1
      fi
    fi
    if [ "$has_dir" -eq 0 ] && [ "$inc_skill_md" -eq 0 ]; then
      continue
    fi

    list_file=$(mktemp -t mp_jlist.XXXXXX)
    : > "$list_file"
    if [ "$has_dir" -eq 1 ]; then
      find -L "$td" -maxdepth 1 -type f -name '*.md' 2>/dev/null \
        | sort >> "$list_file"
    fi
    if [ "$inc_skill_md" -eq 1 ]; then
      printf "__SKILL_MD__\n" >> "$list_file"
    fi
    if [ ! -s "$list_file" ]; then
      rm -f "$list_file"
      continue
    fi

    [ "$first_tier" -eq 1 ] && first_tier=0 || printf ','
    printf '{"tier":%s,"chunks":[' "$n"
    first_chunk=1
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if [ "$f" = "__SKILL_MD__" ]; then
        bn=SKILL.md
        bn_e=SKILL.md
        if [ -n "$manifest_body" ]; then
          body=$(printf "%s\n" "$manifest_body" | mp_body_after_fm /dev/stdin | mp_json_escape | awk 'BEGIN{ORS="\\n"} {print}')
        elif [ -f "$src/SKILL.md" ]; then
          body=$(mp_body_after_fm "$src/SKILL.md" | mp_json_escape | awk 'BEGIN{ORS="\\n"} {print}')
        else
          body=""
        fi
        title=""
        [ "$first_chunk" -eq 1 ] && first_chunk=0 || printf ','
        printf '{"name":"%s","title":"%s","body":"%s"' "$bn_e" "$title" "$body"
        if [ "$with_history" -eq 1 ]; then
          printf ',"history":""'
        fi
        printf '}'
        continue
      fi
      bn=$(basename "$f")
      bn_e=$(printf "%s" "$bn" | mp_json_escape)
      body=$(mp_body_after_fm "$f" | mp_json_escape | awk 'BEGIN{ORS="\\n"} {print}')
      title=$(mp_fm_field title "$f" | mp_json_escape)
      [ "$first_chunk" -eq 1 ] && first_chunk=0 || printf ','
      printf '{"name":"%s","title":"%s","body":"%s"' "$bn_e" "$title" "$body"
      if [ "$with_history" -eq 1 ]; then
        hist=$(_mp_extract_history "$f" | mp_json_escape | awk 'BEGIN{ORS="\\n"} {print}')
        printf ',"history":"%s"' "$hist"
      fi
      printf '}'
    done < "$list_file"
    rm -f "$list_file"
    printf ']}'
  done
  printf ']'
  printf '}\n'
}
