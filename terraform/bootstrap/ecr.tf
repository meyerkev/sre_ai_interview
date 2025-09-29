locals {
  default_suffixes = [
    "backend",
    "web",
    "cloud-web",
    "model-server"
  ]
  repository_names = var.repository_names != null ? var.repository_names : [for suffix in local.default_suffixes : "${var.repository_prefix}-${suffix}"]
}

resource "aws_ecr_repository" "repo" {
  for_each             = toset(local.repository_names)
  name                 = each.value
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Environment = "production"
    Project     = var.interview_name
  }
}

resource "aws_ecr_lifecycle_policy" "repo" {
  for_each   = aws_ecr_repository.repo
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 30 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 30
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.github_repository != null ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

resource "aws_iam_role" "github_ci" {
  count = var.github_repository != null ? 1 : 0

  name = "sre-ai-interview-github-ci"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github[0].arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              "repo:${var.github_repository}:ref:refs/heads/*",
              "repo:${var.github_repository}:ref:refs/tags/*",
              "repo:${var.github_repository}:pull_request"
            ]
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "github_ci_ecr" {
  count = var.github_repository != null ? 1 : 0

  name = "${var.interview_name}-github-ecr"
  role = aws_iam_role.github_ci[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]
        Resource = [for repo in values(aws_ecr_repository.repo) : repo.arn]
      }
    ]
  })
}
