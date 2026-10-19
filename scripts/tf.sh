#!/usr/bin/env bash
# The one way to run Terraform in this repository.
#
#   scripts/tf.sh <target> <command>
#
#   target   account | <env>/<layer>      env: uat, prod   layer: network, data, platform, apps
#   command  check         fmt, validate, tflint, checkov (no AWS calls)
#            plan          check, then plan; saves .plans/<env>.tfplan and a readable .txt
#            apply         apply the saved plan, after a second engineer has read it
#            plan-destroy  like plan, for removing everything in the target
#            drift         plain plan; exit 0 = no drift, 2 = drift
#            output        terraform output [args]
#            init          terraform init only
#
# Examples:
#   scripts/tf.sh uat/network plan
#   scripts/tf.sh uat/network apply
#   scripts/tf.sh uat/apps output -json services
#
# Layers depend on each other in this order: network -> data -> platform -> apps.
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

[[ $# -ge 2 ]] || usage
target="$1"
cmd="$2"
shift 2

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$target" in
  account)
    env="account"
    dir="$ROOT/account"
    stack_path="account"
    rel=".."
    key="account/terraform.tfstate"
    var_files=("$rel/envs/account.tfvars")
    ;;
  */*)
    env="${target%%/*}"
    layer="${target#*/}"
    [[ "$env" == "uat" || "$env" == "prod" ]] || die "Unknown environment '$env' (use uat or prod)."
    [[ "$layer" =~ ^(network|data|platform|apps)$ ]] || die "Unknown layer '$layer' (use network, data, platform or apps)."
    dir="$ROOT/stacks/$layer"
    stack_path="stacks/$layer"
    rel="../.."
    key="$env/$layer.tfstate"
    var_files=("$rel/envs/$env/common.tfvars" "$rel/envs/$env/$layer.tfvars")
    ;;
  *) usage ;;
esac

cd "$dir"
for f in "${var_files[@]}"; do [[ -f "$f" ]] || die "Missing $f"; done

# A separate working directory per environment, so a uat init can never be
# used to apply prod (or the other way round).
export TF_DATA_DIR=".terraform/$env"
var_args=()
for f in "${var_files[@]}"; do var_args+=("-var-file=$f"); done
plan_file=".plans/$env.tfplan"

need() { command -v "$1" >/dev/null 2>&1 || die "$1 is not installed (see README, Tools)."; }

check_identity() {
  need aws
  local arn
  arn="$(aws sts get-caller-identity --query Arn --output text 2>/dev/null)" \
    || die "Not signed in to AWS. Assume the hive-admin role with MFA first (README, Signing in)."
  echo "Signed in as: $arn"
  if [[ "$target" == "account" ]]; then
    [[ "$arn" != *":assumed-role/hive-"* ]] \
      || die "The account stack is applied by the break-glass administrator; the permission boundary stops hive-* roles from changing it."
  elif [[ "${HIVE_SKIP_ROLE_CHECK:-}" != "1" ]]; then
    [[ "$arn" == *":assumed-role/hive-admin/"* ]] \
      || die "Assume the hive-admin role with MFA first (README, Signing in)."
  fi
}

tf_init() {
  [[ -f "$rel/envs/backend.hcl" ]] || die "envs/backend.hcl is missing; apply bootstrap/ first."
  terraform init -input=false -no-color \
    -backend-config="$rel/envs/backend.hcl" \
    -backend-config="key=$key" >/dev/null
}

run_checks() {
  need terraform
  need tflint
  need checkov
  echo "==> terraform fmt"
  terraform fmt -check -recursive "$rel/modules" >/dev/null || die "Run: terraform fmt -recursive (modules)"
  terraform fmt -check -recursive . >/dev/null || die "Run: terraform fmt -recursive ($dir)"
  echo "==> terraform validate"
  terraform init -backend=false -input=false -no-color >/dev/null
  terraform validate -no-color
  echo "==> tflint"
  tflint --init --config "$rel/.tflint.hcl" >/dev/null
  tflint --config "$rel/.tflint.hcl" "${var_args[@]/#-var-file=/--var-file=}"
  echo "==> checkov"
  checkov -d . --config-file "$rel/.checkov.yaml" --external-checks-dir "$rel/policies" \
    "${var_args[@]/#-var-file=/--var-file=}"
  echo "All checks passed."
}

case "$cmd" in
  init)
    check_identity
    tf_init
    echo "Initialised $target."
    ;;

  check)
    run_checks
    ;;

  plan | plan-destroy)
    run_checks
    check_identity
    tf_init
    mkdir -p .plans
    destroy_flag=()
    [[ "$cmd" == "plan-destroy" ]] && destroy_flag=(-destroy)
    terraform plan -input=false "${destroy_flag[@]}" "${var_args[@]}" -out="$plan_file" "$@"
    terraform show -no-color "$plan_file" > ".plans/$env.txt"
    echo
    echo "Plan saved. A second engineer reads $stack_path/.plans/$env.txt (or the output above),"
    echo "then you run: scripts/tf.sh $target apply"
    ;;

  apply)
    [[ -f "$plan_file" ]] || die "No saved plan. Run: scripts/tf.sh $target plan"
    check_identity
    tf_init
    terraform show -no-color "$plan_file" | grep -E '^(Plan:|No changes)' || true
    read -r -p "Who reviewed this plan? " reviewer
    [[ -n "$reviewer" ]] || die "A second engineer must review the plan before it is applied."
    read -r -p "Type '$target' to apply: " confirm
    [[ "$confirm" == "$target" ]] || die "Not confirmed; nothing applied."
    terraform apply -input=false "$plan_file"
    rm -f "$plan_file"
    echo "$(date -u +%FT%TZ) $target applied by $(aws sts get-caller-identity --query Arn --output text), reviewed by $reviewer" >> .plans/apply.log
    ;;

  drift)
    check_identity
    tf_init
    set +e
    terraform plan -input=false -detailed-exitcode -lock=false "${var_args[@]}" >/dev/null
    code=$?
    set -e
    case $code in
      0) echo "$target: no drift." ;;
      2) echo "$target: DRIFT - run 'scripts/tf.sh $target plan' to see it."; exit 2 ;;
      *) die "$target: plan failed." ;;
    esac
    ;;

  output)
    tf_init
    terraform output "$@"
    ;;

  *) usage ;;
esac
