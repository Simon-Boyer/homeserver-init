output "servers_dns" {
  value = concat([ for s in var.servers : "${s.hostname}.${var.network_config.domain}" ], [var.cluster_endpoint])
}