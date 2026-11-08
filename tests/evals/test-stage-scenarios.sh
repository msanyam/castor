#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT_UNDER_TEST="${SCRIPT_UNDER_TEST:-$REPO_ROOT/scripts/evals/stage-scenarios}"

FAILURES=0
TEST_ROOT="$(mktemp -d)"

cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

pass() {
    echo "  [PASS] $1"
}

fail() {
    echo "  [FAIL] $1"
    FAILURES=$((FAILURES + 1))
}

# make_src <case-name>: create an empty source scenarios dir, print its path.
make_src() {
    local src="$TEST_ROOT/$1/src"
    mkdir -p "$src"
    printf '%s\n' "$src"
}

# run_stage <args...>: run the script under test, capturing its exit code in
# STAGE_RC and its combined output in STAGE_OUT. Never aborts the test run.
run_stage() {
    STAGE_RC=0
    STAGE_OUT="$("$SCRIPT_UNDER_TEST" "$@" 2>&1)" || STAGE_RC=$?
}

# assert_file_equals <description> <file> <expected-content>
# Compares exact bytes; a missing file fails (so a no-op script cannot pass).
assert_file_equals() {
    local description="$1"
    local file="$2"
    local expected="$3"

    if [[ ! -f "$file" ]]; then
        fail "$description"
        echo "    missing file: $file"
        return
    fi

    if printf '%s' "$expected" | cmp -s - "$file"; then
        pass "$description"
    else
        fail "$description"
        echo "    expected:"
        printf '%s' "$expected" | sed 's/^/      /'
        echo "    actual:"
        sed 's/^/      /' "$file"
    fi
}

# assert_staged_unchanged <description> <src-file> <dst-file>
# The dst copy must exist and be byte-identical to the source.
assert_staged_unchanged() {
    local description="$1"
    local src_file="$2"
    local dst_file="$3"

    if [[ ! -f "$dst_file" ]]; then
        fail "$description"
        echo "    missing file: $dst_file"
        return
    fi

    if cmp -s "$src_file" "$dst_file"; then
        pass "$description"
    else
        fail "$description"
        echo "    $dst_file differs from $src_file"
    fi
}

assert_exit() {
    local description="$1"
    local expected="$2"

    if [[ "$STAGE_RC" -eq "$expected" ]]; then
        pass "$description"
    else
        fail "$description"
        echo "    expected exit $expected, got $STAGE_RC"
        printf '%s\n' "$STAGE_OUT" | sed 's/^/      /'
    fi
}

echo "stage-scenarios tests"

# 1. checks.sh: superpowers:<skill> becomes castor:<skill>.
src="$(make_src rewrite-checks)"
dst="$TEST_ROOT/rewrite-checks/dst"
mkdir -p "$src/scen"
printf 'check-transcript skill-called superpowers:writing-plans\n' > "$src/scen/checks.sh"
run_stage "$src" "$dst"
assert_file_equals \
    "checks.sh: superpowers:writing-plans is rewritten to castor:writing-plans" \
    "$dst/scen/checks.sh" \
    $'check-transcript skill-called castor:writing-plans\n'

# 2. Several references on one line are all rewritten (the g flag).
src="$(make_src rewrite-two-per-line)"
dst="$TEST_ROOT/rewrite-two-per-line/dst"
mkdir -p "$src/scen"
printf 'check-transcript skill-order superpowers:brainstorming superpowers:test-driven-development\n' \
    > "$src/scen/checks.sh"
run_stage "$src" "$dst"
assert_file_equals \
    "checks.sh: two references on one line are both rewritten" \
    "$dst/scen/checks.sh" \
    $'check-transcript skill-order castor:brainstorming castor:test-driven-development\n'

# 3. story.md is rewritten too.
src="$(make_src rewrite-story)"
dst="$TEST_ROOT/rewrite-story/dst"
mkdir -p "$src/scen"
printf 'The agent is told to start by naming `superpowers:brainstorming`.\n' > "$src/scen/story.md"
run_stage "$src" "$dst"
assert_file_equals \
    "story.md: superpowers:brainstorming is rewritten to castor:brainstorming" \
    "$dst/scen/story.md" \
    $'The agent is told to start by naming `castor:brainstorming`.\n'

