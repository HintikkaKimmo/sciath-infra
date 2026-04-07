terraform {
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.40"
    }
  }
}

resource "scaleway_registry_namespace" "main" {
  name      = var.namespace_name
  region    = var.region
  is_public = false
}
