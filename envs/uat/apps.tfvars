# UAT services. To deploy: push an image (scripts/push-image.sh), set its tag
# below, then plan and apply uat/apps.
#
# Capacity: 1 on-demand task each; autoscaling may add 1 Spot task each (max 2).
# Fargate base cost: $33.14 (hiveconnect-api) + $16.57 (prism) = $49.71 a month.
#
# Environment variables marked TODO depend on plan open question 4. Remove the
# old Kubernetes settings (IS_KUBERENETES, LIGHTHOUSE_CLUSTER_ID, CLUSTER_NAME),
# Redis settings and AWS access keys from the applications: the AWS SDK uses
# the task role automatically.

services = {
  "hiveconnect-api" = {
    image_tag         = "CHANGE-ME" # TODO: commit tag from scripts/push-image.sh
    cpu               = 1024
    memory            = 2048
    port              = 8000
    max_tasks         = 2
    listener_priority = 100

    s3_buckets = ["certificates", "documents", "firmware", "images"]
    iot        = true

    environment = {
      PRISM_API_URL = "https://prism-uat.iotiqinnovations.com"
      AWS_REGION    = "ap-south-1"
      # TODO: bucket names (terraform output app_bucket_names in uat/platform),
      # IoT endpoint and policy name (iot_endpoint, iot_device_policy_name),
      # and the rest of the plain settings.
    }

    secrets = {
      DATABASE_URL = "db-hiveconnect:DATABASE_URL"
      # TODO: for example
      # SMTP_PASSWORD = "smtp:password"
      # ELASTIC_APM_SECRET_TOKEN = "elastic-apm:secret_token"
    }
  }

  "prism" = {
    image_tag         = "CHANGE-ME" # TODO
    cpu               = 512
    memory            = 1024
    port              = 8080
    max_tasks         = 2
    listener_priority = 200

    s3_buckets = ["images"]

    environment = {
      HIVECONNECT_API_URL = "https://hiveconnect-uat.iotiqinnovations.com"
      AWS_REGION          = "ap-south-1"
    }

    # No pooler exists, so DIRECT_URL is the same URL as DATABASE_URL.
    secrets = {
      DATABASE_URL = "db-prism:DATABASE_URL"
      DIRECT_URL   = "db-prism:DIRECT_URL"
    }
  }
}

log_retention_days = 30