# 4. checks-manifest.json is rewritten too.
src="$(make_src rewrite-manifest)"
dst="$TEST_ROOT/rewrite-manifest/dst"
mkdir -p "$src/scen"
printf '{"check": "skill-called", "args": ["superpowers:writing-plans"]}\n' \
    > "$src/scen/checks-manifest.json"
run_stage "$src" "$dst"
assert_file_equals \
    "checks-manifest.json: args entry is rewritten to castor:writing-plans" \
    "$dst/scen/checks-manifest.json" \
    $'{"check": "skill-called", "args": ["castor:writing-plans"]}\n'

# 5. Paths that merely contain "superpowers" are not skill references.
src="$(make_src paths-unchanged)"
dst="$TEST_ROOT/paths-unchanged/dst"
mkdir -p "$src/scen"
printf 'Spec at docs/superpowers/specs/x.md\nProgress in .superpowers/sdd/progress.md\n' \
    > "$src/scen/story.md"
run_stage "$src" "$dst"
assert_staged_unchanged \
    "story.md: docs/superpowers/... and .superpowers/... paths are left unchanged" \
    "$src/scen/story.md" "$dst/scen/story.md"

# 6. "superpowers-bootstrap" and the "superpowers:<name>" placeholder are not
# skill references (the placeholder has no [a-z0-9] after the colon).
src="$(make_src placeholder-unchanged)"
dst="$TEST_ROOT/placeholder-unchanged/dst"
mkdir -p "$src/scen"
printf 'Run superpowers-bootstrap first.\nSkills are written superpowers:<name> upstream.\n' \
    > "$src/scen/story.md"
run_stage "$src" "$dst"
assert_staged_unchanged \
    "story.md: superpowers-bootstrap and superpowers:<name> are left unchanged" \
    "$src/scen/story.md" "$dst/scen/story.md"

# 7. Only checks.sh, checks-manifest.json and story.md are rewritten; setup
# scripts and fixtures keep upstream names byte for byte.
src="$(make_src other-files-unchanged)"
dst="$TEST_ROOT/other-files-unchanged/dst"
mkdir -p "$src/scen/fixtures"
printf 'echo superpowers:executing-plans\n' > "$src/scen/setup.sh"
printf '# Plan\nUse superpowers:executing-plans to run this.\n' > "$src/scen/fixtures/plan.md"
run_stage "$src" "$dst"
assert_staged_unchanged \
    "setup.sh: superpowers:executing-plans is left byte-identical" \
    "$src/scen/setup.sh" "$dst/scen/setup.sh"
assert_staged_unchanged \
    "fixtures/plan.md: superpowers:executing-plans is left byte-identical" \
    "$src/scen/fixtures/plan.md" "$dst/scen/fixtures/plan.md"

# 8. The source tree is never modified, and the rewrite happened in dst.
src="$(make_src source-untouched)"
dst="$TEST_ROOT/source-untouched/dst"
before="$TEST_ROOT/source-untouched/before"
mkdir -p "$src/scen"
printf 'check-transcript skill-called superpowers:writing-plans\n' > "$src/scen/checks.sh"
printf 'naming `superpowers:brainstorming`\n' > "$src/scen/story.md"
printf '{"args": ["superpowers:writing-plans"]}\n' > "$src/scen/checks-manifest.json"
cp -R "$src" "$before"
run_stage "$src" "$dst"
if [[ -f "$dst/scen/checks.sh" ]] && grep -q 'castor:writing-plans' "$dst/scen/checks.sh" \
    && diff -r "$before" "$src" > /dev/null; then
    pass "source tree is identical to its pre-run copy and dst holds the rewrite"
else
    fail "source tree is identical to its pre-run copy and dst holds the rewrite"
fi

# 9. Missing source dir exits 1.
dst="$TEST_ROOT/missing-src/dst"
mkdir -p "$TEST_ROOT/missing-src"
run_stage "$TEST_ROOT/missing-src/does-not-exist" "$dst"
assert_exit "missing source dir exits 1" 1

# 10. Wrong argument count exits 2.
src="$(make_src one-arg)"
run_stage "$src"
assert_exit "one argument exits 2" 2

if [[ "$FAILURES" -gt 0 ]]; then
    echo "STATUS: FAILED ($FAILURES failure(s))"
    exit 1
fi

echo "STATUS: PASSED"
