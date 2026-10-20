"""
Habilita o papel dashboard_leitura para login, com senha gerada na hora.

O papel ja existe no banco (criado por sql/01_schema.sql) com permissao de
leitura apenas sobre o esquema publico, que e onde ficam as views com a
supressao de celulas menores que 5 pessoas. Este script so define a senha.

A senha vai para acesso-leitura.txt, na raiz do projeto, que esta no
.gitignore. Ela nao aparece na saida do script.

Uso:
  python etl/criar_acesso_leitura.py
  python etl/criar_acesso_leitura.py --revogar
"""
from __future__ import annotations

import argparse
import os
import secrets
import string
import sys
from pathlib import Path

import psycopg2
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / "acesso-leitura.txt"
PAPEL = "dashboard_leitura"

load_dotenv(ROOT / ".env")


def senha_forte(n: int = 24) -> str:
    alfabeto = string.ascii_letters + string.digits
    return "".join(secrets.choice(alfabeto) for _ in range(n))


def conecta():
    faltando = [v for v in ("PGHOST", "PGDATABASE", "PGUSER", "PGPASSWORD") if not os.getenv(v)]
    if faltando:
        sys.exit(f"Faltam variaveis no .env: {', '.join(faltando)}")
    return psycopg2.connect(
        host=os.getenv("PGHOST"), port=os.getenv("PGPORT", "5432"),
        dbname=os.getenv("PGDATABASE"), user=os.getenv("PGUSER"),
        password=os.getenv("PGPASSWORD"), sslmode=os.getenv("PGSSLMODE", "require"),
        connect_timeout=30)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--revogar", action="store_true", help="tira o login do papel")
    args = ap.parse_args()

    conn = conecta()
    cur = conn.cursor()

    if args.revogar:
        cur.execute(f"ALTER ROLE {PAPEL} WITH NOLOGIN")
        conn.commit()
        DEST.unlink(missing_ok=True)
        print(f"login removido de {PAPEL}; acesso-leitura.txt apagado")
        conn.close()
        return

    senha = senha_forte()
    cur.execute(f"ALTER ROLE {PAPEL} WITH LOGIN PASSWORD %s", (senha,))
    # Garante a leitura tambem no que for criado depois.
    cur.execute(f"GRANT USAGE ON SCHEMA publico TO {PAPEL}")
    cur.execute(f"GRANT SELECT ON ALL TABLES IN SCHEMA publico TO {PAPEL}")
    cur.execute(f"ALTER DEFAULT PRIVILEGES IN SCHEMA publico GRANT SELECT ON TABLES TO {PAPEL}")
    conn.commit()

    cur.execute("SELECT table_name FROM information_schema.tables "
                "WHERE table_schema='publico' ORDER BY 1")
    views = [r[0] for r in cur.fetchall()]

    DEST.write_text(
        "Acesso somente-leitura ao banco do projeto\n"
        "==========================================\n\n"
        f"Host:     {os.getenv('PGHOST')}\n"
        f"Porta:    {os.getenv('PGPORT')}\n"
        f"Banco:    {os.getenv('PGDATABASE')}\n"
        f"Usuario:  {PAPEL}\n"
        f"Senha:    {senha}\n"
        "SSL:      obrigatorio (sslmode=require)\n\n"
        "String de conexao:\n"
        f"postgresql://{PAPEL}:{senha}@{os.getenv('PGHOST')}:{os.getenv('PGPORT')}"
        f"/{os.getenv('PGDATABASE')}?sslmode=require\n\n"
        "Este usuario so le as views do esquema publico, que ja aplicam a\n"
        "supressao de combinacoes com menos de 5 pessoas. Ele nao enxerga o\n"
        "esquema dw e nao altera nada.\n\n"
        "Views disponiveis:\n" + "".join(f"  publico.{v}\n" for v in views) +
        "\nAs consultas de exemplo estao em sql/02_consultas_exemplo.sql.\n"
        "Para tirar este acesso: python etl/criar_acesso_leitura.py --revogar\n",
        encoding="utf-8")

    print(f"login habilitado para {PAPEL}")
    print(f"{len(views)} views liberadas: {', '.join(views)}")
    print(f"dados de conexao em {DEST.relative_to(ROOT)} (fora do repositorio)")
    conn.close()


if __name__ == "__main__":
    main()
