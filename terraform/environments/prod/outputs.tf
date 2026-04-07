output "cluster_id" {
  value = module.kapsule.cluster_id
}

output "kubeconfig" {
  value     = module.kapsule.kubeconfig
  sensitive = true
}

output "database_url" {
  value     = module.rdb.database_url
  sensitive = true
}

output "db_host" {
  value = module.rdb.db_host
}

output "db_port" {
  value = module.rdb.db_port
}
