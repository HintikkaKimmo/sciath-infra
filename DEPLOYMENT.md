# Sciath Deployment Guide

Complete deployment reference for the Sciath infrastructure on Scaleway.

## Architecture

```
Cloudflare DNS → Scaleway Load Balancer → ingress-nginx
                                            │
                          ┌─────────────────┤
                          ▼                 ▼
                    django-api (2+)    dbos-worker (1)
                    uvicorn, HPA 2-8   Recreate strategy
                          │                 │
                          └────────┬────────┘
                                   ▼
                       Scaleway Managed Postgres 16
                         (Private Network)
```

| Component       | Staging              | Production            |
|-----------------|----------------------|-----------------------|
| Cluster nodes   | DEV1-M, 2-3 nodes   | GP1-XS, 2-4 nodes    |
| PostgreSQL      | DB-DEV-S, 10 GB     | DB-GP-XS HA, 50 GB   |
| Django replicas | 1 (HPA max 3)       | 2 (HPA max 8)        |
| DBOS worker     | 1 (Recreate)        | 1 (Recreate)          |
| TLS issuer      | letsencrypt-staging  | letsencrypt-prod      |
| Domain          | api-staging.sciath.io| api.sciath.io         |

---

## Prerequisites

Install these tools before working with this repo:

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.7.5
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [kustomize](https://kubectl.docs.kubernetes.io/installation/kustomize/) >= 5.3.0
- [Helm](https://helm.sh/docs/intro/install/) >= 3
- [kubeseal](https://github.com/bitnami-labs/sealed-secrets#kubeseal)
- [Scaleway CLI](https://github.com/scaleway/scaleway-cli) (`scw`)
- [pre-commit](https://pre-commit.com/#install)

---

## Initial Setup (One-Time)

### 1. Set Scaleway Credentials

```bash
export SCW_ACCESS_KEY=SCWXXXXXXXXXXXXXXXXX
export SCW_SECRET_KEY=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
export SCW_DEFAULT_PROJECT_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

# Terraform S3 backend uses AWS-compatible credentials
export AWS_ACCESS_KEY_ID=$SCW_ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$SCW_SECRET_KEY
```

### 2. Install Pre-commit Hooks

```bash
pre-commit install
pre-commit install --hook-type commit-msg
```

### 3. Provision Infrastructure

```bash
cd terraform/environments/staging
terraform init
terraform plan
terraform apply
```

This creates the Kapsule cluster, managed PostgreSQL, private network, and container
registry. Repeat for `environments/prod` when ready.

### 4. Configure kubectl

```bash
CLUSTER_ID=$(cd terraform/environments/staging && terraform output -raw cluster_id)
scw k8s kubeconfig get $CLUSTER_ID > ~/.kube/config
chmod 600 ~/.kube/config
```

### 5. Bootstrap Cluster

```bash
./scripts/bootstrap-cluster.sh staging
```

This installs (idempotent, safe to re-run):

1. **ingress-nginx** — LoadBalancer with Scaleway LB-S annotation
2. **cert-manager** — TLS certificate automation
3. **sealed-secrets** — Encrypted secrets in git
4. **ClusterIssuers** — Let's Encrypt staging and production
5. **sciath namespace** — With `restricted` Pod Security Standard

The script prints the LoadBalancer external IP. Create DNS A records:

| Record                 | Value            |
|------------------------|------------------|
| `api-staging.sciath.io`| LoadBalancer IP  |
| `api.sciath.io`        | Prod LB IP       |

### 6. Backup Sealed-Secrets Key

**Critical** — without this, a cluster rebuild requires re-sealing all secrets.

```bash
kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > sealing-key-backup.yaml
```

Store in Scaleway Secret Manager or a secure vault. Do not commit to git.

### 7. Create Image Pull Secret

```bash
kubectl create secret docker-registry scw-registry \
  --namespace sciath \
  --docker-server=rg.fr-par.scw.cloud \
  --docker-username=nologin \
  --docker-password=$SCW_SECRET_KEY
```

### 8. Seal Application Secrets

```bash
kubectl create secret generic sciath-secrets \
  --namespace sciath \
  --from-literal=SECRET_KEY=... \
  --from-literal=DATABASE_URL=postgres://user:pass@host:port/sciath?sslmode=require \
  --from-literal=FIELD_ENCRYPTION_KEY=... \
  --from-literal=SCALEWAY_ACCESS_KEY_ID=... \
  --from-literal=SCALEWAY_SECRET_ACCESS_KEY=... \
  --from-literal=SCALEWAY_BUCKET_NAME=... \
  --from-literal=EMAIL_HOST_USER=... \
  --from-literal=EMAIL_HOST_PASSWORD=... \
  --from-literal=GOOGLE_OAUTH_CLIENT_ID=... \
  --from-literal=GOOGLE_OAUTH_CLIENT_SECRET=... \
  --from-literal=GITHUB_OAUTH_CLIENT_ID=... \
  --from-literal=GITHUB_OAUTH_CLIENT_SECRET=... \
  --from-literal=GITLAB_OAUTH_CLIENT_ID=... \
  --from-literal=GITLAB_OAUTH_CLIENT_SECRET=... \
  --from-literal=NVD_API_KEY=... \
  --from-literal=FRONTEND_URL=https://staging.sciath.io \
  --from-literal=SCIATH_WEB_CLIENT_ID=... \
  --from-literal=ALLOWED_HOSTS=api-staging.sciath.io \
  --dry-run=client -o yaml | kubeseal --format yaml \
  > k8s/base/secrets/sealedsecret.yaml
```

Commit the sealed secret (the encrypted YAML is safe for git):

```bash
git add k8s/base/secrets/sealedsecret.yaml
git commit -m "chore: add sealed secrets for staging"
```

### 9. First Deploy

```bash
cd k8s/overlays/staging
kustomize build . | kubectl apply -f -
```

---

## CI/CD Deployment Flow

Normal deployments are fully automated:

```
sciath repo CI                    sciath-infra deploy.yml
─────────────                    ────────────────────────
1. Build image         ──────►   3. Validate manifests (kubeconform)
2. Push to registry              4. Run migration Job
   + cosign sign       trigger   5. kustomize apply
                      ────────►  6. Wait for rollout (180s)
                                 7. Smoke test /health/
                                 8. Auto-rollback on failure
```

### Triggers

| Trigger              | Source                                    |
|----------------------|-------------------------------------------|
| `repository_dispatch`| sciath repo CI sends `deploy` event       |
| `workflow_dispatch`  | Manual trigger in GitHub Actions UI       |

### What Happens

1. **Manifest validation** — `kustomize build | kubeconform --strict`
2. **Migration job** — Creates `django-migrate-{tag[:8]}`, waits 300s, logs on failure
3. **Deploy** — `kustomize build | kubectl apply`, waits for both `django-api` and
   `dbos-worker` rollouts (180s timeout)
4. **Smoke test** — Hits `/health/` endpoint 10 times with 10s intervals
5. **Auto-rollback** — On smoke test failure, runs `kubectl rollout undo` for both
   deployments

### Concurrency

One deployment per environment at a time. Queued deployments wait (no cancellation).

---

## Manual Deployment

```bash
IMAGE_TAG=abc1234def5678  # git SHA from sciath repo

# 1. Validate
cd k8s/overlays/staging
kustomize edit set image PLACEHOLDER=rg.fr-par.scw.cloud/sciath/api:$IMAGE_TAG
kustomize build . | kubeconform --strict --summary

# 2. Run migrations
JOB_NAME="django-migrate-$(echo $IMAGE_TAG | head -c 8)"
sed -e "s|name: django-migrate|name: $JOB_NAME|" \
    -e "s|image: PLACEHOLDER|image: rg.fr-par.scw.cloud/sciath/api:$IMAGE_TAG|" \
    k8s/base/django/migration-job.yaml | kubectl apply -f -

kubectl wait --for=condition=complete "job/$JOB_NAME" -n sciath --timeout=300s
kubectl logs "job/$JOB_NAME" -n sciath
kubectl delete "job/$JOB_NAME" -n sciath

# 3. Deploy
kustomize build . | kubectl apply -f -
kubectl rollout status deployment/django-api -n sciath --timeout=180s
kubectl rollout status deployment/dbos-worker -n sciath --timeout=180s

# 4. Smoke test
curl -sf https://api-staging.sciath.io/health/ | grep -q '"status".*"healthy"' \
  && echo "OK" || echo "FAILED"
```

---

## Production Promotion

Production deploys use the same image that passed staging. Trigger manually:

### Via CLI

```bash
gh workflow run deploy.yml -f image_tag=$IMAGE_TAG -f environment=prod
```

### Via GitHub UI

Actions → Deploy → Run workflow → enter image tag, select `prod`

Production has GitHub environment protection rules — requires manual approval before
the workflow runs.

---

## Rollback

### Automatic

The deploy workflow auto-rolls back both deployments on smoke test failure.

### Manual

```bash
kubectl rollout undo deployment/django-api -n sciath
kubectl rollout undo deployment/dbos-worker -n sciath
```

### Important

Database migrations are **never** rolled back automatically. All migrations must be
backward-compatible (additive only: new columns, new tables) so old code continues
working with the new schema.

---

## Terraform Operations

### Plan (PR workflow)

Terraform plans run automatically on PRs touching `terraform/**`. Plans for both
staging and prod are posted as PR comments.

### Apply (merge to main)

Staging applies automatically on merge to main. Production apply requires manual
workflow dispatch with environment protection.

### Manual

```bash
cd terraform/environments/staging  # or prod
terraform init
terraform plan
terraform apply
```

---

## Secrets Management

Secrets are encrypted with [SealedSecrets](https://github.com/bitnami-labs/sealed-secrets)
and stored in git. Only the sealed-secrets controller in the cluster can decrypt them.

### Update a Secret

```bash
# Re-seal with all values (kubeseal encrypts per-secret, not per-field)
kubectl create secret generic sciath-secrets \
  --namespace sciath \
  --from-literal=SECRET_KEY=new-value \
  --from-literal=DATABASE_URL=... \
  ... \
  --dry-run=client -o yaml | kubeseal --format yaml \
  > k8s/base/secrets/sealedsecret.yaml

git add k8s/base/secrets/sealedsecret.yaml
git commit -m "chore: update sealed secrets"
```

### Required Secrets

| Secret                        | Description                              |
|-------------------------------|------------------------------------------|
| `SECRET_KEY`                  | Django secret key                        |
| `DATABASE_URL`                | Full Postgres connection string           |
| `FIELD_ENCRYPTION_KEY`        | Field-level encryption                   |
| `SCALEWAY_ACCESS_KEY_ID`      | S3-compatible storage credentials        |
| `SCALEWAY_SECRET_ACCESS_KEY`  | S3-compatible storage credentials        |
| `SCALEWAY_BUCKET_NAME`        | Report storage bucket                    |
| `EMAIL_HOST_USER`             | SMTP credentials (Scaleway TEM)          |
| `EMAIL_HOST_PASSWORD`         | SMTP credentials (Scaleway TEM)          |
| `GOOGLE_OAUTH_CLIENT_ID`     | Google OAuth                             |
| `GOOGLE_OAUTH_CLIENT_SECRET` | Google OAuth                             |
| `GITHUB_OAUTH_CLIENT_ID`     | GitHub OAuth                             |
| `GITHUB_OAUTH_CLIENT_SECRET` | GitHub OAuth                             |
| `GITLAB_OAUTH_CLIENT_ID`     | GitLab OAuth                             |
| `GITLAB_OAUTH_CLIENT_SECRET` | GitLab OAuth                             |
| `NVD_API_KEY`                 | National Vulnerability Database          |
| `FRONTEND_URL`                | Frontend base URL                        |
| `SCIATH_WEB_CLIENT_ID`        | Internal client identifier               |
| `ALLOWED_HOSTS`               | Django ALLOWED_HOSTS                     |

---

## Network Policies

Traffic is restricted by default in the `sciath` namespace:

### django-api

| Direction | Allow                                      |
|-----------|--------------------------------------------|
| Ingress   | Port 8000 from `ingress-nginx` namespace   |
| Egress    | DNS (53), PostgreSQL (5432), HTTPS (443), SMTP (465) |

### dbos-worker

| Direction | Allow                                      |
|-----------|--------------------------------------------|
| Ingress   | None                                       |
| Egress    | DNS (53), PostgreSQL (5432), HTTPS (443)   |

---

## Health Checks and Probes

### django-api

| Probe     | Path       | Delay | Period | Failures | Purpose                     |
|-----------|------------|-------|--------|----------|-----------------------------|
| Startup   | `/health/` | 5s    | 5s     | 12       | 60s window for cold start   |
| Readiness | `/health/` | 10s   | 15s    | 3        | Remove from Service on fail |
| Liveness  | `/health/` | 30s   | 30s    | 3        | Restart on persistent fail  |

### dbos-worker

| Probe    | Command       | Delay | Period | Failures | Purpose                |
|----------|---------------|-------|--------|----------|------------------------|
| Liveness | `kill -0 1`   | 30s   | 30s    | 3        | Process alive check    |

---

## DBOS Worker

The DBOS worker runs as a single replica with `strategy: Recreate`. Key details:

- **Single replica** — DBOS workflows are stateful and resume from Postgres checkpoints
- **Recreate strategy** — Old pod fully terminates before new pod starts
- **DATABASE_URL derivation** — The entrypoint extracts `DB_HOST`, `DB_PORT`, `DB_USER`,
  `DB_PASSWORD`, `DB_NAME` from `DATABASE_URL` so there's one source of truth
- **No ingress** — Worker receives no external traffic (NetworkPolicy blocks all ingress)

---

## GitHub Actions Secrets

Configure these in the repository settings:

| Secret                    | Description                          |
|---------------------------|--------------------------------------|
| `SCW_ACCESS_KEY`          | Scaleway API access key              |
| `SCW_SECRET_KEY`          | Scaleway API secret key              |
| `SCW_PROJECT_ID`          | Scaleway project ID                  |
| `SCW_CLUSTER_ID`          | Kapsule cluster ID                   |
| `AWS_ACCESS_KEY_ID`       | Same as `SCW_ACCESS_KEY` (S3 backend)|
| `AWS_SECRET_ACCESS_KEY`   | Same as `SCW_SECRET_KEY` (S3 backend)|

---

## Monitoring and Debugging

### Check deployment status

```bash
kubectl get pods -n sciath
kubectl get deployments -n sciath
kubectl get hpa -n sciath
```

### View logs

```bash
kubectl logs -n sciath deployment/django-api --tail=100 -f
kubectl logs -n sciath deployment/dbos-worker --tail=100 -f
```

### Check migration job

```bash
kubectl get jobs -n sciath
kubectl logs -n sciath job/django-migrate-XXXXXXXX
```

### Inspect certificates

```bash
kubectl get certificates -n sciath
kubectl describe certificate sciath-api-tls -n sciath
```

### Check ingress

```bash
kubectl get ingress -n sciath
kubectl describe ingress sciath-api -n sciath
```

---

## Disaster Recovery

### Cluster Rebuild

1. Re-provision infrastructure with Terraform (state is in remote S3 backend)
2. Bootstrap cluster: `./scripts/bootstrap-cluster.sh <env>`
3. Restore sealed-secrets key from backup:
   ```bash
   kubectl apply -f sealing-key-backup.yaml
   kubectl delete pod -n kube-system -l app.kubernetes.io/name=sealed-secrets
   ```
4. Re-create image pull secret
5. Apply manifests: `kustomize build k8s/overlays/<env> | kubectl apply -f -`

### Database

Managed PostgreSQL has automated daily backups (24h frequency). Retention:
- Staging: 7 days
- Production: 7 days

Restore via Scaleway console or CLI.

---

## Pre-commit Hooks

The repo enforces quality checks before commit:

| Hook                   | Purpose                                |
|------------------------|----------------------------------------|
| trailing-whitespace    | Clean formatting                       |
| end-of-file-fixer      | Consistent file endings                |
| check-yaml             | YAML syntax                            |
| detect-private-key     | Prevent key leakage                    |
| commitizen             | Conventional commit messages           |
| gitleaks               | Secret scanning                        |
| terraform_fmt          | Terraform formatting                   |
| terraform_validate     | Terraform syntax                       |
| terraform_tflint       | Terraform linting                      |
| kubeconform            | K8s manifest validation                |
| shellcheck             | Shell script linting                   |

---

## Related Repositories

| Repository   | Purpose                      | URL                                            |
|-------------|------------------------------|------------------------------------------------|
| sciath       | Backend API + DBOS engine    | https://github.com/HintikkaKimmo/sciath        |
| sciath-ui    | Next.js frontend (Vercel)    | https://github.com/HintikkaKimmo/sciath-ui     |
| sciath-cli   | CLI tool                     | https://github.com/HintikkaKimmo/sciath-cli    |
| sciath-meta  | Build system plugins         | https://github.com/HintikkaKimmo/sciath-meta   |
