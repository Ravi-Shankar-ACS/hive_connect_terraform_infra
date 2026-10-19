# HiveConnect infrastructure

Terraform for the HiveConnect Infrastructure Plan (Oct 2026): HiveConnect and Prism on ECS Fargate (Graviton, one on-demand task per service with Spot above it), RDS PostgreSQL 17, an ALB with WAF, in a new VPC inside the existing AWS account in Mumbai (ap-south-1). The running EKS and Aurora stack is never touched: a permission boundary on every `hive-*` role denies changes to it.

UAT and production use the same code. Everything that differs lives in `envs/uat/` and `envs/prod/`.

```
bootstrap/            state bucket + KMS key (applied once, by an existing administrator)
account/              account-wide: hive-* roles, permission boundary, GuardDuty, Config,
                      CloudTrail, Access Analyzer, Inspector, cost tags (break-glass admin)
stacks/network/       layer 1: VPC, subnets, NAT, security groups, flow logs, KMS keys
stacks/data/          layer 2: RDS PostgreSQL
stacks/platform/      layer 3: Route 53, ACM, ALB, WAF, ECR, ECS cluster, buckets, secrets,
                      alarms, budget, IoT device policy
stacks/apps/          layer 4: the ECS services, autoscaling, db-admin task, dashboard
modules/              network, alb-waf, ecs-cluster, ecs-service, rds-postgres, ecr,
                      iam-roles, observability, s3-bucket, budgets
envs/                 backend.hcl (written by bootstrap), account.tfvars,
                      uat/*.tfvars, prod/*.tfvars
policies/             custom Checkov rules (no 0.0.0.0/0 to the database, ...)
scripts/              tf.sh (the only way to run Terraform), preflight, push-image,
                      run-task, stop-spot-task, prices-uat
tests/                Terratest suite that builds UAT on Floci (local AWS emulator)
docs/runbook.md       secrets, database roles, deploys, migrations, tests, drills, cutover
```

Each layer has its own state (`<env>/<layer>.tfstate`), so a bad apply in one layer cannot damage another. Apply them in order: network → data → platform → apps.

## Tools

| Tool | Version tested | Used for |
| --- | --- | --- |
| Terraform | 1.16.5 (needs ≥ 1.11 for S3 native locking) | everything |
| AWS provider | 6.67.0 (`~> 6.0`) | |
| TFLint + AWS ruleset | 0.64.0 + 0.49.0 | `tf.sh check` |
| Checkov | 3.3.23 | `tf.sh check` |
| AWS CLI v2 + Session Manager plugin | | sign-in, scripts, ECS Exec |
| Docker with buildx | | arm64 images, local tests |
| Go | 1.26+ | Terratest |

The scripts are bash. On Windows use Git Bash.

## Signing in

Everyone uses their own IAM user with MFA and assumes a role for one hour. Nobody creates access keys for this build. Add to `~/.aws/config`:

```ini
[profile hive-admin]
role_arn         = arn:aws:iam::<account-id>:role/hive-admin
source_profile   = <your-user-profile>
mfa_serial       = arn:aws:iam::<account-id>:mfa/<your-mfa-device>
duration_seconds = 3600
region           = ap-south-1
```

Then `export AWS_PROFILE=hive-admin`. `scripts/tf.sh` refuses to run an environment layer unless you are `hive-admin`. Use `hive-developer` for pushing images and reading logs, and `hive-readonly` to look around.

## First-time setup

This follows plan section 7 (steps 1–4).

1. **Fill in the TODOs.** Search for `TODO` in `envs/`: account ID, engineers' IAM user ARNs, alert emails, hostnames, IoT prefix, service ports, environment variables and secret mappings.
2. **Preflight** (break-glass admin): `scripts/preflight.sh`. It changes nothing. It prints quotas, which security services are already on (set the matching `enable_*` to `false` in `envs/account.tfvars`) and the ARNs of the running stack. Paste those ARNs into `protected_resource_arns`. Raise any quota that is short (Elastic IPs: 4 of 5 were used).
3. **Bootstrap** (break-glass admin):
   ```bash
   cd bootstrap
   cp terraform.tfvars.example terraform.tfvars   # fill in
   terraform init && terraform apply
   ```
   This writes `envs/backend.hcl`; commit it.
4. **Account stack** (break-glass admin): `scripts/tf.sh account plan`, have it reviewed, then `scripts/tf.sh account apply`. Confirm the SNS subscription emails.
5. **UAT** (hive-admin), one layer at a time:
   ```bash
   scripts/tf.sh uat/network plan    # then: apply
   scripts/tf.sh uat/data plan       # then: apply   (RDS takes ~15 min)
   scripts/tf.sh uat/platform plan   # then: apply
   ```
   - After network: send `scripts/tf.sh uat/network output nat_public_ip` to every provider that filters by IP.
   - After platform: confirm the alert subscription emails.
