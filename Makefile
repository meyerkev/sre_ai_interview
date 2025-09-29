.PHONY: fmt fmt-check argo-password

fmt:
	terraform fmt -recursive

fmt-check:
	terraform fmt -recursive -check

argo-password:
	kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 --decode

