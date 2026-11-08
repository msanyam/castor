#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# SCRIPT_UNDER_TEST lets the reconcile step point this at /usr/bin/true to
# prove the tests can fail.
SCRIPT_UNDER_TEST="${SCRIPT_UNDER_TEST:-$REPO_ROOT/scripts/evals/summarize-baseline}"

CASTOR_REV="abcdef1234567890abcdef1234567890abcdef12"
EVALS_REV="1234567890abcdef1234567890abcdef12345678"

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

# write_meta <work> <dirty: true|false> <scenarios json: null|"csv"> <trials>
write_meta() {
    local work="$1"
    local dirty="$2"
    local scenarios="$3"
    local trials="$4"

    mkdir -p "$work"
    printf '{"date":"2026-11-08","castor_rev":"%s","castor_dirty":%s,"evals_rev":"%s","coding_agent":"claude","credential":"opus5_sub","tier":"sentinel","trials":%s,"scenarios":%s}\n' \
        "$CASTOR_REV" "$dirty" "$EVALS_REV" "$trials" "$scenarios" >"$work/meta.json"
}

# add_row <work> <trial> <scenario> <run_id|null> [skipped-reason]
# Appends one row to trial-<n>/batches/b<n>/results.jsonl.
add_row() {
    local work="$1"
    local trial="$2"
    local scenario="$3"
    local run_id="$4"
    local skipped="${5:-}"
    local batch_dir="$work/trial-$trial/batches/b$trial"
    local run_json="null"
    local skipped_json=""

    mkdir -p "$batch_dir"
    if [[ "$run_id" != "null" ]]; then
        run_json="\"$run_id\""
    fi
    if [[ -n "$skipped" ]]; then
        skipped_json=",\"skipped\":\"$skipped\""
    fi
    printf '{"scenario":"%s","coding_agent":"claude","credential":"opus5_sub"%s,"run_id":%s}\n' \
        "$scenario" "$skipped_json" "$run_json" >>"$batch_dir/results.jsonl"
}

# add_verdict <work> <trial> <run_id> <raw file content>
add_verdict() {
    local work="$1"
    local trial="$2"
    local run_id="$3"
    local content="$4"

    mkdir -p "$work/trial-$trial/$run_id"
    printf '%s\n' "$content" >"$work/trial-$trial/$run_id/verdict.json"
}

# build_main_fixture <work>: the Task 2 fixture table.
build_main_fixture() {
    local work="$1"

    write_meta "$work" false null 3

    add_row "$work" 1 alpha r1a
    add_verdict "$work" 1 r1a '{"final":"pass"}'
    add_row "$work" 1 beta r1b
    add_verdict "$work" 1 r1b '{"final":"fail"}'
    add_row "$work" 1 gamma null
    add_row "$work" 1 delta null directive

    add_row "$work" 2 alpha r2a
    add_verdict "$work" 2 r2a '{"final":"pass"}'
    add_row "$work" 2 beta r2b
    add_verdict "$work" 2 r2b '{"final":"indeterminate"}'
    add_row "$work" 2 gamma r2g
    # no verdict file for r2g
    add_row "$work" 2 delta null tier
}

# write_expected <file> <header line> <table rows...> -- <overall line>
# Builds the frozen markdown layout around the variable parts.
write_expected() {
    local file="$1"
    local header="$2"
    shift 2

    {
        printf '# Castor eval baseline: 2026-11-08\n\n'
        printf '%s\n\n' "$header"
        printf '| Scenario | Pass | Fail | Indeterminate | Pass rate |\n'
        printf '|---|---|---|---|---|\n'
        while [[ "$#" -gt 1 ]]; do
            printf '%s\n' "$1"
            shift
        done
        printf '\n%s\n' "$1"
    } >"$file"
}

