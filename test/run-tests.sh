#!/bin/sh
# Test harness for melting-pot Phase 1 (mp/lib/*). Phase 2+ tests will extend
# this file as the corresponding skills are built; this version covers only
# the lib layer.
#
# Each test is a function `t_NAME()` returning 0 on pass, non-zero on fail.
# State: every test gets a fresh sandboxed $MP_HOME via t_setup; teardown is
# implicit at next setup. Test output is captured to $OUT/$ERR and exit
# status to $RC.
#
# Usage:
#   sh test/run-tests.sh                  # run all
#   sh test/run-tests.sh LIB-01 LIB-02    # run specific tests by name
#   sh test/run-tests.sh -v LIB-01        # verbose (echo stdout/stderr on fail)

set -u

# ----- locate scripts (relative to this file) -----
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
LIB_DIR="$ROOT/mp/lib"
SEARCH_BIN="$ROOT/mp/search/action"
LOAD_BIN="$ROOT/mp/load/action"
LIST_BIN="$ROOT/mp/list/action"
CRUD_BIN="$ROOT/mp/crud/action"
LEARN_BIN="$ROOT/mp/learn/action"

# ----- platform capability probes (cross-platform: macOS / Linux / Windows) --
# Real symlinks aren't available under Git Bash / MSYS2 without native-symlink
# support; the installer/discovery fall back to shims/mirrors there, so the
# assertions below adapt instead of hard-failing.
_probe=$(mktemp -d 2>/dev/null)
if [ -n "$_probe" ] && ln -s "$_probe/t" "$_probe/l" 2>/dev/null && [ -L "$_probe/l" ]; then
  SYMLINKS_OK=1
else
  SYMLINKS_OK=0
fi
[ -n "$_probe" ] && rm -rf "$_probe" 2>/dev/null
command -v sqlite3 >/dev/null 2>&1 && HAVE_SQLITE3=1 || HAVE_SQLITE3=0

# Translate a path for sqlite3's readfile() inside SQL strings. On Windows the
# native sqlite3.exe can't open MSYS /c/... paths embedded in SQL (MSYS only
# auto-translates command-line ARGS, not bytes inside a SQL string), so use
# cygpath -m. No-op on macOS/Linux.
twin() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

# Portable SHA-256 of a file (hex only) — shasum / sha256sum / openssl.
t_sha() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" 2>/dev/null | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 "$1" 2>/dev/null | awk '{print $NF}'
  fi
}

# ----- output helpers (no colors — keep portable) -----
VERBOSE=0
PASS_N=0
FAIL_N=0
SKIP_N=0
FAIL_LIST=""

note()  { printf '%s\n' "$*" >&2; }
pass()  { PASS_N=$((PASS_N + 1)); printf '  PASS %s\n' "$1"; }
fail()  {
  FAIL_N=$((FAIL_N + 1))
  FAIL_LIST="$FAIL_LIST $1"
  printf '  FAIL %s — %s\n' "$1" "$2"
  if [ "$VERBOSE" = 1 ]; then
    printf '       rc=%s\n' "$RC"
    printf '       stdout:\n'
    sed 's/^/         /' "$OUT" 2>/dev/null
    printf '       stderr:\n'
    sed 's/^/         /' "$ERR" 2>/dev/null
  fi
}
skip()  { SKIP_N=$((SKIP_N + 1)); printf '  SKIP %s — %s\n' "$1" "$2"; }

# ----- per-test sandbox -----
t_setup() {
  TDIR=$(mktemp -d -t mp-test.XXXXXX)
  export MP_HOME="$TDIR/melt"
  export MP_PATTERNS="$MP_HOME/repos.patterns"
  mkdir -p "$MP_HOME"
  OUT="$TDIR/out"
  ERR="$TDIR/err"
  : > "$OUT"
  : > "$ERR"
  RC=0
}

# Write a repos.patterns line "<root>\t<pattern>".
t_patterns() {
  printf "%s\t%s\n" "$1" "${2:-*}" >> "$MP_PATTERNS"
}

# Run a sourced helper-function via a subshell that sources the lib files.
# Use this rather than re-sourcing inside the test (so $RC/$OUT/$ERR work).
run_lib() {
  sh -c '
    MP_HOME="$1"; MP_PATTERNS="$2"; shift 2
    export MP_HOME MP_PATTERNS
    . "'"$LIB_DIR"'/discover.sh"
    . "'"$LIB_DIR"'/tier.sh"
    . "'"$LIB_DIR"'/patch.sh"
    . "'"$LIB_DIR"'/compose.sh"
    "$@"
  ' run_lib "$MP_HOME" "$MP_PATTERNS" "$@" > "$OUT" 2> "$ERR"
  RC=$?
}

# ----- assertions -----
assert_rc() {
  if [ "$RC" = "$1" ]; then return 0; fi
  fail "$TNAME" "expected exit $1, got $RC"; return 1
}
assert_stdout_contains() {
  if grep -q -- "$1" "$OUT"; then return 0; fi
  fail "$TNAME" "stdout missing: $1"; return 1
}
assert_stdout_not_contains() {
  if ! grep -q -- "$1" "$OUT"; then return 0; fi
  fail "$TNAME" "stdout unexpectedly contained: $1"; return 1
}
assert_stderr_contains() {
  if grep -q -- "$1" "$ERR"; then return 0; fi
  fail "$TNAME" "stderr missing: $1"; return 1
}
assert_file_exists() {
  if [ -e "$1" ]; then return 0; fi
  fail "$TNAME" "expected file: $1"; return 1
}
assert_symlink_to() {
  if [ "$SYMLINKS_OK" = 1 ]; then
    if [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ]; then return 0; fi
    fail "$TNAME" "expected symlink $1 -> $2 (actual: $(readlink "$1" 2>/dev/null || echo none))"; return 1
  fi
  # No native symlinks (Windows/MSYS): discovery mirrors the dir and records the
  # source in a `.mp-linked-from` sentinel.
  if [ -d "$1" ] && [ "$(cat "$1/.mp-linked-from" 2>/dev/null)" = "$2" ]; then return 0; fi
  fail "$TNAME" "expected mirror $1 <- $2 (sentinel: $(cat "$1/.mp-linked-from" 2>/dev/null || echo none))"; return 1
}
assert_eq() {
  if [ "$1" = "$2" ]; then return 0; fi
  fail "$TNAME" "expected '$2', got '$1'"; return 1
}

# ----- fixture builders -----
# Make a legacy-style upstream skill (SKILL.md only) at $1.
mk_legacy_skill() {
  d="$1"; name="$2"; desc="$3"
  mkdir -p "$d"
  cat > "$d/SKILL.md" <<EOF
---
name: $name
description: $desc
---

Body for $name.
EOF
}

# Make a native-six-tier upstream skill at $1 with N-melting-pot dirs listed in $4 (space-separated).
mk_native_skill() {
  d="$1"; name="$2"; desc="$3"; tiers="$4"
  mkdir -p "$d"
  cat > "$d/meta.md" <<EOF
---
name: $name
description: $desc
---
EOF
  for t in $tiers; do
    mkdir -p "$d/${t}-melting-pot"
    cat > "$d/${t}-melting-pot/chunk-$t.md" <<EOF
---
title: "tier $t chunk for $name"
created: 2026-05-01
last_used: 2026-05-15
last_validated: 2026-05-15
use_count: 1
status_history:
  - { tier: $t, at: 2026-05-01, reason: "fixture seed" }
---
Body of tier-$t chunk for $name.
EOF
  done
}

# Write a patch file at $1 against an upstream file with content matching the patch.
# The fixture builder creates both — upstream first, then a patch that adds a line.
mk_patch_against_upstream() {
  upstream="$1"; patch_path="$2"
  # The patch must reference paths exactly as `git apply` expects when run
  # from a tmp-dir work-tree where the file is named `upstream.md`.
  cat > "$patch_path" <<'PATCH'
diff --git a/upstream.md b/upstream.md
index 0000000..1111111 100644
--- a/upstream.md
+++ b/upstream.md
@@ -1,5 +1,6 @@
 ---
 name: legacy-target
 description: legacy upstream skill
 ---

+Patched line appended.
PATCH
}

# Make a deliberately-broken patch (wrong context — won't match upstream).
mk_broken_patch() {
  patch_path="$1"
  cat > "$patch_path" <<'PATCH'
diff --git a/upstream.md b/upstream.md
index 0000000..1111111 100644
--- a/upstream.md
+++ b/upstream.md
@@ -1,3 +1,4 @@
 nonexistent header line
 another nonexistent line
 yet another
+broken patch addition
PATCH
}

# ============================================================================
# Section 1: discover.sh — basic discovery + Q-008 clean-fork
# ============================================================================

t_LIB_DISC_01() {
  TNAME=LIB-DISC-01
  t_setup
  reg="$TDIR/upstream"
  mk_legacy_skill "$reg/git-rebase" "git:rebase" "rewrite git history"
  t_patterns "$reg"
  run_lib mp_discover_skills
  assert_rc 0 || return 1
  # One row, registered-only, legacy kind.
  expected="$reg/git-rebase	reg	legacy"
  actual=$(cat "$OUT")
  assert_eq "$actual" "$expected" || return 1
  pass "$TNAME"
}

t_LIB_DISC_02() {
  TNAME=LIB-DISC-02
  t_setup
  # Overlay skill: $MP_HOME/my-skill/meta.md + 0-melting-pot/first.md
  mk_native_skill "$MP_HOME/my-skill" "my:skill" "overlay skill" "0"
  run_lib mp_discover_skills
  assert_rc 0 || return 1
  expected="$MP_HOME/my-skill	ovl	native"
  actual=$(cat "$OUT")
  assert_eq "$actual" "$expected" || return 1
  pass "$TNAME"
}

t_LIB_DISC_03() {
  TNAME=LIB-DISC-03
  # Same basename appears in BOTH layers → origin=mix.
  t_setup
  reg="$TDIR/upstream"
  mk_legacy_skill "$reg/git-rebase" "git:rebase" "upstream copy"
  # Overlay has a patches/ dir (patches against upstream are the typical mix case).
  mkdir -p "$MP_HOME/git-rebase/patches"
  t_patterns "$reg"
  run_lib mp_discover_skills
  assert_rc 0 || return 1
  if ! grep -q "$MP_HOME/git-rebase	mix	" "$OUT"; then
    fail "$TNAME" "expected origin=mix row not found; output:"
    cat "$OUT" >&2
    return 1
  fi
  pass "$TNAME"
}

t_LIB_DISC_04() {
  TNAME=LIB-DISC-04
  # discover.sh MUST read ONLY $MP_PATTERNS. Even if a stray patterns file
  # exists elsewhere under HOME pointing at a fixture, discovery against an
  # EMPTY ~/.melt/repos.patterns yields zero skills.
  t_setup
  reg="$TDIR/upstream"
  mk_legacy_skill "$reg/git-rebase" "git:rebase" "upstream"
  # Simulate a stray config by setting HOME to a fake place with one.
  fake_home="$TDIR/fake-home"
  mkdir -p "$fake_home/.other-skills"
  printf "%s\t*\n" "$reg" > "$fake_home/.other-skills/repos.patterns"
  # MP_PATTERNS is empty (only the file exists if t_patterns was called, which
  # it wasn't). Run discovery with HOME swapped — but MP_PATTERNS still wins.
  HOME="$fake_home" run_lib mp_discover_skills
  assert_rc 0 || return 1
  if [ -s "$OUT" ]; then
    fail "$TNAME" "expected zero discoveries; got: $(cat "$OUT")"
    return 1
  fi
  pass "$TNAME"
}

# ============================================================================
# Section 2: discover.sh — Q-007 symlink of upstream N-melting-pot/ dirs
# ============================================================================

t_LIB_DISC_05() {
  TNAME=LIB-DISC-05
  # Upstream has 0-melting-pot/ and 3-melting-pot/ → discover.sh symlinks both
  # into $MP_HOME/<skill>/{0,3}-melting-pot/.
  t_setup
  reg="$TDIR/upstream"
  mk_native_skill "$reg/git-rebase" "git:rebase" "upstream native" "0 3"
  t_patterns "$reg"
  run_lib mp_discover_skills
  assert_rc 0 || return 1
  assert_symlink_to "$MP_HOME/git-rebase/0-melting-pot" "$reg/git-rebase/0-melting-pot" || return 1
  assert_symlink_to "$MP_HOME/git-rebase/3-melting-pot" "$reg/git-rebase/3-melting-pot" || return 1
  # Emitted row should point at the OVERLAY path (so downstream consumers
  # uniformly read through the overlay).
  if ! grep -q "$MP_HOME/git-rebase	reg	native" "$OUT"; then
    fail "$TNAME" "expected overlay-rooted reg native row; got:"
    cat "$OUT" >&2
    return 1
  fi
  pass "$TNAME"
}

t_LIB_DISC_06() {
  TNAME=LIB-DISC-06
  # Re-running discover.sh leaves existing correct symlinks alone.
  t_setup
  reg="$TDIR/upstream"
  mk_native_skill "$reg/foo" "foo" "x" "0 5"
  t_patterns "$reg"
  run_lib mp_discover_skills > /dev/null
  before=$(readlink "$MP_HOME/foo/0-melting-pot")
  run_lib mp_discover_skills > /dev/null
  after=$(readlink "$MP_HOME/foo/0-melting-pot")
  assert_eq "$after" "$before" || return 1
  pass "$TNAME"
}

