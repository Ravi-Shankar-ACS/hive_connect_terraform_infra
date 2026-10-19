#!/usr/bin/env bash
# Local test, no AWS account needed:
#   1. static checks (fmt, validate, tflint, checkov) on every layer of uat and prod
#   2. a fresh Floci (local AWS emulator) in Docker
#   3. Terratest builds the whole UAT environment on Floci and checks it
#
#   tests/run-local.sh            everything
#   tests/run-local.sh --no-static  skip step 1
#
# Needs: terraform, tflint, checkov, go, docker. Takes about 10 minutes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
for tool in terraform tflint checkov go docker; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: $tool is not installed (see README, Tools)." >&2; exit 1; }
done

if [[ "${1:-}" != "--no-static" ]]; then
  echo "==> Static checks"
  for t in account uat/network uat/data uat/platform uat/apps prod/network prod/data prod/platform prod/apps; do
    if scripts/tf.sh "$t" check > /dev/null; then
      echo "    ok    $t"
    else
      echo "    FAIL  $t  (run: scripts/tf.sh $t check)"; exit 1
    fi
  done
fi

compose=(docker compose -f "$ROOT/tests/docker-compose.yml")
cleanup() {
  echo "==> Stopping Floci"
  "${compose[@]}" down --remove-orphans > /dev/null 2>&1 || true
  # Containers Floci started for RDS, ECR and so on. Only Floci's own.
  docker ps -aq --filter "name=floci-aws-" | xargs -r docker rm -f > /dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> Starting a fresh Floci"
cleanup
"${compose[@]}" up -d --wait > /dev/null

echo "==> Terratest: building UAT on Floci"
cd "$ROOT/tests"
go test -v -count=1 -timeout 60m -run TestUatStackOnFloci ./... 2>&1 | tee "$ROOT/.terratest.log" | grep -E '^(=== RUN|--- |PASS|FAIL|ok )|Error Trace|Error:|Messages:|expected|actual|==> applying'
exit "${PIPESTATUS[0]}"
