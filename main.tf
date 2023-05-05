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
  count = var.controlplane.nb_vms
  prefix = [0, 22, 62]
}

resource "mikrotik_dhcp_lease" "controlplanes" {
  count = var.controlplane.nb_vms
  address    = var.controlplane.start_ip + count.index
  macaddress = macaddress.controlplanes[count.index].address
  comment    = format("%s-cp-%s", var.cluster_name, count.index)
  blocked    = "false"
}

resource "macaddress" "workers" {
  count = var.worker.nb_vms
  prefix = [0, 22, 62]
}

resource "mikrotik_dhcp_lease" "workers" {
  count = var.worker.nb_vms
  address    = var.worker.start_ip + count.index
  macaddress = macaddress.workers[count.index].address
  comment    = format("%s-worker-%s", var.cluster_name, count.index)
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
  count                       = var.controlplane.nb_vms
  client_configuration        = talos_machine_secrets.secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = format("%s-cp-%s", var.cluster_name, count.index)
  config_patches = [
    templatefile("machine_config.yaml.tmpl", {
      hostname     = format("%s-cp-%s", var.cluster_name, count.index)
      install_disk = "/dev/xvda"
      certSANs = var.certSANs
      oidc-issuer-url = var.oidc-issuer-url
      oidc-client-id = var.oidc-client-id
    })
  ]
}

resource "talos_machine_configuration_apply" "worker" {
  count                       = var.worker.nb_vms
  client_configuration        = talos_machine_secrets.secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = format("%s-cp-%s", var.cluster_name, count.index)
  config_patches = [
    templatefile("machine_config.yaml.tmpl", {
      hostname     = format("%s-worker-%s", var.cluster_name, count.index)
      install_disk = "/dev/xvda"
      certSANs = var.certSANs
      oidc-issuer-url = var.oidc-issuer-url
      oidc-client-id = var.oidc-client-id
    })
  ]
}

resource "talos_machine_bootstrap" "bootstrap" {
  depends_on = [talos_machine_configuration_apply.controlplane]
  client_configuration = talos_machine_secrets.secrets.client_configuration
  node                 = talos_machine_configuration_apply.controlplane[0].node
}

data "talos_cluster_kubeconfig" "kubeconfig" {
  client_configuration = talos_machine_secrets.secrets.client_configuration
  node                 = talos_machine_configuration_apply.controlplane[0].node
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
    command = "curl -L -o talos.iso ${var.talos_repo}/releases/download/v${var.talos_version}/talos-amd64.iso"
  }
}

data "xenorchestra_sr" "iso_storage" {
  name_label = var.iso_sr_label
}

data "xenorchestra_sr" "disks_storage" {
  name_label = var.disks_sr_label
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
  name_label = "talos-${var.talos_version}.iso"
  type = "raw"
}

resource "xenorchestra_vm" "controlplane" {
  count = var.controlplane.nb_vms
  name_label = format("%s-cp-%s", var.cluster_name, count.index)
  template = data.xenorchestra_template.other-template.id
  network {
    network_id = data.xenorchestra_network.xen_network.id
    mac_address = mikrotik_dhcp_lease.controlplanes[count.index].macaddress
    attached = true
  }
  cdrom {
    id = xenorchestra_vdi.talos-iso.id
  }
  disk {
    attached = true
    name_label = "talos"
    size = 53687091200 //50GB
    sr_id = data.xenorchestra_sr.disks_storage
  }
  cpus = var.controlplane.cpus
  memory_max = var.controlplane.memory_max
  auto_poweron = true
  affinity_host = data.xenorchestra_hosts.pool.hosts[count.index % length(data.xenorchestra_hosts.pool.hosts)]
}

resource "xenorchestra_vm" "worker" {
  count = var.worker.nb_vms
  name_label = format("%s-worker-%s", var.cluster_name, count.index)
  template = data.xenorchestra_template.other-template.id
  network {
    network_id = data.xenorchestra_network.xen_network.id
    mac_address = mikrotik_dhcp_lease.workers[count.index].macaddress
    attached = true
  }
  cdrom {
    id = xenorchestra_vdi.talos-iso.id
  }
  disk {
    attached = true
    name_label = "talos"
    size = 53687091200 //50GB
    sr_id = data.xenorchestra_sr.disks_storage
  }
  cpus = var.worker.cpus
  memory_max = var.worker.memory_max
  auto_poweron = true
  affinity_host = data.xenorchestra_hosts.pool.hosts[count.index % length(data.xenorchestra_hosts.pool.hosts)]
}