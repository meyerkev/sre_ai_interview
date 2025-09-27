output "cluster_name" {
  value = try(module.eks.cluster_name, null)
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}

output "oidc_provider_arn" {
  value = try(module.eks.oidc_provider_arn, null)
}

output "aws_default_region" {
  value = var.region
}
