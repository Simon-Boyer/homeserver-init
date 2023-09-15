terraform {
  required_version = "~> 1.3"
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.2.0"
    }
    xenorchestra = {
      source  = "terra-farm/xenorchestra"
      version = "0.24.1"
    }
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
    }
    local = {
      source  = "hashicorp/local"
      version = "2.4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.23.0"
    }
  }
}

provider "kubernetes" {
  config_path = "${var.cluster_name}.kubeconfig.yaml"
}

provider "routeros" {
  hosturl  = "https://${var.router_host}" # Or set MIKROTIK_HOST environment variable
  username = var.router_host              # Or set MIKROTIK_USER environment variable
  password = var.router_password          # Or set MIKROTIK_PASSWORD environment variable
  insecure = true                         # Or set MIKROTIK_INSECURE environment variable
}

provider "routeros" {
  alias    = "switch"
  hosturl  = "https://${var.switch_host}" # Or set MIKROTIK_HOST environment variable
  username = var.switch_host              # Or set MIKROTIK_USER environment variable
  password = var.switch_password          # Or set MIKROTIK_PASSWORD environment variable
  insecure = true                         # Or set MIKROTIK_INSECURE environment variable
}


locals {
  certSANs = concat(routeros_ip_dns_record.server_dns[*].name, var.cluster_endpoint)
}

// ------------
// MIKROTIK
// ------------


resource "routeros_interface_bridge_port" "eth2port" {
  provider  = routeros.switch
  bridge    = "bridge"
  for_each  = toset(var.servers)
  interface = each.value.switch_port
  pvid      = var.vlan
}

resource "routeros_interface_vlan" "cluster-vlan-if" {
  interface = "bridge"
  mtu       = 1500
  name      = "vlan-${var.vlan}-if"
  vlan_id   = var.vlan
}

resource "routeros_ip_address" "lan" {
  address   = "${cidrhost(var.network_config.network, 1)}/${split("/", var.network_config.network)[1]}"
  comment   = "${var.cluster_name} Network"
  interface = routeros_interface_vlan.cluster-vlan-if.name
}

resource "routeros_bridge_vlan" "cluster-vlan" {
  bridge   = "bridge"
  tagged   = ["vlan-${var.vlan}-if"]
  untagged = [for s in var.servers : s.port]
  vlan_ids = var.vlan
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
  dns_server = var.network_config.dns
  comment    = "${var.cluster_name} network"
}

resource "routeros_ip_dhcp_server_lease" "servers_leases" {
  for_each    = { for i, v in var.servers : i => v }
  address     = cidrhost(var.network_config.network, each.key + 3)
  mac_address = each.value.mac_addr
  comment     = each.value.hostname
}

resource "routeros_ip_dns_record" "server_dns" {
  for_each = toset(routeros_ip_dhcp_server_lease.servers_leases)
  name     = "${each.value.comment}.${var.network_config.domain}"
  address  = each.value.address
  type     = "A"
}

resource "routeros_ip_dns_record" "cluster-record" {
  name    = var.cluster_endpoint
  address = cidrhost(var.network_config.network, 2)
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

// ------------
// TALOS
// ------------

resource "talos_machine_secrets" "secrets" {}

data "talos_machine_configuration" "controlplane" {
  cluster_name     = var.cluster_name
  cluster_endpoint = var.cluster_endpoint
  talos_version    = var.talos_version
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.secrets.machine_secrets
}

data "talos_machine_configuration" "worker" {
  cluster_name     = var.cluster_name
  cluster_endpoint = var.cluster_endpoint
  talos_version    = var.talos_version
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.secrets.machine_secrets
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.secrets.client_configuration
  endpoints            = [var.cluster_endpoint]
}

resource "talos_machine_configuration_apply" "controlplanes" {
  for_each                    = { for s in var.servers : s => s if s.controlplane }
  client_configuration        = talos_machine_secrets.secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = "${each.value.hostname}.${var.network_config.domain}"
  config_patches = [
    templatefile("machine_config.yaml.tmpl", {
      hostname        = "${each.value.hostname}.${var.network_config.domain}"
      install_disk    = each.value.install_disk
      certSANs        = local.certSANs
      oidc-issuer-url = var.oidc-issuer-url
      oidc-client-id  = var.oidc-client-id
    })
  ]
}

resource "talos_machine_configuration_apply" "workers" {
  for_each                    = { for s in var.servers : s => s if !s.controlplane }
  client_configuration        = talos_machine_secrets.secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = "${each.value.hostname}.${var.network_config.domain}"
  config_patches = [
    templatefile("machine_config.yaml.tmpl", {
      hostname        = "${each.value.hostname}.${var.network_config.domain}"
      install_disk    = each.value.install_disk
      certSANs        = local.certSANs
      oidc-issuer-url = var.oidc-issuer-url
      oidc-client-id  = var.oidc-client-id
    })
  ]
}


resource "talos_machine_bootstrap" "bootstrap" {
  depends_on           = [talos_machine_configuration_apply.controlplanes]
  client_configuration = talos_machine_secrets.secrets.client_configuration
  node                 = talos_machine_configuration_apply.controlplanes
}

data "talos_cluster_kubeconfig" "kubeconfig" {
  client_configuration = talos_machine_secrets.secrets.client_configuration
  node                 = talos_machine_configuration_apply.controlplanes[0].node
  wait                 = true
}

resource "local_file" "kubeconfig" {
  filename = "${var.cluster_name}.kubeconfig.yaml"
  content  = data.talos_cluster_kubeconfig.kubeconfig.kubeconfig_raw
}

// ------------
// MetalLB
// ------------

resource "terraform_data" "install_olm" {
  provisioner "local-exec" {
    command = <<-EOF
    export KUBECONFIG="${var.cluster_name}.kubeconfig.yaml"
    curl -sL https://github.com/operator-framework/operator-lifecycle-manager/releases/download/v0.25.0/install.sh | bash -s v0.25.0
EOF
  }

  depends_on = [
    local_file.kubeconfig
  ]
}


resource "kubernetes_manifest" "metallb_operator" {
  manifest = {
    "apiVersion" = "operators.coreos.com/v1alpha1"
    "kind"       = "Subscription"
    "metadata" = {
      "name"      = "metallb-operator"
      "namespace" = "operators"
    }
    "spec" = {
      "channel"         = "beta"
      "name"            = "metallb-operator"
      "source"          = "operatorhubio-catalog"
      "sourceNamespace" = "olm"
    }
  }
  depends_on = [
    terraform_data.install_olm
  ]
}

resource "kubernetes_manifest" "metallb_bgp_peer" {
  manifest = {
    "apiVersion" = "metallb.io/v1beta2"
    "kind"       = "BGPPeer"
    "metadata" = {
      "name"      = "router"
      "namespace" = "metallb-system"
    }
    "spec" = {
      "myASN"       = 64500
      "peerASN"     = 65530
      "peerAddress" = cidrhost(var.network_config.network, 1)
    }
  }
  depends_on = [
    kubernetes_manifest.metallb_operator
  ]
}
