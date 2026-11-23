import { Client } from "pg";

/**
 * Uma conexão por requisição, aberta e fechada dentro dela.
 *
 * A tentação em serverless é manter um pool entre invocações, e foi o que estava
 * aqui antes. Não funciona na Vercel: depois de responder, a instância é congelada
 * em vez de encerrada. O temporizador de ocioso do pool não roda enquanto ela está
 * congelada, então a conexão fica pendurada até o próprio Postgres expirá-la. Em
 * teste, doze requisições simultâneas deixaram catorze conexões ociosas presas, de
 * um limite de vinte no plano gratuito do Aiven, e o banco passou a recusar login
 * de todos os usuários.
 *
 * Fechar explicitamente devolve o slot no fim de cada requisição. O custo é o
 * handshake TLS a cada chamada, algo entre 200 e 400 ms, que para um painel
 * consultado por pessoas é irrelevante perto de ficar fora do ar.
 */
function novaConexao(): Client {
  return new Client({
    host: process.env.PGHOST,
    port: Number(process.env.PGPORT ?? 5432),
    database: process.env.PGDATABASE,
    user: process.env.PGUSER,
    password: process.env.PGPASSWORD,
    // O Aiven exige TLS. A cadeia não é validada porque o certificado raiz do
    // projeto não é distribuído junto do código, o tráfego continua criptografado.
    ssl: { rejectUnauthorized: false },
    connectionTimeoutMillis: 12_000,
    query_timeout: 25_000,
  });
}

/**
 * Executa um bloco com uma conexão própria e a encerra, mesmo se houver erro.
 *
 * Todas as consultas de uma requisição devem passar pelo mesmo bloco: o driver
 * enfileira consultas concorrentes numa conexão só, então `Promise.all` continua
 * funcionando sem abrir conexão extra.
 */
export async function comConexao<T>(fn: (c: Client) => Promise<T>): Promise<T> {
  const c = novaConexao();
  await c.connect();
  try {
    return await fn(c);
  } finally {
    // Nunca deixa o slot preso: `end` pode rejeitar se o socket já caiu, e esse
    // erro não deve mascarar o resultado nem a exceção original.
    await c.end().catch(() => {});
  }
}

export async function consultar<T = Record<string, unknown>>(
  c: Client,
  sql: string,
  params: unknown[] = [],
): Promise<T[]> {
  const { rows } = await c.query(sql, params);
  return rows as T[];
}
