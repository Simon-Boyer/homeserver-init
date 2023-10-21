variable "metallb_version" {
  type = string
}

variable "contour_version" {
  type = string
}

variable "argocd_version" {
  type = string
}

variable "argocd_password" {
  type = string
  sensitive = true
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

variable "git_repo" {
  type = string
}