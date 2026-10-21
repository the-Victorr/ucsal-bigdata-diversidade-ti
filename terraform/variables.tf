variable "aiven_api_token" {
  description = "Token da API do Aiven. Vem da variavel de ambiente TF_VAR_aiven_api_token e nunca do arquivo versionado."
  type        = string
  sensitive   = true
}

variable "aiven_project" {
  description = "Nome do projeto na conta do Aiven. No Marco 2: ucsal-bigdata-2026."
  type        = string
}

variable "service_name" {
  description = "Nome do servico PostgreSQL."
  type        = string
  default     = "ti-diversidade-pg"
}

variable "cloud_name" {
  description = "Provedor e regiao, no formato do Aiven. O servico do projeto esta em do-sfo (DigitalOcean, San Francisco)."
  type        = string
  default     = "do-sfo"
}

variable "plan" {
  description = "Plano do servico. free-1-1gb e o nivel gratuito: 1 CPU, 1 GB de RAM e 1 GB de armazenamento."
  type        = string
  default     = "free-1-1gb"
}

variable "pg_version" {
  description = "Versao do PostgreSQL. O servico do projeto roda a 18."
  type        = string
  default     = "18"
}

variable "database_name" {
  description = "Nome do banco logico criado dentro do servico."
  type        = string
  default     = "diversidade_ti"
}