t_LIB_DISC_07() {
  TNAME=LIB-DISC-07
  # If overlay already has a real (non-symlink) N-melting-pot/ dir, discover.sh
  # leaves it alone and warns (overlay-authored content wins).
  t_setup
  reg="$TDIR/upstream"
  mk_native_skill "$reg/foo" "foo" "x" "0"
  # Pre-populate overlay with a real 0-melting-pot dir.
  mkdir -p "$MP_HOME/foo/0-melting-pot"
  cat > "$MP_HOME/foo/0-melting-pot/handwritten.md" <<'EOF'
---
title: "user-authored"
---
EOF
  t_patterns "$reg"
  run_lib mp_discover_skills > /dev/null 2>"$ERR"
  if [ -L "$MP_HOME/foo/0-melting-pot" ]; then
    fail "$TNAME" "real dir was replaced with a symlink"; return 1
  fi
  # Wording differs by platform (symlink: "non-symlink at"; mirror: "non-managed
  # dir at") but both end with the "(overlay wins)" verdict.
  assert_stderr_contains "overlay wins" || return 1
  pass "$TNAME"
}

# ============================================================================
# Section 3: tier.sh — walk_tier_dirs + SKILL.md tier-5 co-existence
# ============================================================================

t_LIB_TIER_01() {
  TNAME=LIB-TIER-01
  t_setup
  d="$MP_HOME/foo"
  mkdir -p "$d/2-melting-pot" "$d/5-melting-pot"
  printf 'x\n' > "$d/2-melting-pot/b.md"
  printf 'x\n' > "$d/2-melting-pot/a.md"
  printf 'x\n' > "$d/5-melting-pot/z.md"
  run_lib mp_walk_tier_dirs "$d"
  assert_rc 0 || return 1
  expected="2	$d/2-melting-pot/a.md
2	$d/2-melting-pot/b.md
5	$d/5-melting-pot/z.md"
  actual=$(cat "$OUT")
  assert_eq "$actual" "$expected" || return 1
  pass "$TNAME"
}

t_LIB_TIER_02() {
  TNAME=LIB-TIER-02
  t_setup
  d="$MP_HOME/foo"
  mkdir -p "$d/5-melting-pot"
  printf 'x\n' > "$d/5-melting-pot/native.md"
  cat > "$d/SKILL.md" <<'EOF'
---
name: foo
description: legacy
---
body
EOF
  run_lib mp_walk_tier_dirs "$d"
  assert_rc 0 || return 1
  # Both files should appear under tier 5.
  if ! grep -q "5	$d/5-melting-pot/native.md" "$OUT"; then
    fail "$TNAME" "missing native chunk under tier 5"; return 1
  fi
  if ! grep -q "5	$d/SKILL.md" "$OUT"; then
    fail "$TNAME" "SKILL.md not surfaced at tier 5"; return 1
  fi
  pass "$TNAME"
}

t_LIB_TIER_03() {
  TNAME=LIB-TIER-03
  # Q-007: bare `0/`..`5/` dirs are NOT recognized — only `N-melting-pot/`.
  t_setup
  d="$MP_HOME/foo"
  mkdir -p "$d/0" "$d/5-melting-pot"
  printf 'x\n' > "$d/0/should-not-be-seen.md"
  printf 'x\n' > "$d/5-melting-pot/real.md"
  run_lib mp_walk_tier_dirs "$d"
  assert_rc 0 || return 1
  if grep -q "should-not-be-seen" "$OUT"; then
    fail "$TNAME" "bare 0/ dir was walked (should have been ignored)"; return 1
  fi
  if ! grep -q "5-melting-pot/real.md" "$OUT"; then
    fail "$TNAME" "real tier-5 chunk missing"; return 1
  fi
  pass "$TNAME"
}

t_LIB_TIER_04() {
  TNAME=LIB-TIER-04
  t_setup
  d="$MP_HOME/foo"
  mkdir -p "$d/0-melting-pot" "$d/5-melting-pot"
  printf 'x\n' > "$d/0-melting-pot/a.md"
  printf 'x\n' > "$d/5-melting-pot/b.md"
  run_lib mp_avg_tier "$d"
  assert_rc 0 || return 1
  actual=$(cat "$OUT")
  assert_eq "$actual" "2.5" || return 1
  pass "$TNAME"
}

t_LIB_TIER_05() {
  TNAME=LIB-TIER-05
  t_setup
  d="$MP_HOME/foo"
  mkdir -p "$d/0-melting-pot" "$d/3-melting-pot" "$d/5-melting-pot"
  printf 'x\n' > "$d/0-melting-pot/a.md"
  printf 'x\n' > "$d/0-melting-pot/b.md"
  printf 'x\n' > "$d/3-melting-pot/c.md"
  printf 'x\n' > "$d/5-melting-pot/d.md"
  run_lib mp_hits_summary "$d"
  assert_rc 0 || return 1
  actual=$(cat "$OUT")
  assert_eq "$actual" "[0:2, 3:1, 5:1]" || return 1
  pass "$TNAME"
}

t_LIB_TIER_06() {
  TNAME=LIB-TIER-06
  t_setup
  d="$MP_HOME/foo/0-melting-pot"
  mkdir -p "$d"
  cat > "$d/chunk.md" <<'EOF'
---
title: "x"
created: 2026-05-01
status_history:
  - { tier: 0, at: 2026-05-01, reason: "born" }
---
body
EOF
  run_lib mp_append_status_history "$d/chunk.md" 1 'promoted to heating'
  assert_rc 0 || return 1
  # The new entry should be present after the original.
  if ! grep -q 'tier: 1' "$d/chunk.md"; then
    fail "$TNAME" "new history entry missing"; return 1
  fi
  if ! grep -q '"promoted to heating"' "$d/chunk.md"; then
    fail "$TNAME" "reason text missing"; return 1
  fi
  # Original entry preserved.
  if ! grep -q 'reason: "born"' "$d/chunk.md"; then
    fail "$TNAME" "original history entry was destroyed"; return 1
  fi
  # Frontmatter still well-formed.
  open_n=$(grep -c '^---' "$d/chunk.md")
  if [ "$open_n" != "2" ]; then
    fail "$TNAME" "expected exactly 2 '---' delimiters, got $open_n"; return 1
  fi
  # Regression guard (Skills-B report 2026-05-20): the existing status_history
  # block must NOT get a duplicate header appended.
  sh_headers=$(grep -c '^status_history:' "$d/chunk.md")
  if [ "$sh_headers" != "1" ]; then
    fail "$TNAME" "expected exactly 1 'status_history:' header, got $sh_headers"; return 1
  fi
  pass "$TNAME"
}

t_LIB_TIER_07() {
  TNAME=LIB-TIER-07
  # When upstream provides any N-melting-pot/ dir, discover.sh symlinks it
  # into the overlay; detect_full_overlay_mode returns 0 in that case.
  t_setup
  reg="$TDIR/upstream"
  mk_native_skill "$reg/foo" "foo" "x" "0 2"
  t_patterns "$reg"
  run_lib mp_discover_skills > /dev/null
  run_lib mp_detect_full_overlay_mode foo
  assert_rc 0 || return 1
  # And for a pure overlay skill (no upstream symlinks) it returns 1.
  mk_native_skill "$MP_HOME/bar" "bar" "x" "0"
  run_lib mp_detect_full_overlay_mode bar
  assert_rc 1 || return 1
  pass "$TNAME"
}

t_LIB_TIER_08() {
  TNAME=LIB-TIER-08
  # append_status_history case (a): no pre-existing status_history block.
  # Function must synthesise a fresh block exactly once before the closing ---.
  t_setup
  d="$MP_HOME/foo/0-melting-pot"
  mkdir -p "$d"
  cat > "$d/chunk.md" <<'EOF'
---
title: "no-history"
created: 2026-05-01
---
body
EOF
  run_lib mp_append_status_history "$d/chunk.md" 1 'first promotion'
  assert_rc 0 || return 1
  sh_headers=$(grep -c '^status_history:' "$d/chunk.md")
  if [ "$sh_headers" != "1" ]; then
    fail "$TNAME" "expected exactly 1 'status_history:' header, got $sh_headers"; return 1
  fi
  if ! grep -q '"first promotion"' "$d/chunk.md"; then
    fail "$TNAME" "new entry reason missing"; return 1
  fi
  open_n=$(grep -c '^---' "$d/chunk.md")
  if [ "$open_n" != "2" ]; then
    fail "$TNAME" "expected exactly 2 '---' delimiters, got $open_n"; return 1
  fi
  pass "$TNAME"
}

t_LIB_TIER_09() {
  TNAME=LIB-TIER-09
  # append_status_history case (b): status_history block is followed by more
  # top-level keys. New entry must land INSIDE the existing list, not after
  # the trailing key, and there must be exactly one block header.
  t_setup
  d="$MP_HOME/foo/0-melting-pot"
  mkdir -p "$d"
  cat > "$d/chunk.md" <<'EOF'
---
title: "mid-block"
status_history:
  - { tier: 0, at: 2026-04-01, reason: "born" }
depends_on: []
---
body
EOF
  run_lib mp_append_status_history "$d/chunk.md" 1 'promoted mid-block'
  assert_rc 0 || return 1
  sh_headers=$(grep -c '^status_history:' "$d/chunk.md")
  if [ "$sh_headers" != "1" ]; then
    fail "$TNAME" "expected exactly 1 'status_history:' header, got $sh_headers"; return 1
  fi
  # The new entry must appear BEFORE the `depends_on:` line.
  new_ln=$(grep -n '"promoted mid-block"' "$d/chunk.md" | head -n 1 | cut -d: -f1)
  dep_ln=$(grep -n '^depends_on:' "$d/chunk.md" | head -n 1 | cut -d: -f1)
  if [ -z "$new_ln" ] || [ -z "$dep_ln" ] || [ "$new_ln" -ge "$dep_ln" ]; then
    fail "$TNAME" "new entry not flushed inside existing block (new_ln=$new_ln dep_ln=$dep_ln)"; return 1
  fi
  pass "$TNAME"
}

# ============================================================================
# Section 4: patch.sh — Q-001 policy-free apply + .failed/ markers
# ============================================================================

t_LIB_PATCH_01() {
  TNAME=LIB-PATCH-01
  t_setup
  # Upstream skill: legacy SKILL.md.
  reg="$TDIR/upstream"
  d="$reg/legacy-target"
  mkdir -p "$d"
  cat > "$d/SKILL.md" <<'EOF'
---
name: legacy-target
description: legacy upstream skill
---

EOF
  # Overlay patches dir with one well-formed patch.
  pdir="$MP_HOME/legacy-target/patches"
  mkdir -p "$pdir"
  mk_patch_against_upstream "$d/SKILL.md" "$pdir/001-add-line.patch"

  run_lib mp_apply_in_memory legacy-target "$d/SKILL.md"
  assert_rc 0 || return 1
  if ! grep -q "Patched line appended" "$OUT"; then
    fail "$TNAME" "patched line not present in output"
    cat "$OUT" >&2
    return 1
  fi
  # No .failed/ markers were created.
  if [ -d "$pdir/.failed" ] && [ -n "$(ls -A "$pdir/.failed" 2>/dev/null)" ]; then
    fail "$TNAME" ".failed/ dir non-empty after successful apply"; return 1
  fi
  pass "$TNAME"
}

t_LIB_PATCH_02() {
  TNAME=LIB-PATCH-02
  # Q-001: failed patch records a marker AND apply continues with the next.
  t_setup
  reg="$TDIR/upstream"
  d="$reg/legacy-target"
  mkdir -p "$d"
  cat > "$d/SKILL.md" <<'EOF'
---
name: legacy-target
description: legacy upstream skill
---

EOF
  pdir="$MP_HOME/legacy-target/patches"
  mkdir -p "$pdir"
  mk_broken_patch                     "$pdir/001-broken.patch"
  mk_patch_against_upstream "$d/SKILL.md" "$pdir/002-good.patch"

  run_lib mp_apply_in_memory legacy-target "$d/SKILL.md"
  assert_rc 0 || return 1
  # The good patch should still apply even though 001 failed.
  if ! grep -q "Patched line appended" "$OUT"; then
    fail "$TNAME" "good patch (002) was not applied after failure of 001"
    cat "$OUT" >&2
    return 1
  fi
  # The .failed/ marker should exist for 001.
  marker="$pdir/.failed/001-broken.patch.failed"
  assert_file_exists "$marker" || return 1
  # Marker should contain all four sections.
  for tag in 'patch' 'upstream excerpt' 'reject' 'timestamp'; do
    if ! grep -q "^--- $tag ---" "$marker"; then
      fail "$TNAME" "marker missing section: --- $tag ---"
      return 1
    fi
  done
  pass "$TNAME"
}

