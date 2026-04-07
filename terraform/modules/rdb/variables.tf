variable "instance_name" {
  type        = string
  description = "Name of the RDB instance"
}

variable "node_type" {
  type        = string
  default     = "DB-DEV-S"
  description = "Scaleway RDB instance type"
}

variable "volume_size_gb" {
  type        = number
  default     = 10
  description = "Volume size in GB"
}

variable "ha_enabled" {
  type        = bool
  default     = false
  description = "Enable HA cluster"
}

variable "max_connections" {
  type        = number
  default     = 400
  description = "PostgreSQL max_connections"
}

variable "backup_retention_days" {
  type        = number
  default     = 7
  description = "Number of days to retain backups"
}

variable "database_name" {
  type        = string
  default     = "sciath"
  description = "Database name"
}

variable "database_user" {
  type        = string
  default     = "sciath"
  description = "Database user name"
}

variable "private_network_id" {
  type        = string
  description = "VPC private network ID for cluster-to-DB communication"
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
