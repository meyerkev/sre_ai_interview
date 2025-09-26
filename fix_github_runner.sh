#!/bin/bash
set -e

echo "🔧 Fixing GitHub runner registration..."

# Get registration token from GitHub API
echo "Getting registration token from GitHub API..."
REGISTRATION_TOKEN=$(curl -s -X POST \
  -H "Authorization: Bearer ${GITHUB_PAT}" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/meyerkev/onyx/actions/runners/registration-token | \
  jq -r '.token')

if [ "$REGISTRATION_TOKEN" = "null" ] || [ -z "$REGISTRATION_TOKEN" ]; then
  echo "❌ Failed to get registration token. Check your GITHUB_PAT permissions."
  echo "Your PAT needs 'repo' and 'workflow' scopes."
  exit 1
fi

echo "✅ Got registration token: ${REGISTRATION_TOKEN:0:20}..."

# Update the Terraform configuration with the registration token
echo "🔄 Updating GitHub runner with registration token..."
cd /Users/meyerkev/development/onyx-interview/terraform/bootstrap

terraform apply \
  -var="interview_name=sre-ai-interview" \
  -var="github_repository=meyerkev/onyx" \
  -var="github_runner_enabled=true" \
  -var="github_runner_token=${REGISTRATION_TOKEN}" \
  -auto-approve

echo "✅ GitHub runner updated with registration token!"
echo "The runner should come online within 2-3 minutes."
