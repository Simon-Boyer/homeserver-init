terraform {
  required_version = "~> 1.3"
  required_providers {
    http = {
      source  = "hashicorp/http"
      version = "3.3.0"
    }
    macaddress = {
      source  = "ivoronin/macaddress"
      version = "0.3.2"
    }
    routeros = {
      source  = "terraform-routeros/routeros"
      version = "1.13.2"
      configuration_aliases = [ routeros.switch ]
    }
    local = {
      source  = "hashicorp/local"
      version = "2.4.0"
    }
  }
}

resource "routeros_interface_bridge_port" "eth2port" {
  provider  = routeros.switch
  bridge    = "bridge"
  for_each  = { for s in var.servers : s.hostname => s }
  interface = each.value.switch_port
  pvid      = var.network_config.vlan
}

resource "routeros_interface_vlan" "cluster-vlan-if" {
  interface = var.network_config.router_downlink
  mtu       = 1500
  name      = "vlan-${var.network_config.vlan}-if"
  vlan_id   = var.network_config.vlan
}

resource "routeros_ip_address" "lan" {
  address   = "${cidrhost(var.network_config.network, 1)}/${split("/", var.network_config.network)[1]}"
  comment   = "${var.cluster_name} Network"
  interface = routeros_interface_vlan.cluster-vlan-if.name
}

# resource "routeros_bridge_vlan" "router-cluster-vlan" {
#   bridge   = "bridge"
#   tagged   = ["vlan-${var.network_config.vlan}-if"]
#   vlan_ids = var.network_config.vlan
#   depends_on = [ routeros_interface_vlan.cluster-vlan-if ]
# }

resource "routeros_bridge_vlan" "switch-cluster-vlan" {
  provider  = routeros.switch
  bridge   = "bridge"
  tagged   = var.network_config.switch_allowed_ports
  untagged = [for s in var.servers : s.switch_port]
  vlan_ids = var.network_config.vlan
}

resource "routeros_ip_pool" "dhcp_pool" {
  name    = "${var.cluster_name}-pool"
  ranges  = ["${cidrhost(var.network_config.network, 0)}-${cidrhost(var.network_config.network, -1)}"]
  comment = var.cluster_name
}

resource "routeros_ip_dhcp_server" "vlan_dhcp" {
  address_pool  = routeros_ip_pool.dhcp_pool.name
  authoritative = "yes"
  disabled      = false
  interface     = routeros_interface_vlan.cluster-vlan-if.name
  name          = "${var.cluster_name}-dhcp-server"
}

resource "routeros_ip_dhcp_server_network" "dhcp_network" {
  address    = var.network_config.network
  gateway    = var.network_config.gateway
  dns_server = var.network_config.gateway
  comment    = "${var.cluster_name} network"
}

resource "routeros_ip_dhcp_server_lease" "servers_leases" {
  for_each    = { for i, v in var.servers : i => v }
  address     = cidrhost(var.network_config.network, each.key + 3)
  mac_address = each.value.mac_addr
  comment     = each.value.hostname
  server = routeros_ip_dhcp_server.vlan_dhcp.name
}

resource "routeros_ip_dns_record" "server_dns" {
  for_each = { for i, v in var.servers : i => v }
  name     = "${each.value.hostname}.${var.network_config.domain}"
  address  = cidrhost(var.network_config.network, each.key + 3)
  type     = "A"
}

resource "routeros_ip_dns_record" "cluster-record" {
  name    = var.cluster_endpoint
  address = cidrhost(var.network_config.network, 3)
  type    = "A"
}


resource "routeros_routing_bgp_connection" "metallb-bgp" {
  name = "${var.cluster_name}-peer"
  as   = var.network_config.bgp_router_as
  remote {
    address = cidrhost(var.network_config.network, 2)
    as      = var.network_config.bgp_cluster_as
  }
  connect = true
  listen  = true
  local {
    role = "ebgp"
    address = var.network_config.gateway
  }
}

#resource "mikrotik_bgp_instance" "instance" {
#  name      = "${var.cluster_name}-bgp"
#  as        = var.network_config.bgp_router_as
#  router_id = "0.0.0.0"
#}

#resource "mikrotik_bgp_peer" "cluster-bgp" {
#  name           = "${var.cluster_name}-peer"
#  remote_as      = var.network_config.bgp_cluster_as
#  remote_address = cidrhost(var.network_config.network, 2)
#  instance       = mikrotik_bgp_instance.instance.name
#}