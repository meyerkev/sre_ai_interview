locals {
  namespaces = {
    "aws-load-balancer-controller" = "aws-load-balancer-controller"
    # "external-dns"                 = "external-dns"
    "cluster-autoscaler" = "cluster-autoscaler"
    "metrics-server"     = "kube-system"
    "argocd"             = "argocd"
    "onyx"               = "terraform-onyx"
    "argocd-onyx"        = "argocd-onyx"
  }

  service_accounts = {
    "aws-load-balancer-controller" = "aws-load-balancer-controller"
    # "external-dns"                 = "external-dns"
    "cluster-autoscaler" = "cluster-autoscaler"
  }


  irsa_roles = {
    "aws-load-balancer-controller" = module.aws-load-balancer-irsa.arn
    # "external-dns"                 = module.external-dns-irsa.arn
    "cluster-autoscaler" = module.aws-cluster-autoscaler-irsa.arn
  }

}

data "aws_ssm_parameter" "oidc_provider" {
  name = "/eks/${var.eks_cluster_name}/oidc_provider"
}

data "aws_secretsmanager_secret" "supabase_postgres" {
  name = "onyx-supabase-postgres"
}

data "aws_secretsmanager_secret_version" "supabase_postgres" {
  secret_id = data.aws_secretsmanager_secret.supabase_postgres.id
}

locals {
  supabase_connection_string = var.supabase_connection_string != null ? var.supabase_connection_string : data.aws_secretsmanager_secret_version.supabase_postgres.secret_string

  # Parse original Supabase connection
  supabase_connection_parts = {
    user     = nonsensitive(regex("postgresql://(?P<user>[^:]+):(?P<password>[^@]+)@(?P<host>[^:]+):(?P<port>[0-9]+)/(?P<database>.+)", local.supabase_connection_string).user)
    password = regex("postgresql://(?P<user>[^:]+):(?P<password>[^@]+)@(?P<host>[^:]+):(?P<port>[0-9]+)/(?P<database>.+)", local.supabase_connection_string).password
    host     = nonsensitive(regex("postgresql://(?P<user>[^:]+):(?P<password>[^@]+)@(?P<host>[^:]+):(?P<port>[0-9]+)/(?P<database>.+)", local.supabase_connection_string).host)
    port     = nonsensitive(regex("postgresql://(?P<user>[^:]+):(?P<password>[^@]+)@(?P<host>[^:]+):(?P<port>[0-9]+)/(?P<database>.+)", local.supabase_connection_string).port)
    database = nonsensitive(regex("postgresql://(?P<user>[^:]+):(?P<password>[^@]+)@(?P<host>[^:]+):(?P<port>[0-9]+)/(?P<database>.+)", local.supabase_connection_string).database)
  }

  onyx_helm_values = yamlencode({
    nginx = {
      service = {
        type = "LoadBalancer"
        annotations = {
          "service.beta.kubernetes.io/aws-load-balancer-type"                              = "nlb-ip"
          "service.beta.kubernetes.io/aws-load-balancer-scheme"                            = "internet-facing"
          "service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags"          = "Name=onyx-nlb"
          "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"                   = "ip"
          "service.beta.kubernetes.io/aws-load-balancer-backend-protocol"                  = "HTTP"
          "service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol"              = "HTTP"
          "service.beta.kubernetes.io/aws-load-balancer-healthcheck-path"                  = "/"
          "service.beta.kubernetes.io/aws-load-balancer-healthcheck-port"                  = "traffic-port"
          "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled" = "true"
        }
      }
      extraEnvVars = [
        {
          name  = "DOMAIN"
          value = "localhost"
        },
        {
          name  = "LISTEN_ADDRESS"
          value = "::"
        }
      ]
      ingress = {
        enabled = false
      }
    }
    minio = {
      resourcesPreset = "none"
      console = {
        enabled = false
      }
    }
    postgresql = {
      enabled = false
    }

    externalDatabase = {
      host                      = local.supabase_connection_parts.host
      port                      = tonumber(local.supabase_connection_parts.port)
      user                      = local.supabase_connection_parts.user
      password                  = local.supabase_connection_parts.password
      database                  = local.supabase_connection_parts.database
      existingSecret            = "onyx-supabase-secret"
      existingSecretPasswordKey = "postgres_password"
    }

    configMap = {
      POSTGRES_API_SERVER_POOL_SIZE     = "15"
      POSTGRES_API_SERVER_POOL_OVERFLOW = "10"
      POSTGRES_CONNECT_TIMEOUT          = "60"
      POSTGRES_POOL_TIMEOUT             = "60"
      ASYNCPG_STATEMENT_CACHE_SIZE      = "0"
      POSTGRES_HOST                     = local.supabase_connection_parts.host
      POSTGRES_PORT                     = local.supabase_connection_parts.port
      POSTGRES_DB                       = local.supabase_connection_parts.database
    }

    api = {
      replicaCount = 1
      image = {
        repository = "386145735201.dkr.ecr.us-east-2.amazonaws.com/onyx-backend"
        tag        = "main"
        pullPolicy = "Always"
      }
      extraEnv = [
        {
          name  = "POSTGRES_USER"
          value = local.supabase_connection_parts.user
        },
        {
          name = "POSTGRES_PASSWORD"
          valueFrom = {
            secretKeyRef = {
              name = "onyx-supabase-secret"
              key  = "postgres_password"
            }
          }
        }
      ]
    }

    inferenceCapability = {
      image = {
        repository = "386145735201.dkr.ecr.us-east-2.amazonaws.com/onyx-model-server"
        tag        = "main"
        pullPolicy = "Always"
      }
      containerPorts = {
        server = 9000
      }
    }

    indexCapability = {
      image = {
        repository = "386145735201.dkr.ecr.us-east-2.amazonaws.com/onyx-model-server"
        tag        = "main"
        pullPolicy = "Always"
      }
    }

    webserver = {
      image = {
        repository = "386145735201.dkr.ecr.us-east-2.amazonaws.com/onyx-web"
        tag        = "main"
        pullPolicy = "Always"
      }
    }

    celery_shared = {
      image = {
        repository = "386145735201.dkr.ecr.us-east-2.amazonaws.com/onyx-backend"
        tag        = "main"
        pullPolicy = "Always"
      }
    }

    slackbot = {
      image = {
        repository = "386145735201.dkr.ecr.us-east-2.amazonaws.com/onyx-backend"
        tag        = "main"
        pullPolicy = "Always"
      }
    }

    model_server = {
      image = {
        repository = "386145735201.dkr.ecr.us-east-2.amazonaws.com/onyx-model-server"
        tag        = "main"
        pullPolicy = "Always"
      }
    }
  })
}

