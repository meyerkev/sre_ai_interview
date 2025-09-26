variable "region" {
  description = "The region to deploy to"
  type        = string
  default     = "us-east-2"
}

variable "interview_name" {
  description = "Identifier for this interview; used for ECR repo name and tags (e.g., 'interview-repo', 'acme-takehome')."
  type        = string
  default     = "sre-ai-interview"
}

variable "repository_prefix" {
  description = "Prefix for generated ECR repository names (e.g., 'onyx' -> onyx-backend)."
  type        = string
  default     = "onyx"
}

variable "repository_names" {
  description = "Optional explicit list of ECR repository names; if null, names are derived from repository_prefix."
  type        = list(string)
  default     = null
}

variable "github_repository" {
  description = "GitHub repository (owner/repo) that is allowed to assume the CI role (set to null to skip creation)."
  type        = string
  default     = "meyerkev/onyx"
}

variable "github_oidc_subject" {
  description = "GitHub OIDC subject (everything after 'repo:owner/repo:'), e.g. 'ref:refs/heads/main'."
  type        = string
  default     = "ref:refs/heads/main"
}

# GitHub runner variables

variable "github_runner_enabled" {
  description = "Whether to create the GitHub self-hosted runner"
  type        = bool
  default     = true
}

variable "github_runner_token" {
  description = "GitHub personal access token or registration token for the runner (sensitive)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_runner_instance_type" {
  description = "EC2 instance type for the GitHub runner"
  type        = string
  default     = "c5.4xlarge"
}

variable "github_runner_disk_size" {
  description = "EBS volume size in GB for the GitHub runner"
  type        = number
  default     = 200
}

variable "github_runner_key_name" {
  description = "EC2 key pair name for SSH access to the runner (optional)"
  type        = string
  default     = null
}
