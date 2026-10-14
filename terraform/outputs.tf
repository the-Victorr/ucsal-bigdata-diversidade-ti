output "host" {
  value = aiven_pg.banco.service_host
}

output "porta" {
  value = aiven_pg.banco.service_port
}

output "usuario" {
  value     = aiven_pg.banco.service_username
  sensitive = true
}

output "senha" {
  value     = aiven_pg.banco.service_password
  sensitive = true
}

output "service_uri" {
  description = "String de conexão completa. Use para preencher o .env."
  value       = aiven_pg.banco.service_uri
  sensitive   = true
}
