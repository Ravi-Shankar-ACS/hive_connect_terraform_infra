# HiveConnect runbook

Commands assume `AWS_PROFILE=hive-admin` (MFA) and region ap-south-1. Replace `uat` with `prod` for production.

## 1. Secret values

Terraform creates the secrets empty, so no value ever enters Terraform state. Every value is new per environment. Each secret holds JSON; `envs/<env>/apps.tfvars` maps environment variables to `"<secret>:<key>"`.

```bash
# Example: write a file, store it, delete it (*.secret.json is git-ignored).
cat > smtp.secret.json <<'EOF'
{ "host": "smtp.example.com", "user": "...", "password": "..." }
EOF
aws secretsmanager put-secret-value --secret-id hive-uat/smtp --secret-string file://smtp.secret.json
rm smtp.secret.json
```

The database secrets come after section 2:

```bash
DB=$(scripts/tf.sh uat/data output -raw db_address)
# hive-uat/db-hiveconnect
{ "DATABASE_URL": "postgresql://hiveconnect_app:<password>@$DB:5432/hiveconnect?sslmode=require" }
# hive-uat/db-prism (no pooler, so DIRECT_URL is the same URL)
{ "DATABASE_URL": "postgresql://prism_app:<password>@$DB:5432/prism?sslmode=require&connection_limit=10",
  "DIRECT_URL":   "postgresql://prism_app:<password>@$DB:5432/prism?sslmode=require" }
```

Keep pool size × maximum tasks under about 100 connections. The `db-connections-high` alarm fires at 80.

A task whose secret is still empty fails to start and reports `ResourceInitializationError`. Set every secret a service references before applying `apps`.

## 2. Database roles (one per application)

The database is private, with no bastion or open port. `db-admin` is a small task on regular Fargate that opens psql as the RDS master user, through ECS Exec:

```bash
scripts/run-task.sh uat db-admin
```

```sql
CREATE ROLE hiveconnect_app LOGIN;
GRANT hiveconnect_app TO CURRENT_USER;     -- needed to hand it the database
\password hiveconnect_app
ALTER DATABASE hiveconnect OWNER TO hiveconnect_app;

CREATE ROLE prism_app LOGIN;
GRANT prism_app TO CURRENT_USER;
\password prism_app
CREATE DATABASE prism OWNER prism_app;
\q
```

`\password` prompts and sends only a hash, so passwords never appear in logs or session recordings. The master password stays in the RDS-managed secret; applications never use it.

## 3. Deploy, migrate, roll back

```bash
scripts/push-image.sh uat hiveconnect-api ../hiveconnect     # tag = commit; scanned on push
# edit envs/uat/apps.tfvars: image_tag = "<tag>"
scripts/run-task.sh uat hiveconnect-api -- npm run migrate    # one-off, on-demand Fargate, waits for exit 0
scripts/tf.sh uat/apps plan && scripts/tf.sh uat/apps apply
```

- Take a manual snapshot before every schema change: `aws rds create-db-snapshot --db-instance-identifier hive-uat-postgres --db-snapshot-identifier hive-uat-before-<change> --tags Key=Project,Value=HiveConnect Key=Env,Value=uat`.
- **Roll back:** put the previous `image_tag` back and apply. The deployment circuit breaker already rolls back a deployment that never becomes healthy.
- **Restart without a deploy:** `aws ecs update-service --cluster hive-uat --service prism --force-new-deployment`. `hive-developer` may do this.
- **Logs:** `aws logs tail /hive-uat/ecs/hiveconnect-api --follow`.
- **Shell in a running task:** `aws ecs execute-command --cluster hive-uat --task <id> --container hiveconnect-api --interactive --command sh`.

## 4. Tests in UAT (plan section 6)

