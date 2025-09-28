# SRE Take-Home Assignment: Onyx on EKS with GitOps

## Task Overview
- Deploy Onyx on AWS EKS using GitOps best practices.
- Replace the default PostgreSQL deployment with Supabase.
- Expected time investment: 2-4 days.
- Use free-tier services when possible; otherwise use the provided virtual card.

## Requirements
1. **Base Deployment**
   - Follow the Onyx EKS deployment guide.
   - Deploy using the existing Helm chart from the Onyx repository.

2. **Deploy from Source**
   - Fork the Onyx repository.
   - Build custom container images from the forked source.
   - Set up CI/CD to build/push those images.
   - Update Helm values to use the custom images instead of the public Docker Hub images.
   - Deploy with the custom images.

3. **Database Migration**
   - Provision Supabase PostgreSQL (free tier).
   - Configure Onyx to use Supabase instead of the in-cluster PostgreSQL.
   - Update Helm values to point to Supabase.

4. **GitOps Setup**
   - Deploy Argo CD onto the EKS cluster.
   - Configure Argo CD to manage the Onyx deployment from the forked Git repository.
   - Demonstrate GitOps by committing a change and showing Argo CD automatically deploying it.

## Deliverables
- Public-facing Onyx instance with a reachable URL.
- GitHub repository containing:
  - Modified Helm values.
  - Argo CD application configuration.
  - README with setup instructions.
- GitOps demo showing a configuration change rolled out via Argo CD.

## Bonus (Optional)
- Add monitoring/observability.
- Provide Infrastructure as Code (Terraform).

## Resources
- Onyx GitHub repository.
- Onyx EKS guide.
- Supabase documentation.

## Submission
- Provide the GitHub repo URL.
- Provide the live application URL.
- Include a brief summary of key decisions.

## Notes
- Ask clarifying questions as needed.
