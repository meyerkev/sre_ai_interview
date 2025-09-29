variable "aws_region" {
  type        = string
  description = "AWS region where the IPv4 EKS cluster runs."
  default     = "us-east-2"
}

variable "aws_elb_webhook_timeout" {
  type        = string
  default     = "120s"
  description = "Duration to wait after installing the AWS Load Balancer Controller before applying dependent resources."
}

variable "eks_cluster_name" {
  type        = string
  description = "Name of the IPv4 EKS cluster to target."
  default     = "sre-ai-interview-eks-ipv4"
}

variable "supabase_connection_string" {
  type        = string
  default     = null
  description = "Optional override for the Supabase Postgres connection string."
}

variable "supabase_upstream_port" {
  type        = number
  default     = 6543
  description = "Port Supavisor listens on for upstream PostgreSQL connections."
}

variable "pgbouncer_replicas" {
  type        = number
  default     = 2
  description = "Number of PgBouncer replicas to run."
}

variable "pgbouncer_max_client_conn" {
  type        = number
  default     = 400
  description = "Maximum number of client connections PgBouncer accepts."
}

variable "pgbouncer_default_pool_size" {
  type        = number
  default     = 20
  description = "Default number of server connections per database/user pair."
}

variable "pgbouncer_reserve_pool_size" {
  type        = number
  default     = 5
  description = "Number of additional server connections allowed in reserve pool."
}