| Test | How | Passes when |
| --- | --- | --- |
| Health through WAF | `curl -i https://hiveconnect-uat.iotiqinnovations.com/healthz` | 200 |
| Scaling | Load test (k6) above 60% CPU or 1,000 requests per task per minute | A Spot task starts, registers healthy, and scales in after load |
| Spot interruption | During the load test: `scripts/stop-spot-task.sh uat hiveconnect-api` | The on-demand task keeps answering; logs show a clean SIGTERM shutdown; a replacement starts |
| WAF | `curl -s -o /dev/null -w '%{http_code}' 'https://hiveconnect-uat.iotiqinnovations.com/?x=<script>alert(1)</script>'` | Counted in WAF sampled requests (Count); 403 after `waf_block_mode = true` |
| Alarms | `aws cloudwatch set-alarm-state --alarm-name hive-uat-alb-5xx --state-value ALARM --state-reason test`, repeated for each alarm | A notification arrives |
| Restore drill | Below | An application role connects and reads data |

**Restore drill** (before production, then every quarter):

```bash
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier hive-uat-postgres --target-db-instance-identifier hive-uat-restore-drill \
  --use-latest-restorable-time --db-subnet-group-name hive-uat-postgres \
  --vpc-security-group-ids "$(scripts/tf.sh uat/network output -raw db_security_group_id)" \
  --db-instance-class db.t4g.medium --no-publicly-accessible --no-multi-az \
  --tags Key=Project,Value=HiveConnect Key=Env,Value=uat
aws rds wait db-instance-available --db-instance-identifier hive-uat-restore-drill
scripts/run-task.sh uat db-admin
#   \c "host=<restored endpoint> dbname=hiveconnect sslmode=require"   (same master password as the source)
#   SELECT count(*) FROM <a table>;                                    (compare with the source)
aws rds delete-db-instance --db-instance-identifier hive-uat-restore-drill --skip-final-snapshot
```

Write down requests per second, p95 latency, database IOPS and CPU credits from the `hive-uat` dashboard. These numbers set production's caps (plan step 6).

## 5. Access

- **Add an engineer:** add their IAM user ARN to `envs/account.tfvars`; the break-glass admin applies `account`. They need MFA on their user.
- **Remove an engineer:** remove the ARN and apply. Their current session ends within an hour.
- The permission boundary blocks any `hive-*` role from changing the old EKS cluster, Aurora, the old load balancers, the default VPC and the account guardrails. If a legitimate change is refused, the break-glass admin does it, never by loosening the boundary in a hurry.

## 6. Production

Production is the same code with `envs/prod/*.tfvars` (10.30.0.0/16; caps of 5 HiveConnect and 3 Prism tasks; WAF in Block mode).

1. Sign off UAT with the measured numbers. Set the production caps, and decide on Multi-AZ separately.
2. Apply `prod/network`, `prod/data`, `prod/platform`, then set the secrets, create the database roles, and apply `prod/apps`.
3. Rehearse the data copy twice: restore an Aurora snapshot, `pg_dump` from it, `pg_restore --jobs 4` into RDS, then compare row counts. This needs a network path, such as VPC peering, from the restored Aurora to the new VPC.
4. A week before cutover, lower the TTL of the existing records to 60 seconds.
5. Cutover with weighted DNS. In Route 53, change the old record to weighted (set identifier `old`, weight 100). Set `dns_weight = 0` in `envs/prod/platform.tfvars` and apply. Stop writes on the old stack, run the final copy, then raise `dns_weight` and lower `old` to 0.
6. Roll back by swapping the weights, as long as no writes have reached the new database.
7. Keep EKS and Aurora read-only for 30 days, then remove them after a final snapshot export.

## 7. Troubleshooting

| Symptom | Look at |
| --- | --- |
| `healthy-tasks-below-minimum` alarm | `aws ecs describe-services --cluster hive-uat --services <svc> --query 'services[0].events[:5]'` |
| "ECS Service Action ... SERVICE_TASK_PLACEMENT_FAILURE" email | No Spot capacity; the on-demand task keeps serving. Check again later. |
| Task stops with `ResourceInitializationError` | An empty secret or a missing JSON key (section 1) |
| Outbound call fails | Is the provider allowlisting the NAT address? Does the port need adding to `app_egress_tcp_ports`? |
| `db-surplus-credits-charged` alarm | Database CPU above baseline: check the dashboard; consider a larger class |
| `tf.sh` says "Saved plan is stale" | Someone applied since your plan. Plan again. |
