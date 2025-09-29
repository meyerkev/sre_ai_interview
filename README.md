# Onyx Zero-to-Hero

The fastest way to launch the interview environment is to run one script. Follow the two steps below.

## Step 1 – Get Your Supabase Connection String
Create a Supabase project (free tier works). In Project Settings → Database, copy the full `postgresql://…` connection URL. You will pass this to the deployment script so Onyx uses Supabase instead of the bundled PostgreSQL.

## Step 2 – Run the Deployment Script
From the repo root:

```bash
./zero_to_hero.sh \
  --supabase-connection-string "postgresql://USER:PASSWORD@HOST:6543/DB" \
  --github-repository meyerkev/onyx

# Optional environment variables:
#   GITHUB_PAT=ghp_xxx            # auto-register the GitHub runner
#   TF_STATE_BUCKET=my-tf-bucket  # remote backend bucket
#   TF_STATE_KEY=path/to/state    # remote backend key
#   TF_STATE_REGION=us-east-2     # remote backend region
```

The script performs three phases automatically:
1. **Bootstrap (`terraform/bootstrap`)** – ECR repositories, GitHub Actions OIDC role, optional self-hosted runner.
2. **Cluster (`terraform/aws-ipv4`)** – IPv4 VPC, EKS control plane, managed node group, addons.
3. **Helm (`terraform/aws-helm-ipv4`)** – AWS load balancer controller, autoscaler, metrics server, Argo CD, and the Onyx chart wired to Supabase.

When it finishes you will see:
- `🌐 Web UI: http://<nlb-hostname>` – Onyx front-end.
- `🌐 Web UI: http://<argo-hostname>` – Argo CD server.
- Retrieve the Argo CD admin password any time with `make argo-password`.

## Cleanup

```bash
# Remove everything (Helm → EKS → bootstrap)
scripts/destroy.sh -- sre-ai-interview-ipv4

# Remove only the EKS cluster (keep bootstrap resources)
scripts/destroy-aws.sh --interview-name sre-ai-interview-ipv4
```

That’s it—grab the Supabase string, run `zero_to_hero.sh`, and you’re live.


