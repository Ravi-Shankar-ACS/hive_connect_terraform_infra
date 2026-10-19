# Production platform. Same design as UAT; built only after UAT sign-off.

domain_name = "iotiqinnovations.com"

# TODO: production hostnames. If they are the hostnames the old stack serves
# today, set dns_weight (below) for the cutover instead of simple records.
services = {
  "hiveconnect-api" = { hostname = "hiveconnect.iotiqinnovations.com" }
  "prism"           = { hostname = "prism.iotiqinnovations.com" }
}

# Cutover (docs/runbook.md): convert the old records to weighted ones, start
# this at 0, then raise it. Leave null for brand-new hostnames.
dns_weight = null

waf_block_mode = true
waf_rate_limit = 2000

alb_idle_timeout        = 60
alb_deletion_protection = true

app_buckets = ["certificates", "documents", "firmware", "images"]

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
secret_recovery_days = 30

iot_topic_prefix = "hive-prod" # TODO: production topic layout

alert_emails       = ["CHANGE-ME@example.com"] # TODO
monthly_budget_usd = 280                       # ceiling is $277.42 with every Spot task running all month

log_retention_days = 30
