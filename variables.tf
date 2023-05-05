variable "cluster_name" {
    type = string
}

variable "cluster_endpoint" {
    type = string
}

variable "talos_version" {
  type = string
  default = "1.4.0"
}