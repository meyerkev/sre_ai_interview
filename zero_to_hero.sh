#!/bin/bash
set -eo pipefail

cd $(dirname $0)



echo "🚀 Starting zero to hero deployment..."

# Optional: choose interview/ECR repo name and bootstrap backend key
INTERVIEW_NAME="sre-ai-interview"
GITHUB_REPOSITORY="meyerkev/onyx"

BOOTSTRAP_STATE_KEY="${INTERVIEW_NAME}-bootstrap-ecr.tfstate"
TERRAFORM_INIT_UPGRADE='-upgrade'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bootstrap-state-key)
      BOOTSTRAP_STATE_KEY="$2"; shift 2 ;;
    --upgrade)
      TERRAFORM_INIT_UPGRADE='-upgrade'; shift ;;
    --no-upgrade)
      TERRAFORM_INIT_UPGRADE=''; shift ;;
    --supabase-connection-string)
      SUPABASE_CONNECTION_STRING="$2"; shift 2 ;;
    --github-repository)
      GITHUB_REPOSITORY="$2"; shift 2 ;;
    --)
      shift; INTERVIEW_NAME="$1"; shift ;;
    -h|--help)
      echo "Usage: $0 [--upgrade] [--supabase-connection-string <postgres url>] [--github-repository owner/repo] [--bootstrap-state-key <s3/key>] [-- <interview-name>]";
      echo "Environment variables:";
      echo "  GITHUB_PAT - GitHub Personal Access Token for runner registration";
      exit 0 ;;
    *)
      if [[ "$1" == -* ]]; then
        echo "Unknown argument: $1" >&2; exit 1
      fi
      INTERVIEW_NAME="$1"; shift ;;
  esac
done

if [ -n "${SUPABASE_CONNECTION_STRING:-}" ]; then
  echo "🔐 Ensuring Supabase secret is populated..."
  aws secretsmanager put-secret-value \
    --secret-id onyx-supabase-postgres \
    --secret-string "${SUPABASE_CONNECTION_STRING}" >/dev/null 2>&1 || \
  aws secretsmanager create-secret \
    --name onyx-supabase-postgres \
    --secret-string "${SUPABASE_CONNECTION_STRING}" >/dev/null
fi

TERRAFORM_INIT_ARGS="$TERRAFORM_INIT_UPGRADE"
if [ ! -z "$TF_STATE_BUCKET" ]; then
    TERRAFORM_INIT_ARGS="${TERRAFORM_INIT_ARGS} --backend-config=bucket=$TF_STATE_BUCKET"
fi
if [ ! -z "$TF_STATE_KEY" ]; then
    TERRAFORM_INIT_ARGS="$TERRAFORM_INIT_ARGS --backend-config=key=$TF_STATE_KEY"
fi
if [ ! -z "$TF_STATE_REGION" ]; then
    TERRAFORM_INIT_ARGS="$TERRAFORM_INIT_ARGS --backend-config=region=$TF_STATE_REGION"
fi

TFVARS=""
if [ ! -z "$SSH_CIDR_BLOCK" ]; then
    # Create a temporary file for the list
    TEMP_FILE=$(mktemp)
    echo "ssh_cidr_blocks = [\"$SSH_CIDR_BLOCK\"]" > "$TEMP_FILE"
    TFVARS="$TFVARS -var-file=$TEMP_FILE"
    # Clean up temp file after terraform runs
    trap 'rm -f "$TEMP_FILE"' EXIT
fi

set -u

# Initialize and apply Terraform
echo "📦 Creating infrastructure with Terraform..."
cd terraform/bootstrap
# Allow overriding only the bootstrap backend key via CLI
BOOTSTRAP_INIT_ARGS="$TERRAFORM_INIT_ARGS"
if [ -n "$BOOTSTRAP_STATE_KEY" ]; then
  BOOTSTRAP_INIT_ARGS="$BOOTSTRAP_INIT_ARGS --backend-config=key=$BOOTSTRAP_STATE_KEY"
fi
# terraform init $BOOTSTRAP_INIT_ARGS
# Build terraform var args for bootstrap
BOOTSTRAP_VAR_ARGS="-var interview_name=${INTERVIEW_NAME} -var github_repository=${GITHUB_REPOSITORY:-}"

# Enable GitHub runner by default and add token if provided
BOOTSTRAP_VAR_ARGS="$BOOTSTRAP_VAR_ARGS -var github_runner_enabled=true"
if [ -n "${GITHUB_PAT:-}" ]; then
  BOOTSTRAP_VAR_ARGS="$BOOTSTRAP_VAR_ARGS -var github_runner_token=${GITHUB_PAT}"
fi

terraform apply -auto-approve $BOOTSTRAP_VAR_ARGS

