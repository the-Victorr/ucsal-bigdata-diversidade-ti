output "host" {
  description = "Endereco do servico, usado em PGHOST."
  value       = aiven_pg.banco.service_host
}

output "porta" {
  description = "Porta do servico, usada em PGPORT."
  value       = aiven_pg.banco.service_port
}

output "usuario" {
  description = "Usuario administrador criado pelo Aiven."
  value       = aiven_pg.banco.service_username
  sensitive   = true
}

output "senha" {
  description = "Senha do administrador. Marcada como sensivel para nao aparecer no log do apply."
  value       = aiven_pg.banco.service_password
  sensitive   = true
}

output "service_uri" {
  description = "String de conexao completa. Use 'terraform output -raw service_uri' para preencher o .env."
  value       = aiven_pg.banco.service_uri
  sensitive   = true
}
