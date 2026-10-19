#!/usr/bin/env bash
# Plan step 1: read-only checks before anything is built. Changes nothing.
#
#   scripts/preflight.sh [zone-name]      default zone: iotiqinnovations.com
#
# Prints: who you are, the service quotas the build needs, which account-wide
# security services are already on (set the matching enable_* to false in
# envs/account.tfvars), the existing VPC ranges, and the ARNs of the running
# stack to paste into protected_resource_arns.
set -uo pipefail

REGION="${AWS_REGION:-ap-south-1}"
ZONE="${1:-iotiqinnovations.com}"
export AWS_PAGER=""

section() { printf '\n== %s ==\n' "$1"; }
quota() { # service-code quota-code label
  local v
  v="$(aws service-quotas get-service-quota --region "$REGION" --service-code "$1" --quota-code "$2" \
        --query 'Quota.Value' --output text 2>/dev/null \
      || aws service-quotas get-aws-default-service-quota --region "$REGION" --service-code "$1" --quota-code "$2" \
        --query 'Quota.Value' --output text 2>/dev/null || echo '?')"
  printf '  %-42s %s\n' "$3" "$v"
}

section "Identity"
aws sts get-caller-identity --output table || { echo "Not signed in."; exit 1; }

section "Quotas in $REGION (each environment needs: 1 EIP, 1 NAT, 1 VPC, 1 ALB, ~1.5-6 Fargate vCPU)"
quota ec2 L-0263D0A3 "Elastic IPs"
printf '  %-42s %s\n' "  Elastic IPs allocated now" "$(aws ec2 describe-addresses --region "$REGION" --query 'length(Addresses)' --output text)"
quota vpc L-F678F1CE "VPCs per region"
printf '  %-42s %s\n' "  VPCs now" "$(aws ec2 describe-vpcs --region "$REGION" --query 'length(Vpcs)' --output text)"
quota vpc L-FE5A380F "NAT gateways per AZ"
quota elasticloadbalancing L-53DA6B97 "Application Load Balancers"
printf '  %-42s %s\n' "  ALBs now" "$(aws elbv2 describe-load-balancers --region "$REGION" --query 'length(LoadBalancers)' --output text)"
quota fargate L-3032A538 "Fargate On-Demand vCPU"
quota fargate L-36FBB829 "Fargate Spot vCPU"

section "Account-wide services already on? (true here => set enable_* = false)"
printf '  %-42s %s\n' "GuardDuty detectors" "$(aws guardduty list-detectors --region "$REGION" --query 'length(DetectorIds)' --output text 2>/dev/null)"
printf '  %-42s %s\n' "Config recorders" "$(aws configservice describe-configuration-recorders --region "$REGION" --query 'length(ConfigurationRecorders)' --output text 2>/dev/null)"
printf '  %-42s %s\n' "CloudTrail trails" "$(aws cloudtrail describe-trails --region "$REGION" --query 'length(trailList)' --output text 2>/dev/null)"
printf '  %-42s %s\n' "Access Analyzer (account)" "$(aws accessanalyzer list-analyzers --region "$REGION" --type ACCOUNT --query 'length(analyzers)' --output text 2>/dev/null)"
printf '  %-42s %s\n' "Inspector ECR scanning" "$(aws inspector2 batch-get-account-status --region "$REGION" --query 'accounts[0].resourceState.ecr.status' --output text 2>/dev/null)"
printf '  %-42s %s\n' "ECR registry scan type" "$(aws ecr get-registry-scanning-configuration --region "$REGION" --query 'scanningConfiguration.scanType' --output text 2>/dev/null)"
printf '  %-42s %s\n' "ECR repositories (old stack)" "$(aws ecr describe-repositories --region "$REGION" --query 'repositories[].repositoryName' --output text 2>/dev/null)"
printf '  %-42s %s\n' "Cost tags Project/Env" "$(aws ce list-cost-allocation-tags --region us-east-1 --tag-keys Project Env --query 'CostAllocationTags[].[TagKey,Status]' --output text 2>/dev/null | tr '\n' ' ')"
printf '  %-42s %s\n' "S3 account Block Public Access" "$(aws s3control get-public-access-block --account-id "$(aws sts get-caller-identity --query Account --output text)" --query 'PublicAccessBlockConfiguration' --output text 2>/dev/null || echo 'not set (leave it that way)')"

section "Hosted zone"
aws route53 list-hosted-zones-by-name --dns-name "$ZONE" --max-items 1 \
  --query 'HostedZones[].[Name,Id,Config.PrivateZone]' --output text

section "Existing VPC ranges (the new VPCs use 10.20.0.0/16 and 10.30.0.0/16)"
aws ec2 describe-vpcs --region "$REGION" --query 'Vpcs[].[VpcId,CidrBlock,IsDefault]' --output text

section "Candidates for protected_resource_arns (review, then paste into envs/account.tfvars)"
for c in $(aws eks list-clusters --region "$REGION" --query 'clusters[]' --output text 2>/dev/null); do
  arn="$(aws eks describe-cluster --region "$REGION" --name "$c" --query 'cluster.arn' --output text)"
  echo "  \"$arn\","
  echo "  \"${arn/:cluster\//:nodegroup/}/*\","
done
aws rds describe-db-clusters --region "$REGION" --query 'DBClusters[].DBClusterArn' --output text 2>/dev/null \
  | tr '\t' '\n' | sed '/^$/d; s/.*/  "&",/'
aws rds describe-db-instances --region "$REGION" --query 'DBInstances[].DBInstanceArn' --output text 2>/dev/null \
  | tr '\t' '\n' | sed '/^$/d; s/.*/  "&",/'
for lb in $(aws elbv2 describe-load-balancers --region "$REGION" --query 'LoadBalancers[].LoadBalancerArn' --output text 2>/dev/null); do
  echo "  \"$lb\","
  echo "  \"${lb/:loadbalancer\//:listener/}/*\","
  echo "  \"${lb/:loadbalancer\//:listener-rule/}/*\","
done
aws ec2 describe-instances --region "$REGION" --filters Name=instance-state-name,Values=running,stopped \
  --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`]|[0].Value]' --output text 2>/dev/null \
  | while read -r id name; do
      echo "  \"arn:aws:ec2:$REGION:$(aws sts get-caller-identity --query Account --output text):instance/$id\", # $name"
    done

echo
echo "Done. Nothing was changed."
