import { NextResponse } from "next/server";
import { consultar } from "@/lib/db";

export const dynamic = "force-dynamic";

/**
 * Rota chamada por um cron da Vercel a cada dois dias. Uma consulta trivial é o
 * bastante para o Aiven contar o serviço como em uso e não hibernar, que foi o que
 * derrubou o banco três vezes durante o projeto.
 */
export async function GET() {
  try {
    const [linha] = await consultar<{ agora: string }>("SELECT now() AS agora");
    return NextResponse.json({ ok: true, banco: linha.agora });
  } catch (erro) {
    return NextResponse.json(
      { ok: false, detalhe: erro instanceof Error ? erro.message : String(erro) },
      { status: 503 },
    );
  }
}
