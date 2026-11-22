// Roda antes do `npm run local`. Existe para o erro aparecer como instrução e não
// como uma pilha de exceção do driver do Postgres meia hora depois.
import { existsSync, readFileSync } from "node:fs";

const NECESSARIAS = ["PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD"];

if (!existsSync(".env.local")) {
  console.error(`
Falta o arquivo .env.local nesta pasta.

Ele guarda a credencial de leitura do banco e não vai para o repositório.
Crie com:

    cp .env.example .env.local

e preencha com os valores que estão em acesso-leitura.txt, na raiz do projeto.
`);
  process.exit(1);
}

const texto = readFileSync(".env.local", "utf8");
const vazias = NECESSARIAS.filter((nome) => {
  const linha = texto.split("\n").find((l) => l.startsWith(`${nome}=`));
  return !linha || linha.slice(nome.length + 1).trim() === "";
});

if (vazias.length > 0) {
  console.error(`
O .env.local existe, mas estas variáveis estão vazias: ${vazias.join(", ")}.

Os valores estão em acesso-leitura.txt, na raiz do projeto.
`);
  process.exit(1);
}

console.log("Ambiente conferido. Subindo o painel em http://localhost:3000");
