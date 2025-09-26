#!/usr/bin/env bash
set -eo pipefail

# This script destroys only the terraform/aws infrastructure

# Parse command line arguments
INTERVIEW_NAME="fake"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --interview-name)
      INTERVIEW_NAME="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 --interview-name <name>";
      echo "Example: $0 --interview-name acme-takehome"; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

TERRAFORM_INIT_ARGS=''
if [ ! -z "$TF_STATE_BUCKET" ]; then
    TERRAFORM_INIT_ARGS="--backend-config=bucket=$TF_STATE_BUCKET"
fi
if [ ! -z "$TF_STATE_KEY" ]; then
    TERRAFORM_INIT_ARGS="$TERRAFORM_INIT_ARGS --backend-config=key=$TF_STATE_KEY"
fi
if [ ! -z "$TF_STATE_REGION" ]; then
    TERRAFORM_INIT_ARGS="$TERRAFORM_INIT_ARGS --backend-config=region=$TF_STATE_REGION"
fi

set -u

# Destroy the EKS cluster
echo "🗑️ Destroying EKS cluster..."
cd terraform/aws
terraform init $TERRAFORM_INIT_ARGS

echo "🧹 Cleaning up Kubernetes-managed resources from state..."
terraform state rm kubernetes_annotations.default >/dev/null 2>&1 || true
terraform state rm module.eks-auth.kubernetes_config_map_v1_data.aws_auth >/dev/null 2>&1 || true

terraform destroy -var "interviewee_name=${INTERVIEW_NAME}" -auto-approve

echo "✨ EKS cluster destroyed successfully!"
