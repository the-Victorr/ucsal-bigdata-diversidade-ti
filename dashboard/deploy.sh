#!/usr/bin/env bash
# Publica o dashboard na Vercel a partir da linha de comando.
#
# Faz o mesmo que a importação pela interface web, mas de forma repetível e
# versionada, que é o que a etapa pede para a infraestrutura complementar.
#
# Uso:
#   ./deploy.sh              publica em preview
#   ./deploy.sh --producao   publica em produção
#
# Pré-requisitos: Node 18+, e um .env.local preenchido nesta pasta.

set -euo pipefail
cd "$(dirname "$0")"

ENV_FILE=".env.local"
VARIAVEIS=(PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD)
ALVO="preview"
[[ "${1:-}" == "--producao" ]] && ALVO="production"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Erro: $ENV_FILE não existe. Copie .env.example e preencha com a" >&2
  echo "credencial de leitura que está em ../acesso-leitura.txt." >&2
  exit 1
fi

echo "==> Verificando o build antes de subir qualquer coisa"
npm run build

echo "==> Autenticando na Vercel"
# O login abre o navegador na primeira vez e guarda o token depois.
npx --yes vercel@latest login

echo "==> Vinculando a pasta ao projeto da Vercel"
npx --yes vercel@latest link --yes

echo "==> Enviando as variáveis de ambiente"
# Cada variável é enviada aos três ambientes. O `|| true` cobre o caso de a
# variável já existir: a Vercel recusa a duplicata e isso não é um erro aqui.
for nome in "${VARIAVEIS[@]}"; do
  valor="$(grep -E "^${nome}=" "$ENV_FILE" | head -1 | cut -d= -f2-)"
  if [[ -z "$valor" ]]; then
    echo "Erro: $nome está vazia em $ENV_FILE." >&2
    exit 1
  fi
  for ambiente in production preview development; do
    printf '%s' "$valor" | npx --yes vercel@latest env add "$nome" "$ambiente" >/dev/null 2>&1 || true
  done
  echo "    $nome enviada"
done

echo "==> Publicando ($ALVO)"
if [[ "$ALVO" == "production" ]]; then
  npx --yes vercel@latest deploy --prod
else
  npx --yes vercel@latest deploy
fi

echo
echo "Pronto. O cron de keep-alive declarado em vercel.json passa a rodar"
echo "sozinho a cada dois dias nos deploys de produção."