resource "kubernetes_namespace" "namespaces" {
  for_each = { for namespace, value in local.namespaces : namespace => value if value != "kube-system" }
  metadata {
    name = each.value
  }
}

resource "kubernetes_service_account" "service_accounts" {
  for_each = local.irsa_roles
  metadata {
    name      = local.service_accounts[each.key]
    namespace = local.namespaces[each.key]
    annotations = {
      "eks.amazonaws.com/role-arn" = each.value
    }
  }
  depends_on = [kubernetes_namespace.namespaces]
}

resource "aws_iam_policy" "aws-load-balancer-controller" {
  name   = "aws-load-balancer-controller-${var.eks_cluster_name}-policy"
  path   = "/"
  policy = file("${path.module}/assets/aws-lb-controller-iam-policy.json")
}


module "aws-load-balancer-irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.2"

  name            = "aws-load-balancer-controller"
  use_name_prefix = false

  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = data.aws_ssm_parameter.oidc_provider.value
      namespace_service_accounts = ["${local.namespaces.aws-load-balancer-controller}:${local.service_accounts.aws-load-balancer-controller}"]
    }
  }
}

resource "helm_release" "aws-load-balancer-controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = local.namespaces["aws-load-balancer-controller"]
  version    = "1.5.3"

  wait = true

  set {
    name  = "clusterName"
    value = var.eks_cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = local.service_accounts.aws-load-balancer-controller
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = data.aws_eks_cluster.cluster.vpc_config[0].vpc_id
  }

  set {
    name  = "replicaCount"
    value = 1
  }
  depends_on = [kubernetes_service_account.service_accounts]
}

/*
module "external-dns-irsa" {
  source          = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  name            = "external-dns"
  use_name_prefix = false

  attach_external_dns_policy    = var.route53_zone_id != null
  external_dns_hosted_zone_arns = var.route53_zone_id != null ? ["arn:aws:route53:::hostedzone/${var.route53_zone_id}"] : []

  oidc_providers = {
    main = {
      provider_arn               = data.aws_ssm_parameter.oidc_provider.value
      namespace_service_accounts = ["${local.namespaces.external-dns}:${local.service_accounts.external-dns}"]
    }
  }
}
*/

module "aws-cluster-autoscaler-irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.2"

  name            = "aws-cluster-autoscaler"
  use_name_prefix = false

  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [var.eks_cluster_name]

  oidc_providers = {
    main = {
      provider_arn               = data.aws_ssm_parameter.oidc_provider.value
      namespace_service_accounts = ["${local.namespaces.cluster-autoscaler}:${local.service_accounts.cluster-autoscaler}"]
    }
  }
}

data "aws_vpc" "eks_vpc" {
  id = data.aws_eks_cluster.cluster.vpc_config[0].vpc_id
}

