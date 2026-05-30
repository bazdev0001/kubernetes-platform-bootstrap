# kubernetes-platform-bootstrap Makefile
#
# Targets are organised into groups:
#   infra-*   — Terraform operations
#   cluster-* — kubectl / ArgoCD cluster operations
#   lint-*    — Linting and validation
#   test-*    — Testing
#
# Default cloud is EKS. Override with: make infra-plan CLOUD=gke ENV=staging

CLOUD    ?= eks
ENV      ?= production
TF_DIR   := terraform/$(CLOUD)
TFVARS   := terraform/environments/$(ENV).tfvars

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help message
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} \
	     /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-28s\033[0m %s\n", $$1, $$2 } \
	     /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)

##@ Infrastructure

.PHONY: infra-init
infra-init: ## Initialise Terraform for the target cloud module
	@echo "==> Initialising Terraform ($(CLOUD))..."
	terraform -chdir=$(TF_DIR) init

.PHONY: infra-plan
infra-plan: ## Plan Terraform changes (set CLOUD= and ENV= to override)
	@echo "==> Planning $(CLOUD) / $(ENV)..."
	@test -f $(TFVARS) || (echo "ERROR: $(TFVARS) not found." && exit 1)
	terraform -chdir=$(TF_DIR) plan -var-file=../../$(TFVARS) -out=.tfplan

.PHONY: infra-apply
infra-apply: ## Apply planned Terraform changes (requires infra-plan first)
	@echo "==> Applying $(CLOUD) / $(ENV)..."
	@test -f $(TF_DIR)/.tfplan || (echo "ERROR: Run 'make infra-plan' first." && exit 1)
	terraform -chdir=$(TF_DIR) apply .tfplan

.PHONY: infra-destroy
infra-destroy: ## Destroy all Terraform-managed infrastructure (DANGEROUS)
	@echo "WARNING: This will destroy all infrastructure in $(CLOUD)/$(ENV)."
	@read -p "Type the environment name to confirm: " confirm && \
	  [ "$$confirm" = "$(ENV)" ] || (echo "Aborted." && exit 1)
	terraform -chdir=$(TF_DIR) destroy -var-file=../../$(TFVARS)

.PHONY: infra-fmt
infra-fmt: ## Auto-format all Terraform files
	terraform fmt -recursive terraform/

##@ Cluster Operations

.PHONY: cluster-bootstrap
cluster-bootstrap: ## Bootstrap ArgoCD and the app-of-apps onto the current cluster
	@echo "==> Bootstrapping cluster ($(ENV))..."
	bash scripts/bootstrap.sh --env $(ENV) --cloud $(CLOUD)

.PHONY: cluster-health
cluster-health: ## Run the cluster health check
	bash scripts/healthcheck.sh

.PHONY: cluster-argocd-status
cluster-argocd-status: ## Show ArgoCD application status
	argocd app list -n argocd

.PHONY: cluster-rollback
cluster-rollback: ## Roll back an ArgoCD app (set APP= to specify)
	@test -n "$(APP)" || (echo "Usage: make cluster-rollback APP=<argocd-app-name>" && exit 1)
	bash scripts/rollback.sh --app $(APP)

.PHONY: cluster-kubeconfig
cluster-kubeconfig: ## Update kubeconfig for the current EKS cluster (EKS only)
	@CLUSTER_NAME=$$(terraform -chdir=$(TF_DIR) output -raw cluster_name 2>/dev/null) && \
	REGION=$$(terraform -chdir=$(TF_DIR) output -raw region 2>/dev/null || echo "us-east-1") && \
	echo "==> Updating kubeconfig for $$CLUSTER_NAME in $$REGION..." && \
	aws eks update-kubeconfig --region "$$REGION" --name "$$CLUSTER_NAME"

##@ Linting & Validation

.PHONY: lint
lint: lint-terraform lint-manifests lint-shell ## Run all linters

.PHONY: lint-terraform
lint-terraform: ## Lint and validate Terraform modules
	@echo "==> Terraform fmt check..."
	terraform fmt -check -recursive terraform/
	@for module in terraform/eks terraform/gke terraform/aks; do \
	  echo "==> Validating $$module..."; \
	  terraform -chdir=$$module init -backend=false -input=false -no-color 2>/dev/null; \
	  terraform -chdir=$$module validate; \
	done

.PHONY: lint-manifests
lint-manifests: ## Validate Kubernetes manifests with kubeconform
	@command -v kubeconform >/dev/null 2>&1 || \
	  (echo "kubeconform not found. Install: https://github.com/yannh/kubeconform" && exit 1)
	@echo "==> Validating manifests..."
	find manifests/ -name "*.yaml" \
	  | grep -v manifests/argocd \
	  | xargs kubeconform -strict -ignore-missing-schemas -kubernetes-version 1.28.0 -summary

.PHONY: lint-shell
lint-shell: ## Lint shell scripts with shellcheck
	@command -v shellcheck >/dev/null 2>&1 || \
	  (echo "shellcheck not found. Install: brew install shellcheck" && exit 1)
	shellcheck scripts/*.sh

.PHONY: lint-helm
lint-helm: ## Lint Helm value overrides
	helm lint argo/argo-cd --values helm/argocd/values.yaml --set global.domain=example.com 2>/dev/null || true

##@ Security

.PHONY: security-scan
security-scan: ## Run checkov security scan on Terraform and manifests
	@command -v checkov >/dev/null 2>&1 || \
	  (echo "checkov not found. Install: pip install checkov" && exit 1)
	@echo "==> Scanning Terraform..."
	checkov -d terraform/ --framework terraform --compact --quiet || true
	@echo "==> Scanning Kubernetes manifests..."
	checkov -d manifests/ --framework kubernetes --compact --quiet || true

##@ Utilities

.PHONY: docs
docs: ## Generate terraform-docs for each module
	@command -v terraform-docs >/dev/null 2>&1 || \
	  (echo "terraform-docs not found. Install: brew install terraform-docs" && exit 1)
	terraform-docs markdown table terraform/eks  > terraform/eks/README.md
	terraform-docs markdown table terraform/gke  > terraform/gke/README.md
	terraform-docs markdown table terraform/aks  > terraform/aks/README.md
	@echo "==> Docs regenerated."

.PHONY: clean
clean: ## Remove local build artefacts (Terraform plans, .terraform dirs)
	@echo "==> Cleaning..."
	find terraform/ -name ".tfplan" -delete
	find terraform/ -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
	find terraform/ -name "terraform.tfstate.backup" -delete 2>/dev/null || true
	@echo "Clean complete."
