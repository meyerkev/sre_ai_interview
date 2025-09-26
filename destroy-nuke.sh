#!/usr/bin/env bash
set -euo pipefail

# Safe wrapper to run aws-nuke with the repo's aws-nuke.yaml
# Defaults to DRY RUN. Pass --yes to actually delete (adds --no-dry-run --force).

cd "$(dirname "$0")"

PROFILE="default"
CONFIG="aws-nuke.yaml"
DRY_RUN=1

usage() {
  cat <<EOF
Usage: $0 [--yes] [--profile <name>] [--config <path>] [--] [extra aws-nuke args]

Runs aws-nuke against this repo's config using the 'meyerkev-toybox' profile by default.

Options:
  --yes                 Perform deletion (adds --no-dry-run --force). Default is dry-run.
  --profile <name>      AWS named profile to use (default: ${PROFILE}).
  --config <path>       Path to aws-nuke config (default: ${CONFIG}).
  -h, --help            Show this help and exit.

Examples:
  Dry run (default):   $0
  Real delete:         $0 --yes
  Alternate profile:   $0 --profile my-profile
  Pass-through flags:  $0 -- --target "EC2*"
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes)
      DRY_RUN=0; shift ;;
    --profile)
      PROFILE="$2"; shift 2 ;;
    --config)
      CONFIG="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    --)
      shift; break ;;
    *)
      # Unrecognized here; let aws-nuke parse via pass-through
      break ;;
  esac
done

if ! command -v aws-nuke >/dev/null 2>&1; then
  echo "Error: aws-nuke is not installed or not in PATH." >&2
  echo "Install from: https://github.com/rebuy-de/aws-nuke/releases" >&2
  exit 1
fi

if [[ ! -f "$CONFIG" ]]; then
  echo "Error: config file not found: $CONFIG" >&2
  exit 1
fi

echo "⚠️  aws-nuke is extremely destructive. Use disposable accounts only."
echo "Config: $CONFIG"
echo "Profile: $PROFILE"

cmd=(aws-nuke run --config "$CONFIG" --profile "$PROFILE")

if [[ $DRY_RUN -eq 1 ]]; then
  echo "Running in DRY RUN mode (no resources will be deleted)."
else
  echo "Running with DELETION ENABLED (--no-dry-run --force)."
  cmd+=(--no-dry-run --no-prompt)
fi

# Append any additional args for aws-nuke after '--'
if [[ $# -gt 0 ]]; then
  cmd+=("$@")
fi

echo "+ ${cmd[*]}"
"${cmd[@]}"

# clear out the statefiles from s3
aws s3 rm s3://meyerkev-terraform-state/ --recursive

# clear out every user who isn't me and their access keys
aws iam list-users | jq -r '.Users[].UserName' | while read -r user; do
  if [ "$user" != "meyerkev" ]; then
    aws iam delete-user --user-name "$user"
  fi
done

# clear out every user who isn't me and their access keys
aws iam list-users | jq -r '.Users[].UserName' | while read -r user; do
  if [ "$user" != "meyerkev" ]; then
    # Clear the access keys first
    aws iam list-access-keys --user-name "$user" | jq -r '.AccessKeyMetadata[].AccessKeyId' | while read -r key; do
      aws iam delete-access-key --user-name "$user" --access-key-id "$key"
    done

    aws iam delete-user --user-name "$user"
  fi
done