# run_script <name> [args...]: captures stdout, stderr and the exit code in
# $TEST_ROOT/<name>.{out,err,rc}.
run_script() {
    local name="$1"
    shift
    local rc=0

    "$SCRIPT_UNDER_TEST" "$@" >"$TEST_ROOT/$name.out" 2>"$TEST_ROOT/$name.err" || rc=$?
    printf '%s\n' "$rc" >"$TEST_ROOT/$name.rc"
}

assert_exit() {
    local description="$1"
    local name="$2"
    local expected="$3"
    local actual

    actual="$(cat "$TEST_ROOT/$name.rc")"
    if [[ "$actual" == "$expected" ]]; then
        pass "$description"
    else
        fail "$description"
        echo "    expected exit $expected, got $actual"
        sed 's/^/      stderr: /' "$TEST_ROOT/$name.err"
    fi
}

# assert_stdout_exact <description> <name> <expected file>: byte-exact diff,
# including the single trailing newline.
assert_stdout_exact() {
    local description="$1"
    local name="$2"
    local expected_file="$3"

    if diff "$expected_file" "$TEST_ROOT/$name.out" >"$TEST_ROOT/$name.diff" 2>&1; then
        pass "$description"
    else
        fail "$description"
        sed 's/^/      /' "$TEST_ROOT/$name.diff"
    fi
}

echo "summarize-baseline tests"

# --- main case: Task 2 fixture, exact stdout --------------------------------
main_work="$TEST_ROOT/main/work"
build_main_fixture "$main_work"
cat >"$TEST_ROOT/main.expected" <<'EOF'
# Castor eval baseline: 2026-11-08

- castor: abcdef1 (dirty: no) · evals: 1234567 · agent: claude · credential: opus5_sub · tier: sentinel · trials: 3

| Scenario | Pass | Fail | Indeterminate | Pass rate |
|---|---|---|---|---|
| alpha | 2 | 0 | 0 | 2/2 (100%) |
| beta | 0 | 1 | 1 | 0/1 (0%) |
| gamma | 0 | 0 | 2 | 0/0 (n/a) |

**Overall:** 2/3 determinate runs passed (67%). 3 indeterminate.
EOF
run_script main "$main_work"
assert_exit "main fixture exits 0" main 0
assert_stdout_exact "main fixture stdout matches the frozen markdown exactly" main "$TEST_ROOT/main.expected"

# Skipped rows must not appear as scenarios at all.
if [[ -s "$TEST_ROOT/main.out" ]] && ! grep -q 'delta' "$TEST_ROOT/main.out"; then
    pass "skipped scenario (delta) is omitted from the output"
else
    fail "skipped scenario (delta) is omitted from the output"
fi

# Reading must not modify the work dir.
if [[ -s "$TEST_ROOT/main.out" && ! -e "$main_work/baseline.md" ]]; then
    pass "summarizer prints to stdout and writes nothing into the work dir"
else
    fail "summarizer prints to stdout and writes nothing into the work dir"
fi

# --- a: dirty flag and scenarios filter in the header -----------------------
a_work="$TEST_ROOT/a/work"
build_main_fixture "$a_work"
write_meta "$a_work" true '"alpha,beta"' 3
write_expected "$TEST_ROOT/a.expected" \
    "- castor: abcdef1 (dirty: yes) · evals: 1234567 · agent: claude · credential: opus5_sub · tier: sentinel · trials: 3 · scenarios: alpha,beta" \
    "| alpha | 2 | 0 | 0 | 2/2 (100%) |" \
    "| beta | 0 | 1 | 1 | 0/1 (0%) |" \
    "| gamma | 0 | 0 | 2 | 0/0 (n/a) |" \
    "**Overall:** 2/3 determinate runs passed (67%). 3 indeterminate."
run_script a "$a_work"
assert_exit "dirty meta with scenarios exits 0" a 0
assert_stdout_exact "dirty meta prints (dirty: yes) and the scenarios suffix" a "$TEST_ROOT/a.expected"

