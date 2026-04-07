terraform {
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.40"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

resource "random_password" "db" {
  length  = 32
  special = false
}

resource "scaleway_rdb_instance" "main" {
  name      = var.instance_name
  engine    = "PostgreSQL-16"
  node_type = var.node_type
  region    = var.region
  tags      = var.tags

  volume_type       = "bssd"
  volume_size_in_gb = var.volume_size_gb

  disable_backup             = false
  backup_schedule_frequency  = 24
  backup_schedule_retention  = var.backup_retention_days

  is_ha_cluster = var.ha_enabled

  settings = {
    max_connections = tostring(var.max_connections)
  }

  private_network {
    pn_id = var.private_network_id
  }
}

resource "scaleway_rdb_database" "sciath" {
  instance_id = scaleway_rdb_instance.main.id
  name        = var.database_name
}

resource "scaleway_rdb_user" "sciath" {
  instance_id = scaleway_rdb_instance.main.id
  name        = var.database_user
  password    = random_password.db.result
  is_admin    = false
}

resource "scaleway_rdb_privilege" "sciath" {
  instance_id   = scaleway_rdb_instance.main.id
  user_name     = scaleway_rdb_user.sciath.name
  database_name = scaleway_rdb_database.sciath.name
  permission    = "all"
}
