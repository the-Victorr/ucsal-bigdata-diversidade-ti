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
  description = "Provedor e regiao. O servico do projeto esta em digitalocean-sfo."
  type        = string
  default     = "digitalocean-sfo"
}

variable "plan" {
  description = "Plano do servico. free-1-5gb e o nivel gratuito, com 1 GB de armazenamento."
  type        = string
  default     = "free-1-5gb"
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
