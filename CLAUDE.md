# Sciath Infrastructure

Infrastructure-as-Code for Sciath's Scaleway deployment.

## What is this?

Terraform modules for Scaleway cloud resources (Kapsule cluster, managed PostgreSQL,
container registry) and Kustomize manifests for what runs inside the cluster (Django API,
DBOS workflow worker, ingress, TLS).

This repo does NOT contain application code. The application lives in
[sciath](https://github.com/HintikkaKimmo/sciath) (backend) and
[sciath-ui](https://github.com/HintikkaKimmo/sciath-ui) (frontend).

## Repo structure

```
terraform/
  modules/kapsule/     Cluster + node pool + VPC
  modules/rdb/         Managed PostgreSQL + private network
  modules/registry/    Container registry
  environments/staging/
  environments/prod/

k8s/
  base/                Kustomize base manifests
    django/            Deployment, Service, HPA, PDB, ConfigMap, migration Job
    dbos-worker/       Deployment (replicas:1, Recreate)
    ingress/           Ingress + cert-manager ClusterIssuers
    network/           NetworkPolicy
    secrets/           SealedSecret template
  overlays/staging/    Staging overrides (reduced resources, staging domain)
  overlays/prod/       Production overrides

scripts/
  bootstrap-cluster.sh One-time cluster bootstrap (ingress-nginx, cert-manager, sealed-secrets)

.github/workflows/
  terraform.yml        Plan on PR, apply on merge
  deploy.yml           Migration job + kustomize apply + smoke test
```

## Commands

```bash
# Terraform (from environments/staging/ or environments/prod/)
terraform init
terraform plan
terraform apply

# Kustomize (validate manifests)
kustomize build k8s/overlays/staging

# Bootstrap a new cluster
./scripts/bootstrap-cluster.sh staging

# Seal a secret
kubectl create secret generic sciath-secrets \
  --namespace sciath --from-literal=SECRET_KEY=xxx \
  --dry-run=client -o yaml | kubeseal --format yaml > k8s/base/secrets/sealedsecret.yaml

# Access cluster
scw k8s kubeconfig get <cluster-id>
```

## Key decisions

- **Kapsule over Instances+Compose** -- DBOS needs persistent processes, k8s gives rolling
  deploys, health checks, HPA for free. Control plane is free on Scaleway.
- **Managed Postgres, not in-cluster** -- DBOS durability depends on DB reliability.
  Connected via private network.
- **Next.js frontend on Vercel** -- Not in this repo. The compliance story is in the backend.
- **SealedSecrets** -- Encrypted secrets in git. Backup the sealing key.
- **Terraform + Kustomize** -- Terraform for cloud, Kustomize for k8s. No Helm charts for
  app workloads. No ArgoCD until >5 services.

## DBOS worker

Single replica with `strategy: Recreate`. DBOS workflows are stateful and resume from
Postgres checkpoints. The worker's entrypoint derives `DB_HOST`/`DB_PORT`/etc from
`DATABASE_URL` so there's a single source of truth for credentials.

## Deployment flow

1. sciath repo CI builds image, pushes to Scaleway registry, signs with cosign
2. repository_dispatch triggers this repo's deploy workflow
3. Deploy: migration Job -> wait -> kustomize apply -> rollout status -> smoke test
4. Prod promotion: manual workflow_dispatch with same image tag

## Migrations

All Django migrations MUST be backward-compatible (additive only: add columns, add tables).
This is required for zero-downtime rolling deploys where old and new pods coexist briefly.