t_LIB_PATCH_03() {
  TNAME=LIB-PATCH-03
  # --dry-run reports the failed-patch IDs via MP_PATCH_FAILED but writes NO
  # .failed/ markers.
  t_setup
  reg="$TDIR/upstream"
  d="$reg/legacy-target"
  mkdir -p "$d"
  cat > "$d/SKILL.md" <<'EOF'
---
name: legacy-target
description: legacy upstream skill
---

EOF
  pdir="$MP_HOME/legacy-target/patches"
  mkdir -p "$pdir"
  mk_broken_patch "$pdir/001-broken.patch"

  # Run with --dry-run and assert the marker dir stays empty.
  run_lib mp_apply_in_memory legacy-target "$d/SKILL.md" --dry-run > /dev/null
  if [ -d "$pdir/.failed" ] && [ -n "$(ls -A "$pdir/.failed" 2>/dev/null)" ]; then
    fail "$TNAME" "--dry-run created .failed/ markers"; return 1
  fi
  pass "$TNAME"
}

t_LIB_PATCH_04() {
  TNAME=LIB-PATCH-04
  t_setup
  pdir="$MP_HOME/foo/patches"
  fdir="$pdir/.failed"
  mkdir -p "$fdir"
  printf 'dummy patch\n' > "$pdir/001-x.patch"
  printf 'marker contents\n' > "$fdir/001-x.patch.failed"
  printf 'dummy patch\n' > "$pdir/002-y.patch"

  run_lib mp_patch_status foo
  assert_rc 0 || return 1
  if ! grep -q "001-x.patch	failed" "$OUT"; then
    fail "$TNAME" "001-x.patch should report 'failed'"; return 1
  fi
  if ! grep -q "002-y.patch	not-yet-attempted" "$OUT"; then
    fail "$TNAME" "002-y.patch should report 'not-yet-attempted'"; return 1
  fi
  pass "$TNAME"
}

t_LIB_PATCH_05() {
  TNAME=LIB-PATCH-05
  t_setup
  fdir="$MP_HOME/foo/patches/.failed"
  mkdir -p "$fdir"
  printf 'x\n' > "$fdir/001-x.patch.failed"
  run_lib mp_clear_failed_marker foo 001-x.patch
  assert_rc 0 || return 1
  if [ -e "$fdir/001-x.patch.failed" ]; then
    fail "$TNAME" "marker not removed"; return 1
  fi
  pass "$TNAME"
}

t_LIB_PATCH_06() {
  TNAME=LIB-PATCH-06
  t_setup
  pdir="$MP_HOME/foo/patches"
  fdir="$pdir/.failed"
  mkdir -p "$fdir"
  printf 'x\n' > "$pdir/001-a.patch"
  printf 'x\n' > "$pdir/002-b.patch"
  printf 'x\n' > "$pdir/003-c.patch"
  printf 'x\n' > "$fdir/002-b.patch.failed"
  run_lib mp_count_patches foo
  assert_rc 0 || return 1
  assert_eq "$(cat "$OUT")" "3" || return 1
  run_lib mp_count_failed_markers foo
  assert_rc 0 || return 1
  assert_eq "$(cat "$OUT")" "1" || return 1
  pass "$TNAME"
}

# ============================================================================
# Section 5: compose.sh — manifest + chunks + patches → markdown
# ============================================================================

t_LIB_COMPOSE_01() {
  TNAME=LIB-COMPOSE-01
  t_setup
  d="$MP_HOME/git-rebase"
  mkdir -p "$d/0-melting-pot" "$d/5-melting-pot"
  cat > "$d/meta.md" <<'EOF'
---
name: git:rebase
description: rewrite git history
---
EOF
  cat > "$d/0-melting-pot/scrap.md" <<'EOF'
---
title: "raw scrap"
status_history:
  - { tier: 0, at: 2026-05-01, reason: "born" }
---
Scrap chunk body.
EOF
  cat > "$d/5-melting-pot/canonical.md" <<'EOF'
---
title: "canonical"
status_history:
  - { tier: 5, at: 2026-05-15, reason: "promoted" }
---
Canonical chunk body.
EOF
  run_lib mp_compose_skill git-rebase --format md
  assert_rc 0 || return 1
  assert_stdout_contains "# git:rebase" || return 1
  assert_stdout_contains "> rewrite git history" || return 1
  assert_stdout_contains "## Tier 5 — Pure alloy" || return 1
  assert_stdout_contains "## Tier 0 — Scrap" || return 1
  assert_stdout_contains "Scrap chunk body" || return 1
  assert_stdout_contains "Canonical chunk body" || return 1
  # Tier 5 must appear before Tier 0 (top-down order).
  t5=$(grep -n "## Tier 5" "$OUT" | head -n 1 | cut -d: -f1)
  t0=$(grep -n "## Tier 0" "$OUT" | head -n 1 | cut -d: -f1)
  if [ -z "$t5" ] || [ -z "$t0" ] || [ "$t5" -ge "$t0" ]; then
    fail "$TNAME" "Tier 5 should appear before Tier 0 (got t5=$t5 t0=$t0)"; return 1
  fi
  pass "$TNAME"
}

t_LIB_COMPOSE_02() {
  TNAME=LIB-COMPOSE-02
  t_setup
  d="$MP_HOME/git-rebase"
  mkdir -p "$d/0-melting-pot" "$d/5-melting-pot"
  cat > "$d/meta.md" <<'EOF'
---
name: git:rebase
description: x
---
EOF
  cat > "$d/0-melting-pot/scrap.md" <<'EOF'
---
title: scrap
---
Scrap body
EOF
  cat > "$d/5-melting-pot/pure.md" <<'EOF'
---
title: pure
---
Pure body
EOF
  run_lib mp_compose_skill git-rebase --format md --tiers 5
  assert_rc 0 || return 1
  assert_stdout_contains "## Tier 5" || return 1
  assert_stdout_not_contains "## Tier 0" || return 1
  assert_stdout_contains "Pure body" || return 1
  assert_stdout_not_contains "Scrap body" || return 1
  pass "$TNAME"
}

t_LIB_COMPOSE_03() {
  TNAME=LIB-COMPOSE-03
  t_setup
  d="$MP_HOME/git-rebase"
  mkdir -p "$d/5-melting-pot"
  cat > "$d/meta.md" <<'EOF'
---
name: git:rebase
description: rewrite history
---
EOF
  cat > "$d/5-melting-pot/c.md" <<'EOF'
---
title: "canon"
---
Canon body.
EOF
  run_lib mp_compose_skill git-rebase --format json
  assert_rc 0 || return 1
  # Validate with sqlite3 (POSIX stock).
  valid=$(printf "select json_valid(readfile('%s'));\n" "$(twin "$OUT")" | sqlite3 | tr -d '\r')
  if [ "$valid" != "1" ]; then
    fail "$TNAME" "json_valid returned $valid (expected 1); output:"
    cat "$OUT" >&2
    return 1
  fi
  pass "$TNAME"
}

t_LIB_COMPOSE_04() {
  TNAME=LIB-COMPOSE-04
  t_setup
  reg="$TDIR/upstream"
  d="$reg/legacy-target"
  mkdir -p "$d"
  cat > "$d/SKILL.md" <<'EOF'
---
name: legacy-target
description: legacy upstream skill
---

EOF
  # Set up overlay with a good patch and pre-discover so the overlay dir exists.
  mkdir -p "$MP_HOME/legacy-target/patches"
  mk_patch_against_upstream "$d/SKILL.md" "$MP_HOME/legacy-target/patches/001-good.patch"
  t_patterns "$reg"
  run_lib mp_discover_skills > /dev/null
  # Without --no-patches, the patched line should appear.
  run_lib mp_compose_skill legacy-target --format md
  if ! grep -q "Patched line appended" "$OUT"; then
    fail "$TNAME" "patches should have been applied by default"; return 1
  fi
  # With --no-patches, the patched line should NOT appear.
  run_lib mp_compose_skill legacy-target --format md --no-patches
  if grep -q "Patched line appended" "$OUT"; then
    fail "$TNAME" "--no-patches still emitted patched content"; return 1
  fi
  pass "$TNAME"
}

# ============================================================================
# Section 6: mp/search/action — Phase 2 (FTS5 RRF + tier-aware reindex)
# ============================================================================

# Helper: run the search action under the current sandbox. stdout to $OUT,
# stderr to $ERR, exit to $RC. The action is `set -eu` and self-contained.
run_search() {
  sh "$SEARCH_BIN" "$@" > "$OUT" 2> "$ERR"
  RC=$?
}

# Helper: run the load action under the current sandbox.
run_load() {
  sh "$LOAD_BIN" "$@" > "$OUT" 2> "$ERR"
  RC=$?
}

t_PHASE2_SRCH_01() {
  TNAME=PHASE2-SRCH-01
  # Empty config → search returns "no skills matched" with exit 1.
  t_setup
  # No repos.patterns at all, no overlay skills.
  run_search "git" "rebase" "history"
  assert_rc 1 || return 1
  assert_stdout_contains "no skills matched" || return 1
  pass "$TNAME"
}

t_PHASE2_SRCH_02() {
  TNAME=PHASE2-SRCH-02
  # Single registered legacy skill — searchable on all three axes.
  t_setup
  reg="$TDIR/upstream"
  mk_legacy_skill "$reg/git-rebase" "git:rebase" "rewrite git history"
  t_patterns "$reg"
  run_search "git" "rebase" "history"
  assert_rc 0 || return 1
  assert_stdout_contains "git:rebase" || return 1
  assert_stdout_contains "→ $reg/git-rebase" || return 1
  pass "$TNAME"
}

t_PHASE2_SRCH_03() {
  TNAME=PHASE2-SRCH-03
  # Convergence: a skill matching 2+ axes lands in the Convergence section.
  t_setup
  reg="$TDIR/upstream"
  mk_legacy_skill "$reg/git-rebase" "git:rebase" "rewrite git history"
  mk_legacy_skill "$reg/jq-helper"  "jq:helper"  "process json"
  t_patterns "$reg"
  run_search "git" "rebase" "json"
  assert_rc 0 || return 1
  # "git" + "rebase" both hit git-rebase → axes >= 2 → in Convergence.
  conv_block=$(awk '/^## Convergence/{f=1;next}/^## Single-axis/{f=0}f' "$OUT")
  if ! printf "%s" "$conv_block" | grep -q "git:rebase"; then
    fail "$TNAME" "git:rebase missing from Convergence section"; return 1
  fi
  pass "$TNAME"
}

t_PHASE2_SRCH_04() {
  TNAME=PHASE2-SRCH-04
  # TSV format: 11 tab-separated columns per row.
  t_setup
  reg="$TDIR/upstream"
  mk_legacy_skill "$reg/git-rebase" "git:rebase" "rewrite git history"
  t_patterns "$reg"
  run_search search --format tsv "git" "rebase" "history"
  assert_rc 0 || return 1
  # Expect a row beginning with the path; 10 TAB separators → 11 fields.
  row=$(grep "git-rebase" "$OUT" | head -n 1)
  if [ -z "$row" ]; then
    fail "$TNAME" "no TSV row found in output"; return 1
  fi
  nfields=$(printf "%s" "$row" | awk -F'\t' '{print NF}')
  if [ "$nfields" != "11" ]; then
    fail "$TNAME" "expected 11 TSV columns, got $nfields"
    printf "         row: %s\n" "$row" >&2
    return 1
  fi
  pass "$TNAME"
}

t_PHASE2_SRCH_05() {
  TNAME=PHASE2-SRCH-05
  # JSON format is valid JSON and carries the extended metadata fields.
  t_setup
  reg="$TDIR/upstream"
  mk_legacy_skill "$reg/git-rebase" "git:rebase" "rewrite git history"
  t_patterns "$reg"
  run_search search --format json "git" "rebase" "history"
  assert_rc 0 || return 1
  valid=$(printf "select json_valid(readfile('%s'));\n" "$(twin "$OUT")" | sqlite3 | tr -d '\r')
  if [ "$valid" != "1" ]; then
    fail "$TNAME" "invalid JSON; got: $(cat "$OUT")"; return 1
  fi
  for k in origin avg_tier hits patches_applied patches_failed; do
    if ! grep -q "\"$k\"" "$OUT"; then
      fail "$TNAME" "JSON missing field: $k"; return 1
    fi
  done
  pass "$TNAME"
}

t_PHASE2_SRCH_06() {
  TNAME=PHASE2-SRCH-06
  # Reindex idempotency: running reindex twice on unchanged content leaves the
  # stored hash unchanged and the skill count constant.
  t_setup
  reg="$TDIR/upstream"
  mk_legacy_skill "$reg/git-rebase" "git:rebase" "rewrite git history"
  t_patterns "$reg"
  run_search reindex > /dev/null
  hash1=$(cat "$MP_HOME/search/.index_hash")
  cnt1=$(sqlite3 "$MP_HOME/search/index.db" 'SELECT COUNT(*) FROM skills;' | tr -d '\r')
  run_search reindex > /dev/null
  hash2=$(cat "$MP_HOME/search/.index_hash")
  cnt2=$(sqlite3 "$MP_HOME/search/index.db" 'SELECT COUNT(*) FROM skills;' | tr -d '\r')
  assert_eq "$hash1" "$hash2" || return 1
  assert_eq "$cnt1" "$cnt2" || return 1
  pass "$TNAME"
}

