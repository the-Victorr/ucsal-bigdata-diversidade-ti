"""
Extrai um .7z do PDET em STREAMING (7zz -so), filtra só o setor de TI
(CNAE 2.0 divisões 62 e 63) em chunks e grava Parquet em data/processed/.

Nunca grava o TXT bruto no disco: a RAIS completa descompactada teria ~350 GB.

Uso:
  python etl/extract_filter.py rais  data/raw/rais/2023/RAIS_VINC_PUB_NORDESTE.7z
  python etl/extract_filter.py rais  data/raw/rais/2023/*.7z
  python etl/extract_filter.py caged data/raw/caged/2024/CAGEDMOV202401.7z
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
import time
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).parent))
from sources import CNAE_SUBCLASSE_COL, DIVISOES_TI, READ_KW, rais_layout  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "processed"
CHUNK = 500_000


def ano_do_caminho(p: Path) -> int:
    m = re.search(r"(20\d{2})", p.parent.name) or re.search(r"(20\d{2})", p.name)
    if not m:
        raise ValueError(f"não consegui inferir o ano de {p}")
    return int(m.group(1))


def stream_7z(path: Path):
    """Abre o único arquivo interno do .7z como stream binário (stdout do 7zz)."""
    proc = subprocess.Popen(
        ["7zz", "e", "-so", str(path)],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=1 << 20,
    )
    return proc


def filtro_ti(chunk: pd.DataFrame, col: str) -> pd.DataFrame:
    sub = chunk[col].astype(str).str.strip().str.zfill(7)
    return chunk[sub.str[:2].isin(DIVISOES_TI)]


def processar(fonte: str, path: Path) -> Path:
    ano = ano_do_caminho(path)
    layout = "caged" if fonte == "caged" else rais_layout(ano)
    col = CNAE_SUBCLASSE_COL[layout]
    kw = READ_KW[layout]

    dest_dir = OUT / fonte / str(ano)
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / (path.stem + ".parquet")
    if dest.exists():
        print(f"  ✔ já processado {dest.relative_to(ROOT)}")
        return dest

    t0 = time.time()
    proc = stream_7z(path)
    partes, lidas, mantidas = [], 0, 0
    reader = pd.read_csv(proc.stdout, dtype=str, chunksize=CHUNK, low_memory=False, **kw)
    for chunk in reader:
        lidas += len(chunk)
        f = filtro_ti(chunk, col)
        mantidas += len(f)
        if len(f):
            partes.append(f)
        print(f"  … {path.name}: lidas {lidas:>12,} | TI {mantidas:>9,}", end="\r", flush=True)
    proc.wait()

    df = pd.concat(partes, ignore_index=True) if partes else pd.DataFrame(columns=[col])
    df.columns = [c.strip() for c in df.columns]
    df["ano"] = ano
    df["arquivo_origem"] = path.name
    df["layout"] = layout
    df.to_parquet(dest, index=False, compression="zstd")
    dt = time.time() - t0
    print(f"\n  ✔ {path.name}: {lidas:,} lidas → {mantidas:,} de TI "
          f"({100*mantidas/max(lidas,1):.2f}%) em {dt/60:.1f} min → {dest.relative_to(ROOT)}")
    return dest


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("fonte", choices=["rais", "caged"])
    ap.add_argument("arquivos", nargs="+", type=Path)
    ap.add_argument("--rm-7z", action="store_true", help="apaga o .7z após processar (economiza disco)")
    args = ap.parse_args()
    for p in args.arquivos:
        print(f"\n== {p} ==")
        processar(args.fonte, p)
        if args.rm_7z:
            p.unlink()
            print(f"  🗑 removido {p.name}")


if __name__ == "__main__":
    main()
