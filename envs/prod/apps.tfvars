# Production services: 1 on-demand task each, Spot above it.
#   hiveconnect-api up to 5 tasks (1 on-demand + 4 Spot)
#   prism           up to 3 tasks (1 on-demand + 2 Spot)
# Fargate costs $49.71 a month at rest and at most about $100.52 with every
# Spot task running all month. Set the caps from the UAT load test (plan step 6).
# If an SLA needs it, raise on_demand_base and min_tasks to 2 (+$49.71 for both).

services = {
  "hiveconnect-api" = {
    image_tag         = "CHANGE-ME" # TODO: the tag signed off in UAT
    cpu               = 1024
    memory            = 2048
    port              = 8000
    max_tasks         = 5
    listener_priority = 100

    s3_buckets = ["certificates", "documents", "firmware", "images"]
    iot        = true

    environment = {
      PRISM_API_URL = "https://prism.iotiqinnovations.com"
      AWS_REGION    = "ap-south-1"
    }

    secrets = {
      DATABASE_URL = "db-hiveconnect:DATABASE_URL"
    }
  }

  "prism" = {
    image_tag         = "CHANGE-ME" # TODO
    cpu               = 512
    memory            = 1024
    port              = 8080
    max_tasks         = 3
    listener_priority = 200

    s3_buckets = ["images"]

    environment = {
      HIVECONNECT_API_URL = "https://hiveconnect.iotiqinnovations.com"
      AWS_REGION          = "ap-south-1"
    }

    secrets = {
      DATABASE_URL = "db-prism:DATABASE_URL"
      DIRECT_URL   = "db-prism:DIRECT_URL"
    }
  }
}

log_retention_days = 30