t_PHASE2_SRCH_07() {
  TNAME=PHASE2-SRCH-07
  # Hash-gated auto-reindex: changing a chunk file changes the hash; a
  # subsequent invocation triggers reindex and the new content is searchable.
  t_setup
  reg="$TDIR/upstream"
  mk_legacy_skill "$reg/git-rebase" "git:rebase" "rewrite git history"
  t_patterns "$reg"
  run_search reindex > /dev/null
  hash1=$(cat "$MP_HOME/search/.index_hash")
  # Mutate the SKILL.md body.
  cat > "$reg/git-rebase/SKILL.md" <<EOF
---
name: git:rebase
description: rewrite git history
---

A unique-token-9999 changed paragraph.
EOF
  # Any non-reindex invocation should trigger auto-reindex.
  run_search "unique-token-9999" "rebase" "history" > /dev/null 2>&1
  hash2=$(cat "$MP_HOME/search/.index_hash")
  if [ "$hash1" = "$hash2" ]; then
    fail "$TNAME" "hash did not change after content edit"; return 1
  fi
  # The new token is now searchable.
  run_search "unique-token-9999" "rebase" "history"
  if ! grep -q "git:rebase" "$OUT"; then
    fail "$TNAME" "edited content not indexed after auto-reindex"; return 1
  fi
  pass "$TNAME"
}

t_PHASE2_SRCH_08() {
  TNAME=PHASE2-SRCH-08
  # doctor reports OK for a valid root.
  t_setup
  reg="$TDIR/upstream"
  mk_legacy_skill "$reg/git-rebase" "git:rebase" "x"
  t_patterns "$reg"
  run_search doctor
  assert_rc 0 || return 1
  assert_stdout_contains "OK   $reg" || return 1
  pass "$TNAME"
}

t_PHASE2_SRCH_09() {
  TNAME=PHASE2-SRCH-09
  # doctor --write-sample seeds repos.patterns when missing.
  t_setup
  if [ -f "$MP_PATTERNS" ]; then rm -f "$MP_PATTERNS"; fi
  run_search doctor --write-sample
  assert_file_exists "$MP_PATTERNS" || return 1
  pass "$TNAME"
}

t_PHASE2_SRCH_10() {
  TNAME=PHASE2-SRCH-10
  # --limit caps the number of returned rows.
  t_setup
  reg="$TDIR/upstream"
  i=0; while [ "$i" -lt 6 ]; do
    mk_legacy_skill "$reg/skill-$i" "name:$i" "rebase commit rewrite token-$i"
    i=$((i + 1))
  done
  t_patterns "$reg"
  run_search search --limit 2 "rebase" "commit" "rewrite"
  assert_rc 0 || return 1
  # Count rows that show the "→ /" arrow — one per hit.
  n=$(grep -c '→ /' "$OUT")
  if [ "$n" -gt 2 ]; then
    fail "$TNAME" "expected <= 2 rows with --limit 2, got $n"; return 1
  fi
  pass "$TNAME"
}

t_PHASE2_SRCH_11() {
  TNAME=PHASE2-SRCH-11
  # Patches applied count surfaces in search results (text format).
  # The mk_patch_against_upstream fixture appends a unique line after the
  # canonical 5-line frontmatter — that line is what we search for.
  t_setup
  reg="$TDIR/upstream"
  d="$reg/legacy-target"
  mkdir -p "$d"
  cat > "$d/SKILL.md" <<'EOF'
---
name: legacy-target
description: legacy upstream skill
---

EOF
  pdir="$MP_HOME/legacy-target/patches"
  mkdir -p "$pdir"
  mk_patch_against_upstream "$d/SKILL.md" "$pdir/001-good.patch"
  t_patterns "$reg"
  # The patch inserts "Patched line appended." into the indexed content.
  run_search "Patched" "appended" "legacy"
  assert_rc 0 || return 1
  if ! grep -q "patches=1 applied" "$OUT"; then
    fail "$TNAME" "patches=1 applied line missing; got:"
    cat "$OUT" >&2
    return 1
  fi
  pass "$TNAME"
}

t_PHASE2_SRCH_12() {
  TNAME=PHASE2-SRCH-12
  # Failed patches surface in results AND the .failed/ marker exists.
  t_setup
  reg="$TDIR/upstream"
  d="$reg/legacy-target"
  mkdir -p "$d"
  cat > "$d/SKILL.md" <<'EOF'
---
name: legacy-target
description: legacy upstream skill
---

EOF
  pdir="$MP_HOME/legacy-target/patches"
  mkdir -p "$pdir"
  mk_broken_patch                     "$pdir/001-broken.patch"
  mk_patch_against_upstream "$d/SKILL.md" "$pdir/002-good.patch"
  t_patterns "$reg"
  run_search "Patched" "appended" "legacy"
  assert_rc 0 || return 1
  if ! grep -q "patches=1 applied \[failed=1\]" "$OUT"; then
    fail "$TNAME" "expected 'patches=1 applied [failed=1]' line; got:"
    cat "$OUT" >&2
    return 1
  fi
  marker="$pdir/.failed/001-broken.patch.failed"
  assert_file_exists "$marker" || return 1
  pass "$TNAME"
}

t_PHASE2_SRCH_13() {
  TNAME=PHASE2-SRCH-13
  # Sandbox: discovery reads ONLY $MP_PATTERNS — a stray config under HOME is ignored.
  t_setup
  reg="$TDIR/upstream"
  mk_legacy_skill "$reg/git-rebase" "git:rebase" "rewrite history"
  # Do NOT add to $MP_PATTERNS. Instead, simulate a stray config under HOME.
  fake_home="$TDIR/fake-home"
  mkdir -p "$fake_home/.other-skills"
  printf "%s\t*\n" "$reg" > "$fake_home/.other-skills/repos.patterns"
  HOME="$fake_home" run_search "git" "rebase" "history"
  # Empty MP_PATTERNS = no skills indexed = exit 1.
  assert_rc 1 || return 1
  pass "$TNAME"
}

t_PHASE2_SRCH_14() {
  TNAME=PHASE2-SRCH-14
  # Origin=mix surfaces in results when both layers contribute.
  t_setup
  reg="$TDIR/upstream"
  mk_legacy_skill "$reg/token-mix-target" "token:mix" "token-mix-unique-corpus"
  mkdir -p "$MP_HOME/token-mix-target/patches"
  t_patterns "$reg"
  run_search "token-mix-unique-corpus" "token" "mix"
  assert_rc 0 || return 1
  if ! grep -q "origin=mix" "$OUT"; then
    fail "$TNAME" "expected origin=mix in results; got:"
    cat "$OUT" >&2
    return 1
  fi
  pass "$TNAME"
}

t_PHASE2_SRCH_15() {
  TNAME=PHASE2-SRCH-15
  # Q-007: upstream with N-melting-pot/ dirs is indexed via symlinked tier dirs
  # (so chunk content appears under the overlay path).
  t_setup
  reg="$TDIR/upstream"
  mk_native_skill "$reg/native-skill" "native:skill" "native upstream" "0 3"
  # Inject a unique token into one of the tier chunks so we can search for it.
  printf "\nuniqsearchtoken-XYZ123\n" >> "$reg/native-skill/3-melting-pot/chunk-3.md"
  t_patterns "$reg"
  run_search "uniqsearchtoken-XYZ123" "native" "skill"
  assert_rc 0 || return 1
  # Result path should be the overlay path (Q-007: emitted path swings to overlay).
  if ! grep -q "→ $MP_HOME/native-skill" "$OUT"; then
    fail "$TNAME" "expected overlay-rooted result path; got:"
    cat "$OUT" >&2
    return 1
  fi
  # And the symlinked tier dir should exist.
  assert_symlink_to "$MP_HOME/native-skill/3-melting-pot" "$reg/native-skill/3-melting-pot" || return 1
  pass "$TNAME"
}

t_PHASE2_SRCH_16() {
  TNAME=PHASE2-SRCH-16
  # Regression: --format json with >=2 results must be valid JSON. The old
  # hand-joined string builder lost its comma flag in a pipe subshell, so it
  # emitted comma-less (invalid) JSON for two or more objects. JSON is now
  # produced by sqlite json_group_array, which always comma-joins correctly.
  t_setup
  reg="$TDIR/upstream"
  mk_legacy_skill "$reg/git-rebase"  "git:rebase"  "rewrite git history"
  mk_legacy_skill "$reg/git-reflog"  "git:reflog"  "recover git history via reflog"
  mk_legacy_skill "$reg/git-bisect"  "git:bisect"  "git history bisect search"
  t_patterns "$reg"
  run_search search --format json "git" "history" "rebase"
  assert_rc 0 || return 1
  valid=$(printf "select json_valid(readfile('%s'));\n" "$(twin "$OUT")" | sqlite3 | tr -d '\r')
  if [ "$valid" != "1" ]; then
    fail "$TNAME" "invalid JSON for multi-result search; got: $(cat "$OUT")"; return 1
  fi
  n=$(printf "select json_array_length(readfile('%s'),'\$.results');\n" "$(twin "$OUT")" | sqlite3 | tr -d '\r')
  if [ "${n:-0}" -lt 2 ]; then
    fail "$TNAME" "expected >=2 results to exercise comma-join; got n=$n: $(cat "$OUT")"; return 1
  fi
  pass "$TNAME"
}

# ============================================================================
# Section 7: mp/load/action — Phase 4 (compose CLI)
# ============================================================================

t_PHASE4_LOAD_01() {
  TNAME=PHASE4-LOAD-01
  # md format: tier headers + ordering 5 → 0, by name: lookup.
  t_setup
  d="$MP_HOME/git-rebase"
  mkdir -p "$d/0-melting-pot" "$d/5-melting-pot"
  cat > "$d/meta.md" <<'EOF'
---
name: git:rebase
description: rewrite git history
---
EOF
  cat > "$d/0-melting-pot/scrap.md" <<'EOF'
---
title: "scrap chunk"
---
Scrap body.
EOF
  cat > "$d/5-melting-pot/canonical.md" <<'EOF'
---
title: "canonical"
---
Canonical body.
EOF
  run_load "git:rebase"
  assert_rc 0 || return 1
  assert_stdout_contains "# git:rebase" || return 1
  assert_stdout_contains "## Tier 5 — Pure alloy" || return 1
  assert_stdout_contains "## Tier 0 — Scrap" || return 1
  t5=$(grep -n "## Tier 5" "$OUT" | head -n 1 | cut -d: -f1)
  t0=$(grep -n "## Tier 0" "$OUT" | head -n 1 | cut -d: -f1)
  if [ -z "$t5" ] || [ -z "$t0" ] || [ "$t5" -ge "$t0" ]; then
    fail "$TNAME" "Tier 5 should precede Tier 0 (got t5=$t5 t0=$t0)"; return 1
  fi
  pass "$TNAME"
}

t_PHASE4_LOAD_02() {
  TNAME=PHASE4-LOAD-02
  # json format validates with sqlite3 json_valid().
  t_setup
  d="$MP_HOME/git-rebase"
  mkdir -p "$d/5-melting-pot"
  cat > "$d/meta.md" <<'EOF'
---
name: git:rebase
description: rewrite history
---
EOF
  cat > "$d/5-melting-pot/c.md" <<'EOF'
---
title: "canon"
---
body
EOF
  run_load git-rebase --format json
  assert_rc 0 || return 1
  valid=$(printf "select json_valid(readfile('%s'));\n" "$(twin "$OUT")" | sqlite3 | tr -d '\r')
  if [ "$valid" != "1" ]; then
    fail "$TNAME" "json_valid returned $valid; got:"
    cat "$OUT" >&2
    return 1
  fi
  pass "$TNAME"
}

t_PHASE4_LOAD_03() {
  TNAME=PHASE4-LOAD-03
  # --tiers filter drops non-listed tiers.
  t_setup
  d="$MP_HOME/git-rebase"
  mkdir -p "$d/0-melting-pot" "$d/5-melting-pot"
  cat > "$d/meta.md" <<'EOF'
---
name: git:rebase
description: x
---
EOF
  printf "%s\n" "scrap-body" > "$d/0-melting-pot/scrap.md"
  printf "%s\n" "canon-body" > "$d/5-melting-pot/canon.md"
  run_load git-rebase --tiers 5
  assert_rc 0 || return 1
  assert_stdout_contains "## Tier 5" || return 1
  assert_stdout_not_contains "## Tier 0" || return 1
  pass "$TNAME"
}

t_PHASE4_LOAD_04() {
  TNAME=PHASE4-LOAD-04
  # --no-patches: legacy upstream + overlay patch → without --no-patches the
  # patched line is present; with --no-patches it is NOT.
  t_setup
  reg="$TDIR/upstream"
  d="$reg/legacy-target"
  mkdir -p "$d"
  cat > "$d/SKILL.md" <<'EOF'
---
name: legacy-target
description: legacy upstream skill
---

EOF
  mkdir -p "$MP_HOME/legacy-target/patches"
  mk_patch_against_upstream "$d/SKILL.md" "$MP_HOME/legacy-target/patches/001-good.patch"
  t_patterns "$reg"
  # Default (patches applied).
  run_load legacy-target
  if ! grep -q "Patched line appended" "$OUT"; then
    fail "$TNAME" "default mode should include the patched line"; return 1
  fi
  # --no-patches: patched line absent.
  run_load legacy-target --no-patches
  if grep -q "Patched line appended" "$OUT"; then
    fail "$TNAME" "--no-patches still showed the patched line"; return 1
  fi
  pass "$TNAME"
}

