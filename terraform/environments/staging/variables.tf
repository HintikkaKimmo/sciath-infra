variable "region" {
  type    = string
  default = "fr-par"
}

variable "k8s_version" {
  type        = string
  description = "Kubernetes version supported by Scaleway in the target region; select explicitly before provisioning."
}
