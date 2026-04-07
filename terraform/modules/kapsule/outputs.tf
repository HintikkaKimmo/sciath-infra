output "cluster_id" {
  value = scaleway_k8s_cluster.main.id
}

output "kubeconfig" {
  value     = scaleway_k8s_cluster.main.kubeconfig[0].config_file
  sensitive = true
}

output "apiserver_url" {
  value = scaleway_k8s_cluster.main.apiserver_url
}

output "wildcard_dns" {
  value = scaleway_k8s_cluster.main.wildcard_dns
}

output "private_network_id" {
  value = scaleway_vpc_private_network.main.id
}