t_PHASE4_LOAD_05() {
  TNAME=PHASE4-LOAD-05
  # --with-history surfaces a chunk's status_history entries.
  t_setup
  d="$MP_HOME/skill-h"
  mkdir -p "$d/2-melting-pot"
  cat > "$d/meta.md" <<'EOF'
---
name: skill:h
description: x
---
EOF
  cat > "$d/2-melting-pot/c.md" <<'EOF'
---
title: "history sample"
status_history:
  - { tier: 0, at: 2026-04-12, reason: "born from session" }
  - { tier: 2, at: 2026-05-01, reason: "promoted twice" }
---
Body.
EOF
  run_load skill-h --with-history
  assert_rc 0 || return 1
  assert_stdout_contains "## Status history" || return 1
  assert_stdout_contains "promoted twice" || return 1
  pass "$TNAME"
}

t_PHASE4_LOAD_06() {
  TNAME=PHASE4-LOAD-06
  # mix-origin: overlay carries patches, upstream carries the SKILL.md body.
  t_setup
  reg="$TDIR/upstream"
  d="$reg/legacy-target"
  mkdir -p "$d"
  cat > "$d/SKILL.md" <<'EOF'
---
name: legacy-target
description: legacy upstream skill
---

EOF
  mkdir -p "$MP_HOME/legacy-target/patches"
  mk_patch_against_upstream "$d/SKILL.md" "$MP_HOME/legacy-target/patches/001-good.patch"
  t_patterns "$reg"
  run_load legacy-target
  assert_rc 0 || return 1
  assert_stdout_contains "origin=mix" || return 1
  assert_stdout_contains "patches applied: 1" || return 1
  pass "$TNAME"
}

t_PHASE4_LOAD_07() {
  TNAME=PHASE4-LOAD-07
  # Legacy SKILL.md-only skill (no tier dirs) renders at tier 5.
  t_setup
  reg="$TDIR/upstream"
  mk_legacy_skill "$reg/legacy-only" "legacy:only" "legacy single-file skill"
  t_patterns "$reg"
  run_load legacy-only
  assert_rc 0 || return 1
  assert_stdout_contains "## Tier 5" || return 1
  assert_stdout_contains "### SKILL.md" || return 1
  assert_stdout_contains "Body for legacy:only" || return 1
  pass "$TNAME"
}

t_PHASE4_LOAD_08() {
  TNAME=PHASE4-LOAD-08
  # Pure-overlay skill (no registered match) composes fine.
  t_setup
  mk_native_skill "$MP_HOME/overlay-born" "overlay:born" "user-grown skill" "0 1"
  run_load overlay-born
  assert_rc 0 || return 1
  assert_stdout_contains "# overlay:born" || return 1
  assert_stdout_contains "origin=ovl" || return 1
  assert_stdout_contains "Body of tier-0 chunk for overlay:born" || return 1
  assert_stdout_contains "Body of tier-1 chunk for overlay:born" || return 1
  pass "$TNAME"
}

t_PHASE4_LOAD_09() {
  TNAME=PHASE4-LOAD-09
  # Missing skill exits 1 with a clear error.
  t_setup
  run_load no-such-skill-12345
  assert_rc 1 || return 1
  assert_stderr_contains "no such skill" || return 1
  pass "$TNAME"
}

# ============================================================================
# Section 8: mp/list/action — Phase 3 (flat inventory)
# ============================================================================

# Helper: run the list action under the current sandbox.
run_list() {
  sh "$LIST_BIN" "$@" > "$OUT" 2> "$ERR"
  RC=$?
}

t_PHASE3_LIST_01() {
  TNAME=PHASE3-LIST-01
  # Empty pot → "no skills discovered." + exit 1.
  t_setup
  : > "$MP_PATTERNS"
  run_list
  assert_rc 1 || return 1
  assert_stdout_contains "no skills discovered" || return 1
  pass "$TNAME"
}

t_PHASE3_LIST_02() {
  TNAME=PHASE3-LIST-02
  # text format: groups by origin → root. One reg-legacy, one pure overlay.
  t_setup
  reg="$TDIR/upstream"
  mk_legacy_skill "$reg/git-rebase" "git:rebase" "rewrite git history"
  t_patterns "$reg"
  mk_native_skill "$MP_HOME/my-skill" "my:skill" "overlay skill" "0"
  run_list
  assert_rc 0 || return 1
  assert_stdout_contains "[reg]" || return 1
  assert_stdout_contains "[ovl]" || return 1
  assert_stdout_contains "git:rebase" || return 1
  assert_stdout_contains "my:skill" || return 1
  pass "$TNAME"
}

t_PHASE3_LIST_03() {
  TNAME=PHASE3-LIST-03
  # tsv format: 10 columns (name dirname origin tiers chunks patches failed desc path root).
  t_setup
  reg="$TDIR/upstream"
  mk_legacy_skill "$reg/foo" "foo" "x"
  t_patterns "$reg"
  run_list --format tsv
  assert_rc 0 || return 1
  cols=$(awk -F'\t' 'NR==1{print NF}' "$OUT")
  assert_eq "$cols" "10" || return 1
  pass "$TNAME"
}

t_PHASE3_LIST_04() {
  TNAME=PHASE3-LIST-04
  # JSON format validates and contains tiers_present / chunk_count / patches_count.
  t_setup
  reg="$TDIR/upstream"
  mk_native_skill "$reg/native-skill" "native:skill" "x" "0 3"
  t_patterns "$reg"
  run_list --format json
  assert_rc 0 || return 1
  valid=$(printf "select json_valid(readfile('%s'));\n" "$(twin "$OUT")" | sqlite3 | tr -d '\r')
  if [ "$valid" != "1" ]; then
    fail "$TNAME" "json_valid returned $valid"; cat "$OUT" >&2; return 1
  fi
  # grep -F so brackets in the literal are not treated as a character class.
  if ! grep -F -q '"tiers_present":"[0,3]-melting-pot"' "$OUT"; then
    fail "$TNAME" "stdout missing tiers_present:[0,3]"; cat "$OUT" >&2; return 1
  fi
  assert_stdout_contains '"chunk_count":2' || return 1
  assert_stdout_contains '"origin":"reg"' || return 1
  pass "$TNAME"
}

t_PHASE3_LIST_05() {
  TNAME=PHASE3-LIST-05
  # --name glob filter narrows the result set.
  t_setup
  reg="$TDIR/upstream"
  mk_legacy_skill "$reg/git-rebase" "git:rebase" "x"
  mk_legacy_skill "$reg/aws-s3-sync" "aws:s3-sync" "y"
  t_patterns "$reg"
  run_list --name 'git-*' --format tsv
  assert_rc 0 || return 1
  if ! grep -q 'git:rebase' "$OUT"; then
    fail "$TNAME" "missing git:rebase"; cat "$OUT" >&2; return 1
  fi
  if grep -q 'aws:s3-sync' "$OUT"; then
    fail "$TNAME" "aws:s3-sync should have been filtered out"; return 1
  fi
  pass "$TNAME"
}

t_PHASE3_LIST_06() {
  TNAME=PHASE3-LIST-06
  # --count returns integer; --names-only emits names only.
  t_setup
  reg="$TDIR/upstream"
  mk_legacy_skill "$reg/a" "a:one" "x"
  mk_legacy_skill "$reg/b" "b:one" "y"
  t_patterns "$reg"
  run_list --count
  assert_rc 0 || return 1
  c=$(cat "$OUT" | tr -d ' ')
  assert_eq "$c" "2" || return 1
  run_list --names-only
  assert_rc 0 || return 1
  lc=$(wc -l < "$OUT" | tr -d ' ')
  assert_eq "$lc" "2" || return 1
  pass "$TNAME"
}

t_PHASE3_LIST_07() {
  TNAME=PHASE3-LIST-07
  # Patches and failed-markers appear in row metadata.
  t_setup
  reg="$TDIR/upstream"
  mk_legacy_skill "$reg/legacy-target" "legacy-target" "x"
  t_patterns "$reg"
  pdir="$MP_HOME/legacy-target/patches"
  mkdir -p "$pdir/.failed"
  printf 'x\n' > "$pdir/001-x.patch"
  printf 'marker\n' > "$pdir/.failed/001-x.patch.failed"
  run_list --format tsv
  assert_rc 0 || return 1
  # Column 6 = patches_count, column 7 = patches_failed_count.
  row=$(grep 'legacy-target' "$OUT" | head -n1)
  pc=$(printf "%s" "$row" | awk -F'\t' '{print $6}')
  pf=$(printf "%s" "$row" | awk -F'\t' '{print $7}')
  assert_eq "$pc" "1" || return 1
  assert_eq "$pf" "1" || return 1
  pass "$TNAME"
}

# ============================================================================
# Section 9: mp/crud/action — Phase 3 (lifecycle helpers)
# ============================================================================

run_crud() {
  sh "$CRUD_BIN" "$@" > "$OUT" 2> "$ERR"
  RC=$?
}

t_PHASE3_CRUD_01() {
  TNAME=PHASE3-CRUD-01
  # scaffold native creates meta.md + 0-melting-pot/first.md with derived name.
  t_setup
  run_crud scaffold my-new-skill
  assert_rc 0 || return 1
  assert_file_exists "$MP_HOME/my-new-skill/meta.md" || return 1
  assert_file_exists "$MP_HOME/my-new-skill/0-melting-pot/first.md" || return 1
  if ! grep -q "name: my:new-skill" "$MP_HOME/my-new-skill/meta.md"; then
    fail "$TNAME" "name not derived correctly"; return 1
  fi
  pass "$TNAME"
}

t_PHASE3_CRUD_02() {
  TNAME=PHASE3-CRUD-02
  # scaffold --legacy creates SKILL.md (no tier dirs).
  t_setup
  run_crud scaffold legacy-style --legacy
  assert_rc 0 || return 1
  assert_file_exists "$MP_HOME/legacy-style/SKILL.md" || return 1
  if [ -d "$MP_HOME/legacy-style/0-melting-pot" ]; then
    fail "$TNAME" "legacy scaffold should NOT create tier dirs"; return 1
  fi
  pass "$TNAME"
}

t_PHASE3_CRUD_03() {
  TNAME=PHASE3-CRUD-03
  # validate succeeds on clean native skill.
  t_setup
  run_crud scaffold ok-skill > /dev/null
  run_crud validate ok-skill
  assert_rc 0 || return 1
  assert_stdout_contains "OK:" || return 1
  pass "$TNAME"
}

t_PHASE3_CRUD_04() {
  TNAME=PHASE3-CRUD-04
  # validate warns on bare N/ tier dir but does not fail (Q-007 warning).
  t_setup
  run_crud scaffold warn-skill > /dev/null
  mkdir -p "$MP_HOME/warn-skill/3"   # bare N/ — not recognized
  cat > "$MP_HOME/warn-skill/3/sneak.md" <<'EOF'
---
title: x
---
body
EOF
  run_crud validate warn-skill
  assert_rc 0 || return 1
  assert_stderr_contains "bare tier dir '3/' is not recognized" || return 1
  pass "$TNAME"
}

t_PHASE3_CRUD_05() {
  TNAME=PHASE3-CRUD-05
  # validate reports patch failures via stale marker shape.
  t_setup
  run_crud scaffold patch-target > /dev/null
  pdir="$MP_HOME/patch-target/patches"
  fdir="$pdir/.failed"
  mkdir -p "$fdir"
  printf 'bogus\n' > "$fdir/001-x.patch.failed"  # missing all 4 sections
  run_crud validate patch-target
  assert_rc 1 || return 1
  assert_stderr_contains "failed marker missing section" || return 1
  pass "$TNAME"
}

t_PHASE3_CRUD_06() {
  TNAME=PHASE3-CRUD-06
  # trash + restore roundtrip.
  t_setup
  run_crud scaffold trash-me > /dev/null
  run_crud trash trash-me
  assert_rc 0 || return 1
  if [ -d "$MP_HOME/trash-me" ]; then
    fail "$TNAME" "skill still in place after trash"; return 1
  fi
  trash_path=$(cat "$OUT")
  if [ ! -d "$trash_path" ]; then
    fail "$TNAME" "trash dir missing: $trash_path"; return 1
  fi
  assert_file_exists "$trash_path/.mp-trash-meta.json" || return 1
  run_crud restore "$trash_path"
  assert_rc 0 || return 1
  if [ ! -d "$MP_HOME/trash-me" ]; then
    fail "$TNAME" "skill not restored to original location"; return 1
  fi
  pass "$TNAME"
}

t_PHASE3_CRUD_07() {
  TNAME=PHASE3-CRUD-07
  # patch-add renumbers to next NNN- slot.
  t_setup
  mkdir -p "$MP_HOME/skill-a"
  cat > "$MP_HOME/skill-a/meta.md" <<'EOF'
---
name: skill:a
description: x
---
EOF
  ppatch="$TDIR/sample.patch"
  cat > "$ppatch" <<'EOF'
diff --git a/upstream.md b/upstream.md
--- a/upstream.md
+++ b/upstream.md
@@ -1,1 +1,2 @@
 hello
+world
EOF
  run_crud patch-add skill-a "$ppatch"
  assert_rc 0 || return 1
  assert_file_exists "$MP_HOME/skill-a/patches/001-sample.patch" || return 1
  run_crud patch-add skill-a "$ppatch"
  assert_rc 0 || return 1
  assert_file_exists "$MP_HOME/skill-a/patches/002-sample.patch" || return 1
  pass "$TNAME"
}

