"use client";

import { useCallback, useEffect, useRef, useState, type CSSProperties, type ReactNode } from "react";
import {
  ArrowDownRight, ArrowUpRight, Banknote, CloudOff, Download, Filter, MapPin,
  Moon, RefreshCw, Scale, Sun, TrendingDown, UserRound, Users,
} from "lucide-react";
import { gsap } from "gsap";
import { useGSAP } from "@gsap/react";
import "@fontsource-variable/manrope";

import { estilos } from "@/components/ui/estilos";
import type { Dados } from "@/lib/indicadores";
import {
  CATEGORIAS, DEGRAUS, calcularKpis, composicaoDoDegrau, cruzamentos, fluxoPor,
  inteiro, pct, rankingUf, real, somaPor, totalDoRecorte, type Recorte, type Tom,
} from "@/lib/calculos";

gsap.registerPlugin(useGSAP);

/* ------------------------------------------------------------------ primitivas */

function Painel({ titulo, subtitulo, acao, classe = "", children }: {
  titulo: string; subtitulo?: string; acao?: ReactNode; classe?: string; children: ReactNode;
}) {
  return (
    <section className={`gd-panel ${classe}`} data-anima>
      <header className="gd-panel-head">
        <div><h2>{titulo}</h2>{subtitulo && <p>{subtitulo}</p>}</div>
        {acao}
      </header>
      {children}
    </section>
  );
}

function Kpi({ titulo, icone, valor, legenda, delta, alerta, destaque }: {
  titulo: string; icone: ReactNode; valor: string; legenda: string;
  delta?: string; alerta?: boolean; destaque?: boolean;
}) {
  return (
    <article className="gd-metric" data-destaque={destaque} data-anima>
      <div className="gd-metric-head"><span>{titulo}</span><span className="gd-metric-icon" aria-hidden="true">{icone}</span></div>
      <strong className="gd-metric-value">{valor}</strong>
      <div className="gd-metric-caption">
        {delta && (
          <span className="gd-delta" data-alerta={alerta}>
            {alerta ? <ArrowDownRight aria-hidden="true" /> : <ArrowUpRight aria-hidden="true" />}{delta}
          </span>
        )}
        <span>{legenda}</span>
      </div>
    </article>
  );
}

function Legenda({ itens }: { itens: { nome: string; tom: Tom }[] }) {
  return (
    <div className="gd-legend">
      {itens.map((i) => <span key={i.nome}><i data-tone={i.tom} aria-hidden="true" />{i.nome}</span>)}
    </div>
  );
}

function Seletor({ rotulo, valor, opcoes, aoMudar, icone }: {
  rotulo: string; valor: string; opcoes: { valor: string; texto: string }[];
  aoMudar: (v: string) => void; icone: ReactNode;
}) {
  return (
    <label className="gd-filter">
      {icone}
      <span className="gd-sr">{rotulo}</span>
      <select aria-label={rotulo} value={valor} onChange={(e) => aoMudar(e.target.value)}>
        {opcoes.map((o) => <option key={o.valor} value={o.valor}>{o.texto}</option>)}
      </select>
    </label>
  );
}

/* --------------------------------------------------------------------- gráficos */

/** Funil: um degrau por linha, fatias proporcionais à composição daquele degrau. */
function Funil({ dados, recorte }: { dados: Dados; recorte: Recorte }) {
  return (
    <div className="gd-funil">
      {DEGRAUS.map((d) => {
        const { total, fatias } = composicaoDoDegrau(dados, d.degrau, recorte);
        return (
          <div className="gd-funil-linha" key={d.degrau}>
            <div className="gd-funil-rotulo">
              <strong>{d.nome}</strong>
              <small>{inteiro.format(total)} vínculos</small>
            </div>
            <div className="gd-funil-barra" role="img"
              aria-label={`${d.nome}: ${fatias.map((f) => `${f.nome} ${pct(f.pct)}`).join(", ")}`}>
              {fatias.map((f) => (
                <span className="gd-funil-fatia" key={f.nome} data-tone={f.tom}
                  style={{ flexGrow: f.pct }} title={`${f.nome}: ${pct(f.pct)} (${inteiro.format(f.vinculos)})`}>
                  {f.pct >= 7 && <span>{pct(f.pct, 0)}</span>}
                </span>
              ))}
            </div>
          </div>
        );
      })}
    </div>
  );
}

