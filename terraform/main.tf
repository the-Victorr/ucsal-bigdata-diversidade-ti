# Provisiona o PostgreSQL do projeto no Aiven (plano gratuito).
# Uso:
#   export TF_VAR_aiven_api_token=...   (nunca commitar)
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
  project                 = var.aiven_project
  service_name            = var.service_name
  cloud_name              = var.cloud_name
  plan                    = "free-1-5gb"
  maintenance_window_dow  = "sunday"
  maintenance_window_time = "04:00:00"

  pg_user_config {
    pg_version = "16"

    public_access {
      pg = true
    }
  }
}

resource "aiven_pg_database" "ti" {
  project       = var.aiven_project
  service_name  = aiven_pg.banco.service_name
  database_name = var.database_name
}
