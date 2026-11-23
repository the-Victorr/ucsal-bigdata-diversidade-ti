import { NextResponse } from "next/server";
import { comConexao } from "@/lib/db";
import { carregarDados, carregarOpcoes } from "@/lib/indicadores";

export const dynamic = "force-dynamic";

// Teto explícito, acima dos timeouts do driver em lib/db.ts. Sem declarar, vale o
// padrão da plataforma, que no plano gratuito é menor que eles: a função morreria
// antes de o driver desistir e a conexão ficaria pendurada.
export const maxDuration = 30;

/**
 * Erros de rede contra o Aiven têm um significado prático: o serviço do plano free
 * hiberna depois de algumas semanas sem uso e o host deixa de resolver. Em vez de
 * devolver um 500 genérico, a API diz qual é o caso para a interface explicar.
 */
function tipoDeFalha(erro: unknown): "hibernando" | "erro" {
  const codigo = (erro as { code?: string })?.code ?? "";
  return ["ENOTFOUND", "EAI_AGAIN", "ETIMEDOUT", "ECONNREFUSED"].includes(codigo)
    ? "hibernando"
    : "erro";
}

export async function GET(requisicao: Request) {
  const params = new URL(requisicao.url).searchParams;
  const ufPedida = params.get("uf");
  const uf = !ufPedida || ufPedida === "BR" ? null : ufPedida.toUpperCase();

  try {
    // As duas consultas compartilham a mesma conexão: descobrir o ano mais recente
    // e carregar os dados dele são partes de uma requisição só.
    const dados = await comConexao(async (c) => {
      let ano = Number(params.get("ano"));
      if (!Number.isFinite(ano) || ano <= 0) {
        const { anos } = await carregarOpcoes(c);
        ano = anos[0];
      }
      return carregarDados(c, ano, uf);
    });
    return NextResponse.json(dados, {
      headers: { "Cache-Control": "s-maxage=30, stale-while-revalidate=120" },
    });
  } catch (erro) {
    const tipo = tipoDeFalha(erro);
    console.error("Falha ao consultar o banco:", erro);
    return NextResponse.json(
      {
        tipo,
        mensagem:
          tipo === "hibernando"
            ? "O banco no Aiven está hibernando. O plano gratuito desliga o serviço depois de algumas semanas sem uso, e religá-lo pelo console leva cerca de cinco minutos."
            : "Não foi possível consultar o banco.",
        detalhe: erro instanceof Error ? erro.message : String(erro),
      },
      { status: 503 },
    );
  }
}
