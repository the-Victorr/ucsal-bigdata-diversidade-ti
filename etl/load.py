"""
Carga dos dados tratados no PostgreSQL (Aiven).

Lê a conexão do .env (nunca de credencial no código), cria o schema a partir
de sql/01_schema.sql, popula as dimensões e carrega os fatos via COPY.

Uso:
  python etl/load.py --schema          # cria tabelas e seeds
  python etl/load.py --fatos           # carrega os fatos
  python etl/load.py --schema --fatos  # tudo
  python etl/load.py --stats           # tamanho e contagem do que está lá
"""
from __future__ import annotations

import argparse
import io
import os
import sys
from pathlib import Path

import pandas as pd
import psycopg2
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent.parent
CURATED = ROOT / "data" / "curated"
SQL = ROOT / "sql"

load_dotenv(ROOT / ".env")


def conecta():
    faltando = [v for v in ("PGHOST", "PGDATABASE", "PGUSER", "PGPASSWORD") if not os.getenv(v)]
    if faltando:
        sys.exit(f"Faltam variáveis no .env: {', '.join(faltando)}. Use .env.example como base.")
    return psycopg2.connect(
        host=os.getenv("PGHOST"),
        port=os.getenv("PGPORT", "5432"),
        dbname=os.getenv("PGDATABASE"),
        user=os.getenv("PGUSER"),
        password=os.getenv("PGPASSWORD"),
        sslmode=os.getenv("PGSSLMODE", "require"),
    )


def roda_schema(conn) -> None:
    for arquivo in sorted(SQL.glob("*.sql")):
        print(f"  executando {arquivo.name}")
        # Meta-comandos do psql (\set, \echo) não existem no protocolo do driver.
        sql = "\n".join(l for l in arquivo.read_text(encoding="utf-8").splitlines()
                         if not l.lstrip().startswith("\\"))
        with conn.cursor() as cur:
            cur.execute(sql)
    conn.commit()
    print("  schema criado")


def copia(conn, df: pd.DataFrame, tabela: str, truncar: bool = True) -> None:
    """Carrega um DataFrame via COPY, que é muito mais rápido que INSERT."""
    buf = io.StringIO()
    df.to_csv(buf, index=False, header=False, na_rep="\\N")
    buf.seek(0)
    cols = ", ".join(f'"{c}"' for c in df.columns)
    with conn.cursor() as cur:
        if truncar:
            cur.execute(f"TRUNCATE {tabela} CASCADE")
        cur.copy_expert(f"COPY {tabela} ({cols}) FROM STDIN WITH (FORMAT csv, NULL '\\N')", buf)
    conn.commit()


# O agregado sai do ETL com os códigos naturais (sexo 2, UF "29", CNAE "6204000").
# O fato guarda chaves surrogate. A tradução é feita aqui, por JOIN, para que
# um código fora do domínio quebre a carga em vez de entrar silenciosamente.
INSERT_VINCULO = """
INSERT INTO dw.fato_vinculo_ti (
    tempo_id, uf_id, setor_id, nivel_lideranca_id, sexo_id, raca_cor_id,
    faixa_etaria_id, escolaridade_id, qtd_vinculos, qtd_com_remuneracao,
    soma_remuneracao, media_remuneracao, mediana_remuneracao, p25_remuneracao,
    p75_remuneracao, soma_horas_contratuais, media_horas_contratuais,
    soma_tempo_emprego, media_tempo_emprego)
SELECT t.tempo_id, u.uf_id, s.setor_id, n.nivel_lideranca_id, sx.sexo_id,
       r.raca_cor_id, f.faixa_etaria_id, e.escolaridade_id,
       g.qtd_vinculos::integer, g.qtd_com_remuneracao::integer, g.soma_remuneracao::numeric,
       g.media_remuneracao::numeric, g.mediana_remuneracao::numeric, g.p25_remuneracao::numeric,
       g.p75_remuneracao::numeric, g.soma_horas_contratuais::integer, g.media_horas_contratuais::numeric,
       g.soma_tempo_emprego::numeric, g.media_tempo_emprego::numeric
  FROM stg_vinculo g
  JOIN dw.dim_tempo            t  ON t.ano = g.ano::smallint AND t.eh_dezembro
  JOIN dw.dim_uf               u  ON u.uf_codigo = g.uf
  JOIN dw.dim_setor            s  ON s.cnae_subclasse = g.cnae_subclasse
  JOIN dw.dim_nivel_lideranca  n  ON n.nivel_lideranca_codigo = g.nivel_lideranca::smallint
  JOIN dw.dim_sexo             sx ON sx.sexo_codigo = g.sexo::smallint
  JOIN dw.dim_raca_cor         r  ON r.raca_cor_codigo = g.raca_cor::smallint
  JOIN dw.dim_faixa_etaria     f  ON f.faixa_etaria_codigo = g.faixa_etaria::smallint
  JOIN dw.dim_escolaridade     e  ON e.escolaridade_codigo = g.escolaridade::smallint
"""

