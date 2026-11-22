import type { Dados, LinhaFunil } from "@/lib/indicadores";

export type Recorte = "sexo" | "raca";
export type Tom = "ink" | "coral" | "teal" | "ochre" | "violet";

/**
 * Ordem e cor de cada categoria. Os rótulos vêm das dimensões conformadas do banco,
 * então qualquer valor fora desta lista é um sinal de que a dimensão mudou.
 */
export const CATEGORIAS: Record<Recorte, { nome: string; tom: Tom }[]> = {
  sexo: [
    { nome: "Feminino", tom: "violet" },
    { nome: "Masculino", tom: "ink" },
    { nome: "Não identificado", tom: "teal" },
  ],
  raca: [
    { nome: "Branca", tom: "ochre" },
    { nome: "Negra", tom: "coral" },
    { nome: "Amarela", tom: "teal" },
    { nome: "Indígena", tom: "violet" },
    { nome: "Sem declaração", tom: "ink" },
  ],
};

/** Categorias com declaração válida. As demais entram nos totais, não nos percentuais. */
const DECLARADAS: Record<Recorte, string[]> = {
  sexo: ["Feminino", "Masculino"],
  raca: ["Branca", "Negra", "Amarela", "Indígena"],
};

const chave = (linha: { sexo: string; grupoRacial: string }, recorte: Recorte) =>
  recorte === "sexo" ? linha.sexo : linha.grupoRacial;

export const DEGRAUS = [
  { degrau: 1, nome: "Liderança", descricao: "Direção e gerência" },
  { degrau: 2, nome: "Profissional", descricao: "Ciências e artes" },
  { degrau: 3, nome: "Técnico/Base", descricao: "Técnico e apoio" },
];

export function somaPor(linhas: LinhaFunil[], recorte: Recorte) {
  const mapa = new Map<string, number>();
  for (const l of linhas) mapa.set(chave(l, recorte), (mapa.get(chave(l, recorte)) ?? 0) + l.vinculos);
  return mapa;
}

/** Percentual de uma categoria sobre o total de quem declarou. */
export function participacao(mapa: Map<string, number>, categoria: string, recorte: Recorte) {
  const base = DECLARADAS[recorte].reduce((s, c) => s + (mapa.get(c) ?? 0), 0);
  return base > 0 ? ((mapa.get(categoria) ?? 0) / base) * 100 : 0;
}

/** Composição de um degrau do funil, em percentual, já ordenada e colorida. */
export function composicaoDoDegrau(dados: Dados, degrau: number, recorte: Recorte) {
  const mapa = somaPor(dados.funil.filter((l) => l.degrau === degrau), recorte);
  const total = [...mapa.values()].reduce((s, v) => s + v, 0);
  return {
    total,
    fatias: CATEGORIAS[recorte]
      .map((c) => ({
        ...c,
        vinculos: mapa.get(c.nome) ?? 0,
        pct: total > 0 ? ((mapa.get(c.nome) ?? 0) / total) * 100 : 0,
      }))
      .filter((f) => f.vinculos > 0),
  };
}

/**
 * Índice de afunilamento: participação da categoria na liderança dividida pela
 * participação dela na base. Abaixo de 1 significa que o grupo perde espaço conforme
 * o funil sobe, que é exatamente a desigualdade que o projeto quer medir.
 */
export function afunilamento(dados: Dados, categoria: string, recorte: Recorte) {
  const porDegrau = DEGRAUS.map((d) => ({
    ...d,
    pct: participacao(somaPor(dados.funil.filter((l) => l.degrau === d.degrau), recorte), categoria, recorte),
  }));
  const naLideranca = porDegrau[0].pct;
  const naBase = porDegrau[2].pct;
  // O degrau mais estreito nem sempre e a lideranca. Na TI brasileira a menor
  // participacao feminina esta no degrau profissional, o nucleo tecnico, e um
  // indice que so compara topo com base esconde exatamente esse estrangulamento.
  const maisEstreito = porDegrau.reduce((a, b) => (b.pct < a.pct ? b : a));
  return {
    indice: naBase > 0 ? naLideranca / naBase : 0,
    naLideranca,
    naBase,
    porDegrau,
    maisEstreito,
    gargaloNoMeio: maisEstreito.degrau === 2,
  };
}

/** Remuneração média de um cruzamento sexo x raça. */
export function remuneracaoDe(dados: Dados, sexo: string | null, grupoRacial: string | null) {
  const linhas = dados.remuneracao.filter(
    (l) => (sexo === null || l.sexo === sexo) && (grupoRacial === null || l.grupoRacial === grupoRacial),
  );
  const peso = linhas.reduce((s, l) => s + l.vinculos, 0);
  return peso > 0 ? linhas.reduce((s, l) => s + l.media * l.vinculos, 0) / peso : 0;
}

