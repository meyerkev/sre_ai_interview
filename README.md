# Onyx SRE.ai Interview

This is a set of Terraform modules to apply our 

The fastest way to launch the interview environment is to run one script. Follow the two steps below.

## Step 0 - Prerequisites

I'm probably missing a few, but install: 

* AWS CLI with a working and configured 
* Kubectl
* Helm
* jq
* yq
* Terraform, which I usually do via tfenv

## Step 1 – Get Your Supabase Connection String
Create a Supabase project (free tier works). In Project Settings → Database, copy the full `postgresql://…` connection URL. You will pass this to the deployment script so Onyx uses Supabase instead of the bundled PostgreSQL.

## Step 1b - Grab your Onyx repository (if relevant)

Onyx is currently running out of meyerkev/onyx on a custom side branch because they broke their main images oevr the weekend. Hence why our main tag is, direct quote, "working_i_hope"

## Step 2 – Run the Deployment Script
From the repo root:

```bash
./zero_to_hero.sh \
  --supabase-connection-string "postgresql://USER:PASSWORD@HOST:6543/DB" \
  --github-repository <me>/<my onyx fork>
  --github_pat <my repo-level github pat>

# Optional environment variables:
#   TF_STATE_BUCKET=my-tf-bucket  # remote backend bucket
#   TF_STATE_KEY=path/to/state    # remote backend key
#   TF_STATE_REGION=us-east-2     # remote backend region
```

The script performs three phases automatically:
1. **Bootstrap (`terraform/bootstrap`)** – ECR repositories, GitHub Actions OIDC role, optional self-hosted runner.

You can and should trigger your Github Pipelines here.  Building images takes about 10 minutes so your applications won't come up until you've pushed those images. But everything else will work.  

2. **Cluster (`terraform/aws-ipv4`)** – IPv4 VPC, EKS control plane, managed node group, addons.
3. **Helm (`terraform/aws-helm-ipv4`)** – AWS load balancer controller, autoscaler, metrics server, Argo CD, and the Onyx chart wired to Supabase.

When it finishes you will see:
- `🌐 Web UI: http://<nlb-hostname>` – Onyx front-end.
- `🌐 Web UI: http://<argo-hostname>` – Argo CD server.
- Retrieve the Argo CD admin password any time with `make argo-password | pbcopy`.

## Cleanup

```bash
# Remove everything (Helm → EKS → bootstrap)
scripts/destroy.sh -- sre-ai-interview-ipv4

# Remove only the EKS cluster (keep bootstrap resources)
scripts/destroy-aws.sh --interview-name sre-ai-interview-ipv4
```

That’s it—grab the Supabase string, run `zero_to_hero.sh`, and you’re live.

## TODOs:

More Helm Charts: 
* External Secrets so that our secrets sync automatically with AWS Secrets Manager
* [https://github.com/stakater/Reloader](Reloader) - Automatically reload our deployments when we rotate our deployment strings

## Key Decisions: 

* We run on ipv4 vs ipv6 beacuse ipv6 is still somewhat painful.  
* We are using a side branch on my onyx repository because main broke late on Friday and it took me some time to find a working side branch.  
* We do not yet have a working Route53 setup with a website
  * This means we do not have a stable set of DNS yet
  * This means we are on NLBs rather than ALBs because ALBs require 
* This was a heavily modified fork of my old EKS interviewing repository which is why we have two repos.  
  * You would think this would have been a timesaver except that I hadn't touched it in 3 months during which point all our old versions failed on us.  
* We do not have a semantic versioning yet, so we push based on branch names from the other repository.  Ideally, we would do something like 1.21.0, 1.21.1, etc.  