# --- b: every verdict indeterminate -----------------------------------------
b_work="$TEST_ROOT/b/work"
write_meta "$b_work" false null 1
add_row "$b_work" 1 alpha r1a
add_verdict "$b_work" 1 r1a '{"final":"indeterminate"}'
add_row "$b_work" 1 beta r1b
add_verdict "$b_work" 1 r1b '{"final":"indeterminate"}'
write_expected "$TEST_ROOT/b.expected" \
    "- castor: abcdef1 (dirty: no) · evals: 1234567 · agent: claude · credential: opus5_sub · tier: sentinel · trials: 1" \
    "| alpha | 0 | 0 | 1 | 0/0 (n/a) |" \
    "| beta | 0 | 0 | 1 | 0/0 (n/a) |" \
    "**Overall:** 0/0 determinate runs passed (n/a). 2 indeterminate."
run_script b "$b_work"
assert_exit "all-indeterminate fixture exits 0" b 0
assert_stdout_exact "all-indeterminate fixture reports 0/0 (n/a) overall" b "$TEST_ROOT/b.expected"

# --- c: no meta.json --------------------------------------------------------
c_work="$TEST_ROOT/c/work"
add_row "$c_work" 1 alpha r1a
add_verdict "$c_work" 1 r1a '{"final":"pass"}'
run_script c "$c_work"
assert_exit "missing meta.json exits 1" c 1

# --- d: meta present, no results.jsonl --------------------------------------
d_work="$TEST_ROOT/d/work"
write_meta "$d_work" false null 3
run_script d "$d_work"
assert_exit "meta.json without any results.jsonl exits 1" d 1

# --- e: no arguments --------------------------------------------------------
run_script e
assert_exit "no arguments exits 2" e 2

# --- f: unparseable verdict counts as indeterminate -------------------------
f_work="$TEST_ROOT/f/work"
write_meta "$f_work" false null 2
add_row "$f_work" 1 alpha r1a
add_verdict "$f_work" 1 r1a 'not json'
add_row "$f_work" 2 alpha r2a
add_verdict "$f_work" 2 r2a '{"final":"pass"}'
write_expected "$TEST_ROOT/f.expected" \
    "- castor: abcdef1 (dirty: no) · evals: 1234567 · agent: claude · credential: opus5_sub · tier: sentinel · trials: 2" \
    "| alpha | 1 | 0 | 1 | 1/1 (100%) |" \
    "**Overall:** 1/1 determinate runs passed (100%). 1 indeterminate."
run_script f "$f_work"
assert_exit "verdict file containing 'not json' exits 0" f 0
assert_stdout_exact "verdict file containing 'not json' counts as indeterminate" f "$TEST_ROOT/f.expected"

# --- fix round: only matrix-reason skips are ignored ------------------------
# Why: dropped runs (stopped, rate-limited) and empty tables were silently
# becoming committed baselines.

# g: a "stopped" skip counts as indeterminate for its scenario.
g_work="$TEST_ROOT/g/work"
write_meta "$g_work" false null 1
add_row "$g_work" 1 alpha r1a
add_verdict "$g_work" 1 r1a '{"final":"pass"}'
add_row "$g_work" 1 alpha null stopped
write_expected "$TEST_ROOT/g.expected" \
    "- castor: abcdef1 (dirty: no) · evals: 1234567 · agent: claude · credential: opus5_sub · tier: sentinel · trials: 1" \
    "| alpha | 1 | 0 | 1 | 1/1 (100%) |" \
    "**Overall:** 1/1 determinate runs passed (100%). 1 indeterminate."
run_script g "$g_work"
assert_exit "skipped:stopped row exits 0" g 0
assert_stdout_exact "skipped:stopped row counts as indeterminate for alpha" g "$TEST_ROOT/g.expected"

