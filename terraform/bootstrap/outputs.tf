output "ecr_repository_urls" {
  description = "Map of ECR repository URLs keyed by repository name"
  value       = { for name, repo in aws_ecr_repository.repo : name => repo.repository_url }
}

output "github_ci_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC (if created)"
  value       = try(aws_iam_role.github_ci[0].arn, null)
}

output "github_runner_asg_name" {
  description = "Auto Scaling Group name for the GitHub runner (if created)"
  value       = try(aws_autoscaling_group.github_runner[0].name, null)
}

output "github_runner_security_group_id" {
  description = "Security group ID for the GitHub runner (if created)"
  value       = try(aws_security_group.github_runner[0].id, null)
}
