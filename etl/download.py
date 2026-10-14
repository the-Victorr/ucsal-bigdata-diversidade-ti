"""
Baixa microdados RAIS / Novo CAGED do FTP do PDET com retomada (curl -C -).

Uso:
  python etl/download.py rais  2023                 # todas as regiões de 2023
  python etl/download.py rais  2023 --only NORDESTE # só um arquivo
  python etl/download.py rais  2015-2023            # intervalo
  python etl/download.py caged 2024                 # 12 meses de CAGEDMOV
  python etl/download.py caged 2020-2025

Os .7z ficam em data/raw/{rais|caged}/{ano}/ e NÃO são versionados (ver .gitignore).
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from sources import caged_files, rais_files  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw"


def parse_anos(s: str) -> list[int]:
    if "-" in s:
        a, b = s.split("-")
        return list(range(int(a), int(b) + 1))
    return [int(s)]


def remote_size(url: str) -> int | None:
    r = subprocess.run(["curl", "-sI", "--max-time", "60", url], capture_output=True, text=True)
    for line in r.stdout.splitlines():
        if line.lower().startswith("content-length:"):
            return int(line.split(":")[1].strip())
    return None


def download(url: str, dest: Path) -> bool:
    dest.parent.mkdir(parents=True, exist_ok=True)
    expected = remote_size(url)
    if dest.exists() and expected and dest.stat().st_size == expected:
        print(f"  ✔ já existe   {dest.name} ({expected/1e6:.0f} MB)")
        return True
    print(f"  ⬇ baixando    {dest.name} ({(expected or 0)/1e6:.0f} MB)")
    cmd = ["curl", "-C", "-", "--retry", "5", "--retry-delay", "10", "--max-time", "7200",
           "-o", str(dest), url]
    for attempt in range(3):
        r = subprocess.run(cmd)
        if r.returncode == 0 and (not expected or dest.stat().st_size == expected):
            print(f"  ✔ ok          {dest.name}")
            return True
        print(f"  ↻ tentativa {attempt + 2}/3 para {dest.name}")
    print(f"  ✖ FALHOU      {dest.name}", file=sys.stderr)
    return False


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("fonte", choices=["rais", "caged"])
    ap.add_argument("anos", help="ano ou intervalo (2015-2023)")
    ap.add_argument("--only", help="substring do nome do arquivo (ex.: NORDESTE, BA, 202401)")
    args = ap.parse_args()

    falhas = []
    for ano in parse_anos(args.anos):
        files = rais_files(ano) if args.fonte == "rais" else caged_files(ano)
        if args.only:
            files = [f for f in files if args.only.upper() in f[1].upper()]
        print(f"\n== {args.fonte.upper()} {ano}: {len(files)} arquivo(s) ==")
        for url, name in files:
            if not download(url, RAW / args.fonte / str(ano) / name):
                falhas.append(name)
    if falhas:
        print("\nFalhas:", ", ".join(falhas), file=sys.stderr)
        sys.exit(1)
    print("\nConcluído.")


if __name__ == "__main__":
    main()
