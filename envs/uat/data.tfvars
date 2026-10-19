# UAT database: PostgreSQL 17, db.t4g.medium, Single-AZ, 50 GB gp3 ($68.32 a month).

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