# Security group for public ALB access
resource "aws_security_group" "alb_public" {
  name_prefix = "onyx-alb-public"
  description = "Security group for public ALB access to Onyx"
  vpc_id      = data.aws_vpc.eks_vpc.id

  ingress {
    description      = "HTTP from anywhere"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "HTTPS from anywhere"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    description      = "All outbound traffic"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "onyx-alb-public"
  }
}

# Security group rule to allow ALB to reach EKS nodes
resource "aws_security_group_rule" "alb_to_nodes" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_public.id
  security_group_id        = data.aws_eks_cluster.cluster.vpc_config[0].cluster_security_group_id
}

# Allow ALB to reach pods on nginx port via cluster security group
resource "aws_security_group_rule" "alb_to_cluster_http" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_public.id
  security_group_id        = data.aws_eks_cluster.cluster.vpc_config[0].cluster_security_group_id
}

resource "aws_security_group_rule" "alb_to_cluster_https" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_public.id
  security_group_id        = data.aws_eks_cluster.cluster.vpc_config[0].cluster_security_group_id
}

# Allow ALB to reach nginx container port
resource "aws_security_group_rule" "alb_to_cluster_nginx" {
  type                     = "ingress"
  from_port                = 1024
  to_port                  = 1024
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_public.id
  security_group_id        = data.aws_eks_cluster.cluster.vpc_config[0].cluster_security_group_id
}

resource "helm_release" "cluster-autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = local.namespaces["cluster-autoscaler"]
  version    = "9.37.0"

  wait = true

  set {
    name  = "autoDiscovery.clusterName"
    value = var.eks_cluster_name
  }

  set {
    name  = "awsRegion"
    value = var.aws_region
  }

  set {
    name  = "rbac.serviceAccount.create"
    value = "false"
  }

  set {
    name  = "rbac.serviceAccount.name"
    value = local.service_accounts.cluster-autoscaler
  }
  depends_on = [kubernetes_service_account.service_accounts]
}

resource "helm_release" "metrics-server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server"
  chart      = "metrics-server"
  namespace  = local.namespaces["metrics-server"]
  version    = "3.12.2"

  wait = true
  # If you don't have a namespace named kube-system yet, what are we even doing here kids?
  create_namespace = false

}

resource "null_resource" "onyx_dependencies" {
  provisioner "local-exec" {
    command     = <<-EOT
      set -euo pipefail
      helm dependency update ../../helm/onyx/charts/onyx
    EOT
    working_dir = path.module
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "helm_release" "onyx" {
  name          = "onyx"
  recreate_pods = true
  chart         = "${path.module}/../../helm/onyx/charts/onyx"
  namespace     = local.namespaces["onyx"]

  wait             = true
  create_namespace = false
  timeout          = 300
  skip_crds        = false

  values = [local.onyx_helm_values]

  lifecycle {
    precondition {
      condition     = length(fileset("${path.module}/../../helm/onyx/charts/onyx/charts", "*.tgz")) == 5
      error_message = "There are not 5 files in the charts directory"
    }
  }

  depends_on = [kubernetes_namespace.namespaces, null_resource.onyx_dependencies, kubernetes_secret.supabase_postgres, helm_release.aws-load-balancer-controller]
}

# Create Kubernetes secret for Supabase database credentials
resource "kubernetes_secret" "supabase_postgres" {
  metadata {
    name      = "onyx-supabase-secret"
    namespace = local.namespaces["onyx"]
  }

  data = {
    postgres_password = local.supabase_connection_parts.password
  }

  type = "Opaque"

  depends_on = [kubernetes_namespace.namespaces]
}

# argo
resource "helm_release" "argo-cd" {
  name       = "argo-cd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = local.namespaces["argocd"]
  version    = "8.5.6"

  wait             = true
  create_namespace = false
  timeout          = 600

  values = [
    yamlencode({
      server = {
        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-type"                              = "nlb-ip"
            "service.beta.kubernetes.io/aws-load-balancer-scheme"                            = "internet-facing"
            "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled" = "true"
            "service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags"          = "Name=argocd-nlb"
          }
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.namespaces, helm_release.aws-load-balancer-controller]
}

# Apply the argo application
resource "kubernetes_manifest" "argo_onyx_application" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "onyx"
      namespace = local.namespaces["argocd"]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/meyerkev/onyx.git"
        targetRevision = "working_i_hope"
        path           = "deployment/helm/charts/onyx"
        helm = {
          values = local.onyx_helm_values
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = local.namespaces["argocd-onyx"]
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  }

  field_manager {
    name            = "terraform"
    force_conflicts = true
  }

  depends_on = [helm_release.argo-cd]
}