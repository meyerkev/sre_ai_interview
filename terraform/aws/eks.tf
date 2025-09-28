locals {
  availability_zones = ["${var.region}a", "${var.region}b", "${var.region}c"]
  # This is sort of weird and I could see myself rewriting it in the future
  # But I have many x86 laptops AND an ARM laptop.  
  # And it's a lot easier to have architecure agreement between the place 
  # I make my docker files and the place I run them.  
  # 
  # If you set an instance type, it will use that and then look up the architecture
  # BUT if you set a target architecture, it will use that and then look up the ideal instance type of that architecture and then re-lookup the architecture
  # And if you don't set anything at all, it will look at your laptop, run `uname -a`, and then keep going
  #
  # Laptop -> laptop architecture lookup -> default instance type lookup -> Architecture lookup
  #
  # And if you don't set either, it will look up the architecture of the machine you're running on so that local Docker builds work by default
  # But what this means is that you can totally say "ARM.  I am ARM", pick an x64 instance type, and get an x64 cluster
  # By accident
  target_architecture    = var.target_architecture == null ? data.external.architecture[0].result.architecture : var.target_architecture
  eks_node_instance_type = var.eks_node_instance_type != null ? var.eks_node_instance_type : local.target_architecture == "arm64" ? "m7g.large" : "m7a.large"

  add_user = strcontains(data.aws_caller_identity.current.arn, ":user/")
}

# This is a wee bit of a hack and requires being on something Linuxy
# But that's why I let you override it.  
data "external" "architecture" {
  count   = var.target_architecture == null ? 1 : 0
  program = ["./scripts/architecture_check.sh"]
}

data "aws_ec2_instance_type" "eks_node_instance_type" {
  instance_type = local.eks_node_instance_type
}

data "aws_caller_identity" "current" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = var.vpc_name == null ? "${var.cluster_name}-eks-vpc" : var.vpc_name
  cidr = var.vpc_cidr

  azs = local.availability_zones

  enable_dns_hostnames = true
  enable_ipv6          = true # Enable IPv6 across the VPC for EKS

  # TODO: Some regions have more than 4 AZ's
  public_subnets   = [for i, az in local.availability_zones : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnets  = [for i, az in local.availability_zones : cidrsubnet(var.vpc_cidr, 8, i + 4)]
  database_subnets = [for i, az in local.availability_zones : cidrsubnet(var.vpc_cidr, 8, i + 8)]

  # Make subnets dual-stack and ensure resources launched into them receive IPv6 addresses
  public_subnet_assign_ipv6_address_on_creation   = true
  private_subnet_assign_ipv6_address_on_creation  = true
  database_subnet_assign_ipv6_address_on_creation = true

  # Assign IPv6 CIDR blocks to subnets to enable DNS64
  public_subnet_ipv6_prefixes   = [for i in range(length(local.availability_zones)) : i]
  private_subnet_ipv6_prefixes  = [for i in range(length(local.availability_zones)) : i + 4]
  database_subnet_ipv6_prefixes = [for i in range(length(local.availability_zones)) : i + 8]

  # Enable NAT Gateway
  # Expensive, but a requirement 
  enable_nat_gateway      = true
  single_nat_gateway      = true
  one_nat_gateway_per_az  = false
  enable_vpn_gateway      = false
  map_public_ip_on_launch = true
  create_egress_only_igw  = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" : 1
    "kubernetes.io/cluster/${var.cluster_name}" : "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" : 1
    "kubernetes.io/cluster/${var.cluster_name}" : "shared"
  }
}

module "eks-auth" {
  source  = "terraform-aws-modules/eks/aws//modules/aws-auth"
  version = "~> 20.0"

