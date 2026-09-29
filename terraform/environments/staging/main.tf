terraform {
  required_version = ">= 1.16.4, < 2.0"

  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.40"
    }
  }
}

provider "scaleway" {
  region = var.region
  zone   = "${var.region}-1"
}

locals {
  tags = ["env:staging", "project:sciath"]
}

module "kapsule" {
  source = "../../modules/kapsule"

  cluster_name   = "sciath-staging"
  k8s_version    = var.k8s_version
  node_type      = "DEV1-M"
  node_pool_size = 2
  node_pool_min  = 2
  node_pool_max  = 3
  region         = var.region
  tags           = local.tags
}

module "rdb" {
  source = "../../modules/rdb"

  instance_name      = "sciath-staging"
  node_type          = "DB-DEV-S"
  volume_size_gb     = 10
  ha_enabled         = false
  max_connections    = 200
  private_network_id = module.kapsule.private_network_id
  region             = var.region
  tags               = local.tags
}

module "registry" {
  source = "../../modules/registry"

  namespace_name = "sciath"
  region         = var.region
}
