"""
Catálogo das fontes PDET/MTE (FTP público) e dos 3 layouts da RAIS.

Layouts confirmados no download (set/2026):
  - 2015-2017: um .7z por UF (ex.: BA2015.7z) -> UF2015.txt
                ';' | Latin-1 | decimal vírgula | zero-padded | nulos "{ñ c}" / "{ñ class}"
  - 2018-2022: um .7z por região (RAIS_VINC_PUB_NORDESTE.7z) -> .txt
                ';' | Latin-1 | decimal vírgula | zero-padded | nulos 9997/999999
  - 2023+    : um .7z por região -> .COMT
                ',' com aspas | Latin-1 | decimal PONTO | nulos 999997/999/999999
                nomes de coluna com sufixo " - Código"
"""
from __future__ import annotations

FTP_BASE = "ftp://ftp.mtps.gov.br/pdet/microdados"

UFS = [
    "AC", "AL", "AM", "AP", "BA", "CE", "DF", "ES", "GO", "MA", "MG", "MS", "MT",
    "PA", "PB", "PE", "PI", "PR", "RJ", "RN", "RO", "RR", "RS", "SC", "SE", "SP", "TO",
]

REGIOES = ["CENTRO_OESTE", "MG_ES_RJ", "NI", "NORDESTE", "NORTE", "SP", "SUL"]


def rais_layout(ano: int) -> str:
    if ano <= 2017:
        return "uf_2015"
    if ano <= 2022:
        return "regiao_2018"
    return "regiao_2023"


def rais_files(ano: int) -> list[tuple[str, str]]:
    """Retorna [(url, nome_local)] dos arquivos de VÍNCULOS de um ano."""
    if rais_layout(ano) == "uf_2015":
        return [(f"{FTP_BASE}/RAIS/{ano}/{uf}{ano}.7z", f"{uf}{ano}.7z") for uf in UFS]
    return [
        (f"{FTP_BASE}/RAIS/{ano}/RAIS_VINC_PUB_{r}.7z", f"RAIS_VINC_PUB_{r}.7z")
        for r in REGIOES
    ]


def caged_files(ano: int, meses: range = range(1, 13)) -> list[tuple[str, str]]:
    """Arquivos de MOVIMENTAÇÃO do Novo CAGED (CAGEDMOV). FOR/EXC ficam para depois."""
    out = []
    for m in meses:
        comp = f"{ano}{m:02d}"
        out.append(
            (f"{FTP_BASE}/NOVO%20CAGED/{ano}/{comp}/CAGEDMOV{comp}.7z", f"CAGEDMOV{comp}.7z")
        )
    return out


# Parâmetros de leitura por layout (pandas.read_csv)
READ_KW = {
    "uf_2015":     dict(sep=";", encoding="latin-1", quoting=3),
    "regiao_2018": dict(sep=";", encoding="latin-1", quoting=3),
    "regiao_2023": dict(sep=",", encoding="latin-1", quotechar='"'),
    "caged":       dict(sep=";", encoding="utf-8"),
}

# Nome da coluna de subclasse CNAE em cada layout (base do filtro setorial)
CNAE_SUBCLASSE_COL = {
    "uf_2015":     "CNAE 2.0 Subclasse",
    "regiao_2018": "CNAE 2.0 Subclasse",
    "regiao_2023": "CNAE 2.0 Subclasse - Codigo",
    "caged":       "subclasse",
}

# Divisões CNAE 2.0 consideradas "TI" no projeto (62 = serviços de TI, 63 = informação)
DIVISOES_TI = ("62", "63")