function Rosca({ dados, recorte }: { dados: Dados; recorte: Recorte }) {
  const [ativo, setAtivo] = useState<number | null>(null);
  const mapa = somaPor(dados.funil, recorte);
  const total = totalDoRecorte(mapa, recorte);
  const fatias = CATEGORIAS[recorte]
    .map((c) => ({ ...c, vinculos: mapa.get(c.nome) ?? 0 }))
    .filter((f) => f.vinculos > 0)
    .map((f) => ({ ...f, pct: total > 0 ? (f.vinculos / total) * 100 : 0 }));

  let acumulado = 0;
  const segmentos = fatias.map((f) => {
    const inicio = acumulado;
    acumulado += f.pct;
    return { ...f, inicio };
  });

  return (
    <div className="gd-rosca-wrap">
      <div className="gd-rosca">
        <svg viewBox="0 0 124 124" aria-hidden="true">
          <circle cx="62" cy="62" r="47" fill="none" stroke="var(--gd-track)" strokeWidth="14" />
          <g transform="rotate(-90 62 62)">
            {segmentos.map((s, i) => (
              <circle key={s.nome} cx="62" cy="62" r="47" pathLength="100" fill="none" strokeWidth="14"
                data-tone={s.tom} className="gd-rosca-seg"
                data-apagado={ativo !== null && i !== ativo}
                strokeDasharray={`${Math.max(0, s.pct - 0.8)} 100`} strokeDashoffset={-s.inicio} />
            ))}
          </g>
        </svg>
        <div className="gd-rosca-centro">
          <strong>{ativo === null ? pct(fatias[0]?.pct ?? 0, 0) : pct(fatias[ativo].pct)}</strong>
          <span>{ativo === null ? fatias[0]?.nome : fatias[ativo].nome}</span>
        </div>
      </div>
      <div className="gd-lista">
        {fatias.map((f, i) => (
          <button type="button" key={f.nome} aria-pressed={ativo === i}
            aria-label={`${f.nome}: ${pct(f.pct)}, ${inteiro.format(f.vinculos)} vínculos`}
            onClick={() => setAtivo(ativo === i ? null : i)}>
            <span><i data-tone={f.tom} aria-hidden="true" />{f.nome}</span>
            <span className="gd-trilha" aria-hidden="true">
              <i className="gd-fill" data-tone={f.tom} style={{ width: `${f.pct}%` }} />
            </span>
            <strong>{pct(f.pct, 0)}</strong>
          </button>
        ))}
      </div>
    </div>
  );
}

function BarrasRemuneracao({ dados }: { dados: Dados }) {
  const barras = cruzamentos(dados).filter((b) => b.media > 0);
  const max = Math.max(1, ...barras.map((b) => b.media));
  if (barras.length === 0) return <p className="gd-vazio">Sem remuneração publicável para estes filtros.</p>;
  return (
    <div className="gd-barras" style={{ "--gd-n": barras.length } as CSSProperties}>
      {barras.map((b) => (
        <div className="gd-barra-col" key={b.rotulo}>
          <span className="gd-barra-valor">{real.format(b.media)}</span>
          <span className="gd-barra-haste gd-anima-barra" data-tone={b.tom}
            style={{ height: `${(b.media / max) * 100}%` }}
            title={`${b.rotulo}: ${real.format(b.media)}`} />
          <span className="gd-barra-rotulo">{b.rotulo}</span>
        </div>
      ))}
    </div>
  );
}

