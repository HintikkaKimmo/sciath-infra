terraform {
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.40"
    }
  }
}

# Shared private network for cluster <-> RDB communication
resource "scaleway_vpc_private_network" "main" {
  name   = "${var.cluster_name}-vpc"
  region = var.region
  tags   = var.tags
}

resource "scaleway_k8s_cluster" "main" {
  name    = var.cluster_name
  version = var.k8s_version
  cni     = "cilium"
  region  = var.region
  tags    = var.tags

  private_network_id = scaleway_vpc_private_network.main.id

  auto_upgrade {
    enable                        = true
    maintenance_window_start_hour = 3
    maintenance_window_day        = "sunday"
  }

  autoscaler_config {
    disable_scale_down              = false
    scale_down_delay_after_add      = "5m"
    scale_down_unneeded_time        = "5m"
    estimator                       = "binpacking"
    expander                        = "random"
    ignore_daemonsets_utilization    = true
    balance_similar_node_groups     = true
    expendable_pods_priority_cutoff = -10
  }

  delete_additional_resources = true
}

resource "scaleway_k8s_pool" "default" {
  cluster_id  = scaleway_k8s_cluster.main.id
  name        = "${var.cluster_name}-pool"
  node_type   = var.node_type
  size        = var.node_pool_size
  min_size    = var.node_pool_min
  max_size    = var.node_pool_max
  autoscaling = true
  autohealing = true
  region      = var.region
  tags        = var.tags
}
