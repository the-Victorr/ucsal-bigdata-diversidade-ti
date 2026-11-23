import { NextResponse } from "next/server";
import { comConexao, consultar } from "@/lib/db";

export const dynamic = "force-dynamic";

// Teto explícito, acima dos timeouts do driver em lib/db.ts. Sem declarar, vale o
// padrão da plataforma, que no plano gratuito é menor que eles: a função morreria
// antes de o driver desistir e a conexão ficaria pendurada.
export const maxDuration = 30;

/**
 * Rota chamada por um cron da Vercel a cada dois dias. Uma consulta trivial é o
 * bastante para o Aiven contar o serviço como em uso e não hibernar, que foi o que
 * derrubou o banco três vezes durante o projeto.
 */
export async function GET() {
  try {
    const [linha] = await comConexao((c) =>
      consultar<{ agora: string }>(c, "SELECT now() AS agora"),
    );
    return NextResponse.json({ ok: true, banco: linha.agora });
  } catch (erro) {
    return NextResponse.json(
      { ok: false, detalhe: erro instanceof Error ? erro.message : String(erro) },
      { status: 503 },
    );
  }
}