  manage_aws_auth_configmap = true
  aws_auth_users = concat(
    var.interviewee_name != null ? [
      # Once again, this might not be ideal except in an interview setting
      {
        userarn  = aws_iam_user.interviewee[0].arn
        username = aws_iam_user.interviewee[0].name
        groups   = ["system:masters"]
      }
    ] : [],
    local.add_user ? [
      {
        userarn  = data.aws_caller_identity.current.arn
        username = data.aws_caller_identity.current.user_id
        groups   = ["system:masters"]
      }
    ] : [],
    [
      {
        userarn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        username = "root"
        groups   = ["system:masters"]
      }
    ]
  )

  aws_auth_roles = [
    for node_group in values(module.eks.eks_managed_node_groups) : {
      rolearn  = node_group.iam_role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups   = ["system:bootstrappers", "system:nodes"]
    }
  ]

  depends_on = [null_resource.sleep]
}

# Sleep 30 seconds to allow the EKS cluster to be created
resource "null_resource" "sleep" {
  provisioner "local-exec" {
    command = "sleep 30"
  }
  depends_on = [module.eks]
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  # Module v21 renamed inputs to align with upstream JSON; use `name`
  name               = var.cluster_name
  kubernetes_version = var.cluster_k8s_version
  ip_family          = "ipv6"

  endpoint_public_access                   = true
  enable_cluster_creator_admin_permissions = true

  create_auto_mode_iam_resources = false
  compute_config                 = {}
  create_cni_ipv6_iam_policy     = true

  addons = {
    coredns = {
      most_recent = true
    }
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent    = true
      before_compute = true
      configuration_values = jsonencode({
        env = {
          ENABLE_IPV6              = "true"
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
          WARM_ENI_TARGET          = "1"
        }
      })
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = aws_iam_role.ebs_csi.arn
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  security_group_additional_rules = {
    eks_cluster = {
      type        = "ingress"
      description = "Never do this in production"
      from_port   = 0
      to_port     = 65535
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  eks_managed_node_groups = {
    default_node_group = {
      ami_type                   = contains(data.aws_ec2_instance_type.eks_node_instance_type.supported_architectures, "arm64") ? "AL2023_ARM_64_STANDARD" : "AL2023_x86_64_STANDARD"
      instance_types             = [local.eks_node_instance_type]
      iam_role_attach_cni_policy = true
      # Use AWS defaults with existing optimizations
      create_launch_template     = false
      use_custom_launch_template = false

      attach_csi_policy = true

      min_size     = var.min_nodes
      max_size     = var.max_nodes
      desired_size = var.desired_nodes

      disk_size = var.node_disk_size

      remote_access = {
        ec2_ssh_key               = module.key_pair.key_pair_name
        source_security_group_ids = [aws_security_group.remote_access.id]
      }

      tags = {
        "k8s.io/cluster-autoscaler/enabled"             = "true"
        "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
      }

      iam_role_additional_policies = {
        AmazonEBSCSIDriverPolicy = var.ebs_csi_driver_policy_arn
      }

    }
  }
}

module "key_pair" {
  source  = "terraform-aws-modules/key-pair/aws"
  version = "~> 2.1"

  key_name_prefix    = "meyerkev-local"
  create_private_key = true
}

resource "aws_security_group" "remote_access" {
  name_prefix = "eks-remote-access"
  description = "Allow remote SSH access"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "All access"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    # TODO: This is also bad and I would never do this in production
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    # TODO: This is also bad and I would never do this in production
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = { Name = "eks-remote" }
}

# VPC Endpoints for ECR - Dramatically improves image pull performance
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.cluster_name}-ecr-dkr-endpoint"
  }
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.cluster_name}-ecr-api-endpoint"
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids

  tags = {
    Name = "${var.cluster_name}-s3-endpoint"
  }
}

# Security group for VPC endpoints
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.cluster_name}-vpc-endpoints"
  description = "Security group for VPC endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-vpc-endpoints"
  }
}

resource "aws_ssm_parameter" "oidc_provider" {
  name  = "/eks/${var.cluster_name}/oidc_provider"
  type  = "String"
  value = module.eks.oidc_provider_arn
}