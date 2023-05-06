module "sandbox-cluster" {
  source = "../"
  cluster_name = "sandbox"
  cluster_endpoint = "sandbox.codegameeat.com"
  talos_version = "1.4.0"
  disks_sr_id = "74720acf-dc07-4dae-9602-e9397a1a2974"
  iso_sr_id = "28d66416-ae15-402f-8ecd-2f0be8e0910a"
  network_id = "207e7703-5fae-4cd4-8b07-6e93e7f8c53d"
  xen_pool_id = "c04f50bb-a479-4098-b4f6-123f8b335beb"
  oidc-client-id = "SOME_ID"
  oidc-issuer-url = "https://accounts.google.com"
  subnet = "10.0.1.0/24"
  controlplane = {
    cpus = 1
    disk_gb = 20
    memory_max = 4
    nb_vms = 3
  }
  worker = {
    cpus = 2
    disk_gb = 40
    memory_max = 12
    nb_vms = 3
  }
}

