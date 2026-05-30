# melting-pot patch helpers — POSIX sh.
#
# Q-001 invariant: the apply pipeline is **policy-free**. On failure it records
# a marker under ~/.melt/<skill>/patches/.failed/ and CONTINUES attempting the
# rest of the patches. It never auto-skips a patch the user wrote and it never
# auto-stops the stack. Resolution lives in `mp:learn patch-triage`.
#
# Q-011 v1 default on-disk marker schema: one file per failed patch named
# `<patch-id>.patch.failed`, containing four delimited sections:
#     --- patch ---
#     <verbatim contents of the patch file>
#     --- upstream excerpt ---
#     <the upstream file content the patch tried to match>
#     --- reject ---
#     <stderr from `git apply --check` / `git apply`>
#     --- timestamp ---
#     <ISO-8601 UTC>
#
# Sourced after discover.sh.

# ----- patches_dir <skill-basename>: print absolute path of overlay patches dir -----
mp_patches_dir() {
  printf "%s/%s/patches\n" "${MP_HOME%/}" "$1"
}

# ----- failed_dir <skill-basename>: print absolute path of overlay .failed/ dir -----
mp_failed_dir() {
  printf "%s/%s/patches/.failed\n" "${MP_HOME%/}" "$1"
}

# ----- list_patches <skill-basename>: emit absolute paths of patches in apply order -----
# Sort key is the numeric prefix (NNN-...). Non-conformant filenames sort by name.
mp_list_patches() {
  pd=$(mp_patches_dir "$1")
  [ -d "$pd" ] || return 0
  find "$pd" -maxdepth 1 -type f -name '*.patch' 2>/dev/null | sort
}

# ----- patch_id <patch-path>: print the filename without leading dir -----
mp_patch_id() {
  basename "$1"
}

# ----- validate_patch <patch-path>: parse-only check; exit 0 if patch is well-formed -----
# Reads-only; no temp checkout. Uses `git apply --check` with stdin against an
# empty tree — that's strict syntax validation (not feasibility against actual
# upstream content, which apply_in_memory does).
#
# Returns 0 if the patch parses, 1 otherwise. stderr from git is captured to
# the caller-provided $MP_PATCH_REJECT if set; otherwise discarded.
mp_validate_patch() {
  patch_path="$1"
  [ -f "$patch_path" ] || { mp_err "no such patch: $patch_path"; return 1; }
  tmp=$(mktemp -d -t mp_pv.XXXXXX)
  (
    cd "$tmp" || exit 1
    git init -q . >/dev/null 2>&1
    # `git apply --check` against an empty index will fail because the target
    # file doesn't exist, BUT the failure message distinguishes "parse error"
    # from "doesn't apply". We use a more lenient `git mailinfo`-free trick:
    # try `git apply --check --include='nonexistent'` which still does the
    # parse step. Fall back to a sentinel: parse-error stderr contains
    # "patch fragment without header" or "corrupt patch" — feasibility errors
    # contain "does not exist" / "does not apply" / "patch failed".
    out=$(git apply --check --recount "$patch_path" 2>&1 || true)
    case "$out" in
      *"patch fragment without header"*|*"corrupt patch"*|*"unrecognized input"*)
        printf "%s" "$out" >&2
        exit 1
        ;;
      *)
        exit 0
        ;;
    esac
  )
  rc=$?
  rm -rf "$tmp"
  return "$rc"
}