/** Os quatro cruzamentos que sustentam a leitura interseccional. */
export function cruzamentos(dados: Dados) {
  const combos: { rotulo: string; sexo: string; raca: string; tom: Tom }[] = [
    { rotulo: "Homem branco", sexo: "Masculino", raca: "Branca", tom: "ochre" },
    { rotulo: "Homem negro", sexo: "Masculino", raca: "Negra", tom: "ink" },
    { rotulo: "Mulher branca", sexo: "Feminino", raca: "Branca", tom: "violet" },
    { rotulo: "Mulher negra", sexo: "Feminino", raca: "Negra", tom: "coral" },
  ];
  return combos.map((c) => ({ ...c, media: remuneracaoDe(dados, c.sexo, c.raca) }));
}

export type Kpis = ReturnType<typeof calcularKpis>;

export function calcularKpis(dados: Dados, recorte: Recorte) {
  const geral = somaPor(dados.funil, recorte);
  const totalVinculos = dados.funil.reduce((s, l) => s + l.vinculos, 0);

  const pctFeminino = participacao(somaPor(dados.funil, "sexo"), "Feminino", "sexo");
  const pctNegra = participacao(somaPor(dados.funil, "raca"), "Negra", "raca");

  const homemBranco = remuneracaoDe(dados, "Masculino", "Branca");
  const mulherNegra = remuneracaoDe(dados, "Feminino", "Negra");
  const razaoInterseccional = homemBranco > 0 ? (mulherNegra / homemBranco) * 100 : 0;

  const categoriaFoco = recorte === "sexo" ? "Feminino" : "Negra";
  const funil = afunilamento(dados, categoriaFoco, recorte);

  return {
    totalVinculos,
    pctFeminino,
    pctNegra,
    razaoInterseccional,
    homemBranco,
    mulherNegra,
    categoriaFoco,
    afunilamento: funil,
    gapGenero: (() => {
      const h = remuneracaoDe(dados, "Masculino", null);
      const m = remuneracaoDe(dados, "Feminino", null);
      return h > 0 ? (m / h) * 100 : 0;
    })(),
    gapRacial: (() => {
      const b = remuneracaoDe(dados, null, "Branca");
      const n = remuneracaoDe(dados, null, "Negra");
      return b > 0 ? (n / b) * 100 : 0;
    })(),
    categoriasPresentes: CATEGORIAS[recorte].filter((c) => (geral.get(c.nome) ?? 0) > 0),
  };
}

/** Ranking de UFs pela participação da categoria em foco, só com volume relevante. */
export function rankingUf(dados: Dados, recorte: Recorte, categoria: string, minimo = 1000) {
  const porUf = new Map<string, { regiao: string; mapa: Map<string, number>; total: number }>();
  for (const l of dados.porUf) {
    const atual = porUf.get(l.uf) ?? { regiao: l.regiao, mapa: new Map(), total: 0 };
    const k = chave(l, recorte);
    atual.mapa.set(k, (atual.mapa.get(k) ?? 0) + l.vinculos);
    atual.total += l.vinculos;
    porUf.set(l.uf, atual);
  }
  return [...porUf.entries()]
    .filter(([, v]) => v.total >= minimo)
    .map(([uf, v]) => ({ uf, regiao: v.regiao, total: v.total, pct: participacao(v.mapa, categoria, recorte) }))
    .sort((a, b) => b.pct - a.pct);
}

/** Saldo do CAGED por categoria: quem o setor contratou e quem dispensou no ano. */
export function fluxoPor(dados: Dados, recorte: Recorte) {
  const mapa = new Map<string, { admissoes: number; desligamentos: number; saldo: number }>();
  for (const l of dados.fluxo) {
    const k = chave(l, recorte);
    const a = mapa.get(k) ?? { admissoes: 0, desligamentos: 0, saldo: 0 };
    a.admissoes += l.admissoes;
    a.desligamentos += l.desligamentos;
    a.saldo += l.saldo;
    mapa.set(k, a);
  }
  return CATEGORIAS[recorte]
    .map((c) => ({ ...c, ...(mapa.get(c.nome) ?? { admissoes: 0, desligamentos: 0, saldo: 0 }) }))
    .filter((f) => f.admissoes > 0 || f.desligamentos > 0);
}

export const inteiro = new Intl.NumberFormat("pt-BR");
export const real = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL", maximumFractionDigits: 0 });
export const pct = (v: number, casas = 1) => `${v.toFixed(casas).replace(".", ",")}%`;
