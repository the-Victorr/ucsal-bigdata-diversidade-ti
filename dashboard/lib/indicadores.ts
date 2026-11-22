import { consultar } from "@/lib/db";

/**
 * Todas as consultas leem as views do schema `publico`, que já aplicam a supressão
 * de k-anonimato (k >= 5). Nenhuma célula com menos de 5 vínculos chega até aqui,
 * então os totais do dashboard são do universo publicável, não do universo bruto.
 */

export type LinhaFunil = {
  degrau: number;
  nivel: string;
  sexo: string;
  grupoRacial: string;
  vinculos: number;
};

export type LinhaRemuneracao = {
  sexo: string;
  grupoRacial: string;
  media: number;
  vinculos: number;
};

export type LinhaUf = {
  uf: string;
  regiao: string;
  sexo: string;
  grupoRacial: string;
  vinculos: number;
};

export type LinhaFluxo = {
  sexo: string;
  grupoRacial: string;
  admissoes: number;
  desligamentos: number;
  saldo: number;
};

export type Filtros = { ano: number; uf: string | null };

/** Mesmo grão do funil, para o ano imediatamente anterior ao selecionado. */
export type LinhaAnterior = LinhaFunil;

export type Dados = {
  filtros: Filtros;
  anoAnterior: number | null;
  funilAnterior: LinhaAnterior[];
  opcoes: { anos: number[]; ufs: { sigla: string; regiao: string }[] };
  funil: LinhaFunil[];
  remuneracao: LinhaRemuneracao[];
  porUf: LinhaUf[];
  fluxo: LinhaFluxo[];
  atualizadoEm: string;
};

const num = (v: unknown) => (v === null || v === undefined ? 0 : Number(v));

export async function carregarOpcoes() {
  const [anos, ufs] = await Promise.all([
    consultar<{ ano: number }>(
      `SELECT DISTINCT ano FROM publico.vw_funil_lideranca ORDER BY ano DESC`,
    ),
    consultar<{ uf_sigla: string; regiao_nome: string }>(
      `SELECT DISTINCT uf_sigla, regiao_nome FROM publico.vw_funil_lideranca
        ORDER BY regiao_nome, uf_sigla`,
    ),
  ]);
  return {
    anos: anos.map((r) => num(r.ano)),
    ufs: ufs.map((r) => ({ sigla: r.uf_sigla, regiao: r.regiao_nome })),
  };
}

export async function carregarDados(ano: number, uf: string | null): Promise<Dados> {
  const p = [ano, uf];

  const [opcoes, funil, remuneracao, porUf, fluxo, funilAnterior] = await Promise.all([
    carregarOpcoes(),

    // Composição de cada degrau do funil. O degrau 99 ("Não classificado") fica de
    // fora: ele existe para não inflar a base da pirâmide com CBO ausente.
    consultar(
      `SELECT degrau_funil, nivel_lideranca_nome, sexo_nome, grupo_racial_ibge,
              SUM(qtd_vinculos) AS vinculos
         FROM publico.vw_funil_lideranca
        WHERE ano = $1 AND ($2::text IS NULL OR uf_sigla = $2) AND degrau_funil < 99
        GROUP BY 1, 2, 3, 4`,
      p,
    ),

    // Remuneração média ponderada pelo número de vínculos de cada célula.
    consultar(
      `SELECT sexo_nome, grupo_racial_ibge,
              SUM(media_remuneracao * qtd_vinculos) / NULLIF(SUM(qtd_vinculos), 0) AS media,
              SUM(qtd_vinculos) AS vinculos
         FROM publico.vw_gap_salarial
        WHERE ano = $1 AND ($2::text IS NULL OR uf_sigla = $2)
          AND media_remuneracao IS NOT NULL
        GROUP BY 1, 2`,
      p,
    ),

    // Recorte territorial. Ignora o filtro de UF de propósito: este painel existe
    // justamente para comparar as unidades da federação entre si.
    consultar(
      `SELECT uf_sigla, regiao_nome, sexo_nome, grupo_racial_ibge,
              SUM(qtd_vinculos) AS vinculos
         FROM publico.vw_funil_lideranca
        WHERE ano = $1 AND degrau_funil < 99
        GROUP BY 1, 2, 3, 4`,
      [ano],
    ),

    // Fluxo do CAGED: quem entrou e quem saiu no ano.
    consultar(
      `SELECT sexo_nome, grupo_racial_ibge,
              SUM(admissoes) AS admissoes,
              SUM(desligamentos) AS desligamentos,
              SUM(saldo) AS saldo
         FROM publico.vw_rotatividade_ti
        WHERE ano = $1 AND ($2::text IS NULL OR uf_sigla = $2)
          AND admissoes IS NOT NULL
        GROUP BY 1, 2`,
      p,
    ),

    // Mesma consulta do funil, um ano atrás. Serve ao painel comparativo e volta
    // vazia quando o ano anterior não está carregado, caso em que o painel some.
    consultar(
      `SELECT degrau_funil, nivel_lideranca_nome, sexo_nome, grupo_racial_ibge,
              SUM(qtd_vinculos) AS vinculos
         FROM publico.vw_funil_lideranca
        WHERE ano = $1 - 1 AND ($2::text IS NULL OR uf_sigla = $2) AND degrau_funil < 99
        GROUP BY 1, 2, 3, 4`,
      p,
    ),
  ]);

  const temAnterior = funilAnterior.length > 0;

  return {
    filtros: { ano, uf },
    anoAnterior: temAnterior ? ano - 1 : null,
    funilAnterior: funilAnterior.map((r) => ({
      degrau: num(r.degrau_funil),
      nivel: String(r.nivel_lideranca_nome),
      sexo: String(r.sexo_nome),
      grupoRacial: String(r.grupo_racial_ibge),
      vinculos: num(r.vinculos),
    })),
    opcoes,
    funil: funil.map((r) => ({
      degrau: num(r.degrau_funil),
      nivel: String(r.nivel_lideranca_nome),
      sexo: String(r.sexo_nome),
      grupoRacial: String(r.grupo_racial_ibge),
      vinculos: num(r.vinculos),
    })),
    remuneracao: remuneracao.map((r) => ({
      sexo: String(r.sexo_nome),
      grupoRacial: String(r.grupo_racial_ibge),
      media: num(r.media),
      vinculos: num(r.vinculos),
    })),
    porUf: porUf.map((r) => ({
      uf: String(r.uf_sigla),
      regiao: String(r.regiao_nome),
      sexo: String(r.sexo_nome),
      grupoRacial: String(r.grupo_racial_ibge),
      vinculos: num(r.vinculos),
    })),
    fluxo: fluxo.map((r) => ({
      sexo: String(r.sexo_nome),
      grupoRacial: String(r.grupo_racial_ibge),
      admissoes: num(r.admissoes),
      desligamentos: num(r.desligamentos),
      saldo: num(r.saldo),
    })),
    atualizadoEm: new Date().toISOString(),
  };
}
