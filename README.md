# kubernetes-platform-bootstrap

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Kubernetes](https://img.shields.io/badge/kubernetes-1.28+-blue.svg)](https://kubernetes.io/)
[![Terraform](https://img.shields.io/badge/terraform-1.6+-purple.svg)](https://www.terraform.io/)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-2.9+-orange.svg)](https://argo-cd.readthedocs.io/)
[![Helm](https://img.shields.io/badge/helm-3.13+-0F1689.svg)](https://helm.sh/)

Production-ready Kubernetes cluster bootstrapping with GitOps, Prometheus, and multi-cloud support. Opinionated, battle-tested scaffolding for EKS, GKE, and AKS environments with day-2 operations built in from day one.

---

## What This Project Does

This repository provides a complete, end-to-end bootstrapping toolkit for production Kubernetes clusters. Instead of cobbling together cluster setup from a dozen different sources, this gives you:

- **Multi-cloud Terraform modules** for EKS (AWS), GKE (GCP), and AKS (Azure) with sensible production defaults
- **ArgoCD GitOps installation** with app-of-apps pattern so the cluster manages itself after initial bootstrap
- **Prometheus/Grafana/Alertmanager** stack pre-wired with Kubernetes dashboards and alert rules
- **RBAC templates** for teams with least-privilege by default
- **Helm chart wrappers** for common platform services (cert-manager, external-dns, ingress-nginx, sealed-secrets)
- **Automated rollout scripts** with health checks and rollback capability

The design principle is: run the bootstrap once and get a cluster that is observable, secure, and self-managing.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Git Repository                           │
│  ┌────────────┐  ┌──────────────┐  ┌──────────────────────┐   │
│  │ Terraform  │  │ Helm Charts  │  │  ArgoCD App Manifests │   │
│  │ (infra)    │  │ (platform)   │  │  (app-of-apps)        │   │
│  └─────┬──────┘  └──────┬───────┘  └──────────┬───────────┘   │
└────────┼────────────────┼──────────────────────┼───────────────┘
         │                │                       │
         ▼                │                       ▼
┌────────────────┐        │             ┌──────────────────┐
│  Cloud Infra   │        │             │   ArgoCD         │
│  EKS/GKE/AKS   │        └────────────►│   (GitOps ctrl)  │
│                │                      └────────┬─────────┘
│  ┌──────────┐  │                               │ syncs
│  │  Node    │  │                               ▼
│  │  Groups  │  │               ┌───────────────────────────────┐
│  └──────────┘  │               │         Platform Layer        │
└────────────────┘               │  ┌─────────┐  ┌───────────┐  │
                                 │  │cert-mgr │  │ ext-dns   │  │
                                 │  └─────────┘  └───────────┘  │
                                 │  ┌─────────┐  ┌───────────┐  │
                                 │  │ingress  │  │sealed-sec │  │
                                 │  └─────────┘  └───────────┘  │
                                 └───────────────────────────────┘
                                               │
                                               ▼
                                 ┌───────────────────────────────┐
                                 │       Observability Stack     │
                                 │  ┌──────────┐ ┌───────────┐  │
                                 │  │Prometheus│ │ Grafana   │  │
                                 │  └──────────┘ └───────────┘  │
                                 │  ┌──────────────────────────┐ │
                                 │  │    Alertmanager           │ │
                                 │  └──────────────────────────┘ │
                                 └───────────────────────────────┘
```

### Component Breakdown

| Component | Purpose | Version |
|-----------|---------|---------|
| Terraform | Infrastructure provisioning (VPC, node groups, IAM) | >= 1.6 |
| ArgoCD | GitOps controller — syncs cluster state from this repo | 2.9.x |
| Prometheus Operator | Metrics collection and alerting rules | 0.69.x |
| Grafana | Dashboards and visualization | 10.2.x |
| cert-manager | Automatic TLS certificate lifecycle | 1.13.x |
| external-dns | Automatic DNS record management | 0.14.x |
| ingress-nginx | HTTP/S ingress controller | 4.8.x |
| sealed-secrets | Encrypted secrets safe to commit to git | 0.24.x |

---

## Prerequisites

- Terraform >= 1.6
- kubectl >= 1.28
- Helm >= 3.13
- ArgoCD CLI >= 2.9 (`brew install argocd` or see [install docs](https://argo-cd.readthedocs.io/en/stable/cli_installation/))
- Cloud CLI configured:
  - AWS: `aws configure` with EKS permissions
  - GCP: `gcloud auth application-default login`
  - Azure: `az login`

---

## Quick Start

### 1. Clone and configure

```bash
git clone https://github.com/barry-oyoung/kubernetes-platform-bootstrap
cd kubernetes-platform-bootstrap

# Copy and edit the environment config
cp terraform/environments/example.tfvars terraform/environments/production.tfvars
```

### 2. Provision the cluster (EKS example)

```bash
cd terraform/eks

# Initialise and plan
terraform init
terraform plan -var-file=../environments/production.tfvars -out=tfplan

# Review the plan, then apply
terraform apply tfplan
```

### 3. Configure kubectl

```bash
# EKS
aws eks update-kubeconfig --region us-east-1 --name my-cluster

# GKE
gcloud container clusters get-credentials my-cluster --region us-central1

# AKS
az aks get-credentials --resource-group my-rg --name my-cluster
```

### 4. Bootstrap ArgoCD and the platform

```bash
# Runs the full bootstrap sequence: ArgoCD, then app-of-apps
./scripts/bootstrap.sh --env production
```

### 5. Access ArgoCD UI

```bash
# Port-forward ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get initial admin password
argocd admin initial-password -n argocd

# Login
argocd login localhost:8080
```

Access the UI at https://localhost:8080.

---

## Detailed Usage

### Deploying to Multiple Environments

The repo is structured to support multiple environments via Terraform workspaces and ArgoCD ApplicationSets.

```bash
# Stage environment
terraform workspace new staging
terraform apply -var-file=terraform/environments/staging.tfvars

# Production environment
terraform workspace new production
terraform apply -var-file=terraform/environments/production.tfvars
```

### Adding a New Application via GitOps

Create an ArgoCD Application manifest in `manifests/applications/`:

```yaml
# manifests/applications/my-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/my-app
    targetRevision: HEAD
    path: k8s/overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

ArgoCD will pick this up on the next sync cycle.

### Customising the Prometheus Stack

Alert rules live in `manifests/monitoring/`. Add a new PrometheusRule:

```yaml
# manifests/monitoring/custom-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: custom-alerts
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
    - name: custom.rules
      rules:
        - alert: HighErrorRate
          expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.1
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "High error rate on {{ $labels.service }}"
```

### RBAC Setup

Create team-scoped roles using the templates in `manifests/rbac/`:

```bash
# Create a namespace for a team
kubectl create namespace team-payments

# Apply the template role binding
kubectl apply -f manifests/rbac/team-developer-role.yaml

# Bind to your team's service accounts or OIDC groups
kubectl create rolebinding payments-developers \
  --role=team-developer \
  --group=payments-team \
  --namespace=team-payments
```

---

## Configuration Reference

### Terraform Variables (EKS)

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `cluster_name` | EKS cluster name | — | Yes |
| `region` | AWS region | `us-east-1` | No |
| `kubernetes_version` | Kubernetes version | `1.28` | No |
| `node_group_instance_type` | EC2 instance type for worker nodes | `t3.medium` | No |
| `node_group_min_size` | Minimum nodes in the autoscaler group | `2` | No |
| `node_group_max_size` | Maximum nodes in the autoscaler group | `10` | No |
| `node_group_desired_size` | Initial desired node count | `3` | No |
| `vpc_cidr` | VPC CIDR block | `10.0.0.0/16` | No |
| `availability_zones` | AZs to deploy across | `["us-east-1a","us-east-1b","us-east-1c"]` | No |
| `enable_cluster_autoscaler` | Attach autoscaler IAM policy | `true` | No |
| `enable_external_dns` | Attach external-dns IAM policy | `true` | No |
| `tags` | Additional resource tags | `{}` | No |

### Bootstrap Script Flags

```
Usage: ./scripts/bootstrap.sh [OPTIONS]

Options:
  --env <name>       Environment name (matches tfvars filename)   [required]
  --cloud <provider> Cloud provider: eks | gke | aks              [default: eks]
  --skip-argocd      Skip ArgoCD installation (already installed)
  --skip-monitoring  Skip Prometheus stack installation
  --dry-run          Print steps without executing
  -h, --help         Show this message
```

---

## Repository Layout

```
kubernetes-platform-bootstrap/
├── terraform/
│   ├── eks/              # EKS-specific Terraform module
│   ├── gke/              # GKE-specific Terraform module
│   ├── aks/              # AKS-specific Terraform module
│   └── environments/     # Per-environment .tfvars files
├── helm/
│   ├── argocd/           # ArgoCD values overrides
│   ├── kube-prometheus/  # kube-prometheus-stack overrides
│   └── platform/         # Umbrella chart for platform services
├── manifests/
│   ├── applications/     # ArgoCD Application CRDs
│   ├── monitoring/       # PrometheusRules, Grafana dashboards
│   └── rbac/             # ClusterRoles, Roles, RoleBindings
├── scripts/
│   ├── bootstrap.sh      # Main entry point for cluster bootstrap
│   ├── rollback.sh       # Emergency rollback for ArgoCD apps
│   └── healthcheck.sh    # Cluster health validation
├── .github/
│   └── workflows/
│       └── ci.yml        # Lint, validate, and security scan
├── docs/
│   └── runbooks/         # Operational runbooks
├── Makefile
└── README.md
```

---

## Runbooks

- [Bootstrap a New Cluster](docs/runbooks/bootstrap.md)
- [Rotating Secrets with Sealed Secrets](docs/runbooks/sealed-secrets-rotation.md)
- [Cluster Upgrade Procedure](docs/runbooks/cluster-upgrade.md)
- [Incident Response](docs/runbooks/incident-response.md)

---

## Contributing

1. Fork the repo and create a branch from `main`.
2. Make your changes. Run `make lint` and `make validate` before pushing.
3. Open a pull request. Describe what changed and why.
4. All PRs require one review and passing CI.

Please follow the existing file structure and naming conventions. Terraform modules must include `variables.tf`, `outputs.tf`, and a module-level `README.md`.

---

## Author

Barry O Young — Senior DevOps Engineer

---

## License

MIT License. See [LICENSE](LICENSE) for details.
# TODO: Add retry logic




