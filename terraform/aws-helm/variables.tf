variable "aws_region" {
  type    = string
  default = "us-east-2"
}

variable "aws_elb_webhook_timeout" {
  type        = string
  default     = "120s"
  description = "Duration to wait after installing the AWS Load Balancer Controller before applying dependent resources."
}

variable "eks_cluster_name" {
  type    = string
  default = "sre-ai-interview-eks-cluster"
}

variable "supabase_connection_string" {
  type        = string
  default     = null
  description = "Optional override for the Supabase Postgres connection string."
}

