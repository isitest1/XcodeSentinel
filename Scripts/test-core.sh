#!/usr/bin/env bash
# Runs the SentinelCore unit tests reliably inside the dev container.
#
# Why not just `swift test`? Under the dev container on Apple Silicon the Linux
# XCTest runner (via QEMU user emulation) intermittently hangs in its
# between-tests / teardown bookkeeping when many tests share one process.
# Individual runs are fast and reliable, so this script:
#   1. runs each suite in its own process;
#   2. if a suite has no clean "Executed N tests, with 0 failures" summary
#      (i.e. it hung on teardown), re-runs that suite one test per process.
#
# On CI (native x86_64 Linux) `swift test` works normally and is what the
# `core-tests` workflow uses.
#
# Usage:
#   Scripts/test-core.sh            # build, then run
#   Scripts/test-core.sh --no-build # skip the build step
set -uo pipefail

PKG="Packages/SentinelCore"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ "${1:-}" != "--no-build" ]]; then
  echo "==> swift build --build-tests"
  swift build --package-path "$PKG" --build-tests || exit 1
fi

BIN="$(find "$PKG/.build" -path '*debug*' -name 'SentinelCorePackageTests.xctest' -type f 2>/dev/null | head -1)"
[[ -z "$BIN" ]] && BIN="$(find "$PKG/.build" -name '*PackageTests.xctest' 2>/dev/null | head -1)"
if [[ -z "$BIN" ]]; then
  echo "!! test bundle not found; run without --no-build" >&2
  exit 1
fi

mapfile -t TESTS < <("$BIN" --list-tests 2>/dev/null | sed -n 's#^SentinelCoreTests\.##p')
if [[ ${#TESTS[@]} -eq 0 ]]; then
  echo "!! could not enumerate tests" >&2
  exit 1
fi

mapfile -t SUITES < <(printf '%s\n' "${TESTS[@]}" | cut -d/ -f1 | sort -u)

total_fail=0
total_run=0

run_test_by_test() {
  local suite="$1" t out rc attempt ok
  for t in "${TESTS[@]}"; do
    [[ "$t" == "$suite/"* ]] || continue
    total_run=$((total_run + 1))
    ok=0
    # The emulated XCTest runner can hang on teardown (rc=124) even for a single
    # test that already printed "passed". Retry a timeout; only a real
    # "failed"/"error:" line, or never seeing "passed", counts as a failure.
    for attempt in 1 2 3; do
      out="$(timeout 30 "$BIN" "SentinelCoreTests.$t" 2>&1)"; rc=$?
      if grep -qE "^Test Case .* failed|: error:" <<<"$out"; then
        ok=0; break
      fi
      if grep -q "^Test Case .* passed" <<<"$out"; then
        ok=1; break
      fi
      [[ $rc -eq 124 ]] || break   # non-timeout, non-pass, non-fail: stop retrying
    done
    if [[ $ok -eq 0 ]]; then
      total_fail=$((total_fail + 1))
      printf '    FAIL  %s (rc=%d)\n' "$t" "$rc"
      grep -E ": error:|failed \(" <<<"$out" | sed 's/^/          /'
    fi
  done
}

for suite in "${SUITES[@]}"; do
  out="$(timeout 90 "$BIN" "SentinelCoreTests.$suite" 2>&1)"
  summary="$(grep -oE "Executed [0-9]+ tests, with [0-9]+ failures" <<<"$out" | tail -1)"
  if [[ -n "$summary" ]]; then
    fails="$(sed -E 's/.*with ([0-9]+) failures/\1/' <<<"$summary")"
    ran="$(sed -E 's/Executed ([0-9]+) tests.*/\1/' <<<"$summary")"
    total_run=$((total_run + ran))
    if [[ "$fails" -gt 0 ]]; then
      total_fail=$((total_fail + fails))
      printf '  FAIL  %-30s %s\n' "$suite" "$summary"
      grep -E ": error:|failed \(" <<<"$out" | sed 's/^/        /'
    else
      printf '  ok    %-30s %s\n' "$suite" "$summary"
    fi
  else
    printf '  ??    %-30s no summary (teardown hang) — re-running test-by-test\n' "$suite"
    run_test_by_test "$suite"
  fi
done

echo "----"
if [[ "$total_fail" -gt 0 ]]; then
  echo "FAILED: $total_fail failing, ~$total_run run"
  exit 1
fi
echo "all green: ~$total_run tests"
