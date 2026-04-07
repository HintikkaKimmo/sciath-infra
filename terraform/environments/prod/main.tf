terraform {
  required_version = ">= 1.5"

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
  tags = ["env:prod", "project:sciath"]
}

module "kapsule" {
  source = "../../modules/kapsule"

  cluster_name   = "sciath-prod"
  k8s_version    = var.k8s_version
  node_type      = "GP1-XS"
  node_pool_size = 2
  node_pool_min  = 2
  node_pool_max  = 4
  region         = var.region
  tags           = local.tags
}

module "rdb" {
  source = "../../modules/rdb"

  instance_name      = "sciath-prod"
  node_type          = "DB-GP-XS"
  volume_size_gb     = 50
  ha_enabled         = true
  max_connections     = 400
  private_network_id = module.kapsule.private_network_id
  region             = var.region
  tags               = local.tags
}

# Registry is shared, only created in staging
