import PainelDiversidade from "@/components/ui/painel";
import { comConexao } from "@/lib/db";
import { carregarDados, carregarOpcoes, type Dados } from "@/lib/indicadores";

export const dynamic = "force-dynamic";

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
