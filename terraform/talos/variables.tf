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

variable "servers" {
  type = list(object({
    controlplane = bool
    switch_port  = string
    mac_addr     = string
    hostname     = string
    install_disk = string
  }))
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

variable "servers_dns" {
  type = list(string)
}

variable "network_config" {
  type = object({
    lease_time     = optional(string, "30d 00:00:00")
    domain         = string
    gateway        = string
    network        = string
    bgp_cluster_as = optional(number, 64500)
    bgp_router_as  = optional(number, 65530)
    vlan = number
    switch_allowed_ports = list(string)
    router_downlink = string
  })
}