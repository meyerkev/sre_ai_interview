variable "region" {
  type    = string
  default = "us-east-2"
}

variable "cluster_name" {
  type    = string
  default = "sre-ai-interview-eks-ipv4"
}

variable "vpc_name" {
  type    = string
  default = null
}

variable "vpc_cidr" {
  type    = string
  default = "10.1.0.0/16"
}

variable "interviewee_name" {
  type    = string
  default = "sre-ai-interview-ipv4"
}

variable "cluster_k8s_version" {
  type    = string
  default = "1.33"
}

variable "eks_node_instance_type" {
  type    = string
  default = "c6in.8xlarge" # Upgraded from c5.2xlarge for better network performance (40 Gigabit vs 10 Gigabit)
}

variable "target_architecture" {
  type    = string
  default = null
}

variable "min_nodes" {
  type    = number
  default = 1
}

variable "max_nodes" {
  type    = number
  default = 10
}

variable "desired_nodes" {
  type    = number
  default = 4
}

variable "node_disk_size" {
  type        = number
  default     = 500
  description = "Size of the EKS node disk in GB - Increased for large AI/ML container images"
}

variable "ebs_csi_driver_policy_arn" {
  description = "IAM policy ARN to attach for EBS CSI driver permissions"
  type        = string
  default     = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

variable "ebs_csi_role_name" {
  description = "Name of the IAM role for the EBS CSI driver"
  type        = string
  default     = "eks-ebs-csi-driver"
}



