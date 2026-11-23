import PainelDiversidade from "@/components/ui/painel";
import { comConexao } from "@/lib/db";
import { carregarDados, carregarOpcoes, type Dados } from "@/lib/indicadores";

export const dynamic = "force-dynamic";

// Teto explícito, acima dos timeouts do driver em lib/db.ts. Sem declarar, vale o
// padrão da plataforma, que no plano gratuito é menor que eles: a função morreria
// antes de o driver desistir e a conexão ficaria pendurada.
export const maxDuration = 30;

/**
 * A primeira carga acontece no servidor, para a página já chegar preenchida. Se o
 * banco estiver fora do ar a página ainda renderiza, e o componente do cliente
 * mostra o aviso com as instruções de religar o serviço.
 */
export default async function Home() {
  let inicial: Dados | null = null;
  try {
    inicial = await comConexao(async (c) => {
      const { anos } = await carregarOpcoes(c);
      return carregarDados(c, anos[0], null);
    });
  } catch (erro) {
    console.error("Carga inicial falhou, o cliente vai tentar de novo:", erro);
  }
  return <PainelDiversidade inicial={inicial} />;
}
