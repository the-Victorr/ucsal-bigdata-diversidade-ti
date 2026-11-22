import { Pool } from "pg";

/**
 * Pool único por instância serverless. O plano free do Aiven tem poucas conexões
 * disponíveis, então o limite aqui é baixo de propósito: cada função da Vercel que
 * acorda abre no máximo 3 conexões e as devolve rápido.
 */
const globalForPool = globalThis as unknown as { pgPool?: Pool };

export function getPool(): Pool {
  if (!globalForPool.pgPool) {
    globalForPool.pgPool = new Pool({
      host: process.env.PGHOST,
      port: Number(process.env.PGPORT ?? 5432),
      database: process.env.PGDATABASE,
      user: process.env.PGUSER,
      password: process.env.PGPASSWORD,
      // O Aiven exige TLS. A cadeia não é validada porque o certificado raiz do
      // projeto não é distribuído junto do código, o tráfego continua criptografado.
      ssl: { rejectUnauthorized: false },
      max: 3,
      idleTimeoutMillis: 10_000,
      connectionTimeoutMillis: 15_000,
    });
  }
  return globalForPool.pgPool;
}

export async function consultar<T = Record<string, unknown>>(
  sql: string,
  params: unknown[] = [],
): Promise<T[]> {
  const { rows } = await getPool().query(sql, params);
  return rows as T[];
}