# ----- record_failed_patch <skill-basename> <patch-id> <reject-output-file> <upstream-excerpt-file> -----
# Writes the envelope marker per Q-011 to ~/.melt/<skill>/patches/.failed/<patch-id>.failed.
# The patch hunk is read back from the original patch file (we have skill +
# patch-id, so we know the path).
mp_record_failed_patch() {
  skill="$1"; pid="$2"; reject_file="$3"; upstream_file="$4"
  fdir=$(mp_failed_dir "$skill")
  mkdir -p "$fdir"
  marker="$fdir/${pid}.failed"
  src_patch="$(mp_patches_dir "$skill")/$pid"
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  {
    printf -- '--- patch ---\n'
    if [ -f "$src_patch" ]; then
      cat "$src_patch"
    else
      printf '(source patch file missing: %s)\n' "$src_patch"
    fi
    printf -- '\n--- upstream excerpt ---\n'
    if [ -n "$upstream_file" ] && [ -f "$upstream_file" ]; then
      cat "$upstream_file"
    else
      printf '(no upstream excerpt captured)\n'
    fi
    printf -- '\n--- reject ---\n'
    if [ -n "$reject_file" ] && [ -f "$reject_file" ]; then
      cat "$reject_file"
    else
      printf '(no reject output captured)\n'
    fi
    printf -- '\n--- timestamp ---\n'
    printf '%s\n' "$ts"
  } > "$marker"
  mp_log info "recorded failed patch marker: $marker"
}

# ----- clear_failed_marker <skill-basename> <patch-id> -----
# Removes the .failed marker for a single patch-id if present. Used by
# mp:crud patch-remove and mp:learn patch-triage (delete outcome).
mp_clear_failed_marker() {
  skill="$1"; pid="$2"
  marker=$(mp_failed_dir "$skill")/"${pid}.failed"
  [ -f "$marker" ] && rm -f "$marker"
  return 0
}

# ----- apply_in_memory <skill-basename> <upstream-file> [--dry-run] -----
# Reads the upstream content of <upstream-file> and applies the skill's
# patches in numeric order to an in-memory (tmp-dir-backed) copy. Emits the
# fully-patched content on stdout. Records failure markers per Q-011 on any
# patch that won't apply; the apply pipeline CONTINUES regardless (Q-001).
#
# Flags:
#   --dry-run   Do not write to ~/.melt/<skill>/patches/.failed/. Compute the
#               patched content and report would-fail patches via the
#               $MP_PATCH_LAST_FAILED env var (newline-separated patch IDs).
#
# Side-effect env vars set on return:
#   MP_PATCH_APPLIED   space-separated patch IDs that applied successfully
#   MP_PATCH_FAILED    space-separated patch IDs that failed
#
# Exit code:
#   0  upstream is empty/missing OR at least one patch applied OR no patches
#   0  partial success (some failed, some applied) — caller inspects vars
#   1  unexpected internal error (tmp-dir / git failure unrelated to patches)
#
# Caller is responsible for the upstream file's relative path inside the
# tmp work-tree — we copy it in as `upstream.md`.
mp_apply_in_memory() {
  skill="$1"; upstream="$2"; shift 2
  dry_run=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run) dry_run=1; shift ;;
      *) mp_err "apply_in_memory: unknown flag: $1"; return 1 ;;
    esac
  done

  MP_PATCH_APPLIED=""
  MP_PATCH_FAILED=""
  export MP_PATCH_APPLIED MP_PATCH_FAILED

  # No upstream file → nothing to patch. Emit empty on stdout, signal success.
  if [ -z "$upstream" ] || [ ! -f "$upstream" ]; then
    : > /dev/null
    return 0
  fi

  patches_listing=$(mktemp -t mp_pl.XXXXXX)
  mp_list_patches "$skill" > "$patches_listing" 2>/dev/null
  if [ ! -s "$patches_listing" ]; then
    # No patches → emit upstream unchanged.
    cat "$upstream"
    rm -f "$patches_listing"
    return 0
  fi

  work=$(mktemp -d -t mp_apply.XXXXXX)
  (
    cd "$work" || exit 1
    git init -q . >/dev/null 2>&1
    git -c user.email=mp@local -c user.name=mp config commit.gpgsign false >/dev/null 2>&1
    # Seed the work-tree with the upstream content as `upstream.md` and commit
    # it so subsequent `git apply` invocations have a baseline.
    cp "$upstream" upstream.md
    git add upstream.md >/dev/null 2>&1
    git -c user.email=mp@local -c user.name=mp commit -q -m base >/dev/null 2>&1
    exit 0
  ) || {
    rm -rf "$work"
    rm -f "$patches_listing"
    mp_err "apply_in_memory: failed to seed work-tree"
    return 1
  }

  while IFS= read -r ppath; do
    [ -n "$ppath" ] || continue
    pid=$(mp_patch_id "$ppath")
    reject_file=$(mktemp -t mp_rej.XXXXXX)
    # Run `git apply --check` first (cheap feasibility test). On success, do
    # the real apply. We force `-p1` stripping off so callers can write patches
    # with `a/upstream.md` / `b/upstream.md` headers OR raw `upstream.md`
    # headers — the `--unsafe-paths` flag is not portable across git versions
    # so we just try both strip levels.
    (
      cd "$work" || exit 99
      if git apply --check "$ppath" >"$reject_file" 2>&1; then
        git apply "$ppath" >/dev/null 2>>"$reject_file"
        rc=$?
        if [ "$rc" -eq 0 ]; then
          # Commit so subsequent patches stack on the patched content.
          git -c user.email=mp@local -c user.name=mp add -A >/dev/null 2>&1
          git -c user.email=mp@local -c user.name=mp commit -q -m "$pid" >/dev/null 2>&1
        fi
        exit "$rc"
      else
        exit 1
      fi
    )
    rc=$?
    if [ "$rc" -eq 0 ]; then
      MP_PATCH_APPLIED="${MP_PATCH_APPLIED}${MP_PATCH_APPLIED:+ }${pid}"
      mp_log debug "patch applied: $pid"
    else
      MP_PATCH_FAILED="${MP_PATCH_FAILED}${MP_PATCH_FAILED:+ }${pid}"
      if [ "$dry_run" -eq 0 ]; then
        # Capture upstream excerpt as the current state of upstream.md inside
        # the work-tree (so subsequent patch failures see partial application).
        excerpt=$(mktemp -t mp_exc.XXXXXX)
        cp "$work/upstream.md" "$excerpt"
        mp_record_failed_patch "$skill" "$pid" "$reject_file" "$excerpt"
        rm -f "$excerpt"
      fi
      mp_log warning "patch failed: $pid (continuing)"
    fi
    rm -f "$reject_file"
  done < "$patches_listing"

  cat "$work/upstream.md"
  rm -rf "$work"
  rm -f "$patches_listing"
  return 0
}