INSERT_MOVIMENTACAO = """
INSERT INTO dw.fato_movimentacao_ti (
    tempo_id, uf_id, setor_id, nivel_lideranca_id, sexo_id, raca_cor_id,
    faixa_etaria_id, escolaridade_id, admissoes, desligamentos, saldo,
    qtd_admissoes_com_sal, soma_salario_admissao, media_salario_admissao)
SELECT t.tempo_id, u.uf_id, s.setor_id, n.nivel_lideranca_id, sx.sexo_id,
       r.raca_cor_id, f.faixa_etaria_id, e.escolaridade_id,
       g.admissoes::integer, g.desligamentos::integer, g.saldo::integer, g.qtd_admissoes_com_sal::integer,
       g.soma_salario_admissao::numeric, g.media_salario_admissao::numeric
  FROM stg_movimentacao g
  JOIN dw.dim_tempo            t  ON t.data_competencia = g.competencia::date
  JOIN dw.dim_uf               u  ON u.uf_codigo = g.uf
  JOIN dw.dim_setor            s  ON s.cnae_subclasse = g.cnae_subclasse
  JOIN dw.dim_nivel_lideranca  n  ON n.nivel_lideranca_codigo = g.nivel_lideranca::smallint
  JOIN dw.dim_sexo             sx ON sx.sexo_codigo = g.sexo::smallint
  JOIN dw.dim_raca_cor         r  ON r.raca_cor_codigo = g.raca_cor::smallint
  JOIN dw.dim_faixa_etaria     f  ON f.faixa_etaria_codigo = g.faixa_etaria::smallint
  JOIN dw.dim_escolaridade     e  ON e.escolaridade_codigo = g.escolaridade::smallint
"""


def carrega_fatos(conn) -> None:
    jobs = [
        ("fato_vinculo_ti", "stg_vinculo", "dw.fato_vinculo_ti", INSERT_VINCULO),
        ("fato_movimentacao_ti", "stg_movimentacao", "dw.fato_movimentacao_ti", INSERT_MOVIMENTACAO),
    ]
    for arquivo, staging, fato, insert in jobs:
        p = CURATED / f"{arquivo}.parquet"
        if not p.exists():
            print(f"  (pulando {arquivo}: arquivo não existe)")
            continue
        df = pd.read_parquet(p)

        cols = ", ".join(f'"{c}" TEXT' for c in df.columns)
        with conn.cursor() as cur:
            cur.execute(f"DROP TABLE IF EXISTS {staging}")
            cur.execute(f"CREATE TEMP TABLE {staging} ({cols})")
        conn.commit()

        copia(conn, df, staging, truncar=False)

        with conn.cursor() as cur:
            cur.execute(f"TRUNCATE {fato}")
            cur.execute(insert)
            inseridas = cur.rowcount
            cur.execute(f"SELECT count(*) FROM {staging}")
            no_staging = cur.fetchone()[0]
        conn.commit()

        print(f"  {fato}: {inseridas:,} linhas")
        if inseridas != no_staging:
            print(f"  ATENÇÃO: {no_staging - inseridas:,} linhas não casaram com as dimensões")


def stats(conn) -> None:
    with conn.cursor() as cur:
        cur.execute("SELECT pg_size_pretty(pg_database_size(current_database()))")
        print(f"  tamanho do banco: {cur.fetchone()[0]}")
        cur.execute("""
            SELECT relname, n_live_tup,
                   pg_size_pretty(pg_total_relation_size(relid))
              FROM pg_stat_user_tables
             ORDER BY pg_total_relation_size(relid) DESC
        """)
        print(f"  {'tabela':<32} {'linhas':>12}  tamanho")
        for nome, linhas, tam in cur.fetchall():
            print(f"  {nome:<32} {linhas:>12,}  {tam}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--schema", action="store_true")
    ap.add_argument("--fatos", action="store_true")
    ap.add_argument("--stats", action="store_true")
    args = ap.parse_args()
    if not any((args.schema, args.fatos, args.stats)):
        ap.error("escolha --schema, --fatos ou --stats")

    conn = conecta()
    try:
        if args.schema:
            roda_schema(conn)
        if args.fatos:
            carrega_fatos(conn)
        if args.stats:
            stats(conn)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
