#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="$PROJECT_DIR/bin/cog-nix"
FIXTURES="$SCRIPT_DIR/fixtures"

pass=0
fail=0

run_test() {
  local name="$1"
  local file="$2"
  local output="/tmp/cog-nix-test-${name}.scip"
  local errfile="/tmp/cog-nix-test-${name}.err"

  echo -n "Test: $name ... "
  if "$BIN" --output "$output" "$file" 2>"$errfile"; then
    if [[ -s "$output" ]]; then
      if command -v protoc &>/dev/null; then
        if protoc --decode_raw < "$output" >/dev/null 2>&1; then
          echo "PASS (valid protobuf)"
          pass=$((pass + 1))
        else
          echo "FAIL (invalid protobuf)"
          fail=$((fail + 1))
        fi
      else
        echo "PASS (non-empty output, protoc not available for validation)"
        pass=$((pass + 1))
      fi
    else
      echo "FAIL (empty output)"
      echo "  stderr: $(cat "$errfile")"
      fail=$((fail + 1))
    fi
  else
    echo "FAIL (non-zero exit)"
    echo "  stderr: $(cat "$errfile")"
    fail=$((fail + 1))
  fi
  rm -f "$output" "$errfile"
}

echo "=== cog-nix smoke tests ==="
echo ""

# Verify nix is available
if ! command -v nix &>/dev/null; then
  echo "SKIP: nix not found in PATH"
  exit 0
fi

echo "nix version: $(nix --version)"
echo ""

run_test "simple_project" "$FIXTURES/simple_project/default.nix"
run_test "flake_project"  "$FIXTURES/flake_project/flake.nix"
run_test "let_functions"  "$FIXTURES/let_and_functions/test.nix"
run_test "inherit_with"   "$FIXTURES/inherit_and_with/test.nix"

echo ""
echo "Results: $pass passed, $fail failed"

if [[ $fail -gt 0 ]]; then
  exit 1
fi
