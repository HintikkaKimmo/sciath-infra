# Changelog

All notable changes to the Sciath infrastructure will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.1.0] - 2026-04-07

### Added

- **Terraform modules** for Scaleway Kapsule cluster, managed PostgreSQL, and container registry
- **Kustomize base manifests** for Django API (2+ replicas, HPA, PDB), DBOS worker (single replica, Recreate strategy), ingress-nginx, cert-manager TLS
- **NetworkPolicy** restricting pod-to-pod and egress traffic from day one
- **Staging and production overlays** with environment-specific resource sizing and domains
- **GitHub Actions CI/CD** with Terraform plan-on-PR/apply-on-merge and deploy workflow (migration Job, kustomize apply, smoke test, auto-rollback)
- **Bootstrap script** for one-time cluster setup (ingress-nginx, cert-manager, sealed-secrets)
- **SealedSecrets template** with documentation for secret sealing workflow
- **DBOS worker entrypoint** that derives individual DB vars from DATABASE_URL (single source of truth)
- **Migration Job** with initContainer ordering guarantee on deployments
- **Pre-commit hooks** adapted for Terraform/infra: terraform_fmt, terraform_validate, tflint, kubeconform, shellcheck, gitleaks, commitizen
- **README** with architecture diagram, quick start, cost estimate, and rollback runbook
