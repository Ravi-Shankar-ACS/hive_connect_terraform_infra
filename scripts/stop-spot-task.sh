#!/usr/bin/env bash
# Spot interruption test (plan section 6): stop one running Spot task the way
# Fargate reclaims it (SIGTERM, then SIGKILL after stopTimeout), during a load
# test. Pass: the on-demand task keeps answering, the app shuts down cleanly,
# and ECS starts a replacement.
#
#   scripts/stop-spot-task.sh <env> <service>
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
[[ $# -eq 2 ]] || die "Usage: scripts/stop-spot-task.sh <env> <service>"

REGION="${AWS_REGION:-ap-south-1}"
export AWS_PAGER=""
cluster="hive-$1"
service="$2"

tasks="$(aws ecs list-tasks --region "$REGION" --cluster "$cluster" --service-name "$service" \
  --desired-status RUNNING --query 'taskArns' --output text)"
[[ -n "$tasks" && "$tasks" != "None" ]] || die "No running tasks for $service."

# shellcheck disable=SC2086
spot="$(aws ecs describe-tasks --region "$REGION" --cluster "$cluster" --tasks $tasks \
  --query "tasks[?capacityProviderName=='FARGATE_SPOT'].taskArn | [0]" --output text)"
[[ "$spot" != "None" && -n "$spot" ]] || die "No Spot task is running. Scale out first (load test), then retry."

echo "Stopping Spot task $spot"
aws ecs stop-task --region "$REGION" --cluster "$cluster" --task "$spot" --reason "Spot interruption test" >/dev/null
echo "Now watch:"
echo "  - the service URL keeps answering"
echo "  - logs /hive-$1/ecs/$service show a clean shutdown after SIGTERM"
echo "  - aws ecs describe-services --cluster $cluster --services $service --query 'services[0].[runningCount,desiredCount]'"
