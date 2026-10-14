variable "aiven_api_token" {
  description = "Token da API do Aiven. Vem da variável de ambiente TF_VAR_aiven_api_token."
  type        = string
  sensitive   = true
}

variable "aiven_project" {
  description = "Nome do projeto no Aiven."
  type        = string
}

variable "service_name" {
  description = "Nome do serviço PostgreSQL."
  type        = string
  default     = "ti-diversidade-pg"
}

variable "cloud_name" {
  description = "Região. google-southamerica-east1 é São Paulo."
  type        = string
  default     = "google-southamerica-east1"
}

variable "database_name" {
  description = "Nome do banco criado dentro do serviço."
  type        = string
  default     = "diversidade_ti"
}
