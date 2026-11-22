/**
 * Visual adaptado do componente "glassy dashboard" (21st.dev). O que veio de lá é a
 * linguagem visual: vidro fosco, cantos arredondados, paleta quente, tema claro e
 * escuro. Os gráficos e a estrutura de dados são próprios, porque o original traz
 * séries fixas de duas categorias e aqui há recortes com até sete.
 */
export const estilos = `
.gd-app {
  --gd-ink: #25201e;
  --gd-muted: #5c4e46;
  --gd-line: rgb(74 49 33 / 15%);
  --gd-grid: rgb(74 49 33 / 19%);
  --gd-rim: rgb(255 253 246 / 51%);
  --gd-edge-light: rgb(255 254 247 / 84%);
  --gd-edge-shade: rgb(57 40 28 / 19%);
  --gd-gloss: rgb(255 251 242 / 45%);
  --gd-frame: rgb(250 240 229 / 47%);
  --gd-rail: rgb(241 222 206 / 48%);
  --gd-card: rgb(250 242 232 / 46%);
  --gd-card-light: rgb(255 251 245 / 34%);
  --gd-raised: rgb(255 249 243 / 81%);
  --gd-inner: rgb(255 250 245 / 37%);
  --gd-surface: #f6ece2;
  --gd-track: rgb(81 49 32 / 14%);
  --gd-primary: #261e1b;
  --gd-primary-ink: #fffaf5;
  --gd-pick: #fff9f3;
  --gd-pick-ink: #241b17;
  --gd-coral: #a43c27;
  --gd-teal: #09644f;
  --gd-ochre: #8a5800;
  --gd-violet: #5b3a8e;
  --gd-graph-ink: #40332d;
  --gd-focus: #194b48;
  --gd-dark-shadow: 35 21 14;
  inline-size: 100%;
  min-inline-size: 0;
  position: relative;
  isolation: isolate;
  min-block-size: 100svh;
  background: #ab8e76;
  color: var(--gd-ink);
  color-scheme: light;
  font-family: "Manrope Variable", Manrope, system-ui, sans-serif;
  font-size: 13px;
  font-weight: 550;
  font-variant-numeric: tabular-nums;
}
.gd-app[data-theme="dark"] {
  --gd-ink: #fff6e9;
  --gd-muted: #cdbbac;
  --gd-line: rgb(243 221 198 / 19%);
  --gd-grid: rgb(243 221 198 / 19%);
  --gd-rim: rgb(255 236 212 / 31%);
  --gd-edge-light: rgb(255 242 225 / 49%);
  --gd-edge-shade: rgb(11 6 5 / 30%);
  --gd-gloss: rgb(255 237 213 / 13%);
  --gd-frame: rgb(40 30 28 / 68%);
  --gd-rail: rgb(45 32 30 / 59%);
  --gd-card: rgb(47 36 34 / 53%);
  --gd-card-light: rgb(106 88 81 / 30%);
  --gd-raised: rgb(80 67 61 / 82%);
  --gd-inner: rgb(78 61 56 / 49%);
  --gd-surface: #3b302c;
  --gd-track: rgb(245 226 212 / 16%);
  --gd-primary: #f3ddca;
  --gd-primary-ink: #231a16;
  --gd-pick: #f9eee0;
  --gd-pick-ink: #241b17;
  --gd-coral: #ff9177;
  --gd-teal: #75dac0;
  --gd-ochre: #f1be58;
  --gd-violet: #c3a3f5;
  --gd-graph-ink: #e7d9cd;
  --gd-focus: #f9bf9b;
  --gd-dark-shadow: 10 4 3;
  background: #40322b;
  color-scheme: dark;
}

.gd-app *, .gd-app *::before, .gd-app *::after { box-sizing: border-box; }
.gd-app :where(button, input, select) { color: inherit; font: inherit; }
.gd-app :where(button, a, input, select):focus-visible { outline: 2px solid var(--gd-focus); outline-offset: 3px; }
.gd-app a { color: inherit; text-decoration: none; }
.gd-app button { cursor: pointer; }
.gd-app :where(h1, h2, h3, p, figure) { margin: 0; }
.gd-app svg { flex: none; }
.gd-sr { position: absolute; inline-size: 1px; block-size: 1px; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }

.gd-app::before {
  content: ""; position: fixed; z-index: -1; inset: 0; inline-size: 100%; block-size: 100%; pointer-events: none;
  background:
    radial-gradient(ellipse 70% 55% at 12% 8%, rgb(255 214 170 / 85%), transparent 62%),
    radial-gradient(ellipse 60% 50% at 88% 12%, rgb(214 178 226 / 62%), transparent 60%),
    radial-gradient(ellipse 75% 60% at 78% 92%, rgb(142 198 182 / 55%), transparent 64%),
    radial-gradient(ellipse 65% 55% at 22% 88%, rgb(232 160 128 / 60%), transparent 62%),
    linear-gradient(152deg, #e8c9a8, #c9a688 48%, #b08f74);
}
.gd-app[data-theme="dark"]::before {
  background:
    radial-gradient(ellipse 70% 55% at 12% 8%, rgb(120 72 46 / 72%), transparent 62%),
    radial-gradient(ellipse 60% 50% at 88% 12%, rgb(78 52 102 / 62%), transparent 60%),
    radial-gradient(ellipse 75% 60% at 78% 92%, rgb(22 86 74 / 58%), transparent 64%),
    radial-gradient(ellipse 65% 55% at 22% 88%, rgb(126 58 40 / 52%), transparent 62%),
    linear-gradient(152deg, #4a3a30, #3a2d27 48%, #2c2320);
}

.gd-surround { inline-size: min(calc(100% - 64px), 1420px); margin-inline: auto; padding-block: 24px 8px; }
.gd-top {
  display: grid; grid-template-columns: minmax(0, 1fr) auto; align-items: center; gap: 12px;
  min-block-size: 60px; border-radius: 999px; padding: 6px 9px 6px 13px;
  border: 1px solid var(--gd-rim);
  background: linear-gradient(165deg, var(--gd-gloss), transparent 32% 73%, var(--gd-gloss)), var(--gd-rail);
  box-shadow: inset 1px 1px 1px var(--gd-edge-light), inset -1px -1px 1px var(--gd-edge-shade),
    inset 0 -2px 5px var(--gd-gloss), 0 7px 20px rgb(var(--gd-dark-shadow) / 17%);
  backdrop-filter: blur(15px) saturate(1.35);
  -webkit-backdrop-filter: blur(15px) saturate(1.35);
}
.gd-brand { display: flex; align-items: center; gap: 10px; min-inline-size: 0; padding-inline-start: 3px; }
.gd-logo {
  inline-size: 35px; block-size: 35px; display: grid; place-items: center; border-radius: 50%;
  background: var(--gd-pick); color: var(--gd-pick-ink);
  box-shadow: inset 0 0 0 1px var(--gd-gloss), 0 2px 7px rgb(var(--gd-dark-shadow) / 12%);
}
.gd-logo svg { width: 20px; height: 20px; }
.gd-brand strong { display: block; font-size: 12px; letter-spacing: .17em; line-height: 1.1; font-weight: 850; }
.gd-brand small { display: block; margin-block-start: 3px; font-size: 10px; color: var(--gd-muted); }
.gd-top-actions { display: flex; justify-content: flex-end; align-items: center; gap: 6px; }
.gd-icon-button {
  position: relative; min-inline-size: 44px; min-block-size: 44px; display: inline-grid; place-items: center;
  border-radius: 999px; border: 1px solid var(--gd-line); padding: 0; background: var(--gd-inner);
}
.gd-icon-button:hover { background: var(--gd-raised); }
.gd-icon-button svg { width: 17px; height: 17px; stroke-width: 1.75; }

.gd-stage-wrap { position: relative; margin-block: 11px 0; }
.gd-stage {
  display: block; color: var(--gd-ink); border: 1px solid var(--gd-rim); border-radius: 34px;
  background: linear-gradient(148deg, var(--gd-gloss), transparent 19% 77%, color-mix(in srgb, var(--gd-gloss) 48%, transparent)), var(--gd-frame);
  box-shadow: inset 1px 1px 1px var(--gd-edge-light), inset -1px -1px 1px var(--gd-edge-shade),
    inset 0 0 7px var(--gd-gloss), 0 1px 3px rgb(var(--gd-dark-shadow) / 17%), 0 22px 72px rgb(var(--gd-dark-shadow) / 22%);
  backdrop-filter: blur(12px) saturate(1.24);
  -webkit-backdrop-filter: blur(12px) saturate(1.24);
  padding: clamp(19px, 2.15vw, 35px) clamp(20px, 3.2vw, 44px) 36px;
}
.gd-view-head { display: flex; align-items: flex-end; justify-content: space-between; gap: 14px 22px; flex-wrap: wrap; margin-block-end: 18px; }
.gd-view-head h1 { font-size: clamp(26px, 3vw, 42px); font-weight: 760; line-height: 1.04; letter-spacing: -.062em; max-inline-size: 18ch; }
.gd-view-head p { color: var(--gd-muted); font-size: 12.5px; margin-block-start: 8px; max-inline-size: 62ch; line-height: 1.5; }
.gd-view-actions { display: flex; align-items: center; flex-wrap: wrap; justify-content: flex-end; gap: 7px; }

.gd-period { display: inline-flex; align-items: center; padding: 3px; border-radius: 999px; border: 1px solid var(--gd-rim); background: var(--gd-inner); box-shadow: inset 0 1px 0 var(--gd-gloss); }
.gd-period button { min-block-size: 35px; min-inline-size: 52px; border: 0; border-radius: 999px; background: transparent; padding: 0 12px; font-size: 11px; font-weight: 750; white-space: nowrap; }
.gd-period button[aria-pressed="true"] { background: var(--gd-primary); color: var(--gd-primary-ink); }
.gd-period button[aria-pressed="false"]:hover { background: var(--gd-raised); }

.gd-primary, .gd-secondary {
  display: inline-flex; justify-content: center; align-items: center; gap: 7px; min-block-size: 40px;
  padding: 7px 13px; font-size: 11.5px; font-weight: 790; line-height: 1.2; border-radius: 999px; border: 1px solid transparent;
}
.gd-primary { background: var(--gd-primary); color: var(--gd-primary-ink); }
.gd-secondary { background: var(--gd-raised); border-color: var(--gd-rim); color: var(--gd-ink); }
.gd-primary:hover { filter: brightness(1.17); }
.gd-secondary:hover { background: var(--gd-surface); }
.gd-primary svg, .gd-secondary svg { width: 14px; height: 14px; }

.gd-filter { display: inline-flex; align-items: center; gap: 6px; border: 1px solid var(--gd-line); border-radius: 999px; background: var(--gd-inner); min-block-size: 41px; padding: 0 11px; }
.gd-filter svg { width: 13px; height: 13px; color: var(--gd-muted); }
.gd-filter select { border: 0; background: transparent; padding: 5px 0; min-inline-size: 0; font-size: 11.5px; font-weight: 740; }
.gd-filter select option { color: var(--gd-ink); background: var(--gd-surface); }
.gd-filter:focus-within { outline: 2px solid var(--gd-focus); }
.gd-app .gd-filter select:focus-visible { outline: none; }

.gd-metric-grid { display: grid; gap: 12px; grid-template-columns: repeat(4, minmax(0, 1fr)); margin-block-end: 12px; }
.gd-grid-2 { display: grid; gap: 12px; grid-template-columns: minmax(0, 1.35fr) minmax(0, 1fr); margin-block-end: 12px; }
.gd-grid-2b { display: grid; gap: 12px; grid-template-columns: minmax(0, 1fr) minmax(0, 1.35fr); margin-block-end: 12px; }

.gd-panel, .gd-metric {
  min-inline-size: 0; border: 1px solid var(--gd-rim); border-radius: 20px;
  background: linear-gradient(144deg, var(--gd-card-light), transparent 66%), var(--gd-card);
  box-shadow: inset 0 1px 1px var(--gd-edge-light), inset 0 -1px 1px var(--gd-edge-shade), 0 6px 18px rgb(var(--gd-dark-shadow) / 9%);
}
.gd-panel { padding: 15px 17px 17px; }
.gd-panel-head { display: flex; flex-wrap: wrap; justify-content: space-between; align-items: flex-start; gap: 7px 12px; margin-block-end: 13px; }
.gd-panel-head h2 { font-size: 14px; font-weight: 810; letter-spacing: -.024em; }
.gd-panel-head p { font-size: 11px; color: var(--gd-muted); margin-block-start: 4px; max-inline-size: 58ch; line-height: 1.45; }

.gd-metric { display: flex; flex-direction: column; justify-content: space-between; min-block-size: 124px; padding: 12px 13px; }
.gd-metric[data-destaque="true"] {
  --gd-muted: #e4f5ef; color: #fff; border-color: rgb(196 248 231 / 55%);
  background: radial-gradient(ellipse at 5% -20%, #3a9381, transparent 68%), linear-gradient(145deg, #1e7461, #08443a);
  box-shadow: inset 0 1px 2px rgb(214 252 240 / 45%), 0 6px 14px rgb(19 78 64 / 17%);
}
.gd-metric-head { display: flex; justify-content: space-between; align-items: center; gap: 4px; min-inline-size: 0; font-size: 11px; font-weight: 740; }
.gd-metric-icon { display: grid; place-items: center; flex: none; color: inherit; inline-size: 28px; block-size: 28px; border-radius: 10px; background: var(--gd-inner); box-shadow: inset 0 1px 0 var(--gd-gloss); }
.gd-metric[data-destaque="true"] .gd-metric-icon { background: rgb(235 255 247 / 16%); }
.gd-metric-icon svg { width: 14px; height: 14px; }
.gd-metric-value { display: block; font-size: clamp(24px, 2.5vw, 36px); line-height: 1.05; margin-block: 5px 7px; letter-spacing: -.052em; font-weight: 815; }
.gd-metric-caption { display: flex; flex-wrap: wrap; align-items: center; gap: 4px; color: var(--gd-muted); font-size: 10.5px; font-weight: 680; line-height: 1.4; }
.gd-delta { display: inline-flex; align-items: center; gap: 2px; color: var(--gd-teal); font-weight: 850; border-radius: 6px; padding: 2px 5px; background: color-mix(in srgb, var(--gd-teal) 12%, transparent); }
.gd-delta[data-alerta="true"] { color: var(--gd-coral); background: color-mix(in srgb, var(--gd-coral) 11%, transparent); }
.gd-metric[data-destaque="true"] .gd-delta { color: #b8f1dd; background: rgb(235 255 247 / 14%); }
.gd-delta svg { width: 11px; height: 11px; stroke-width: 2.4; }

.gd-app [data-tone="ink"] { --gd-series: var(--gd-graph-ink); }
.gd-app [data-tone="coral"] { --gd-series: var(--gd-coral); }
.gd-app [data-tone="teal"] { --gd-series: var(--gd-teal); }
.gd-app [data-tone="ochre"] { --gd-series: var(--gd-ochre); }
.gd-app [data-tone="violet"] { --gd-series: var(--gd-violet); }
.gd-legend { display: inline-flex; flex-wrap: wrap; align-items: center; gap: 6px 13px; color: var(--gd-muted); }
.gd-legend span { display: inline-flex; align-items: center; gap: 5px; font-size: 10px; font-weight: 740; }
.gd-legend i { inline-size: 8px; block-size: 8px; border-radius: 3px; background: var(--gd-series); }

/* Funil: barras horizontais empilhadas, um degrau por linha. */
.gd-funil { display: grid; gap: 11px; }
.gd-funil-linha { display: grid; grid-template-columns: 104px minmax(0, 1fr); gap: 11px; align-items: center; }
.gd-funil-rotulo strong { display: block; font-size: 11.5px; font-weight: 830; }
.gd-funil-rotulo small { display: block; margin-top: 3px; font-size: 9.5px; color: var(--gd-muted); }
.gd-funil-barra { display: flex; block-size: 38px; border-radius: 9px; overflow: hidden; background: var(--gd-track); }
.gd-funil-fatia { position: relative; display: grid; place-items: center; min-inline-size: 0; background: var(--gd-series); color: #fff; font-size: 10px; font-weight: 830; transition: filter .18s ease; overflow: hidden; }
.gd-app[data-theme="dark"] .gd-funil-fatia { color: #241b17; }
.gd-funil-fatia:hover { filter: brightness(1.12); }
.gd-funil-fatia span { padding-inline: 3px; white-space: nowrap; }

/* Barras verticais comparativas, usadas na remuneração. */
.gd-barras { display: grid; grid-template-columns: repeat(var(--gd-n), minmax(0, 1fr)); gap: 8px; block-size: 212px; align-items: end; }
.gd-barra-col { display: flex; flex-direction: column; align-items: center; justify-content: flex-end; min-inline-size: 0; block-size: 100%; gap: 6px; }
.gd-barra-valor { font-size: 10.5px; font-weight: 840; white-space: nowrap; }
.gd-barra-haste { inline-size: min(78%, 56px); border-radius: 8px 8px 3px 3px; background: var(--gd-series); transform-origin: bottom; }
.gd-barra-rotulo { font-size: 9.5px; color: var(--gd-muted); text-align: center; line-height: 1.3; min-block-size: 24px; }

/* Rosca de composição. */
.gd-rosca-wrap { display: grid; gap: 10px; }
.gd-rosca { position: relative; inline-size: min(100%, 168px); aspect-ratio: 1; justify-self: center; }
.gd-rosca svg { display: block; inline-size: 100%; block-size: 100%; }
.gd-rosca-seg { stroke: var(--gd-series); transition: opacity .2s ease; }
.gd-rosca-seg[data-apagado="true"] { opacity: .28; }
.gd-rosca-centro { position: absolute; inset: 0; display: flex; flex-direction: column; justify-content: center; align-items: center; pointer-events: none; }
.gd-rosca-centro strong { font-size: 22px; line-height: 1.05; letter-spacing: -.05em; font-weight: 850; }
.gd-rosca-centro > span { font-size: 10px; margin-top: 4px; color: var(--gd-muted); text-align: center; max-inline-size: 13ch; line-height: 1.25; }
.gd-lista { display: grid; gap: 2px; }
.gd-lista button { display: grid; grid-template-columns: 92px minmax(0, 1fr) 44px; gap: 8px; align-items: center; min-block-size: 30px; text-align: start; background: transparent; border: 0; border-radius: 8px; padding: 3px 6px; }
.gd-lista button:is(:hover, [aria-pressed="true"]) { background: var(--gd-inner); }
.gd-lista button > span:first-child { display: inline-flex; align-items: center; gap: 6px; font-size: 10.5px; font-weight: 740; }
.gd-lista button i { inline-size: 8px; block-size: 8px; border-radius: 3px; background: var(--gd-series); flex: none; }
.gd-lista button strong { text-align: end; font-weight: 850; font-size: 11px; }
.gd-trilha { display: block; height: 5px; border-radius: 999px; overflow: hidden; background: var(--gd-track); }
.gd-trilha i { display: block; block-size: 100%; border-radius: inherit; background: var(--gd-series); transform-origin: left center; }

/* Tabela do ranking e do fluxo. */
.gd-tabela-scroll { max-inline-size: 100%; overflow: auto; scrollbar-width: thin; }
.gd-tabela-scroll table { inline-size: 100%; border-spacing: 0; text-align: start; }
.gd-tabela-scroll th, .gd-tabela-scroll td { padding: 8px 10px; text-align: start; }
/* O cabecalho fica fixo durante o scroll, entao precisa de fundo opaco: com a cor
   translucida do painel as linhas passavam por tras e o texto ficava ilegivel. */
.gd-tabela-scroll th { background: var(--gd-surface); font-size: 10px; color: var(--gd-muted); font-weight: 800; position: sticky; top: 0; z-index: 1; box-shadow: 0 1px 0 var(--gd-line); }
.gd-tabela-scroll th:first-child { border-radius: 8px 0 0 8px; }
.gd-tabela-scroll th:last-child { border-radius: 0 8px 8px 0; }
.gd-tabela-scroll td { white-space: nowrap; font-size: 11px; }
.gd-tabela-scroll td:first-child { font-weight: 780; }
.gd-tabela-scroll tr + tr td { border-top: 1px solid var(--gd-line); }
.gd-num { text-align: end !important; font-variant-numeric: tabular-nums; }
.gd-mini { display: inline-block; block-size: 6px; border-radius: 999px; background: var(--gd-series); min-inline-size: 2px; vertical-align: middle; }

.gd-aviso { display: flex; gap: 11px; align-items: flex-start; border: 1px solid var(--gd-rim); border-radius: 16px; background: var(--gd-inner); padding: 13px 15px; margin-block-end: 12px; }
.gd-aviso svg { width: 17px; height: 17px; color: var(--gd-coral); margin-top: 1px; }
.gd-aviso strong { display: block; font-size: 12px; font-weight: 830; }
.gd-aviso p { font-size: 11.5px; color: var(--gd-muted); margin-top: 5px !important; line-height: 1.5; }
.gd-aviso code { font-size: 11px; background: var(--gd-track); border-radius: 5px; padding: 1px 5px; }

.gd-carregando { display: grid; place-items: center; min-block-size: 340px; gap: 11px; color: var(--gd-muted); font-size: 12px; }
.gd-spinner { inline-size: 26px; block-size: 26px; border-radius: 50%; border: 2.5px solid var(--gd-track); border-top-color: var(--gd-ink); animation: gd-girar .7s linear infinite; }
@keyframes gd-girar { to { transform: rotate(360deg); } }
.gd-vazio { padding: 22px 4px; color: var(--gd-muted); font-size: 12px; text-align: center; }

.gd-nota { font-size: 10.5px; color: var(--gd-muted); line-height: 1.55; margin-top: 11px; }
.gd-footer { padding: 26px 4px 2px; display: flex; justify-content: space-between; align-items: center; gap: 10px; flex-wrap: wrap; }
.gd-footer > * { border-radius: 999px; padding: 6px 10px; color: var(--gd-ink); font-size: 10px; font-weight: 740; background: var(--gd-raised); min-block-size: 24px; display: flex; align-items: center; gap: 5px; }
.gd-footer a:hover { text-decoration: underline; }
.gd-footer svg { width: 11px; height: 11px; }

@media (max-width: 1100px) {
  .gd-surround { inline-size: calc(100% - 40px); }
  .gd-metric-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .gd-grid-2, .gd-grid-2b { grid-template-columns: minmax(0, 1fr); }
}
@media (max-width: 760px) {
  .gd-surround { padding-top: 12px; inline-size: calc(100% - 24px); }
  .gd-top { grid-template-columns: minmax(0, 1fr) auto; padding: 7px 9px; border-radius: 21px; }
  .gd-stage { border-radius: 23px; padding: 16px 14px 20px; }
  .gd-view-head { align-items: flex-start; flex-direction: column; gap: 10px; }
  .gd-view-actions { justify-content: flex-start; }
  .gd-funil-linha { grid-template-columns: 78px minmax(0, 1fr); gap: 8px; }
  .gd-barras { block-size: 180px; }
  .gd-lista button { grid-template-columns: 78px minmax(0, 1fr) 40px; }
}
@media (max-width: 460px) {
  .gd-metric-grid { grid-template-columns: minmax(0, 1fr); }
  .gd-panel { padding: 13px; }
  .gd-tabela-scroll table { min-inline-size: 300px; }
}
@media (prefers-reduced-motion: reduce) {
  .gd-app *, .gd-app *::before, .gd-app *::after { animation-duration: .01ms !important; transition-duration: .01ms !important; }
}
@media (prefers-reduced-transparency: reduce), (prefers-contrast: more), (forced-colors: active) {
  .gd-top, .gd-stage, .gd-panel, .gd-metric { background: var(--gd-surface); backdrop-filter: none; -webkit-backdrop-filter: none; }
  .gd-metric[data-destaque="true"] { background: var(--gd-surface); color: var(--gd-ink); --gd-muted: var(--gd-ink); }
}
@media (forced-colors: active) {
  .gd-app { --gd-ink: CanvasText; --gd-muted: CanvasText; --gd-focus: Highlight; --gd-surface: Canvas; }
  .gd-app :is(.gd-metric, .gd-panel, button, .gd-stage) { border: 1px solid CanvasText; }
}
`;