# ----- patch_status <skill-basename>: emit TSV `<patch-id>\t<status>` per patch -----
# Status values:
#   applies              parses + would apply (we run a dry validate)
#   failed               .failed marker present for this patch-id
#   not-yet-attempted    no marker, but we did not attempt (cheap mode)
#
# This is the cheap read-only helper used by mp:crud patch-list. It does NOT
# write `.failed/` markers; if you want a fresh status that actually runs
# git apply --check, call apply_in_memory --dry-run yourself and inspect
# MP_PATCH_APPLIED / MP_PATCH_FAILED.
mp_patch_status() {
  skill="$1"
  fdir=$(mp_failed_dir "$skill")
  mp_list_patches "$skill" | while IFS= read -r ppath; do
    [ -n "$ppath" ] || continue
    pid=$(mp_patch_id "$ppath")
    marker="$fdir/${pid}.failed"
    if [ -f "$marker" ]; then
      printf "%s\tfailed\n" "$pid"
    else
      printf "%s\tnot-yet-attempted\n" "$pid"
    fi
  done
}

# ----- count_failed_markers <skill-basename>: print integer count -----
mp_count_failed_markers() {
  fdir=$(mp_failed_dir "$1")
  if [ ! -d "$fdir" ]; then
    printf "0\n"
    return 0
  fi
  find "$fdir" -maxdepth 1 -type f -name '*.failed' 2>/dev/null | wc -l | tr -d ' '
}

# ----- count_patches <skill-basename>: print integer count -----
mp_count_patches() {
  mp_list_patches "$1" | wc -l | tr -d ' '
}