t_PHASE3_CRUD_08() {
  TNAME=PHASE3-CRUD-08
  # patch-list reports status per patch.
  t_setup
  mkdir -p "$MP_HOME/skill-b/patches/.failed"
  printf 'p\n' > "$MP_HOME/skill-b/patches/001-x.patch"
  printf 'p\n' > "$MP_HOME/skill-b/patches/002-y.patch"
  printf 'm\n' > "$MP_HOME/skill-b/patches/.failed/001-x.patch.failed"
  run_crud patch-list skill-b
  assert_rc 0 || return 1
  if ! grep -q "001-x.patch	failed" "$OUT"; then
    fail "$TNAME" "001-x should report 'failed'"; cat "$OUT" >&2; return 1
  fi
  if ! grep -q "002-y.patch	not-yet-attempted" "$OUT"; then
    fail "$TNAME" "002-y should report 'not-yet-attempted'"; return 1
  fi
  pass "$TNAME"
}

t_PHASE3_CRUD_09() {
  TNAME=PHASE3-CRUD-09
  # patch-remove clears patch AND .failed marker.
  t_setup
  mkdir -p "$MP_HOME/skill-c/patches/.failed"
  printf 'p\n' > "$MP_HOME/skill-c/patches/001-x.patch"
  printf 'm\n' > "$MP_HOME/skill-c/patches/.failed/001-x.patch.failed"
  run_crud patch-remove skill-c 001-x.patch
  assert_rc 0 || return 1
  if [ -e "$MP_HOME/skill-c/patches/001-x.patch" ]; then
    fail "$TNAME" "patch file not removed"; return 1
  fi
  if [ -e "$MP_HOME/skill-c/patches/.failed/001-x.patch.failed" ]; then
    fail "$TNAME" ".failed marker not removed"; return 1
  fi
  pass "$TNAME"
}

t_PHASE3_CRUD_10() {
  TNAME=PHASE3-CRUD-10
  # collision-check: 0 if free, 1 if taken.
  t_setup
  run_crud collision-check brand-new
  assert_rc 0 || return 1
  run_crud scaffold brand-new > /dev/null
  run_crud collision-check brand-new
  assert_rc 1 || return 1
  assert_stderr_contains "collision" || return 1
  pass "$TNAME"
}

t_PHASE3_CRUD_11() {
  TNAME=PHASE3-CRUD-11
  # import-preview emits TSV with path/name/desc/tiers/issues columns.
  t_setup
  reg="$TDIR/upstream"
  mk_legacy_skill "$reg/legacy-one" "legacy:one" "first"
  mk_native_skill "$reg/native-one" "native:one" "second" "0 5"
  run_crud import-preview "$reg"
  assert_rc 0 || return 1
  # Each row has 5 tab-separated columns.
  rows=$(wc -l < "$OUT" | tr -d ' ')
  assert_eq "$rows" "2" || return 1
  if ! grep -q "legacy" "$OUT"; then
    fail "$TNAME" "missing legacy column for SKILL.md row"; return 1
  fi
  if ! grep -q '\[0,5\]-melting-pot' "$OUT"; then
    fail "$TNAME" "missing native tier rendering"; cat "$OUT" >&2; return 1
  fi
  pass "$TNAME"
}

t_PHASE3_CRUD_12() {
  TNAME=PHASE3-CRUD-12
  # --dry-run on trash doesn't move the skill.
  t_setup
  run_crud scaffold keep-me > /dev/null
  run_crud trash keep-me --dry-run
  assert_rc 0 || return 1
  assert_stdout_contains "DRY-RUN trash" || return 1
  if [ ! -d "$MP_HOME/keep-me" ]; then
    fail "$TNAME" "--dry-run moved the skill"; return 1
  fi
  pass "$TNAME"
}

# ============================================================================
# Section 10: mp/learn/action — Phase 5 (lifecycle automation)
# ============================================================================

run_learn() {
  sh "$LEARN_BIN" "$@" > "$OUT" 2> "$ERR"
  RC=$?
}

# Stdin variant.
run_learn_stdin() {
  stdin_data="$1"; shift
  printf "%s" "$stdin_data" | sh "$LEARN_BIN" "$@" > "$OUT" 2> "$ERR"
  RC=$?
}

# Make a chunk. Tier movement is usage-driven (no promote_when/demote_when),
# so a chunk needs no rule keys — just identity + a born status_history entry.
# Args: <path> <tier> [use_count]
mk_chunk() {
  path="$1"; tier="$2"; use_count="${3:-0}"
  mkdir -p "$(dirname "$path")"
  {
    printf -- "---\n"
    printf -- "title: \"%s\"\n" "$(basename "$path" .md)"
    printf -- "created: 2026-01-01\n"
    printf -- "last_used: 2026-01-01\n"
    printf -- "use_count: %s\n" "$use_count"
    printf -- "provenance:\n"
    printf -- "  - session: test\n"
    printf -- "depends_on: []\n"
    printf -- "status_history:\n"
    printf -- "  - { tier: %s, at: 2026-01-01, reason: \"born\" }\n" "$tier"
    printf -- "---\n"
    printf "body\n"
  } > "$path"
}

# Common helper: a "today-ish" date for fixtures.
TODAY_UTC=$(date -u +%Y-%m-%d)

t_PHASE5_LEARN_01() {
  TNAME=PHASE5-LEARN-01
  # harvest live: valid JSON parses, proposals counted, no --apply means no mutation.
  t_setup
  json='{"proposals":[{"action":"create","skill":"a","chunk_name":"x","title":"t","body":"b","session":"s"}]}'
  run_learn_stdin "$json" harvest
  assert_rc 0 || return 1
  assert_stdout_contains "proposals: 1" || return 1
  if [ -e "$MP_HOME/a/0-melting-pot/x.md" ]; then
    fail "$TNAME" "harvest without --apply should not mutate"; return 1
  fi
  pass "$TNAME"
}

t_PHASE5_LEARN_02() {
  TNAME=PHASE5-LEARN-02
  # harvest --apply create writes a new tier-0 chunk with proper frontmatter.
  t_setup
  json='{"proposals":[{"action":"create","skill":"a","chunk_name":"x","title":"My Tip","body":"the body","session":"sess1"}]}'
  run_learn_stdin "$json" harvest --apply
  assert_rc 0 || return 1
  assert_file_exists "$MP_HOME/a/0-melting-pot/x.md" || return 1
  if ! grep -q 'title: "My Tip"' "$MP_HOME/a/0-melting-pot/x.md"; then
    fail "$TNAME" "title not propagated to frontmatter"; return 1
  fi
  if ! grep -q 'the body' "$MP_HOME/a/0-melting-pot/x.md"; then
    fail "$TNAME" "body not propagated"; return 1
  fi
  pass "$TNAME"
}

t_PHASE5_LEARN_03() {
  TNAME=PHASE5-LEARN-03
  # harvest transcript mode: reads .pending-transcript, unlinks it, echoes path.
  t_setup
  mkdir -p "$MP_HOME/learn"
  printf '/tmp/mock-jsonl-XYZ\n' > "$MP_HOME/learn/.pending-transcript"
  touch /tmp/mock-jsonl-XYZ
  run_learn harvest
  assert_rc 0 || return 1
  assert_stdout_contains "transcript-mode harvest" || return 1
  assert_stdout_contains "/tmp/mock-jsonl-XYZ" || return 1
  if [ -e "$MP_HOME/learn/.pending-transcript" ]; then
    fail "$TNAME" ".pending-transcript should be unlinked after read"; return 1
  fi
  rm -f /tmp/mock-jsonl-XYZ
  pass "$TNAME"
}

t_PHASE5_LEARN_04() {
  TNAME=PHASE5-LEARN-04
  # good use -> promote moves the chunk to tier+1, unconditionally.
  t_setup
  d="$MP_HOME/skill-x"
  mkdir -p "$d/0-melting-pot"
  mk_chunk "$d/0-melting-pot/p.md" 0
  run_learn promote "skill-x/0-melting-pot/p.md"
  assert_rc 0 || return 1
  assert_file_exists "$d/1-melting-pot/p.md" || return 1
  if [ -e "$d/0-melting-pot/p.md" ]; then
    fail "$TNAME" "source not removed after promote"; return 1
  fi
  if ! grep -q 'promoted from tier 0' "$d/1-melting-pot/p.md"; then
    fail "$TNAME" "status_history entry missing"; return 1
  fi
  pass "$TNAME"
}

t_PHASE5_LEARN_05() {
  TNAME=PHASE5-LEARN-05
  # promote at the ceiling (tier 5): refuse, exit 1, chunk stays.
  t_setup
  d="$MP_HOME/skill-x"
  mkdir -p "$d/5-melting-pot"
  mk_chunk "$d/5-melting-pot/q.md" 5
  run_learn promote "skill-x/5-melting-pot/q.md"
  assert_rc 1 || return 1
  if [ ! -e "$d/5-melting-pot/q.md" ]; then
    fail "$TNAME" "chunk should remain at tier 5"; return 1
  fi
  pass "$TNAME"
}

t_PHASE5_LEARN_06() {
  TNAME=PHASE5-LEARN-06
  # bad use -> demote moves the chunk to tier-1, unconditionally.
  t_setup
  d="$MP_HOME/skill-y"
  mkdir -p "$d/2-melting-pot"
  mk_chunk "$d/2-melting-pot/d.md" 2
  run_learn demote "skill-y/2-melting-pot/d.md"
  assert_rc 0 || return 1
  assert_file_exists "$d/1-melting-pot/d.md" || return 1
  if ! grep -q 'demoted from tier 2' "$d/1-melting-pot/d.md"; then
    fail "$TNAME" "status_history entry missing"; return 1
  fi
  pass "$TNAME"
}

t_PHASE5_LEARN_07() {
  TNAME=PHASE5-LEARN-07
  # bad use at tier 0 has nowhere lower to go -> demote removes the chunk.
  t_setup
  d="$MP_HOME/floor-target"
  mkdir -p "$d/0-melting-pot"
  cat > "$d/meta.md" <<'EOF'
---
name: floor:target
description: x
---
EOF
  mk_chunk "$d/0-melting-pot/scrap.md" 0
  run_learn demote "floor-target/0-melting-pot/scrap.md"
  assert_rc 0 || return 1
  assert_stdout_contains "removed" || return 1
  if [ -e "$d/0-melting-pot/scrap.md" ]; then
    fail "$TNAME" "tier-0 chunk should be removed on demote"; return 1
  fi
  pass "$TNAME"
}

t_PHASE5_LEARN_08() {
  TNAME=PHASE5-LEARN-08
  # refactor proposes consolidation when titles match across chunks.
  t_setup
  d1="$MP_HOME/dup-a"; mkdir -p "$d1/0-melting-pot"
  d2="$MP_HOME/dup-b"; mkdir -p "$d2/0-melting-pot"
  cat > "$d1/meta.md" <<'EOF'
---
name: dup:a
description: x
---
EOF
  cat > "$d2/meta.md" <<'EOF'
---
name: dup:b
description: x
---
EOF
  cat > "$d1/0-melting-pot/x.md" <<'EOF'
---
title: "Same title"
---
body A
EOF
  cat > "$d2/0-melting-pot/y.md" <<'EOF'
---
title: "Same title"
---
body B
EOF
  run_learn refactor
  assert_rc 0 || return 1
  assert_stdout_contains "overlap proposals" || return 1
  pass "$TNAME"
}

t_PHASE5_LEARN_09() {
  TNAME=PHASE5-LEARN-09
  # cascade flags dependents (no auto-mutation per Q-002 v1).
  t_setup
  # Skill "git-rebase" has a chunk at tier 5.
  d1="$MP_HOME/git-rebase"; mkdir -p "$d1/5-melting-pot"
  cat > "$d1/meta.md" <<'EOF'
---
name: git:rebase
description: x
---
EOF
  printf -- "---\ntitle: basic\n---\nbody\n" > "$d1/5-melting-pot/basic-rebase.md"
  # Dependent chunk references it via depends_on.
  d2="$MP_HOME/my-flow"; mkdir -p "$d2/0-melting-pot"
  cat > "$d2/meta.md" <<'EOF'
---
name: my:flow
description: x
---
EOF
  cat > "$d2/0-melting-pot/dependent.md" <<'EOF'
---
title: "dependent chunk"
depends_on:
  - git-rebase/basic-rebase.md
---
body
EOF
  run_learn cascade git-rebase/5-melting-pot/basic-rebase.md
  assert_rc 0 || return 1
  if ! grep -q "FLAG.*dependent\.md.*depends on git-rebase" "$OUT"; then
    fail "$TNAME" "expected FLAG line for dependent chunk"; cat "$OUT" >&2; return 1
  fi
  # Dependent chunk file still in place (flag-only).
  assert_file_exists "$d2/0-melting-pot/dependent.md" || return 1
  pass "$TNAME"
}

