# sciath-infra

Infrastructure templates for the earlier Sciath **embedded-Linux CRA compliance**
service: Scaleway Kapsule, managed PostgreSQL 16, a container registry, and
Kustomize manifests for a Django API and DBOS worker.

This repository does not contain the application or the AI-agent debugging
product. A compatible compliance backend image is required. The current private
`sciath` repository is not assumed to produce that image.

## Deployment status

These are legacy deployment templates, not a production-ready SaaS installer.
The manifests and bootstrap script still use **Ingress NGINX**, which
[retired in March 2026](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/).
A maintained ingress or Gateway API implementation must be selected and the
routing/TLS configuration migrated before a new production deployment. The legacy
bootstrap script stops by default; `SCIATH_ALLOW_RETIRED_INGRESS=1` permits
reproduction of the old stack only. Its charts are pinned to ingress-nginx
4.15.1, cert-manager v1.21.2 and sealed-secrets 2.20.0; pinning does not restore
support for the retired controller.

The previous Kubernetes 1.30 default has been removed. Explicitly choose a
version supported by Scaleway in your region. A provider upgrade or successful
local validation does not prove that a live cluster upgrade is safe.

## Contents

- `terraform/modules/` — Kapsule/private network, database, registry
- `terraform/environments/staging/` — development node/DB sizes, no database HA
- `terraform/environments/prod/` — larger node/DB sizes and database HA
- `k8s/base/` — Django, DBOS worker, networking, ingress, certificate issuers
- `k8s/overlays/` — staging and production configuration
- `scripts/bootstrap-cluster.sh` — legacy cluster add-on installation
- `.github/workflows/terraform.yml` — local validation and explicit cloud operations
- `.github/workflows/deploy.yml` — application migration, rollout and smoke checks

The Next.js frontend is separate. Hostnames, issuer email addresses, registry
paths, resource sizing and state-bucket settings in these templates must be
reviewed for the target deployment. Historical cost estimates have been removed;
obtain a current provider estimate before provisioning.

## Validate without cloud access

Use Terraform 1.16.4, Kustomize 5.8.1 and kubeconform 0.8.0. Provider selections
and checksums are committed in each environment's `.terraform.lock.hcl`.

```bash
terraform fmt -check -recursive terraform
terraform -chdir=terraform/environments/staging init -backend=false -lockfile=readonly
terraform -chdir=terraform/environments/staging validate
terraform -chdir=terraform/environments/prod init -backend=false -lockfile=readonly
terraform -chdir=terraform/environments/prod validate
kustomize build k8s/overlays/staging > /tmp/sciath-staging.yaml
kustomize build k8s/overlays/prod > /tmp/sciath-prod.yaml
kubeconform -strict -summary -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  /tmp/sciath-staging.yaml /tmp/sciath-prod.yaml
```

The overlays include cert-manager `ClusterIssuer` custom resources. kubeconform
needs a matching custom-resource schema to validate those resources; do not
mistake skipped custom resources for a complete cluster compatibility check.
No cloud credentials, state download, plan or apply are required for Terraform
configuration validation.

## Cloud provisioning and deployment

Before deployment, complete the ingress migration above, provide a compatible
application image, configure the state bucket, and choose supported cluster
versions and infrastructure sizes. Provisioning requires Scaleway credentials
and can create billable resources.

For a deliberately reviewed local plan, set `SCW_ACCESS_KEY`, `SCW_SECRET_KEY`,
`SCW_DEFAULT_PROJECT_ID`, the matching `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`
for the S3-compatible state backend, and `TF_VAR_k8s_version`. Then initialize
with the backend enabled and review `terraform plan` before applying it.
Do not commit state, plan files, credentials, database passwords or sealing keys.

The Terraform workflow runs formatting and credential-free validation on pull
requests and pushes. It **does not automatically deploy on merge**. Cloud `plan`
or `apply` requires a manual dispatch on `main`, a target environment, and an
explicit Kubernetes version. `plan` is the default; choosing `apply` generates
and applies a fresh plan in that run. Configure GitHub environment protection
rules for deployments that need human review.

The separate Deploy workflow accepts `repository_dispatch` or manual dispatch
with a compatible image tag and `staging`/`prod`. It runs database migrations,
updates both workloads, and checks the configured health endpoint. GitHub
secrets, registry access, cluster access and application secrets must already
exist. Publishing this repository does not configure any of those services.

`sealedsecret-template.yaml` is a template, not a deployable secret. A sealed
secret must be created for the target cluster and explicitly applied or added to
the relevant overlay; the base kustomization does not include one automatically.
Back up the sealing key securely outside the repository.

## Rollback limitations

The deploy workflow attempts workload rollback after a failed smoke check.
Database migrations are not automatically rolled back. Changes must remain
compatible with the preceding application version; a workload rollback alone
does not recover an incompatible database migration.

## License

[PolyForm Shield 1.0.0](LICENSE.md). Copyright 2026 Kimmo Hintikka; see
[NOTICE](NOTICE). This is source-available software, not OSI-approved open
source. Noncompeting uses, including commercial uses, are permitted under the
license's terms. Contact the licensor for uses outside those terms. Cloud
services, tools, charts and container images retain their own licenses.
