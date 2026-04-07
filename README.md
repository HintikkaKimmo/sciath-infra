# sciath-infra

Infrastructure-as-Code for [Sciath](https://sciath.io), a CRA compliance platform for embedded/IoT manufacturers.

## Architecture

```
Cloudflare DNS → Scaleway LB (auto-provisioned) → ingress-nginx
                                                      │
                          ┌───────────────────────────┤
                          ▼                           ▼
                    django-api (2+ replicas)    dbos-worker (1 replica)
                          │                           │
                          └─────────┬─────────────────┘
                                    ▼
                          Scaleway Managed Postgres 16
                          (Private Network, not in-cluster)
```

- **Django API**: uvicorn ASGI, rolling updates, HPA 2-8 replicas
- **DBOS Worker**: durable workflow processor, single replica with `strategy: Recreate`
- **Next.js Frontend**: hosted on Vercel (not in this repo)
- **PostgreSQL**: Scaleway Managed Database, connected via private network

## Repository Structure

```
terraform/
  modules/
    kapsule/           Kapsule cluster + node pool + VPC
    rdb/               Managed PostgreSQL + private network
    registry/          Container registry
  environments/
    staging/           DEV1-M nodes, DB-DEV-S, no HA
    prod/              GP1-XS nodes, DB-GP-XS, HA enabled

k8s/
  base/                Kustomize base manifests
  overlays/
    staging/           Reduced resources, staging domain, LE staging issuer
    prod/              Full resources, production domain, LE prod issuer

scripts/
  bootstrap-cluster.sh One-time: ingress-nginx, cert-manager, sealed-secrets

.github/workflows/
  terraform.yml        Plan on PR, apply on merge to main
  deploy.yml           Migration Job → kustomize apply → smoke test
```

## Prerequisites

- [Terraform](https://terraform.io) >= 1.5
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [kustomize](https://kustomize.io/) or `kubectl kustomize`
- [kubeseal](https://github.com/bitnami-labs/sealed-secrets) (for secret management)
- [Scaleway CLI](https://github.com/scaleway/scaleway-cli) (`scw`)
- [pre-commit](https://pre-commit.com/)

## Quick Start

### 1. Set up pre-commit hooks

```bash
pre-commit install
pre-commit install --hook-type commit-msg
```

### 2. Provision infrastructure

```bash
cd terraform/environments/staging
export SCW_ACCESS_KEY=xxx SCW_SECRET_KEY=xxx
export AWS_ACCESS_KEY_ID=$SCW_ACCESS_KEY AWS_SECRET_ACCESS_KEY=$SCW_SECRET_KEY
terraform init
terraform plan
terraform apply
```

### 3. Bootstrap the cluster

```bash
scw k8s kubeconfig get <cluster-id>
./scripts/bootstrap-cluster.sh staging
```

### 4. Seal secrets and deploy

```bash
# Create and seal secrets (see scripts/bootstrap-cluster.sh output for full command)
kubectl create secret generic sciath-secrets \
  --namespace sciath --from-literal=SECRET_KEY=xxx ... \
  --dry-run=client -o yaml | kubeseal --format yaml > k8s/base/secrets/sealedsecret.yaml

# Deploy
cd k8s/overlays/staging
kustomize build . | kubectl apply -f -
```

## Deployment Flow

1. **sciath repo CI** builds image, pushes to Scaleway registry, signs with cosign
2. **repository_dispatch** triggers this repo's deploy workflow
3. **Deploy**: migration Job → wait → kustomize apply → rollout status → smoke test
4. **Prod promotion**: manual `workflow_dispatch` with same image tag

## Cost Estimate

| Component | Staging | Production |
|-----------|---------|------------|
| Compute (Kapsule nodes) | ~€15-25/mo | ~€30-50/mo |
| Database (Managed PG) | ~€15/mo | ~€25-40/mo |
| Load Balancer | ~€10/mo | ~€10/mo |
| Object Storage | ~€2/mo | ~€2/mo |
| **Total** | **~€42-52/mo** | **~€67-102/mo** |

## Rollback

```bash
kubectl rollout undo deployment/django-api -n sciath
kubectl rollout undo deployment/dbos-worker -n sciath
```

Note: database migrations are NOT automatically rolled back. All migrations must be
backward-compatible (additive only) for zero-downtime deploys.

## Related Repositories

| Repo | What |
|------|------|
| [sciath](https://github.com/HintikkaKimmo/sciath) | Backend API + engine |
| [sciath-ui](https://github.com/HintikkaKimmo/sciath-ui) | Next.js frontend |
| [sciath-cli](https://github.com/HintikkaKimmo/sciath-cli) | CLI tool |
| [sciath-meta](https://github.com/HintikkaKimmo/sciath-meta) | Build system plugins |
