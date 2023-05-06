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
    disk_gb = number
  })
}

variable "worker" {
  type = object({
    nb_vms = number
    start_ip = number
    cpus = number
    memory_max = number
    disk_gb = number
  })
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

variable "iso_sr_id" {
  type = string
}

variable "disks_sr_id" {
  type = string
}

variable "network_id" {
  type = string
}

variable "xen_pool_id" {
  type = string
}

variable "subnet" {
  type = string
}

variable "max_controlplanes" {
  type = number
  default = 20
}

variable "vlan" {
  type = number
}

variable "mikrotik_network_interfaces" {
  type = list(string)
}