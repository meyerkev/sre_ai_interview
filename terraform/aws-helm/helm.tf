locals {
  namespaces = {
    "aws-load-balancer-controller" = "aws-load-balancer-controller"
    # "external-dns"                 = "external-dns"
    "cluster-autoscaler" = "cluster-autoscaler"
    "metrics-server"     = "kube-system"
    "argocd"             = "argocd"
    "onyx"               = "onyx"
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
  depends_on = [kubernetes_service_account.service_accounts]
}

/*
resource "helm_release" "external-dns" {
  name       = "external-dns"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "external-dns"
  namespace  = local.namespaces["external-dns"]
  version    = "6.20.3"

  wait = true

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = local.service_accounts.external-dns
  }

  depends_on = [kubernetes_service_account.service_accounts]
}
*/

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

# Create a Kubernetes Service for the dual-stack proxy (if enabled)
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = local.namespaces["argocd"]
  version    = "5.46.8"

  wait             = true
  create_namespace = true
  timeout          = 600

  values = [
    yamlencode({
      server = {
        service = {
          type = "LoadBalancer"
        }
        insecure = true
      }
    })
  ]

  depends_on = [kubernetes_namespace.namespaces]
}

resource "helm_release" "onyx" {
  recreate_pods = true
  name          = "onyx"
  chart         = "onyx"
  namespace     = local.namespaces["onyx"]
  repository    = "file://${path.module}/../../helm/onyx/charts"

  # wait             = true
  create_namespace = false
  timeout          = 300
  skip_crds        = false

  set {
    name  = "postgresql.enabled"
    value = "false"
  }

  set {
    name  = "api.replicaCount"
    value = "1"
  }

  set {
    name  = "auth.postgresql.enabled"
    value = "false"
  }

  set {
    name  = "minio.consoleService.ports.http"
    value = "9090"
  }

  set {
    name  = "minio.consoleService.readinessProbe.httpGet.path"
    value = "/"
  }

  set {
    name  = "minio.resourcesPreset"
    value = "none"
  }

  # Database connection pool settings for Supabase
  set {
    name  = "configMap.POSTGRES_API_SERVER_POOL_SIZE"
    value = "5"
  }

  set {
    name  = "configMap.POSTGRES_API_SERVER_POOL_OVERFLOW"
    value = "3"
  }

  # Fix pgbouncer prepared statement issue
  set {
    name  = "configMap.ASYNCPG_STATEMENT_CACHE_SIZE"
    value = "0"
  }

  # Use ECR repositories for faster image pulls
  set {
    name  = "api.image.repository"
    value = "386145735201.dkr.ecr.us-east-2.amazonaws.com/onyx-backend"
  }

  set {
    name  = "api.image.tag"
    value = "main"
  }

  set {
    name  = "api.image.pullPolicy"
    value = "Always"
  }

  set {
    name  = "inferenceCapability.image.repository"
    value = "386145735201.dkr.ecr.us-east-2.amazonaws.com/onyx-model-server"
  }

  set {
    name  = "inferenceCapability.image.tag"
    value = "main"
  }

  set {
    name  = "inferenceCapability.image.pullPolicy"
    value = "Always"
  }

  set {
    name  = "indexCapability.image.repository"
    value = "386145735201.dkr.ecr.us-east-2.amazonaws.com/onyx-model-server"
  }

  set {
    name  = "indexCapability.image.tag"
    value = "main"
  }

  set {
    name  = "indexCapability.image.pullPolicy"
    value = "Always"
  }

  set {
    name  = "webserver.image.repository"
    value = "386145735201.dkr.ecr.us-east-2.amazonaws.com/onyx-web"
  }

  set {
    name  = "webserver.image.tag"
    value = "main"
  }

  set {
    name  = "webserver.image.pullPolicy"
    value = "Always"
  }

  set {
    name  = "webserver.image.pullPolicy"
    value = "Always"
  }

  set {
    name  = "celery_shared.image.repository"
    value = "386145735201.dkr.ecr.us-east-2.amazonaws.com/onyx-backend"
  }

  set {
    name  = "celery_shared.image.tag"
    value = "main"
  }

  set {
    name  = "celery_shared.image.pullPolicy"
    value = "Always"
  }

  set {
    name  = "slackbot.image.repository"
    value = "386145735201.dkr.ecr.us-east-2.amazonaws.com/onyx-backend"
  }

  set {
    name  = "slackbot.image.tag"
    value = "main"
  }

  set {
    name  = "slackbot.image.pullPolicy"
    value = "Always"
  }

  # Use ECR for model server as well
  set {
    name  = "model_server.image.repository"
    value = "386145735201.dkr.ecr.us-east-2.amazonaws.com/onyx-model-server"
  }

  set {
    name  = "model_server.image.tag"
    value = "main"
  }

  set {
    name  = "model_server.image.pullPolicy"
    value = "Always"
  }


  dynamic "set" {
    for_each = [
      {
        name  = "configMap.POSTGRES_USER"
        value = local.supabase_connection_parts.user
      },
      {
        name  = "configMap.POSTGRES_PASSWORD"
        value = local.supabase_connection_parts.password
      },
      {
        name  = "configMap.POSTGRES_HOST"
        value = local.supabase_connection_parts.host
      },
      {
        name  = "configMap.POSTGRES_PORT"
        value = local.supabase_connection_parts.port
      },
      {
        name  = "configMap.POSTGRES_DB"
        value = local.supabase_connection_parts.database
      },
      {
        name  = "api.extraEnv[0].name"
        value = "POSTGRES_USER"
      },
      {
        name  = "api.extraEnv[0].value"
        value = local.supabase_connection_parts.user
      },
      {
        name  = "api.extraEnv[1].name"
        value = "POSTGRES_PASSWORD"
      },
      {
        name  = "api.extraEnv[1].value"
        value = local.supabase_connection_parts.password
      },
      {
        name  = "api.extraEnv[2].name"
        value = "POSTGRES_HOST"
      },
      {
        name  = "api.extraEnv[2].value"
        value = local.supabase_connection_parts.host
      },
      {
        name  = "api.extraEnv[3].name"
        value = "POSTGRES_PORT"
      },
      {
        name  = "api.extraEnv[3].value"
        value = local.supabase_connection_parts.port
      },
      {
        name  = "api.extraEnv[4].name"
        value = "POSTGRES_DB"
      },
      {
        name  = "api.extraEnv[4].value"
        value = local.supabase_connection_parts.database
      },
      {
        name  = "api.extraEnv[5].name"
        value = "POSTGRES_API_SERVER_POOL_SIZE"
      },
      {
        name  = "api.extraEnv[5].value"
        value = "5"
      },
      {
        name  = "api.extraEnv[6].name"
        value = "POSTGRES_API_SERVER_POOL_OVERFLOW"
      },
      {
        name  = "api.extraEnv[6].value"
        value = "3"
      },
      {
        name  = "api.extraEnv[7].name"
        value = "ASYNCPG_STATEMENT_CACHE_SIZE"
      },
      {
        name  = "api.extraEnv[7].value"
        value = "0"
      }
    ]

    content {
      name  = set.value.name
      value = set.value.value
    }
  }

  depends_on = [kubernetes_namespace.namespaces]
}