6. **Secrets and database roles:** follow [docs/runbook.md](docs/runbook.md), sections 1 and 2.
7. **Images and services:** `scripts/push-image.sh uat hiveconnect-api <src>`, then the same for `prism`. Set both `image_tag`s in `envs/uat/apps.tfvars`, then `scripts/tf.sh uat/apps plan` and `apply`.
8. **A day later:** set `activate_cost_tags = true` in `envs/account.tfvars` and apply `account`. AWS only offers a tag for activation once it has seen it. The budget filters on the `Env` tag.
9. **After one clean UAT week:** set `waf_block_mode = true` in `envs/uat/platform.tfvars` and apply `uat/platform`.

## Everyday work

```bash
scripts/tf.sh uat/apps plan     # fmt, validate, tflint, checkov, then plan
                                # a second engineer reads stacks/apps/.plans/uat.txt
scripts/tf.sh uat/apps apply    # applies exactly the reviewed plan; asks who reviewed it
scripts/tf.sh uat/network drift # weekly: exit 2 means someone changed something by hand
```

- **Deploy a new version:** push the image, change `image_tag`, run the migration as a one-off task (`scripts/run-task.sh uat hiveconnect-api -- <migrate command>`), then plan and apply `uat/apps`.
- **Roll back:** put the previous `image_tag` back and apply. A deployment that never gets healthy rolls back on its own (deployment circuit breaker).

## Testing

| What | Command | AWS needed |
| --- | --- | --- |
| Static checks: fmt, validate, TFLint, Checkov with `policies/` | `scripts/tf.sh <target> check` | no |
| Full local build of UAT, with assertions | `tests/run-local.sh` | no (Docker) |
| Scaling, Spot interruption, restore drill, WAF, alarms | [docs/runbook.md](docs/runbook.md), section 4 | yes (UAT) |

`tests/run-local.sh` runs the static checks for every layer of both environments. It then starts [Floci](https://github.com/floci-io/floci), a free local AWS emulator, and Terratest builds bootstrap → account → network → data → platform → apps with the real UAT values. After each layer it checks, through the AWS API:

- **State and roles:** the state bucket is locked to `hive-admin` and break-glass.
- **Boundary:** the permission boundary has every guardrail, and every role carries it; `hive-admin` needs MFA and lasts one hour.
- **Network:** subnet ranges match the plan; the data subnets have no route out.
- **Security groups:** `db-sg` accepts only `app-sg` on 5432 and has no egress; `app-sg` allows only 443 out plus the database.
- **Database:** RDS is private, encrypted, PostgreSQL 17, Single-AZ, with 14-day backups and deletion protection.
- **Edge:** the ALB uses TLS 1.2/1.3 and redirects HTTP; WAF has its four rules in Count mode and is attached to the ALB.
- **Images and storage:** ECR tags are immutable and scanned on push; buckets are private, versioned, TLS-only and KMS-encrypted (ALB logs use SSE-S3).
- **Secrets and alerts:** the eight secrets are on the CMK; the alert topic is encrypted; every alarm exists; the budget is $230.
- **Services:** FARGATE base 1 / weight 0 with FARGATE_SPOT weight 1; ARM64; 120 s stop timeout; no keys or Redis settings; autoscaling 1–2 with both policies.

It takes about 9 minutes. Known Floci gaps, where the code is right but the emulator falls short:

- Access Analyzer and ECR registry scanning are not implemented, so the test switches those two toggles off.
- Floci keeps AWS's default egress rule, which the provider revokes. The test ignores that one unlabelled rule.
- Floci cannot start ECS tasks for services that use a capacity-provider strategy, so running containers and live traffic through the ALB are tested in UAT itself (runbook section 4).

## Where this differs from the plan, and why

- **Running-tasks alarm:** "Running tasks below desired" needs Container Insights, which adds about $15–20 a month. Instead each service alarms when healthy tasks behind the ALB stay below the minimum for 10 minutes (free ALB metric). An ECS event rule alerts at once when a task, such as a Spot task, cannot be placed. To turn Container Insights on, add `container_insights = true` to the `cluster` module in `stacks/platform/main.tf`.
- **Directory layout:** layers live in `stacks/` and environments in `envs/<env>/*.tfvars`, so UAT and production run the same code with only variables different. That is what plan section 6 asks for, without copying code per environment.
- **Account-wide pieces:** roles, boundary and security baseline live in `account/`, applied by the break-glass administrator. The boundary stops `hive-*` roles from editing their own guardrails.
- **Additions:**
  - ECS Exec sessions are encrypted with the environment key and logged.
  - A `db-admin` task gives psql on the private database without a bastion.
  - An IOPS alarm watches the 3,000 IOPS gp3 ceiling.
  - WAF's `SizeRestrictions_BODY` rule only counts, so file uploads over 8 KB are not blocked.
- **Not built (plan options, not decisions):** the off-hours schedule (saves about $78 a month in UAT) and a NAT instance. A real-AWS Terratest throwaway stack is also not built yet; the local Floci suite covers the configuration, and runbook section 4 covers live behaviour in UAT.
