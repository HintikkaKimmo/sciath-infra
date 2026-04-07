output "database_url" {
  value     = "postgres://${scaleway_rdb_user.sciath.name}:${random_password.db.result}@${scaleway_rdb_instance.main.private_network[0].ip}:${scaleway_rdb_instance.main.private_network[0].port}/${scaleway_rdb_database.sciath.name}?sslmode=require"
  sensitive = true
}

output "db_host" {
  value = scaleway_rdb_instance.main.private_network[0].ip
}

output "db_port" {
  value = scaleway_rdb_instance.main.private_network[0].port
}

output "db_user" {
  value = scaleway_rdb_user.sciath.name
}

output "db_password" {
  value     = random_password.db.result
  sensitive = true
}

output "db_name" {
  value = scaleway_rdb_database.sciath.name
}

output "instance_id" {
  value = scaleway_rdb_instance.main.id
}