# h: a "rate-limited" skip counts the same way.
h_work="$TEST_ROOT/h/work"
write_meta "$h_work" false null 1
add_row "$h_work" 1 alpha r1a
add_verdict "$h_work" 1 r1a '{"final":"pass"}'
add_row "$h_work" 1 alpha null rate-limited
run_script h "$h_work"
assert_exit "skipped:rate-limited row exits 0" h 0
assert_stdout_exact "skipped:rate-limited row counts as indeterminate for alpha" h "$TEST_ROOT/g.expected"

# i: only matrix-reason skips leaves nothing to count, so exit 1.
i_work="$TEST_ROOT/i/work"
write_meta "$i_work" false null 1
add_row "$i_work" 1 alpha null tier
add_row "$i_work" 1 beta null directive
add_row "$i_work" 1 gamma null draft
add_row "$i_work" 1 delta null harness
add_row "$i_work" 1 epsilon null os
run_script i "$i_work"
assert_exit "only matrix-reason skipped rows (no counted rows) exits 1" i 1

# j: rounding is round-half-up: 1/8 = 12.5% prints 13%, not printf's 12%.
j_work="$TEST_ROOT/j/work"
write_meta "$j_work" false null 1
add_row "$j_work" 1 alpha r1a
add_verdict "$j_work" 1 r1a '{"final":"pass"}'
for n in 1 2 3 4 5 6 7; do
    add_row "$j_work" 1 alpha "f$n"
    add_verdict "$j_work" 1 "f$n" '{"final":"fail"}'
done
write_expected "$TEST_ROOT/j.expected" \
    "- castor: abcdef1 (dirty: no) · evals: 1234567 · agent: claude · credential: opus5_sub · tier: sentinel · trials: 1" \
    "| alpha | 1 | 7 | 0 | 1/8 (13%) |" \
    "**Overall:** 1/8 determinate runs passed (13%). 0 indeterminate."
run_script j "$j_work"
assert_exit "1 pass and 7 fails exits 0" j 0
assert_stdout_exact "1 pass and 7 fails rounds half up to 1/8 (13%)" j "$TEST_ROOT/j.expected"

# k: rows are sorted by scenario name (LC_ALL=C), not in file order.
k_work="$TEST_ROOT/k/work"
write_meta "$k_work" false null 1
for s in zeta alpha mid; do
    add_row "$k_work" 1 "$s" "r-$s"
    add_verdict "$k_work" 1 "r-$s" '{"final":"pass"}'
done
write_expected "$TEST_ROOT/k.expected" \
    "- castor: abcdef1 (dirty: no) · evals: 1234567 · agent: claude · credential: opus5_sub · tier: sentinel · trials: 1" \
    "| alpha | 1 | 0 | 0 | 1/1 (100%) |" \
    "| mid | 1 | 0 | 0 | 1/1 (100%) |" \
    "| zeta | 1 | 0 | 0 | 1/1 (100%) |" \
    "**Overall:** 3/3 determinate runs passed (100%). 0 indeterminate."
run_script k "$k_work"
assert_exit "unsorted scenarios exit 0" k 0
assert_stdout_exact "scenarios written zeta, alpha, mid print as alpha, mid, zeta" k "$TEST_ROOT/k.expected"

# l: a results.jsonl with a truncated line AFTER a valid counted row is bad
# input. Why the corruption comes last: a truncated first line would also
# exit 1 through the "no counted rows" path, hiding a missing JSON precheck.
# Here, without the precheck, jq prints the alpha row, then fails, and a
# naive reader exits 0 with a partial table.
l_work="$TEST_ROOT/l/work"
write_meta "$l_work" false null 1
add_row "$l_work" 1 alpha r1a
add_verdict "$l_work" 1 r1a '{"final":"pass"}'
printf '{"scenario":"al\n' >>"$l_work/trial-1/batches/b1/results.jsonl"
run_script l "$l_work"
assert_exit "results.jsonl with a truncated JSON line after a valid row exits 1" l 1

if [[ "$FAILURES" -gt 0 ]]; then
    echo "STATUS: FAILED ($FAILURES failure(s))"
    exit 1
fi

echo "STATUS: PASSED"