# Surface which ECR repository is being used
ECR_REPO_URLS=$(terraform output -json ecr_repository_urls | tr -d '\n')
GITHUB_CI_ROLE_ARN=$(terraform output -raw github_ci_role_arn 2>/dev/null || echo "")
if [ -n "${GITHUB_CI_ROLE_ARN}" ]; then
  echo "🔐 GitHub CI role: ${GITHUB_CI_ROLE_ARN}"
fi
echo "📦 Available ECR repositories:"
echo "${ECR_REPO_URLS}" | jq -r 'to_entries[] | "  - \(.key): \(.value)"'

# Check GitHub runner status
GITHUB_RUNNER_INSTANCE_ID=$(terraform output -raw github_runner_instance_id 2>/dev/null || echo "")
if [ -n "${GITHUB_RUNNER_INSTANCE_ID}" ]; then
  echo "GitHub self-hosted runner created: ${GITHUB_RUNNER_INSTANCE_ID}"
  if [ -n "${GITHUB_PAT:-}" ]; then
    echo "   Runner configured with provided GitHub token"
  else
    echo "   WARNING: No GitHub token provided - runner may not register successfully"
    echo "   TIP: Set GITHUB_PAT environment variable for automatic registration"
  fi
else
  echo "WARNING: GitHub runner not created (github_runner_enabled=false or creation failed)"
fi

echo "✨ Bootstrap Infrastructure created successfully!"

# Initialize the EKS cluster
echo "📦 Initializing EKS cluster..."
cd ../aws
# Init with the bucket we just created, but the standard key from that module
# terraform init $TERRAFORM_INIT_ARGS
terraform apply -var "interviewee_name=${INTERVIEW_NAME}" -auto-approve

# Capture key outputs we need for downstream steps
CLUSTER_NAME=$(terraform output -raw cluster_name)
AWS_REGION=$(terraform output -raw aws_default_region)

echo "✨ EKS cluster initialized successfully!"

# update kubeconfig
$(terraform output -raw kubeconfig_command)
# Set the default namespsace to onyx
kubectl config set-context --current --namespace=onyx

# And install helm
cd ../aws-helm
#$ terraform init $TERRAFORM_INIT_ARGS

HELM_VAR_ARGS="-var eks_cluster_name=${CLUSTER_NAME} -var aws_region=${AWS_REGION}"
if [ -n "${ROUTE53_ZONE_ID:-}" ]; then
  HELM_VAR_ARGS="$HELM_VAR_ARGS -var route53_zone_id=${ROUTE53_ZONE_ID}"
fi
# Local chart usage: Uncomment and adjust CHART_PATH if you plan to maintain
# a checked-in copy of the Onyx chart (per step 3 of the plan).
# Example:
# if [ -n "${LOCAL_HELM_CHART_PATH:-}" ]; then
#   HELM_VAR_ARGS="$HELM_VAR_ARGS -var \"onyx_chart_path=${LOCAL_HELM_CHART_PATH}\""
#   echo "📦 Using local Onyx Helm chart at ${LOCAL_HELM_CHART_PATH}"
# fi

echo "terraform apply -auto-approve $HELM_VAR_ARGS"
terraform apply -auto-approve $HELM_VAR_ARGS

echo "⏳ Waiting for NLB to provision (up to 5 minutes)..."

# Wait for NLB to be ready
for i in {1..30}; do
  NLB_HOSTNAME=$(kubectl get svc onyx-nginx -n onyx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  if [ -n "$NLB_HOSTNAME" ]; then
    break
  fi
  echo "⏳ NLB not ready yet, waiting... (attempt $i/30)"
  sleep 10
done

# And now ArgoCD
echo "Waiting for ArgoCD to provision (up to 5 minutes)..."

# Wait for ArgoCD to be ready
for i in {1..30}; do
  ARGOCD_HOSTNAME=$(kubectl get svc argo-cd-argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  if [ -n "$ARGOCD_HOSTNAME" ]; then
    break
  fi
  echo "⏳ ArgoCD not ready yet, waiting... (attempt $i/30)"
  sleep 10
done

if [ -n "$NLB_HOSTNAME" ]; then
  echo ""
  echo "🎉 Onyx is ready!"
  echo "🌐 Web UI: http://$NLB_HOSTNAME"
  echo ""
else
  echo "⚠️  NLB not ready after 5 minutes. Check service status:"
  echo "   kubectl get svc onyx-nginx -n terraform-onyx"
  echo "   kubectl describe svc onyx-nginx -n terraform-onyx"
fi

if [ -n "$ARGOCD_HOSTNAME" ]; then
  echo ""
  echo "🎉 ArgoCD is ready!"
  echo "🌐 Web UI: http://$ARGOCD_HOSTNAME"
  echo ""
else
  echo "⚠️  ArgoCD not ready after 5 minutes. Check service status:"
  echo "   kubectl get svc argocd-server -n argocd"
  echo "   kubectl describe svc argocd-server -n argocd"
fi
