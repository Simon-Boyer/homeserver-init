cluster_name     = "kubernetes"
cluster_endpoint = "kubernetes.servers.lan"

network_config = {
  bgp_cluster_as = 64500
  bgp_router_as = 65530
  domain = "servers.lan"
  gateway = "192.168.10.1"
  network = "192.168.10.0/24"
  vlan = 100
  switch_allowed_ports = [ "sfp-sfpplus3", "sfp-sfpplus5" ]
  router_downlink = "sfp-sfpplus1"
}

servers = [{
  controlplane = true
  hostname     = "talos-01"
  install_disk = "/pci0000:00/0000:00:01.1"
  mac_addr     = "90:E2:BA:38:7D:BF"
  switch_port = "sfp-sfpplus2"
}]

metallb_version = "0.13.12"
argocd_version = "5.46.8"
contour_version = "1.26"

oidc-client-id = "249011382126-88j8gt5r4h1q7uktj4qufrjqd2uc12pq.apps.googleusercontent.com"
oidc-issuer-url = "https://accounts.google.com"

router_host = "192.168.88.1"
router_user = "admin"
switch_host = "192.168.88.235"
switch_user = "admin"

talos_version = "v1.5.4"

tfc_org = "Simon-Boyer"
tfc_workspace = "homelab"
git_repo = "https://github.com/Simon-Boyer/homeserver-init"