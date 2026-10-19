variable "services" {
  description = "The ECS services. Keys must match the services in envs/<env>/platform.tfvars."
  type = map(object({
    image_tag           = string # commit tag pushed with scripts/push-image.sh
    cpu                 = number # 1024 = 1 vCPU
    memory              = number # MiB
    port                = number # container port (must be in network app_ports)
    max_tasks           = number # cap; tasks above on_demand_base run on Spot
    listener_priority   = number # unique per service
    min_tasks           = optional(number, 1)
    on_demand_base      = optional(number, 1)
    health_check_path   = optional(string, "/healthz")
    cpu_target          = optional(number, 60)
    requests_per_target = optional(number, 1000)
    command             = optional(list(string))
    environment         = optional(map(string), {})
    secrets             = optional(map(string), {})  # ENV_VAR = "<secret>" or "<secret>:<json key>"
    s3_buckets          = optional(list(string), []) # short names from platform app_buckets
    iot                 = optional(bool, false)      # may use this environment's IoT topics
  }))

  validation {
    condition     = alltrue([for s in values(var.services) : s.max_tasks >= s.min_tasks && s.min_tasks >= s.on_demand_base])
    error_message = "Each service needs max_tasks >= min_tasks >= on_demand_base."
  }
}

variable "log_retention_days" {
  description = "Application log retention."
  type        = number
  default     = 30
}

variable "db_admin_image" {
  description = "Image of the db-admin task (psql). Pulled from the public ECR mirror of Docker Official Images."
  type        = string
  default     = "public.ecr.aws/docker/library/postgres:17-alpine"
}
