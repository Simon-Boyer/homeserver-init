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

variable "talos_repo" {
  type = string
  default = "https://github.com/siderolabs/talos"
}

variable "controlplane" {
  type = object({
    nb_vms = number
    start_ip = number
    cpus = number
    memory_max = number
  })
}

variable "worker" {
  type = object({
    nb_vms = number
    start_ip = number
    cpus = number
    memory_max = number
  })
}

variable "certSANs" {
  type = list(string)
}

variable "oidc-issuer-url" {
  type = string
}

variable "oidc-client-id" {
  type = string
}

variable "oidc-client-secret" {
  type = string
  sensitive = true
}

variable "iso_sr_label" {
  type = string
}

variable "disks_sr_label" {
  type = string
}

variable "network_label" {
  type = string
}

variable "xen_pool_name" {
  type = string
}

