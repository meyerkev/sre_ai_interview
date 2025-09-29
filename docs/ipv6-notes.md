# IPv6 Operational Notes

- AWS Network Load Balancers only register IPv4 targets today. In an IPv6-only EKS cluster, Services of type `LoadBalancer` that rely on NLB will remain pending because the controller has no IPv4 pod IPs to attach.
- Application Load Balancers (managed by the AWS Load Balancer Controller) can front IPv6 pods when `target-type=ip`. Use Ingress + ALB for public exposure in IPv6-only clusters.
- Keep the backing Service as `ClusterIP` and let the ALB route to it.
- Leave the ingress host unset (`null`) if you plan to access the AWS `*.elb.amazonaws.com` endpoint directly; set a host only when you control the DNS record.