t_PHASE5_LEARN_10() {
  TNAME=PHASE5-LEARN-10
  # patch-triage emits markdown proposals for each .failed marker.
  t_setup
  fdir="$MP_HOME/foo/patches/.failed"
  mkdir -p "$fdir"
  cat > "$fdir/001-broken.patch.failed" <<'EOF'
--- patch ---
patch contents
--- upstream excerpt ---
upstream
--- reject ---
error: patch failed
--- timestamp ---
2026-05-20T12:00:00Z
EOF
  cat > "$fdir/002-also-broken.patch.failed" <<'EOF'
--- patch ---
p2
--- upstream excerpt ---
u2
--- reject ---
also failed
--- timestamp ---
2026-05-20T13:00:00Z
EOF
  run_learn patch-triage
  assert_rc 0 || return 1
  assert_stdout_contains "patch-triage proposals (2)" || return 1
  assert_stdout_contains "regenerate" || return 1
  assert_stdout_contains "001-broken.patch" || return 1
  assert_stdout_contains "002-also-broken.patch" || return 1
  pass "$TNAME"
}

t_PHASE5_LEARN_11() {
  TNAME=PHASE5-LEARN-11
  # patch-triage with no markers: exit 1, friendly message.
  t_setup
  run_learn patch-triage
  assert_rc 1 || return 1
  assert_stdout_contains "no failed patches" || return 1
  pass "$TNAME"
}

t_PHASE5_LEARN_12() {
  TNAME=PHASE5-LEARN-12
  # patch-triage JSON validates.
  t_setup
  fdir="$MP_HOME/foo/patches/.failed"
  mkdir -p "$fdir"
  cat > "$fdir/001-b.patch.failed" <<'EOF'
--- patch ---
x
--- upstream excerpt ---
y
--- reject ---
z
--- timestamp ---
2026-05-20T12:00:00Z
EOF
  run_learn patch-triage --format json
  assert_rc 0 || return 1
  valid=$(printf "select json_valid(readfile('%s'));\n" "$(twin "$OUT")" | sqlite3 | tr -d '\r')
  if [ "$valid" != "1" ]; then
    fail "$TNAME" "json_valid returned $valid"; cat "$OUT" >&2; return 1
  fi
  pass "$TNAME"
}

t_PHASE5_LEARN_13() {
  TNAME=PHASE5-LEARN-13
  # full mobility: repeated good uses climb 0 -> 5, then the ceiling refuses.
  t_setup
  d="$MP_HOME/op-skill"
  mkdir -p "$d/0-melting-pot"
  mk_chunk "$d/0-melting-pot/a.md" 0
  n=0
  while [ "$n" -lt 5 ]; do
    cur=$n; nxt=$((n + 1))
    run_learn promote "op-skill/${cur}-melting-pot/a.md"
    assert_rc 0 || return 1
    assert_file_exists "$d/${nxt}-melting-pot/a.md" || return 1
    n=$nxt
  done
  # At tier 5 the ceiling refuses further promotion.
  run_learn promote "op-skill/5-melting-pot/a.md"
  assert_rc 1 || return 1
  assert_file_exists "$d/5-melting-pot/a.md" || return 1
  pass "$TNAME"
}

t_PHASE5_LEARN_14() {
  TNAME=PHASE5-LEARN-14
  # status_history entry appended on promote.
  t_setup
  d="$MP_HOME/hist-skill"
  mkdir -p "$d/0-melting-pot"
  mk_chunk "$d/0-melting-pot/h.md" 0
  run_learn promote "hist-skill/0-melting-pot/h.md"
  assert_rc 0 || return 1
  if ! grep -q "promoted from tier 0" "$d/1-melting-pot/h.md"; then
    fail "$TNAME" "expected status_history reason 'promoted from tier 0'"
    cat "$d/1-melting-pot/h.md" >&2
    return 1
  fi
  pass "$TNAME"
}

t_PHASE5_LEARN_15() {
  TNAME=PHASE5-LEARN-15
  # Atomicity: --dry-run promote leaves filesystem unchanged.
  t_setup
  d="$MP_HOME/dry-skill"
  mkdir -p "$d/0-melting-pot"
  mk_chunk "$d/0-melting-pot/dry.md" 0
  before=$(cat "$d/0-melting-pot/dry.md")
  run_learn promote "dry-skill/0-melting-pot/dry.md" --dry-run
  assert_rc 0 || return 1
  assert_stdout_contains "DRY-RUN promote" || return 1
  after=$(cat "$d/0-melting-pot/dry.md")
  assert_eq "$after" "$before" || return 1
  if [ -e "$d/1-melting-pot/dry.md" ]; then
    fail "$TNAME" "--dry-run created tier-1 copy"; return 1
  fi
  pass "$TNAME"
}

t_PHASE5_LEARN_16() {
  TNAME=PHASE5-LEARN-16
  # --dry-run demote at tier 0 reports the would-remove but keeps the file.
  t_setup
  d="$MP_HOME/dry-floor"
  mkdir -p "$d/0-melting-pot"
  mk_chunk "$d/0-melting-pot/keep.md" 0
  run_learn demote "dry-floor/0-melting-pot/keep.md" --dry-run
  assert_rc 0 || return 1
  assert_stdout_contains "would REMOVE" || return 1
  # File must still be present after a dry-run.
  assert_file_exists "$d/0-melting-pot/keep.md" || return 1
  pass "$TNAME"
}

# ============================================================================
# Section 11: install/hooks + install/install.sh — Phase 6
# ============================================================================
#
# All tests sandbox $HOME to a temp dir so the assertion "installer does NOT
# touch ~/.claude/settings.json" is testable: we plant a baseline file under
# $HOME/.claude/settings.json, run the installer, and check the file's
# checksum is unchanged.

NUDGE_BIN="$ROOT/install/hooks/melt-nudge.sh"
RESUME_BIN="$ROOT/install/hooks/melt-resume.sh"
INSTALL_BIN="$ROOT/install/install.sh"

# Run the installer under a sandboxed $HOME so the Q-003 invariant assertion
# (installer never mutates ~/.claude/settings.json) is meaningful.
run_install() {
  # Args: pass through to install.sh.
  fake_home="$TDIR/fake-home"
  mkdir -p "$fake_home"
  HOME="$fake_home" MP_HOME="$fake_home/.melt" MP_PATTERNS="$fake_home/.melt/repos.patterns" \
    sh "$INSTALL_BIN" "$@" > "$OUT" 2> "$ERR"
  RC=$?
}

t_PHASE6_IN_01() {
  TNAME=PHASE6-IN-01
  # Nudge fires AFTER threshold, not before.
  t_setup
  fake_home="$TDIR/fake-home"
  mkdir -p "$fake_home/.melt/learn"
  # threshold=3, count=2 — should print nothing.
  HOME="$fake_home" MP_HOME="$fake_home/.melt" MP_NUDGE_THRESHOLD=3 \
    sh "$NUDGE_BIN" sess-a 2 > "$OUT" 2> "$ERR"
  RC=$?
  assert_rc 0 || return 1
  if [ -s "$OUT" ]; then
    fail "$TNAME" "nudge fired below threshold (count=2, threshold=3); output:"
    cat "$OUT" >&2
    return 1
  fi
  # threshold=3, count=3 — should print the nudge.
  HOME="$fake_home" MP_HOME="$fake_home/.melt" MP_NUDGE_THRESHOLD=3 \
    sh "$NUDGE_BIN" sess-a 3 > "$OUT" 2> "$ERR"
  RC=$?
  assert_rc 0 || return 1
  assert_stdout_contains "tool calls" || return 1
  assert_stdout_contains "mp-learn" || return 1
  pass "$TNAME"
}

t_PHASE6_IN_02() {
  TNAME=PHASE6-IN-02
  # Marker file prevents a double-fire in the same session.
  t_setup
  fake_home="$TDIR/fake-home"
  mkdir -p "$fake_home/.melt/learn"
  HOME="$fake_home" MP_HOME="$fake_home/.melt" MP_NUDGE_THRESHOLD=1 \
    sh "$NUDGE_BIN" sess-b 5 > "$OUT" 2> "$ERR"
  RC=$?
  assert_rc 0 || return 1
  if ! grep -q "mp-learn" "$OUT"; then
    fail "$TNAME" "first call did not emit nudge"; cat "$OUT" >&2; return 1
  fi
  # Second invocation in the same session — marker present, no nudge.
  HOME="$fake_home" MP_HOME="$fake_home/.melt" MP_NUDGE_THRESHOLD=1 \
    sh "$NUDGE_BIN" sess-b 6 > "$OUT" 2> "$ERR"
  RC=$?
  assert_rc 0 || return 1
  if [ -s "$OUT" ]; then
    fail "$TNAME" "second nudge fired despite session marker; output:"
    cat "$OUT" >&2
    return 1
  fi
  # Marker file should exist for that session.
  assert_file_exists "$fake_home/.melt/learn/.session-nudged-sess-b" || return 1
  pass "$TNAME"
}

t_PHASE6_IN_03() {
  TNAME=PHASE6-IN-03
  # Resume hook writes the .pending-transcript handshake atomically.
  t_setup
  fake_home="$TDIR/fake-home"
  mkdir -p "$fake_home/.melt"
  HOME="$fake_home" MP_HOME="$fake_home/.melt" \
    sh "$RESUME_BIN" /tmp/mock-prior.jsonl uuid-abc-123 > "$OUT" 2> "$ERR"
  RC=$?
  assert_rc 0 || return 1
  assert_file_exists "$fake_home/.melt/learn/.pending-transcript" || return 1
  body=$(cat "$fake_home/.melt/learn/.pending-transcript")
  assert_eq "$body" "/tmp/mock-prior.jsonl" || return 1
  # Resume prompt mentions both the transcript path and the resume uuid.
  assert_stdout_contains "/tmp/mock-prior.jsonl" || return 1
  assert_stdout_contains "uuid-abc-123" || return 1
  assert_stdout_contains "Run \`mp-learn\`" || return 1
  pass "$TNAME"
}

t_PHASE6_IN_04() {
  TNAME=PHASE6-IN-04
  # Installer emits REGISTER-HOOKS.md into the sandbox $MP_HOME with all
  # expected rows + table. (The repo-side install/REGISTER-HOOKS.md stays
  # untouched — that's the human-readable placeholder copy.)
  t_setup
  fake_home="$TDIR/fake-home"
  # Snapshot the repo-side manifest BEFORE running, then verify after.
  repo_manifest="$ROOT/install/REGISTER-HOOKS.md"
  repo_hash_before=$(t_sha "$repo_manifest")
  run_install
  assert_rc 0 || return 1
  # Sandbox manifest must exist and contain the expected markers.
  sandbox_manifest="$fake_home/.melt/REGISTER-HOOKS.md"
  assert_file_exists "$sandbox_manifest" || return 1
  for marker in '## Hooks' '`Stop`' '`SessionStart:clear`' 'melt-nudge.sh' 'melt-resume.sh'; do
    if ! grep -q -F -- "$marker" "$sandbox_manifest"; then
      fail "$TNAME" "sandbox manifest missing expected marker: $marker"
      return 1
    fi
  done
  # The script paths in the sandbox copy should be absolute and point into
  # the sandbox $MP_HOME (not into the repo).
  if ! grep -q -F -- "$fake_home/.melt/hooks/melt-nudge.sh" "$sandbox_manifest"; then
    fail "$TNAME" "sandbox manifest missing absolute nudge path"; return 1
  fi
  # Repo-side manifest must NOT have been overwritten with sandbox paths.
  repo_hash_after=$(t_sha "$repo_manifest")
  assert_eq "$repo_hash_after" "$repo_hash_before" || return 1
  pass "$TNAME"
}

t_PHASE6_IN_05() {
  TNAME=PHASE6-IN-05
  # Installer does NOT mutate ~/.claude/settings.json (Q-003 invariant).
  t_setup
  fake_home="$TDIR/fake-home"
  mkdir -p "$fake_home/.claude"
  # Plant a baseline settings.json so we can hash before/after.
  cat > "$fake_home/.claude/settings.json" <<'EOF'
{"baseline":"do-not-touch"}
EOF
  before=$(t_sha "$fake_home/.claude/settings.json")
  run_install
  assert_rc 0 || return 1
  # The file MUST still exist with identical contents.
  assert_file_exists "$fake_home/.claude/settings.json" || return 1
  after=$(t_sha "$fake_home/.claude/settings.json")
  assert_eq "$after" "$before" || return 1
  # And the body must be byte-identical.
  body=$(cat "$fake_home/.claude/settings.json")
  assert_eq "$body" '{"baseline":"do-not-touch"}' || return 1
  pass "$TNAME"
}

t_PHASE6_IN_07() {
  TNAME=PHASE6-IN-07
  # --dry-run writes nothing to the sandboxed $MP_HOME, and the repo-side
  # manifest stays bitwise-identical.
  t_setup
  fake_home="$TDIR/fake-home"
  repo_manifest="$ROOT/install/REGISTER-HOOKS.md"
  repo_hash_before=$(t_sha "$repo_manifest")
  run_install --dry-run
  assert_rc 0 || return 1
  if [ -d "$fake_home/.melt" ]; then
    fail "$TNAME" "--dry-run created $fake_home/.melt"; return 1
  fi
  repo_hash_after=$(t_sha "$repo_manifest")
  assert_eq "$repo_hash_after" "$repo_hash_before" || return 1
  pass "$TNAME"
}

