.PHONY: fmt fmt-check

fmt:
	terraform fmt -recursive

fmt-check:
	terraform fmt -recursive -check

