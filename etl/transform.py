"""
Tratamento dos microdados de TI: limpeza, tipagem, harmonização e agregação.

Entra: Parquet filtrado por etl/extract_filter.py (só CNAE 62/63, ainda cru).
Sai:   Parquet agregado, pronto para carga no PostgreSQL.

O que é feito aqui:
  1. padroniza nomes de coluna entre os layouts da RAIS;
  2. converte texto -> número, respeitando vírgula ou ponto decimal;
  3. troca os marcadores de ausência (9997, {ñ class}, ...) por nulo;
  4. harmoniza sexo, raça/cor e escolaridade entre RAIS e CAGED;
  5. deriva nível de liderança, UF e divisão CNAE;
  6. remove duplicatas e registros sem informação essencial;
  7. agrega, porque o banco tem 1 GB e não guardamos linha por pessoa.

Uso:
  python etl/transform.py rais  data/processed/rais/2025/*.parquet
  python etl/transform.py caged data/processed/caged/2025/*.parquet
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).parent))
from dominios import (ESCOLARIDADE_CAGED, NULOS, RACA_CAGED, RACA_RAIS,  # noqa: E402
                      SEXO_CAGED, SEXO_RAIS, faixa_etaria_de_idade, nivel_lideranca)

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "curated"

# Nome na origem -> nome padronizado. Cobre os três layouts da RAIS.
COLS_RAIS = {
    "CBO 2002 Ocupação - Código": "cbo", "CBO Ocupação 2002": "cbo",
    "CNAE 2.0 Subclasse - Codigo": "cnae_subclasse", "CNAE 2.0 Subclasse": "cnae_subclasse",
    "Município - Código": "municipio", "Município": "municipio",
    "Sexo - Código": "sexo", "Sexo Trabalhador": "sexo",
    "Raça Cor - Código": "raca_cor", "Raça Cor": "raca_cor",
    "Faixa Etária - Código": "faixa_etaria", "Faixa Etária": "faixa_etaria",
    "Escolaridade Após 2005 - Código": "escolaridade", "Escolaridade após 2005": "escolaridade",
    "Vl Rem Média Nom": "remuneracao", "Vl Remun Média Nom": "remuneracao",
    "Qtd Hora Contr": "horas_contratuais",
    "Tempo Emprego": "tempo_emprego",
    "Idade": "idade",
    "Ind Vínculo Ativo 31/12 - Código": "vinculo_ativo", "Vínculo Ativo 31/12": "vinculo_ativo",
}

COLS_CAGED = {
    "competênciamov": "competencia", "município": "municipio", "subclasse": "cnae_subclasse",
    "cbo2002ocupação": "cbo", "graudeinstrução": "escolaridade", "idade": "idade",
    "horascontratuais": "horas_contratuais", "raçacor": "raca_cor", "sexo": "sexo",
    "salário": "salario", "saldomovimentação": "saldo", "uf": "uf_cod",
}


def limpa_texto(s: pd.Series) -> pd.Series:
    """Tira espaços e troca os marcadores de ausência por nulo."""
    out = s.astype(str).str.strip()
    return out.where(~out.str.lower().isin({v.lower() for v in NULOS}), None)


def para_numero(s: pd.Series, decimal: str) -> pd.Series:
    """Converte texto monetário para float. decimal é ',' ou '.'."""
    t = limpa_texto(s)
    if decimal == ",":
        t = t.str.replace(".", "", regex=False).str.replace(",", ".", regex=False)
    return pd.to_numeric(t, errors="coerce")


def para_codigo(s: pd.Series, largura: int) -> pd.Series:
    """Mantém código como texto, com zero à esquerda. Nunca vira int."""
    t = limpa_texto(s)
    return t.str.replace(r"\D", "", regex=True).str.zfill(largura).where(t.notna())


# --------------------------------------------------------------------- RAIS
def trata_rais(df: pd.DataFrame) -> pd.DataFrame:
    ano = int(df["ano"].iloc[0])
    layout = df["layout"].iloc[0]
    decimal = "." if layout == "regiao_2023" else ","

    df = df.rename(columns={k: v for k, v in COLS_RAIS.items() if k in df.columns})
    d = pd.DataFrame(index=df.index)
    d["ano"] = ano
    d["cbo"] = para_codigo(df["cbo"], 6)
    d["cnae_subclasse"] = para_codigo(df["cnae_subclasse"], 7)
    d["municipio"] = para_codigo(df["municipio"], 6)
    d["sexo"] = limpa_texto(df["sexo"]).str.lstrip("0").map(SEXO_RAIS)
    d["raca_cor"] = limpa_texto(df["raca_cor"]).str.lstrip("0").map(RACA_RAIS)
    d["faixa_etaria"] = pd.to_numeric(limpa_texto(df["faixa_etaria"]), errors="coerce")
    d["escolaridade"] = pd.to_numeric(limpa_texto(df["escolaridade"]), errors="coerce")
    d["remuneracao"] = para_numero(df["remuneracao"], decimal)
    d["horas_contratuais"] = pd.to_numeric(limpa_texto(df["horas_contratuais"]), errors="coerce")
    d["tempo_emprego"] = para_numero(df["tempo_emprego"], decimal)
    d["vinculo_ativo"] = limpa_texto(df["vinculo_ativo"]).isin({"1", "01"})

    d["nivel_lideranca"] = d["cbo"].map(nivel_lideranca)
    d["uf"] = d["municipio"].str[:2]
    d["cnae_divisao"] = d["cnae_subclasse"].str[:2]

    antes = len(d)
    d = d[d["vinculo_ativo"]]                       # só estoque em 31/12
    d = d[d["remuneracao"].gt(0)]                   # remuneração zerada não entra na média
    d = d[d["horas_contratuais"].between(1, 44)]    # jornada fora da lei é inconsistência
    d = d.dropna(subset=["sexo", "raca_cor", "municipio", "cbo"])
    d = d.drop_duplicates()
    print(f"    limpeza: {antes:,} -> {len(d):,} linhas")
    return d


def agrega_rais(d: pd.DataFrame) -> pd.DataFrame:
    """Grão: ano x UF x subclasse CNAE x nivel x sexo x raca x faixa etaria x escolaridade.

    As colunas soma_* existem porque média não é agregável: trocar o filtro de
    um estado para a região inteira exige SUM(soma)/SUM(qtd), nunca média de médias.
    """
    d = d.copy()
    d["escolaridade"] = d["escolaridade"].fillna(99)
    d["faixa_etaria"] = d["faixa_etaria"].fillna(9)
    d["nivel_lideranca"] = d["nivel_lideranca"].fillna(9)

    chaves = ["ano", "uf", "cnae_subclasse", "nivel_lideranca", "sexo",
              "raca_cor", "faixa_etaria", "escolaridade"]
    out = d.groupby(chaves, dropna=False).agg(
        qtd_vinculos=("remuneracao", "size"),
        qtd_com_remuneracao=("remuneracao", "count"),
        soma_remuneracao=("remuneracao", "sum"),
        media_remuneracao=("remuneracao", "mean"),
        mediana_remuneracao=("remuneracao", "median"),
        p25_remuneracao=("remuneracao", lambda s: s.quantile(.25)),
        p75_remuneracao=("remuneracao", lambda s: s.quantile(.75)),
        soma_horas_contratuais=("horas_contratuais", "sum"),
        media_horas_contratuais=("horas_contratuais", "mean"),
        soma_tempo_emprego=("tempo_emprego", "sum"),
        media_tempo_emprego=("tempo_emprego", "mean"),
    ).reset_index()
    for c in ("soma_remuneracao", "media_remuneracao", "mediana_remuneracao",
              "p25_remuneracao", "p75_remuneracao", "media_horas_contratuais",
              "soma_tempo_emprego", "media_tempo_emprego"):
        out[c] = out[c].round(2)
    out["soma_horas_contratuais"] = out["soma_horas_contratuais"].fillna(0).astype(int)
    for c in ("nivel_lideranca", "faixa_etaria", "escolaridade"):
        out[c] = out[c].astype(int)
    return out


# -------------------------------------------------------------------- CAGED
def trata_caged(df: pd.DataFrame) -> pd.DataFrame:
    df = df.rename(columns={k: v for k, v in COLS_CAGED.items() if k in df.columns})
    d = pd.DataFrame(index=df.index)
    comp = limpa_texto(df["competencia"])
    d["competencia"] = pd.to_datetime(comp, format="%Y%m", errors="coerce")
    d["ano"] = d["competencia"].dt.year
    d["cbo"] = para_codigo(df["cbo"], 6)
    d["cnae_subclasse"] = para_codigo(df["cnae_subclasse"], 7)
    d["municipio"] = para_codigo(df["municipio"], 6)
    d["sexo"] = limpa_texto(df["sexo"]).map(SEXO_CAGED)
    d["raca_cor"] = limpa_texto(df["raca_cor"]).map(RACA_CAGED)
    d["escolaridade"] = limpa_texto(df["escolaridade"]).map(ESCOLARIDADE_CAGED)
    d["idade"] = pd.to_numeric(limpa_texto(df["idade"]), errors="coerce")
    d["faixa_etaria"] = d["idade"].map(faixa_etaria_de_idade)
    d["salario"] = para_numero(df["salario"], ",")
    d["saldo"] = pd.to_numeric(df["saldo"].astype(str).str.strip(), errors="coerce")

    d["nivel_lideranca"] = d["cbo"].map(nivel_lideranca)
    d["uf"] = d["municipio"].str[:2]
    d["cnae_divisao"] = d["cnae_subclasse"].str[:2]

    antes = len(d)
    d = d[d["saldo"].isin([1, -1])]
    d = d.dropna(subset=["competencia", "sexo", "raca_cor", "municipio", "cbo"])
    print(f"    limpeza: {antes:,} -> {len(d):,} linhas")
    return d


def agrega_caged(d: pd.DataFrame) -> pd.DataFrame:
    """Mesmo grão do fato de estoque, com competência mensal no lugar do ano."""
    d = d.copy()
    d["escolaridade"] = d["escolaridade"].fillna(99)
    d["faixa_etaria"] = d["faixa_etaria"].fillna(9)
    d["nivel_lideranca"] = d["nivel_lideranca"].fillna(9)
    d = d.assign(
        _adm=np.where(d["saldo"] == 1, 1, 0),
        _des=np.where(d["saldo"] == -1, 1, 0),
        _sal_adm=d["salario"].where(d["saldo"] == 1),
    )
    chaves = ["competencia", "uf", "cnae_subclasse", "nivel_lideranca", "sexo",
              "raca_cor", "faixa_etaria", "escolaridade"]
    out = d.groupby(chaves, dropna=False).agg(
        admissoes=("_adm", "sum"),
        desligamentos=("_des", "sum"),
        saldo=("saldo", "sum"),
        qtd_admissoes_com_sal=("_sal_adm", "count"),
        soma_salario_admissao=("_sal_adm", "sum"),
        media_salario_admissao=("_sal_adm", "mean"),
    ).reset_index()
    out["soma_salario_admissao"] = out["soma_salario_admissao"].fillna(0).round(2)
    out["media_salario_admissao"] = out["media_salario_admissao"].round(2)
    for c in ("nivel_lideranca", "faixa_etaria", "escolaridade"):
        out[c] = out[c].astype(int)
    return out


# --------------------------------------------------------------------- main
def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("fonte", choices=["rais", "caged"])
    ap.add_argument("arquivos", nargs="+", type=Path)
    args = ap.parse_args()

    trata, agrega = (trata_rais, agrega_rais) if args.fonte == "rais" else (trata_caged, agrega_caged)
    partes = []
    for p in args.arquivos:
        bruto = pd.read_parquet(p)
        if bruto.empty:            # região sem nenhum vínculo de TI (acontece no arquivo NI)
            print(f"  {p.name}: vazio, pulando")
            continue
        print(f"  {p.name}")
        partes.append(trata(bruto))

    if not partes:
        sys.exit("Nenhum arquivo com dados. Rode o extract_filter antes.")

    limpo = pd.concat(partes, ignore_index=True)
    agregado = agrega(limpo)

    OUT.mkdir(parents=True, exist_ok=True)
    dest = OUT / f"fato_{'vinculo' if args.fonte == 'rais' else 'movimentacao'}_ti.parquet"
    agregado.to_parquet(dest, index=False, compression="zstd")
    print(f"\n  {len(limpo):,} linhas limpas -> {len(agregado):,} linhas agregadas")
    print(f"  {dest.relative_to(ROOT)} ({dest.stat().st_size/1e6:.1f} MB)")


if __name__ == "__main__":
    main()