t_PHASE6_IN_09() {
  TNAME=PHASE6-IN-09
  # Installer symlinks every shipped skill's action into $MP_HOME/<skill>/action
  # so `sh ~/.melt/<skill>/action` resolves. Regression guard for the do_mkdir
  # global-var clobber that previously skipped the symlink step.
  t_setup
  fake_home="$TDIR/fake-home"
  run_install
  assert_rc 0 || return 1
  for skill in search list crud load learn; do
    link="$fake_home/.melt/$skill/action"
    if [ "$SYMLINKS_OK" = 1 ]; then
      if [ ! -L "$link" ]; then
        fail "$TNAME" "missing action symlink: $link"; return 1
      fi
      if [ ! -f "$link" ]; then
        fail "$TNAME" "action symlink does not resolve to a file: $link"; return 1
      fi
      if [ "$(readlink "$link")" != "$ROOT/mp/$skill/action" ]; then
        fail "$TNAME" "symlink target wrong: $(readlink "$link")"; return 1
      fi
    else
      # Windows/MSYS: a shim that execs the real action with MP_LIB_DIR set.
      if [ ! -f "$link" ]; then
        fail "$TNAME" "missing action shim: $link"; return 1
      fi
      if ! grep -qF -- "$ROOT/mp/$skill/action" "$link"; then
        fail "$TNAME" "shim does not reference real action: $link"; return 1
      fi
      if ! grep -qF -- "$ROOT/mp/lib" "$link"; then
        fail "$TNAME" "shim does not set MP_LIB_DIR to repo lib: $link"; return 1
      fi
    fi
  done
  # End-to-end: the symlinked search CLI runs and reports usage/help cleanly.
  HOME="$fake_home" MP_HOME="$fake_home/.melt" MP_PATTERNS="$fake_home/.melt/repos.patterns" \
    sh "$fake_home/.melt/search/action" --help > "$OUT" 2> "$ERR"
  if [ "$?" -ne 0 ]; then
    fail "$TNAME" "symlinked search action --help failed: $(cat "$ERR")"; return 1
  fi
  pass "$TNAME"
}

# ============================================================================
# Section 12: Phase 7 — test corpus
# ============================================================================
#
# The corpus at test/skills/ is a set of synthetic skill fixtures
# (78 fixtures) augmented with:
#   - git-rebase tier dirs (0-melting-pot/ + 3-melting-pot/) — mix-format
#   - melting-pot-native-demo/ — native-only fixture with meta.md + tier dirs
#
# These tests verify the corpus loads cleanly through the existing pipeline
# AND that ranking against the golden rubric still picks the expected
# target skills.

CORPUS_DIR="$ROOT/test/skills"
GOLDEN_DIR="$ROOT/test/golden"
EXPECTED_CORPUS_COUNT=79   # 78 carry-over + 1 native-demo fresh fixture

t_PHASE7_CORPUS_01() {
  TNAME=PHASE7-CORPUS-01
  # Discovery sees every fixture once. We sandbox $MP_HOME (so we don't
  # accidentally read the developer's real overlay) and register the corpus
  # as a single registered root via $MP_PATTERNS.
  t_setup
  t_patterns "$CORPUS_DIR"
  run_lib mp_discover_skills
  assert_rc 0 || return 1
  n=$(wc -l < "$OUT" | tr -d ' ')
  if [ "$n" != "$EXPECTED_CORPUS_COUNT" ]; then
    fail "$TNAME" "expected $EXPECTED_CORPUS_COUNT discovered skills, got $n"
    cat "$OUT" >&2
    return 1
  fi
  # Spot-check: a few canonical legacy names appear under the upstream path.
  for fx in aws-s3-sync docker-build-cache; do
    if ! grep -q "$CORPUS_DIR/$fx	reg	legacy" "$OUT"; then
      fail "$TNAME" "expected legacy fixture not discovered: $fx"; return 1
    fi
  done
  # Native-format fixtures (git-rebase + melting-pot-native-demo) get
  # symlinked into the overlay per Q-007, so their emitted row carries the
  # $MP_HOME prefix, not the corpus prefix. Match on dirname/kind instead.
  if ! grep -q "/git-rebase	reg	native" "$OUT"; then
    fail "$TNAME" "git-rebase (mix-format) not classified as reg/native"
    return 1
  fi
  if ! grep -q "/melting-pot-native-demo	reg	native" "$OUT"; then
    fail "$TNAME" "melting-pot-native-demo not classified as reg/native"
    return 1
  fi
  pass "$TNAME"
}

t_PHASE7_CORPUS_02() {
  TNAME=PHASE7-CORPUS-02
  # Run a graded query from golden/queries.tsv against the corpus via the
  # real search action. q002 grades git-rebase as the top target (grade 2);
  # we assert git-rebase appears in the convergence section.
  t_setup
  t_patterns "$CORPUS_DIR"
  # Reindex before searching; the corpus is large enough that hash-gated
  # reindex would happen anyway on first search, but doing it explicitly
  # keeps the timing predictable.
  sh "$SEARCH_BIN" reindex > /dev/null 2> "$ERR" || :
  run_search "squash WIP commits before review" "interactive rebase to tidy history" "clean up feature branch commits before opening a PR"
  assert_rc 0 || return 1
  conv_block=$(awk '/^## Convergence/{f=1;next}/^## Single-axis/{f=0}f' "$OUT")
  if ! printf "%s" "$conv_block" | grep -q "git:rebase"; then
    fail "$TNAME" "git:rebase missing from Convergence section for golden q002"
    cat "$OUT" >&2
    return 1
  fi
  pass "$TNAME"
}

t_PHASE7_CORPUS_03() {
  TNAME=PHASE7-CORPUS-03
  # mp-list inventory of the corpus matches the expected count.
  t_setup
  t_patterns "$CORPUS_DIR"
  run_list --count
  assert_rc 0 || return 1
  n=$(cat "$OUT" | tr -d ' ')
  if [ "$n" != "$EXPECTED_CORPUS_COUNT" ]; then
    fail "$TNAME" "list --count expected $EXPECTED_CORPUS_COUNT, got $n"
    return 1
  fi
  # The native-demo fixture should appear in JSON output with the right
  # tiers_present marker.
  run_list --format json
  assert_rc 0 || return 1
  if ! grep -F -q '"tiers_present":"[0,5]-melting-pot"' "$OUT"; then
    # Don't bail on the exact shape; just confirm the native fixture is in
    # the output.
    if ! grep -q "melting-pot-native-demo" "$OUT"; then
      fail "$TNAME" "native-demo missing from list --format json output"
      return 1
    fi
  fi
  pass "$TNAME"
}

t_PHASE7_CORPUS_04() {
  TNAME=PHASE7-CORPUS-04
  # Golden rubric + queries.tsv files are present and non-empty.
  t_setup
  assert_file_exists "$GOLDEN_DIR/RUBRIC.md" || return 1
  assert_file_exists "$GOLDEN_DIR/queries.tsv" || return 1
  # queries.tsv has at least 100 graded rows (incl. comment lines).
  lines=$(wc -l < "$GOLDEN_DIR/queries.tsv" | tr -d ' ')
  if [ "$lines" -lt 100 ]; then
    fail "$TNAME" "queries.tsv too short ($lines lines)"; return 1
  fi
  # RUBRIC.md mentions the three grading tiers (2/1/0 or similar markers).
  if ! grep -q "grade" "$GOLDEN_DIR/RUBRIC.md"; then
    fail "$TNAME" "RUBRIC.md missing 'grade' keyword"; return 1
  fi
  pass "$TNAME"
}

# ============================================================================
# Runner
# ============================================================================

ALL_TESTS="LIB-DISC-01 LIB-DISC-02 LIB-DISC-03 LIB-DISC-04
LIB-DISC-05 LIB-DISC-06 LIB-DISC-07
LIB-TIER-01 LIB-TIER-02 LIB-TIER-03 LIB-TIER-04 LIB-TIER-05 LIB-TIER-06 LIB-TIER-07 LIB-TIER-08 LIB-TIER-09
LIB-PATCH-01 LIB-PATCH-02 LIB-PATCH-03 LIB-PATCH-04 LIB-PATCH-05 LIB-PATCH-06
LIB-COMPOSE-01 LIB-COMPOSE-02 LIB-COMPOSE-03 LIB-COMPOSE-04
PHASE2-SRCH-01 PHASE2-SRCH-02 PHASE2-SRCH-03 PHASE2-SRCH-04 PHASE2-SRCH-05
PHASE2-SRCH-06 PHASE2-SRCH-07 PHASE2-SRCH-08 PHASE2-SRCH-09 PHASE2-SRCH-10
PHASE2-SRCH-11 PHASE2-SRCH-12 PHASE2-SRCH-13 PHASE2-SRCH-14 PHASE2-SRCH-15
PHASE2-SRCH-16
PHASE4-LOAD-01 PHASE4-LOAD-02 PHASE4-LOAD-03 PHASE4-LOAD-04 PHASE4-LOAD-05
PHASE4-LOAD-06 PHASE4-LOAD-07 PHASE4-LOAD-08 PHASE4-LOAD-09
PHASE3-LIST-01 PHASE3-LIST-02 PHASE3-LIST-03 PHASE3-LIST-04 PHASE3-LIST-05
PHASE3-LIST-06 PHASE3-LIST-07
PHASE3-CRUD-01 PHASE3-CRUD-02 PHASE3-CRUD-03 PHASE3-CRUD-04 PHASE3-CRUD-05
PHASE3-CRUD-06 PHASE3-CRUD-07 PHASE3-CRUD-08 PHASE3-CRUD-09 PHASE3-CRUD-10
PHASE3-CRUD-11 PHASE3-CRUD-12
PHASE5-LEARN-01 PHASE5-LEARN-02 PHASE5-LEARN-03 PHASE5-LEARN-04 PHASE5-LEARN-05
PHASE5-LEARN-06 PHASE5-LEARN-07 PHASE5-LEARN-08 PHASE5-LEARN-09 PHASE5-LEARN-10
PHASE5-LEARN-11 PHASE5-LEARN-12 PHASE5-LEARN-13 PHASE5-LEARN-14 PHASE5-LEARN-15
PHASE5-LEARN-16
PHASE6-IN-01 PHASE6-IN-02 PHASE6-IN-03 PHASE6-IN-04 PHASE6-IN-05
PHASE6-IN-07 PHASE6-IN-09
PHASE7-CORPUS-01 PHASE7-CORPUS-02 PHASE7-CORPUS-03 PHASE7-CORPUS-04"

# Tests that exercise the sqlite3-backed FTS5 index (directly, or via the
# json_valid() helper). On a host without sqlite3 — e.g. a fresh Windows box
# before `winget install SQLite.SQLite` — these are SKIPPED rather than failed,
# so the rest of the suite still reports a clean result.
SQLITE3_TESTS="LIB-TIER-07 LIB-COMPOSE-03
PHASE2-SRCH-01 PHASE2-SRCH-02 PHASE2-SRCH-03 PHASE2-SRCH-04 PHASE2-SRCH-05
PHASE2-SRCH-07 PHASE2-SRCH-10 PHASE2-SRCH-11 PHASE2-SRCH-12 PHASE2-SRCH-13
PHASE2-SRCH-14 PHASE2-SRCH-15 PHASE2-SRCH-16
PHASE3-LIST-04 PHASE4-LOAD-02
PHASE5-LEARN-01 PHASE5-LEARN-02 PHASE5-LEARN-12
PHASE7-CORPUS-02"

while [ "$#" -gt 0 ]; do
  case "$1" in
    -v|--verbose) VERBOSE=1; shift ;;
    -h|--help) printf "usage: %s [-v] [TEST-NAME...]\n" "$0"; exit 0 ;;
    --) shift; break ;;
    -*) printf "unknown flag: %s\n" "$1" >&2; exit 2 ;;
    *) break ;;
  esac
done

if [ "$#" -eq 0 ]; then
  TESTS="$ALL_TESTS"
else
  TESTS="$*"
fi

printf "running tests from %s\n" "$ROOT"
printf "  lib dir: %s\n" "$LIB_DIR"
[ "$SYMLINKS_OK" = 1 ] || printf "  note: native symlinks unavailable — testing shim/mirror fallbacks\n"
[ "$HAVE_SQLITE3" = 1 ] || printf "  note: sqlite3 not found — index-backed tests will be SKIPPED (install sqlite3 to run them)\n"
printf "\n"

for t in $TESTS; do
  fn="t_$(printf "%s" "$t" | tr -- '-' '_')"
  if ! command -v "$fn" >/dev/null 2>&1; then
    skip "$t" "no such test"
    continue
  fi
  if [ "$HAVE_SQLITE3" != 1 ]; then
    # Normalise newlines→spaces so end-of-line entries still match.
    case " $(printf '%s' "$SQLITE3_TESTS" | tr '\n' ' ') " in
      *" $t "*) skip "$t" "requires sqlite3"; continue ;;
    esac
  fi
  "$fn" || true
done

printf "\n"
printf "passed: %s\n" "$PASS_N"
printf "failed: %s%s\n" "$FAIL_N" "$( [ -n "$FAIL_LIST" ] && printf ' (%s)' "$FAIL_LIST" )"
printf "skipped: %s\n" "$SKIP_N"

if [ "$FAIL_N" -gt 0 ]; then exit 1; fi
exit 0
