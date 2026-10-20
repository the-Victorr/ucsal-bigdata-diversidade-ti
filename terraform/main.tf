# Provisiona o banco de dados do projeto no Aiven.
#
# O estado atual do servico foi criado pelo painel durante o Marco 2 e este
# codigo reproduz a mesma configuracao. Para recriar do zero em outra conta:
#   export TF_VAR_aiven_api_token=...   (nunca commitar o valor)
#   export TF_VAR_aiven_project=...
#   terraform init && terraform apply

terraform {
  required_version = ">= 1.5"
  required_providers {
    aiven = {
      source  = "aiven/aiven"
      version = "~> 4.0"
    }
  }
}

provider "aiven" {
  api_token = var.aiven_api_token
}

resource "aiven_pg" "banco" {
  project      = var.aiven_project
  service_name = var.service_name
  cloud_name   = var.cloud_name
  plan         = var.plan

  maintenance_window_dow  = "tuesday"
  maintenance_window_time = "22:00:59"

  pg_user_config {
    pg_version = var.pg_version

    # O ETL roda da maquina da equipe e o painel de visualizacao rodara em
    # servico externo, entao o banco precisa de acesso pela internet publica.
    public_access {
      pg = true
    }
  }
}

# Banco logico dentro do servico. O Aiven ja cria o 'defaultdb', usado na carga
# do Marco 2; este recurso deixa explicito o banco proprio do projeto.
resource "aiven_pg_database" "projeto" {
  project       = var.aiven_project
  service_name  = aiven_pg.banco.service_name
  database_name = var.database_name
}
