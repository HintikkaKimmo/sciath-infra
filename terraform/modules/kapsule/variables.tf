variable "cluster_name" {
  type        = string
  description = "Name of the Kapsule cluster"
}

variable "k8s_version" {
  type        = string
  default     = "1.30"
  description = "Kubernetes version"
}

variable "node_type" {
  type        = string
  default     = "DEV1-M"
  description = "Scaleway instance type for worker nodes"
}

variable "node_pool_size" {
  type        = number
  default     = 2
  description = "Initial number of nodes"
}

variable "node_pool_min" {
  type        = number
  default     = 2
  description = "Minimum number of nodes (autoscaling)"
}

variable "node_pool_max" {
  type        = number
  default     = 4
  description = "Maximum number of nodes (autoscaling)"
}

variable "region" {
  type        = string
  default     = "fr-par"
  description = "Scaleway region"
}

variable "tags" {
  type        = list(string)
  default     = []
  description = "Tags for all resources"
}
