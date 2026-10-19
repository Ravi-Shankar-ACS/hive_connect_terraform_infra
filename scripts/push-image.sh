#!/usr/bin/env bash
# Build an application image for linux/arm64 and push it to ECR, tagged with
# the commit. Run as hive-developer or hive-admin (short-lived credentials).
#
#   scripts/push-image.sh <env> <service> <source-dir> [tag]
#
#   scripts/push-image.sh uat hiveconnect-api ../hiveconnect
#   scripts/push-image.sh uat prism ../prism
#
# Then set image_tag for the service in envs/<env>/apps.tfvars and plan/apply <env>/apps.
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
[[ $# -ge 3 ]] || die "Usage: scripts/push-image.sh <env> <service> <source-dir> [tag]"

env="$1"
service="$2"
src="$3"
REGION="${AWS_REGION:-ap-south-1}"
export AWS_PAGER=""

[[ -f "$src/Dockerfile" ]] || die "No Dockerfile in $src"

if [[ -n "${4:-}" ]]; then
  tag="$4"
else
  tag="$(git -C "$src" rev-parse --short=12 HEAD)" || die "$src is not a git repository; pass a tag."
  [[ -z "$(git -C "$src" status --porcelain)" ]] \
    || die "$src has uncommitted changes, so the tag would not match the code. Commit first, or pass a tag."
fi

account="$(aws sts get-caller-identity --query Account --output text)"
registry="$account.dkr.ecr.$REGION.amazonaws.com"
image="$registry/hive-$env/$service:$tag"

echo "==> Signing in to $registry"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$registry"

echo "==> Building and pushing $image (linux/arm64)"
docker buildx build --platform linux/arm64 --provenance=false -t "$image" --push "$src"

echo "==> Waiting for the image scan"
if aws ecr wait image-scan-complete --region "$REGION" --repository-name "hive-$env/$service" --image-id imageTag="$tag" 2>/dev/null; then
  aws ecr describe-image-scan-findings --region "$REGION" --repository-name "hive-$env/$service" \
    --image-id imageTag="$tag" --query 'imageScanFindings.findingSeverityCounts' --output table || true
else
  echo "   (scan still running or handled by Inspector; check the ECR console)"
fi

echo
echo "Pushed. Now set in envs/$env/apps.tfvars:"
echo "  \"$service\" = { image_tag = \"$tag\" ... }"
echo "then: scripts/tf.sh $env/apps plan"
