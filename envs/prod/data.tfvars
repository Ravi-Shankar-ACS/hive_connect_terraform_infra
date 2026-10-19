# Production database: same size as UAT unless the UAT load test says otherwise.
# Multi-AZ (+$67.59 a month) is a separate decision (plan section 9).

engine_version        = "17"
instance_class        = "db.t4g.medium"
allocated_storage     = 50
max_allocated_storage = 200
multi_az              = false

db_name         = "hiveconnect"
master_username = "hive_admin"

backup_retention_days = 14
deletion_protection   = true
apply_immediately     = false
log_retention_days    = 30
