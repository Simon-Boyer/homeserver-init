terraform {
  required_version = "~> 1.3"
  required_providers {
    talos = {
      source = "siderolabs/talos"
      version = "0.2.0"
    }
    xenorchestra = {
      source = "terra-farm/xenorchestra"
      version = "0.24.1"
    }
    http = {
      source = "hashicorp/http"
      version = "3.3.0"
    }
    macaddress = {
      source = "ivoronin/macaddress"
      version = "0.3.2"
    }
    mikrotik = {
      source = "ddelnano/mikrotik"
      version = "0.10.0"
    }
  }
}

// ------------
// MIKROTIK
// ------------

resource "mikrotik_pool" "bar" {
  name    = "dhcp-pool"
  ranges  = "10.10.10.100-10.10.10.200"
  comment = "Home devices"
}

resource "mikrotik_dhcp_server" "default" {
  address_pool  = mikrotik_pool.bar.name
  authoritative = "yes"
  disabled      = false
  interface     = "ether2"
  name          = "main-dhcp-server"
}

resource "mikrotik_dhcp_server_network" "default" {
  address    = "192.168.100.0/24"
  netmask    = "0" # use mask from address
  gateway    = "192.168.100.1"
  dns_server = "192.168.100.2"
  comment    = "Default DHCP server network"
}

resource "macaddress" "controlplanes" {
  for_each = var.node_data.controlplanes
  prefix = "00:16:3E"
}

resource "mikrotik_dhcp_lease" "controlplanes" {
  for_each = var.node_data.controlplanes
  address    = each.value.ip
  macaddress = macaddress.controlplanes[each.key]
  comment    = each.key
  blocked    = "false"
}

resource "macaddress" "workers" {
  for_each = var.node_data.workers
  prefix = "00:16:3E"
}

resource "mikrotik_dhcp_lease" "workers" {
  for_each = var.node_data.workers
  address    = each.value.ip
  macaddress = macaddress.workers[each.key]
  comment    = each.key
  blocked    = "false"
}

// ------------
// TALOS
// ------------

resource "talos_machine_secrets" "secrets" {}

data "talos_machine_configuration" "controlplane" {
    cluster_name = var.cluster_name
    cluster_endpoint = var.cluster_endpoint
    talos_version = var.talos_version
    machine_type = "controlplane"
    machine_secrets = talos_machine_secrets.secrets.machine_secrets
}

data "talos_machine_configuration" "worker" {
    cluster_name = var.cluster_name
    cluster_endpoint = var.cluster_endpoint
    talos_version = var.talos_version
    machine_type = "worker"
    machine_secrets = talos_machine_secrets.secrets.machine_secrets
}

# data "talos_client_configuration" "this" {
#   cluster_name         = var.cluster_name
#   client_configuration = talos_machine_secrets.this.client_configuration
#   endpoints            = [for k, v in var.node_data.controlplanes : k]
# }

resource "talos_machine_configuration_apply" "controlplane" {
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  for_each                    = var.node_data.controlplanes
  node                        = each.key
  config_patches = [
    templatefile("machine_config.yaml.tmpl", {
      hostname     = each.value.hostname == null ? format("%s-cp-%s", var.cluster_name, index(keys(var.node_data.controlplanes), each.key)) : each.value.hostname
      install_disk = each.value.install_disk
      certSANs = var.certSANs
      oidc-issuer-url = var.oidc-issuer-url
      oidc-client-id = var.oidc-client-id
    })
  ]
}

resource "talos_machine_configuration_apply" "worker" {
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  for_each                    = var.node_data.workers
  node                        = each.key
  config_patches = [
    templatefile("machine_config.yaml.tmpl", {
      hostname     = each.value.hostname == null ? format("%s-cp-%s", var.cluster_name, index(keys(var.node_data.controlplanes), each.key)) : each.value.hostname
      install_disk = each.value.install_disk
      certSANs = var.certSANs
      oidc-issuer-url = var.oidc-issuer-url
      oidc-client-id = var.oidc-client-id
    })
  ]
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.controlplane]
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = [for k, v in var.node_data.controlplanes : k][0]
}

data "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = [for k, v in var.node_data.controlplanes : k][0]
  wait                 = true
}

// ------------
// XEN
// ------------

data "xenorchestra_template" "other-template" {
  name_label = "Other install media"
}

resource "null_resource" "talos-iso" {
  triggers = {
    on_version_change = "${var.talos_version}"
  }

  provisioner "local-exec" {
    command = "curl -L -o talos.iso https://github.com/siderolabs/talos/releases/download/v${var.talos_version}/talos-amd64.iso"
  }
}

data "xenorchestra_sr" "iso_storage" {
  name_label = var.iso_sr_label
}

data "xenorchestra_network" "xen_network" {
  name_label = var.network_label
}

data "xenorchestra_pool" "pool" {
  name_label = var.xen_pool_name
}

data "xenorchestra_hosts" "pool" {
  pool_id = data.xenorchestra_pool.pool.id

  sort_by = "name_label"
  sort_order = "asc"
}

resource "xenorchestra_vdi" "talos-iso" {
  filepath = "talos.iso"
  depends_on = [ null_resource.talos-iso ]
  sr_id = data.xenorchestra_sr.iso_storage.id
}

resource "xenorchestra_vm" "controlplane" {
  for_each = var.node_data.controlplanes
  name_label = each.key
  template = data.xenorchestra_template.other-template.id
  network {
    network_id = data.xenorchestra_network.xen_network.id
    mac_address = mikrotik_dhcp_lease.controlplanes[each.key].macaddress
    attached = true
  }
  cdrom {
    id = xenorchestra_vdi.talos-iso.id
  }
  auto_poweron = true
  affinity_host = xenorchestra_hosts.pool.hosts[index(values(var.node_data.controlplanes), each.key) % length(xenorchestra_hosts.pool.hosts)]
}