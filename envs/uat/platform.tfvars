# UAT platform: edge, ECR, cluster, buckets, secrets, alarms and budget.

domain_name = "iotiqinnovations.com"

# TODO: confirm the UAT hostnames (plan open question 6).
services = {
  "hiveconnect-api" = { hostname = "hiveconnect-uat.iotiqinnovations.com" }
  "prism"           = { hostname = "prism-uat.iotiqinnovations.com" }
}

# Count mode for the first UAT week; set true after a clean week (plan step 4).
waf_block_mode = false
waf_rate_limit = 2000

alb_idle_timeout        = 60
alb_deletion_protection = true

# Buckets hive-uat-<name>-<account id>; sample files are copied in by hand.
app_buckets = ["certificates", "documents", "firmware", "images"]

# Created empty; set values with the commands in docs/runbook.md. Every value
# is new for UAT. Store JSON; apps.tfvars maps env vars to "<secret>:<key>".
secrets = {
  "db-hiveconnect" = "DATABASE_URL for the hiveconnect_app database role"
  "db-prism"       = "DATABASE_URL and DIRECT_URL for the prism_app database role"
  "elastic-apm"    = "Elasticsearch and Halo APM credentials"
  "smtp"           = "SMTP credentials"
  "email"          = "Resend and Gmail credentials"
  "whatsapp"       = "WhatsApp API credentials"
  "oauth"          = "OAuth sign-in provider client IDs and secrets"
  "messaging"      = "Other messaging credentials"
}
secret_recovery_days = 7

# TODO: confirm the prefix and the test things (plan open question 1).
iot_topic_prefix = "hive-uat"

alert_emails       = ["CHANGE-ME@example.com"] # TODO: people and/or a chat channel's email address
monthly_budget_usd = 230                       # alerts at 80% ($184), 100% and 120% ($276)

log_retention_days = 30
