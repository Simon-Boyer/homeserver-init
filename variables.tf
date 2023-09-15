variable "cluster_name" {
  type = string
}

variable "cluster_endpoint" {
  type = string
}

variable "talos_version" {
  type    = string
  default = "1.4.0"
}

variable "talos_repo" {
  type    = string
  default = "https://github.com/siderolabs/talos"
}

variable "router_host" {
  type    = string
  default = "192.168.88.1"
}

variable "router_user" {
  type    = string
  default = "admin"
}

variable "router_password" {
  type      = string
  sensitive = true
}

variable "switch_host" {
  type = string
}

variable "switch_user" {
  type    = string
  default = "admin"
}

variable "switch_password" {
  type      = string
  sensitive = true
}

variable "servers" {
  type = list(object({
    controlplane = bool
    switch_port  = string
    mac_addr     = string
    hostname     = string
    install_disk = string
  }))
}

variable "vlan" {
  type = number
}

variable "network_config" {
  type = object({
    lease_time     = optional(string, "30d 00:00:00")
    domain         = string
    gateway        = string
    network        = string
    dns            = string
    bgp_cluster_as = optional(number, 64500)
    bgp_router_as  = optional(number, 65530)
  })
}

variable "oidc-issuer-url" {
  type = string
}

variable "oidc-client-id" {
  type = string
}

variable "oidc-client-secret" {
  type      = string
  sensitive = true
}
