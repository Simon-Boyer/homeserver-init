module "mikrotik" {
    source = "./mikrotik"
    providers = {
      routeros = routeros
      routeros.switch = routeros.switch
    }

    cluster_endpoint = var.cluster_endpoint
    cluster_name = var.cluster_name
    network_config = var.network_config
    router_host = var.router_host
    router_password = var.router_password
    router_user = var.router_user
    switch_host = var.switch_host
    switch_password = var.switch_password
    switch_user = var.switch_user
    servers = var.servers
}

module "talos" {
    source = "./talos"
    cluster_endpoint = var.cluster_endpoint
    cluster_name = var.cluster_name
    oidc-client-id = var.oidc-client-id
    oidc-client-secret = var.oidc-client-secret
    oidc-issuer-url = var.oidc-issuer-url
    talos_version = var.talos_version
    servers = var.servers
    servers_dns = module.mikrotik.servers_dns
    network_config = var.network_config

    depends_on = [ module.mikrotik ]
}

module "helm" {
    source = "./helm"
    argocd_version = var.argocd_version
    argocd_password = var.argocd_password
    contour_version = var.contour_version
    metallb_version = var.metallb_version
    network_config = var.network_config
    git_repo = var.git_repo
    
    depends_on = [ module.talos ]
}


output "kubeconfig" {
  value = module.talos.kubeconfig
  sensitive = true
}