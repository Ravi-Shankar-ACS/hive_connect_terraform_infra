#!/usr/bin/env bash
# Run a one-off task on regular (on-demand) Fargate, never on Spot.
#
#   scripts/run-task.sh <env> <service> -- <command...>   run a command and wait for it
#   scripts/run-task.sh <env> db-admin                     open psql on the private database
#
# Examples:
#   scripts/run-task.sh uat hiveconnect-api -- npm run migrate      (database migration before a deploy)
#   scripts/run-task.sh uat prism -- npx prisma migrate deploy
#   scripts/run-task.sh uat db-admin
#
# Needs the AWS CLI and, for db-admin, the Session Manager plugin.
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
[[ $# -ge 2 ]] || die "Usage: scripts/run-task.sh <env> <service|db-admin> [-- command...]"

env="$1"
name="$2"
shift 2
[[ "${1:-}" == "--" ]] && shift

REGION="${AWS_REGION:-ap-south-1}"
export AWS_PAGER=""
cluster="hive-$env"
family="hive-$env-$name"

json_str() {
  local s="${1//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\n'/\\n}"
  printf '"%s"' "$s"
}

# Same subnets and security group as the running services.
first_service="$(aws ecs list-services --region "$REGION" --cluster "$cluster" --query 'serviceArns[0]' --output text)"
[[ "$first_service" != "None" ]] || die "No services in $cluster; apply $env/apps first."
network="$(aws ecs describe-services --region "$REGION" --cluster "$cluster" --services "$first_service" \
  --query 'services[0].networkConfiguration' --output json)"
container="$(aws ecs describe-task-definition --region "$REGION" --task-definition "$family" \
  --query 'taskDefinition.containerDefinitions[0].name' --output text)"

overrides='{}'
if [[ $# -gt 0 ]]; then
  parts=()
  for a in "$@"; do parts+=("$(json_str "$a")"); done
  overrides="{\"containerOverrides\":[{\"name\":\"$container\",\"command\":[$(IFS=,; echo "${parts[*]}")]}]}"
fi

echo "==> Starting $family on FARGATE in $cluster"
task="$(aws ecs run-task --region "$REGION" --cluster "$cluster" --task-definition "$family" \
  --capacity-provider-strategy capacityProvider=FARGATE,weight=1 \
  --network-configuration "$network" --enable-execute-command \
  --overrides "$overrides" --started-by "run-task.sh" \
  --query 'tasks[0].taskArn' --output text)"
[[ "$task" != "None" && -n "$task" ]] || die "The task did not start."
echo "    $task"

if [[ "$name" == "db-admin" && $# -eq 0 ]]; then
  echo "==> Waiting for it to run"
  aws ecs wait tasks-running --region "$REGION" --cluster "$cluster" --tasks "$task"
  sleep 15 # the ECS Exec agent needs a moment after the task starts
  echo "==> Opening psql (\\q to leave; the task stops afterwards)"
  aws ecs execute-command --region "$REGION" --cluster "$cluster" --task "$task" \
    --container "$container" --interactive --command "psql" || true
  aws ecs stop-task --region "$REGION" --cluster "$cluster" --task "$task" --reason "psql session ended" >/dev/null
  echo "Stopped."
  exit 0
fi

echo "==> Waiting for it to finish"
aws ecs wait tasks-stopped --region "$REGION" --cluster "$cluster" --tasks "$task"
code="$(aws ecs describe-tasks --region "$REGION" --cluster "$cluster" --tasks "$task" \
  --query 'tasks[0].containers[0].exitCode' --output text)"
echo "Exit code: $code   (logs: /hive-$env/ecs/$name, stream app/$container/${task##*/})"
[[ "$code" == "0" ]]
