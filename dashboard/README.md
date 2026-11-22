# Dashboard — Funil TI

Camada de visualização do projeto. Lê o banco PostgreSQL hospedado na Aiven a cada
requisição, pelas views do schema `publico`, e mostra quatro indicadores de
diversidade no setor de tecnologia brasileiro.

## Como rodar na sua máquina

```bash
cd dashboard
npm install
cp .env.example .env.local   # preencha com a credencial de leitura
npm run dev
```

Abre em `http://localhost:3000`. Os valores de `.env.local` saem de
`acesso-leitura.txt`, que o script `etl/criar_acesso_leitura.py` gera na raiz do
projeto. O usuário `dashboard_leitura` só enxerga as views do schema `publico` e
não escreve nada.

## Como publicar na Vercel

A aplicação não precisa de build especial: é um projeto Next.js padrão.

1. Em `vercel.com/new`, importe o repositório do GitHub.
2. Em **Root Directory**, aponte para `dashboard`. Sem isso a Vercel procura o
   `package.json` na raiz e falha.
3. Em **Environment Variables**, cadastre `PGHOST`, `PGPORT`, `PGDATABASE`,
   `PGUSER` e `PGPASSWORD` com os mesmos valores do `.env.local`.
4. Deploy.

O arquivo `vercel.json` já registra um cron que chama `/api/keep-alive` a cada dois
dias. Essa rota abre uma conexão trivial com o banco, o que basta para o Aiven
contar o serviço como em uso. Sem isso o plano gratuito hiberna depois de algumas
semanas e o dashboard passa a mostrar o aviso de serviço desligado.

## Estrutura

| Caminho | Papel |
|---|---|
| `lib/db.ts` | Pool de conexões, com limite baixo por causa do plano gratuito |
| `lib/indicadores.ts` | As cinco consultas às views e a tipagem do retorno |
| `lib/calculos.ts` | Participação, afunilamento, cruzamentos e rankings |
| `app/api/dados/route.ts` | Endpoint que o painel consome, com filtros de ano e UF |
| `app/api/keep-alive/route.ts` | Alvo do cron que impede a hibernação |
| `components/ui/painel.tsx` | A interface inteira |
| `components/ui/estilos.ts` | Folha de estilos, tema claro e escuro |

## Decisões que valem registro

**Os totais são do universo publicável, não do universo bruto.** As views aplicam
supressão de k-anonimato: qualquer cruzamento com menos de cinco vínculos não sai do
banco. Por isso o painel fala em 695.978 vínculos e não nos 1,4 milhão que a RAIS tem
para as divisões 62 e 63.

**Percentuais ignoram quem não declarou.** Participação feminina é calculada sobre
quem tem sexo declarado, participação negra sobre quem tem raça/cor declarada. Somar
"não informada" ao denominador reduziria todos os percentuais por um motivo que não
tem nada a ver com desigualdade.

**O recorte troca sem ir ao servidor.** A API devolve as linhas já agregadas por
degrau, sexo e raça/cor. Alternar entre gênero e raça/cor é recálculo no navegador.
Trocar ano ou UF dispara nova consulta ao banco.

**A conexão usa TLS sem validar a cadeia.** O certificado raiz do projeto Aiven não é
distribuído junto do código, então `rejectUnauthorized` fica desligado. O tráfego
continua criptografado. Para validar a cadeia, baixe o CA do console da Aiven e
aponte `ssl.ca` em `lib/db.ts`.