function TabelaUf({ dados, recorte, categoria }: { dados: Dados; recorte: Recorte; categoria: string }) {
  const linhas = rankingUf(dados, recorte, categoria);
  const max = Math.max(1, ...linhas.map((l) => l.pct));
  if (linhas.length === 0) return <p className="gd-vazio">Nenhuma UF com volume suficiente.</p>;
  return (
    <div className="gd-tabela-scroll" style={{ maxBlockSize: 268 }}>
      <table>
        <thead>
          <tr>
            <th scope="col">UF</th><th scope="col">Região</th>
            <th scope="col" className="gd-num">Vínculos</th>
            <th scope="col">Participação</th>
            <th scope="col" className="gd-num">%</th>
          </tr>
        </thead>
        <tbody>
          {linhas.map((l) => (
            <tr key={l.uf}>
              <td>{l.uf}</td>
              <td style={{ color: "var(--gd-muted)" }}>{l.regiao}</td>
              <td className="gd-num">{inteiro.format(l.total)}</td>
              <td style={{ width: "40%" }}>
                <span className="gd-mini" data-tone={recorte === "sexo" ? "violet" : "coral"}
                  style={{ width: `${(l.pct / max) * 100}%` }} aria-hidden="true" />
              </td>
              <td className="gd-num">{pct(l.pct)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function TabelaFluxo({ dados, recorte }: { dados: Dados; recorte: Recorte }) {
  const linhas = fluxoPor(dados, recorte);
  if (linhas.length === 0) return <p className="gd-vazio">Sem movimentações publicáveis para estes filtros.</p>;
  return (
    <div className="gd-tabela-scroll">
      <table>
        <thead>
          <tr>
            <th scope="col">Grupo</th>
            <th scope="col" className="gd-num">Admissões</th>
            <th scope="col" className="gd-num">Desligamentos</th>
            <th scope="col" className="gd-num">Saldo</th>
          </tr>
        </thead>
        <tbody>
          {linhas.map((l) => (
            <tr key={l.nome}>
              <td><span className="gd-legend"><span><i data-tone={l.tom} aria-hidden="true" />{l.nome}</span></span></td>
              <td className="gd-num">{inteiro.format(l.admissoes)}</td>
              <td className="gd-num">{inteiro.format(l.desligamentos)}</td>
              <td className="gd-num" style={{ color: l.saldo >= 0 ? "var(--gd-teal)" : "var(--gd-coral)", fontWeight: 850 }}>
                {l.saldo >= 0 ? "+" : ""}{inteiro.format(l.saldo)}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/* ------------------------------------------------------------------- principal */

function baixarCsv(nome: string, linhas: (string | number)[][]) {
  const csv = linhas.map((l) => l.map((c) => `"${String(c).replaceAll('"', '""')}"`).join(";")).join("\r\n");
  const url = URL.createObjectURL(new Blob(["﻿" + csv], { type: "text/csv;charset=utf-8" }));
  const a = document.createElement("a");
  a.href = url;
  a.download = nome;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 0);
}

export default function PainelDiversidade({ inicial }: { inicial: Dados | null }) {
  const [dados, setDados] = useState<Dados | null>(inicial);
  const [carregando, setCarregando] = useState(false);
  const [falha, setFalha] = useState<{ tipo: string; mensagem: string } | null>(null);
  const [ano, setAno] = useState<number | null>(inicial?.filtros.ano ?? null);
  const [uf, setUf] = useState<string>(inicial?.filtros.uf ?? "BR");
  const [recorte, setRecorte] = useState<Recorte>("sexo");
  const [tema, setTema] = useState<"light" | "dark">("light");
  const raiz = useRef<HTMLDivElement>(null);
  const corpo = useRef<HTMLDivElement>(null);

  const buscar = useCallback(async (novoAno: number | null, novaUf: string) => {
    setCarregando(true);
    setFalha(null);
    try {
      const q = new URLSearchParams();
      if (novoAno) q.set("ano", String(novoAno));
      q.set("uf", novaUf);
      const r = await fetch(`/api/dados?${q}`, { cache: "no-store" });
      const corpo = await r.json();
      if (!r.ok) {
        setFalha({ tipo: corpo.tipo ?? "erro", mensagem: corpo.mensagem ?? "Falha ao consultar o banco." });
        return;
      }
      setDados(corpo as Dados);
      setAno(corpo.filtros.ano);
    } catch {
      setFalha({ tipo: "erro", mensagem: "Não foi possível falar com a API do dashboard." });
    } finally {
      setCarregando(false);
    }
  }, []);

  useEffect(() => { if (!inicial) void buscar(null, "BR"); }, [inicial, buscar]);

  useGSAP(() => {
    if (!corpo.current || !dados) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const t = gsap.timeline({ defaults: { ease: "power3.out" } });
    t.from("[data-anima]", { y: 16, opacity: 0, stagger: 0.04, duration: 0.45, clearProps: "transform,opacity" }, 0);
    t.from(".gd-funil-fatia", { scaleX: 0, transformOrigin: "left center", stagger: 0.02, duration: 0.4, clearProps: "transform" }, 0.12);
    t.from(".gd-anima-barra", { scaleY: 0, stagger: 0.05, duration: 0.45, clearProps: "transform" }, 0.15);
    t.from(".gd-rosca svg", { scale: 0.82, opacity: 0, duration: 0.5, transformOrigin: "center" }, 0.12);
    t.from(".gd-trilha i", { scaleX: 0, transformOrigin: "left center", stagger: 0.04, duration: 0.5, clearProps: "transform" }, 0.2);
  }, { scope: corpo, dependencies: [dados, recorte], revertOnUpdate: true });

  const kpis = dados ? calcularKpis(dados, recorte) : null;
  const categoriaFoco = kpis?.categoriaFoco ?? "Feminino";
  const rotuloFoco =
    recorte === "sexo" ? "mulheres" : recorte === "raca" ? "pessoas negras" : "mulheres negras";

  const exportar = () => {
    if (!dados) return;
    baixarCsv(`diversidade-ti-${dados.filtros.ano}-${dados.filtros.uf ?? "BR"}.csv`, [
      ["Degrau", "Nível", "Sexo", "Raça/cor (IBGE)", "Vínculos"],
      ...dados.funil.map((l) => [l.degrau, l.nivel, l.sexo, l.grupoRacial, l.vinculos]),
    ]);
  };

  return (
    <div className="gd-app" data-theme={tema} ref={raiz}>
      <style>{estilos}</style>

      <div className="gd-surround">
        <header className="gd-top">
          <div className="gd-brand">
            <span className="gd-logo" aria-hidden="true">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                <path d="M4 20V10M10 20V5M16 20v-7M22 20V8" />
              </svg>
            </span>
            <div>
              <strong>FUNIL TI</strong>
              <small>Diversidade no setor de tecnologia · UCSAL</small>
            </div>
          </div>
          <div className="gd-top-actions">
            <button type="button" className="gd-icon-button" title="Recarregar do banco"
              aria-label="Recarregar os dados do banco" onClick={() => buscar(ano, uf)}>
              <RefreshCw aria-hidden="true" />
            </button>
            <button type="button" className="gd-icon-button"
              title={tema === "light" ? "Mudar para o tema escuro" : "Mudar para o tema claro"}
              aria-label={tema === "light" ? "Mudar para o tema escuro" : "Mudar para o tema claro"}
              onClick={() => setTema(tema === "light" ? "dark" : "light")}>
              {tema === "light" ? <Moon aria-hidden="true" /> : <Sun aria-hidden="true" />}
            </button>
          </div>
        </header>

        <div className="gd-stage-wrap">
          <main className="gd-stage">
            <header className="gd-view-head">
              <div>
                <h1>Raça, gênero e o funil de liderança na TI brasileira</h1>
                <p>
                  Quem trabalha nas empresas de tecnologia do Brasil, quem chega aos cargos de
                  chefia e quanto cada grupo recebe. Os dados são de todos os empregos com
                  carteira assinada em empresas de TI, declarados pelas próprias empresas ao
                  Ministério do Trabalho. Use os botões ao lado para ver o mesmo retrato por
                  gênero, por raça/cor, ou pelos dois cruzados na mesma pessoa.
                </p>
              </div>
              <div className="gd-view-actions">
                <div className="gd-period" role="group" aria-label="Recorte da análise">
                  <button type="button" aria-pressed={recorte === "sexo"} onClick={() => setRecorte("sexo")}>Gênero</button>
                  <button type="button" aria-pressed={recorte === "raca"} onClick={() => setRecorte("raca")}>Raça/cor</button>
                  <button type="button" aria-pressed={recorte === "cruzado"} onClick={() => setRecorte("cruzado")}>Os dois juntos</button>
                </div>
                {dados && (
                  <>
                    <Seletor rotulo="Ano de referência" icone={<Filter aria-hidden="true" />}
                      valor={String(ano ?? dados.filtros.ano)}
                      opcoes={dados.opcoes.anos.map((a) => ({ valor: String(a), texto: String(a) }))}
                      aoMudar={(v) => { setAno(Number(v)); void buscar(Number(v), uf); }} />
                    <Seletor rotulo="Unidade da federação" icone={<MapPin aria-hidden="true" />}
                      valor={uf}
                      opcoes={[{ valor: "BR", texto: "Brasil" },
                        ...dados.opcoes.ufs.map((u) => ({ valor: u.sigla, texto: `${u.sigla} · ${u.regiao}` }))]}
                      aoMudar={(v) => { setUf(v); void buscar(ano, v); }} />
                    <button type="button" className="gd-primary" onClick={exportar}>
                      <Download aria-hidden="true" />Exportar CSV
                    </button>
                  </>
                )}
              </div>
            </header>

            {falha && (
              <div className="gd-aviso" role="status">
                <CloudOff aria-hidden="true" />
                <div>
                  <strong>{falha.tipo === "hibernando" ? "O banco está hibernando" : "Falha ao consultar o banco"}</strong>
                  <p>
                    {falha.mensagem}{" "}
                    {falha.tipo === "hibernando" && (
                      <>Para religar: console da Aiven, projeto <code>ucsal-bigdata-2026</code>, serviço{" "}
                      <code>ti-diversidade-pg</code>, menu de ações, <code>Power on service</code>.</>
                    )}
                  </p>
                </div>
              </div>
            )}

            <div ref={corpo}>
              {carregando && !dados && (
                <div className="gd-carregando"><span className="gd-spinner" aria-hidden="true" />Consultando o banco…</div>
              )}

              {dados && kpis && (
                <>
                  <div className="gd-metric-grid">
                    <Kpi titulo={`No setor · ${rotuloFoco}`} icone={<Users />}
                      valor={pct(kpis.noSetor)}
                      delta={kpis.referencia ? pct(kpis.noSetor - kpis.referencia.valor, 1) : undefined}
                      alerta={!!kpis.referencia && kpis.noSetor < kpis.referencia.valor}
                      legenda={kpis.referencia
                        ? `de cada 100 pessoas empregadas em TI. São ${pct(kpis.referencia.valor, 1)} ${kpis.referencia.fonte}`
                        : "de cada 100 pessoas empregadas em TI"} />

                    <Kpi titulo={`Na chefia · ${rotuloFoco}`} icone={<UserRound />}
                      valor={pct(kpis.naLideranca)}
                      delta={pct(kpis.naLideranca - kpis.noSetor, 1)}
                      alerta={kpis.naLideranca < kpis.noSetor}
                      legenda={`dos cargos de direção e gerência. ${
                        kpis.naLideranca < kpis.noSetor
                          ? "Menos espaço no topo do que no setor como um todo"
                          : "Mais espaço no topo do que no setor como um todo"}`} />

                    <Kpi titulo="A cada R$ 100 de um homem branco" icone={<Banknote />} destaque
                      valor={kpis.razaoInterseccional > 0 ? `R$ ${kpis.razaoInterseccional.toFixed(0)}` : "—"}
                      delta={kpis.razaoInterseccional > 0 ? pct(kpis.razaoInterseccional - 100, 0) : undefined}
                      alerta={kpis.razaoInterseccional < 100}
                      legenda="é o que recebe, em média, uma mulher negra no mesmo setor" />

                    <Kpi titulo="Onde o grupo mais perde espaço" icone={<TrendingDown />}
                      valor={pct(kpis.afunilamento.maisEstreito.pct)}
                      delta={kpis.afunilamento.maisEstreito.nome}
                      alerta={kpis.afunilamento.maisEstreito.pct < kpis.afunilamento.naBase}
                      legenda={`é o degrau da carreira em que ${rotuloFoco} têm a menor fatia dos postos`} />
                  </div>

                  <div className="gd-grid-2">
                    <Painel titulo="O funil de liderança"
                      subtitulo="Pense na carreira em tecnologia como uma escada de três degraus. Embaixo estão os cargos de apoio e suporte. No meio, quem faz o trabalho técnico: programar, analisar, projetar sistemas. No topo, quem dirige e gerencia. Cada barra mostra como aquele degrau se divide entre os grupos."
                      acao={<Legenda itens={kpis.categoriasPresentes} />}>
                      <Funil dados={dados} recorte={recorte} />
                      <p className="gd-nota">
                        <strong>Como ler:</strong>{" "}
                        {kpis.afunilamento.gargaloNoMeio
                          ? `se o grupo tivesse o mesmo espaço em todos os degraus, as três barras teriam fatias do mesmo tamanho. Aqui ${rotuloFoco} ocupam ${pct(kpis.afunilamento.naBase)} da base e ${pct(kpis.afunilamento.naLideranca)} da chefia, mas só ${pct(kpis.afunilamento.maisEstreito.pct)} do degrau do meio. O aperto não está no topo da escada, está no meio dela, justamente onde fica o trabalho técnico.`
                          : `se o grupo tivesse o mesmo espaço em todos os degraus, as três barras teriam fatias do mesmo tamanho. Aqui a fatia encolhe conforme a escada sobe: ${rotuloFoco} são ${pct(kpis.afunilamento.naBase)} da base e apenas ${pct(kpis.afunilamento.naLideranca)} da chefia.`}
                        {" "}Quem tem o cargo em branco no registro do governo fica de fora desta conta.
                      </p>
                    </Painel>

                    <Painel titulo="Quem está no setor"
                      subtitulo="De cada 100 pessoas empregadas em empresas de tecnologia, quantas são de cada grupo. Clique numa linha para destacá-la.">
                      <Rosca dados={dados} recorte={recorte} />
                    </Painel>
                  </div>

                  <div className="gd-grid-2b">
                    <Painel titulo="Quanto cada grupo recebe"
                      subtitulo="Salário médio mensal de quem trabalha em TI, separando as pessoas por gênero e cor ao mesmo tempo. Este gráfico não muda com os botões de recorte: ele existe para mostrar o que acontece quando as duas desvantagens caem sobre a mesma pessoa.">
                      <BarrasRemuneracao dados={dados} />
                      <p className="gd-nota">
                        <strong>Como ler:</strong> olhe a primeira e a última barra. Sozinho, o fato
                        de ser mulher já custa salário: elas recebem {pct(kpis.gapGenero, 0)} do que
                        os homens recebem. Sozinho, ser uma pessoa negra também custa:{" "}
                        {pct(kpis.gapRacial, 0)} do que recebe uma pessoa branca. Quando as duas
                        coisas se encontram na mesma pessoa, a conta não soma, multiplica, e sobra{" "}
                        {pct(kpis.razaoInterseccional, 0)}.
                      </p>
                    </Painel>

                    <Painel titulo={`Em que estados ${rotuloFoco} têm mais espaço`}
                      subtitulo="A mesma participação do primeiro indicador, agora estado por estado. Estados com menos de mil empregos em TI ficam fora, porque com pouca gente qualquer variação vira ruído.">
                      <TabelaUf dados={dados} recorte={recorte} categoria={categoriaFoco} />
                    </Painel>
                  </div>

                  <Painel titulo="O setor está mudando de cara?"
                    subtitulo="Contratações e demissões em empresas de TI ao longo do ano. Se o perfil de quem está entrando for mais diverso que o perfil de quem já está empregado, a composição do setor tende a mudar com o tempo.">
                    <TabelaFluxo dados={dados} recorte={recorte} />
                    <p className="gd-nota">
                      <strong>Como ler:</strong> o saldo é quanto o grupo cresceu no ano, contratações
                      menos demissões. Um saldo positivo em todos os grupos significa que o setor
                      cresceu para todo mundo, o que não diz nada sobre igualdade por si só. O que
                      importa é comparar a fatia do grupo entre as contratações com a fatia que ele
                      já tem no setor, mostrada no primeiro indicador.
                    </p>
                  </Painel>

                </>
              )}
            </div>
          </main>
        </div>

        <footer className="gd-footer">
          <span>
            {dados
              ? `${inteiro.format(dados.funil.reduce((s, l) => s + l.vinculos, 0))} vínculos publicáveis · ${dados.filtros.ano} · ${dados.filtros.uf ?? "Brasil"}`
              : "Carregando…"}
          </span>
          <span>
            <Scale aria-hidden="true" />
            Fonte: RAIS e Novo CAGED (PDET/MTE). Supressão k≥5 aplicada no banco.
          </span>
        </footer>
      </div>
    </div>
  );
}
