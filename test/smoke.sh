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

  echo -n "Test: $name ... "
  if "$BIN" --output "$output" "$file" 2>/dev/null; then
    # Verify output is non-empty
    if [[ -s "$output" ]]; then
      # If protoc is available, verify it's valid protobuf
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
      fail=$((fail + 1))
    fi
    rm -f "$output"
  else
    echo "FAIL (non-zero exit)"
    fail=$((fail + 1))
    rm -f "$output"
  fi
}

echo "=== cog-nix smoke tests ==="
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
