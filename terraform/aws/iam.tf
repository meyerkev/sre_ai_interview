resource "aws_iam_user" "interviewee" {
  count = var.interviewee_name != null ? 1 : 0
  name  = var.interviewee_name
  path  = "/"
}

# Write a policy that lets us get the kubeconfig for the cluster and attach it to our user
resource "aws_iam_user_policy" "kubeconfig" {
  count = var.interviewee_name != null ? 1 : 0
  name  = "kubeconfig"
  user  = aws_iam_user.interviewee[0].name

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowKubeconfig",
            "Effect": "Allow",
            "Action": [
                "eks:DescribeCluster",
                "eks:updateKubeconfig",
                "eks:ListFargateProfiles",
                "eks:DescribeNodegroup",
                "eks:ListNodegroups",
                "eks:ListUpdates",
                "eks:AccessKubernetesApi",
                "eks:ListAddons",
                "eks:DescribeCluster",
                "eks:DescribeAddonVersions",
                "eks:ListClusters",
                "eks:ListIdentityProviderConfigs",
                "iam:ListRoles"

            ],
            "Resource": "${module.eks.cluster_arn}"
        },
        {
            "Effect": "Allow",
            "Action": "ssm:GetParameter",
            "Resource": "arn:aws:ssm:*:${data.aws_caller_identity.current.account_id}:parameter/*"
        }
    ]
}
EOF
}

resource "aws_iam_role" "ebs_csi" {
  name = var.ebs_csi_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRoleWithWebIdentity"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = var.ebs_csi_driver_policy_arn
}

# Add an IAM keypair for the interviewee (used in interview flow)
resource "aws_iam_access_key" "interviewee_key" {
  count = var.interviewee_name != null ? 1 : 0
  user  = aws_iam_user.interviewee[0].name
}
