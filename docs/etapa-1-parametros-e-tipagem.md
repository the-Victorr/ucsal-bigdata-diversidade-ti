# Etapa 1 — Levantamento de Parâmetros e Tipagem de Dados

**Projeto:** Diversidade na Tecnologia: Raça, Gênero e o Funil de Liderança no Setor de TI Brasileiro
**Disciplina:** Big Data e Analytics (UCSAL, 2026.2)
**Bloco temático do guia:** Analytics de GAP Salarial e Funil de Liderança Corporativa
**Base pública oficial (designada no guia):** Microdados da RAIS e do Novo CAGED (PDET / MTE)
**ODS de alinhamento:** ODS 5 (Igualdade de Gênero) e ODS 18 (Igualdade Étnico-Racial)
**Etapa do ciclo (guia, seção 2):** 2. Ingestão & Tipagem — subsidia também a 3 (ETL) e a 4 (Modelagem BD)

> **Convenção de veracidade deste documento.** Tudo o que é marcado como **[estimativa]** é ordem de grandeza calculada a partir de premissas explicitadas, não medição. Tudo o que é marcado como **[a confirmar no download]** é detalhe que deve ser verificado no arquivo real (layout, encoding, nome de coluna) antes de virar código. Tudo o que é marcado como **[proposta]** é decisão de modelagem nossa, não regra da fonte.

---

## 0. Por que esta etapa existe

O barema do guia (critério 2, *Pipeline de Dados, Tratamento e Modelagem*, 2,5 pts) avalia explicitamente **conversão correta de tipos** e **respeito ao limite de 1 GB** do Aiven for PostgreSQL Free Tier. Os microdados da RAIS têm dezenas de gigabytes por ano; portanto, antes de escrever uma linha de ETL, precisamos saber: (1) exatamente de onde os dados vêm e em que formato; (2) como reduzir o volume sem destruir a análise interseccional; (3) qual o tipo de cada coluna na origem e qual será no destino.

Este documento responde a esses três pontos.

---

## 1. Identificação da Fonte

> **Atualização de 18/09/2026 — confirmado por download.** Os itens abaixo marcados "[a confirmar no download]" foram verificados com arquivos reais (RAIS AC/2015, NI/2022, NI/2023 e CAGEDMOV 2024-01). Resultado consolidado:
>
> | Base | Interno | Delimitador | Encoding | Decimal | Nulo |
> |---|---|---|---|---|---|
> | RAIS 2015–2017 (1 `.7z` por UF, ex. `BA2015.7z`) | `.txt`, 57 col. | `;` | Latin-1 | vírgula, zero à esquerda | `{ñ c}` / `{ñ class}` |
> | RAIS 2018–2022 (1 `.7z` por região) | `.txt`, 60 col. | `;` | Latin-1 | vírgula, zero à esquerda | `9997` / `999999` |
> | **RAIS 2023+** (1 `.7z` por região) | **`.COMT`**, 62 col., campos entre aspas, nomes com sufixo ` - Código` | **`,`** | Latin-1 | **ponto** (`2242.58`) | `999997` / `999` / `999999` |
> | Novo CAGED 2020+ | `.txt`, 28 col., nomes minúsculos com acento | `;` | **UTF-8** | vírgula | `9` / `99` |
>
> Onde o texto original desta seção diz "`;` e vírgula decimal" para a RAIS, isso vale só até 2022. Os três leitores estão em `etl/sources.py`. Tamanhos reais no FTP: RAIS 2,4–3,2 GB/ano comprimido (~15× ao descompactar); CAGED 0,35–0,6 GB/ano.

### 1.1 Fonte primária A — RAIS (Relação Anual de Informações Sociais), base "Vínculos"

| Parâmetro | Valor | Status |
|---|---|---|
| Órgão responsável | Ministério do Trabalho e Emprego (MTE), via PDET (Programa de Disseminação das Estatísticas do Trabalho) | Confirmado (guia + PDET) |
| Natureza | Registro administrativo anual, censitário (todos os vínculos formais declarados pelos empregadores no ano-base) | Confirmado |
| Unidade de observação | **Vínculo empregatício** (1 linha = 1 vínculo em 1 ano-base). Um mesmo trabalhador pode ter mais de uma linha no ano | Confirmado |
| Periodicidade | Anual (ano-base t é publicado em t+1, geralmente no segundo semestre) | Confirmado |
| Canal de distribuição | FTP público do PDET: `ftp://ftp.mtps.gov.br/pdet/microdados/RAIS/{ANO}/` | [a confirmar no download] — o endereço já mudou de host no passado; validar se o caminho ainda responde |
| Formato do pacote | Arquivos comprimidos **.7z**, um por região/UF (ex.: `RAIS_VINC_PUB_NORDESTE.7z`, `RAIS_VINC_PUB_SP.7z`, `RAIS_VINC_PUB_MG_ES_RJ.7z`, `RAIS_VINC_PUB_SUL.7z`, `RAIS_VINC_PUB_NORTE.7z`, `RAIS_VINC_PUB_CENTRO_OESTE.7z` para os anos mais recentes). Anos antigos podem vir particionados por UF (ex.: `BA{ANO}.7z`) | [a confirmar no download] — o particionamento variou ao longo dos anos |
| Formato interno | Texto plano (**.txt**) com **cabeçalho na primeira linha**, campos delimitados por **`;`** | Confirmado pela prática com a base; validar a cada ano |
| Encoding | **Latin-1 (ISO-8859-1)** — nomes de coluna e rótulos têm acentos (ex.: `Município`, `CBO Ocupação 2002`) | [a confirmar no download] — se o `pandas.read_csv(encoding="latin-1")` produzir cabeçalho legível, está confirmado |
| Separador decimal | **Vírgula** (`1234,56`) nos campos monetários e em `Tempo Emprego` | Confirmado pela prática; validar |
| Separador de milhar | Ausente (não há `.` de milhar) | [a confirmar no download] |
| Quantidade de colunas | Ordem de 60 colunas no layout público (vínculos) | [a confirmar no download] |
| Chave/identificação | A versão **pública** (sufixo `PUB`) **não traz CPF, PIS, nome, CNPJ/CEI do estabelecimento**; a versão identificada só é cedida por convênio. Trabalharemos exclusivamente com a versão pública | Confirmado (política PDET); validar que nenhuma coluna identificadora "sobrou" |
| Licença | Dados abertos governamentais (Lei 12.527/2011 – LAI; Decreto 8.777/2016) | Confirmado |

**Como a fonte se encaixa no tema:** a RAIS é a única base pública que traz, na mesma linha, **sexo + raça/cor + ocupação (CBO) + remuneração + setor (CNAE) + escolaridade + UF**. É ela que permite construir o funil de liderança (quem chega a cargos de direção/gerência em TI) cruzado com gênero e raça.

### 1.2 Fonte primária B — Novo CAGED (Cadastro Geral de Empregados e Desempregados)

| Parâmetro | Valor | Status |
|---|---|---|
| Órgão responsável | MTE, via PDET | Confirmado |
| Natureza | Registro administrativo **mensal** de admissões e desligamentos (movimentações), a partir de jan/2020 alimentado pelo eSocial | Confirmado |
| Unidade de observação | **Movimentação** (1 linha = 1 admissão ou 1 desligamento) | Confirmado |
| Periodicidade | Mensal (competência AAAAMM) | Confirmado |
| Canal de distribuição | FTP público do PDET: `ftp://ftp.mtps.gov.br/pdet/microdados/NOVO CAGED/{ANO}/{AAAAMM}/` | [a confirmar no download] |
| Formato do pacote | Arquivos **.7z** por competência: `CAGEDMOV{AAAAMM}.7z` (movimentações no prazo), `CAGEDFOR{AAAAMM}.7z` (declaradas fora do prazo) e `CAGEDEXC{AAAAMM}.7z` (exclusões/estornos) | [a confirmar no download] — existência dos três tipos |
| Formato interno | Texto plano (**.txt**) com cabeçalho, delimitado por **`;`** | [a confirmar no download] |
| Encoding | Latin-1 ou UTF-8 — **[a confirmar no download]**. Não assumir; detectar com `chardet`/tentativa dupla no ETL |
| Separador decimal | Vírgula em `salário` e `valorsaláriofixo` | [a confirmar no download] |
| Nomes de coluna | Minúsculos, sem espaço, com acento (ex.: `competênciamov`, `saldomovimentação`, `cbo2002ocupação`, `raçacor`) | [a confirmar no download] |
| Recorte temporal disponível | 2020 em diante (o CAGED antigo, pré-2020, tem layout diferente e será **descartado** para evitar quebra de série) | Decisão nossa [proposta] |

**Como a fonte se encaixa no tema:** o Novo CAGED fornece a **rotatividade** (admissões × desligamentos) mês a mês, por sexo, raça/cor, CBO e CNAE — é a métrica alternável "Taxa de Rotatividade" exigida no dashboard.

### 1.3 Fontes secundárias (dicionários, tabelas auxiliares e APIs)

| Fonte | Conteúdo | Formato | Uso no projeto | Status |
|---|---|---|---|---|
| **Layout/dicionário RAIS** (PDET, pasta do ano, ex.: `Layout RAIS Vínculos.xls` ou `.pdf`) | Nome, posição, tipo e domínio de cada coluna | XLS/PDF | Fonte de verdade para a seção 3; gera as tabelas de lookup (`dim_*`) | [a confirmar no download] — nome exato do arquivo |
| **Layout/dicionário Novo CAGED** (PDET, `Layout Novo CAGED Movimentação.xlsx`) | Idem para CAGED | XLSX | Idem | [a confirmar no download] |
| **CBO 2002** (MTE, portal CBO — tabelas de Grande Grupo, Subgrupo Principal, Subgrupo, Família, Ocupação) | Código de 6 dígitos + título + descrição sumária | CSV/XLS (download) ou HTML | `dim_ocupacao`; regra do funil de liderança (seção 3.6); título e descrição = dado **não estruturado** | Confirmado que existe; formato de download [a confirmar] |
| **CNAE 2.0** (IBGE/CONCLA) | Seção, divisão, grupo, classe (5 dígitos), subclasse (7 dígitos) + denominação | XLS/CSV ou API CONCLA | `dim_setor`; filtro do recorte TI (divisões 62/63) | Confirmado |
| **API IBGE Localidades** (`https://servicodados.ibge.gov.br/api/v1/localidades/municipios`) | Municípios, UF, região, mesorregião | **JSON** (semi-estruturado) | `dim_localidade`; converte código de município RAIS (6 dígitos) em UF/região | Confirmado |
| **Salário mínimo por ano** (IPEA/Ipeadata ou série do BCB, ex.: série SGS 1619) | Valor nominal do SM em cada ano | CSV/JSON (API) | Deflacionar/normalizar remuneração em múltiplos de SM quando a coluna `(SM)` não bastar | Confirmado que existe; série exata [a confirmar] |
| **IPCA** (IBGE/SIDRA ou BCB SGS 433) | Índice mensal | JSON (API) | Opcional: salários a preços constantes para comparação entre anos | Opcional [proposta] |

Todas as fontes acima são **abertas, governamentais e brasileiras**, atendendo à regra obrigatória do guia.

---

## 2. Estratégia de Otimização de Volume (limite de 1 GB)

### 2.1 O problema em números **[estimativa]**

| Grandeza | Ordem de grandeza | Premissa |
|---|---|---|
| Vínculos na RAIS por ano-base (Brasil, todos os setores, ativos + desligados no ano) | **~60–75 milhões de linhas** | Divulgações do PDET indicam ~48–55 milhões de vínculos ativos em 31/12 + vínculos encerrados durante o ano |
| Tamanho de uma linha descompactada (txt) | **~350–600 bytes** | ~60 colunas × média de 6–10 bytes + separadores |
| Tamanho descompactado por ano | **~25–45 GB** | 65 mi × 500 B |
| Tamanho comprimido (.7z) por ano | **~3–5 GB** | Taxa de compressão típica de texto tabular |
| 9 anos-base (2015–2023) descompactados | **~250–400 GB** | Soma |
| Novo CAGED, movimentações por mês | **~3–5 milhões de linhas** | Admissões + desligamentos mensais divulgados |
| Novo CAGED, 2020–2024 (60 competências) | **~200–300 milhões de linhas** | Soma |

Conclusão: carregar microdados brutos é **impossível** no plano de 1 GB (a diferença é de 2 a 3 ordens de grandeza). A redução precisa ocorrer no ETL, **antes** da carga, e por quatro mecanismos combinados.

### 2.2 Mecanismo 1 — Filtro de recorte setorial (o mais poderoso)

| Filtro | Regra | Justificativa |
|---|---|---|
| **Setor de TI** | `CNAE 2.0 Classe` com os dois primeiros dígitos ∈ {**62**, **63**} | Divisão 62 = *Atividades dos serviços de tecnologia da informação* (desenvolvimento de software, consultoria em TI, suporte técnico); 63 = *Atividades de prestação de serviços de informação* (tratamento de dados, hospedagem, portais). É a definição de "setor de TI" na CNAE 2.0 |
| Extensão opcional | Divisão **61** (Telecomunicações) | Incluir apenas se o grupo decidir tratar "TIC" em vez de "TI". Padrão: **excluído** [proposta] |
| Alternativa/complemento | Ocupações de TI (CBO famílias 2122, 2123, 2124, 3171, 3172, 1425) em **qualquer** setor | Captura profissionais de TI em bancos, varejo, governo. Fica como **camada opcional** de comparação, não no núcleo, para não estourar o volume [proposta] |

**Efeito [estimativa]:** a participação das divisões 62+63 no emprego formal brasileiro é de aproximadamente **1,5–2,5 %**. Aplicado a ~65 milhões de vínculos/ano, resultam **~1,0–1,6 milhão de vínculos/ano** — redução de ~98 %.

### 2.3 Mecanismo 2 — Recorte temporal

| Opção | Anos | Prós | Contras |
|---|---|---|---|
| **A (padrão) [proposta]** | **2015–2023** (9 anos-base) | Cobre um ciclo econômico completo (recessão 2015–16, recuperação, pandemia 2020–21, pós-pandemia), o que dá sentido ao filtro "Ano" do dashboard; a coluna `Raça Cor` já está estável no layout; `Escolaridade após 2005` é uniforme | Volume 9× maior que 1 ano |
| B | 2019–2023 (5 anos) | Menor volume, foco no período com CAGED novo (2020+) | Perde a série histórica pré-pandemia |
| C | Último ano disponível apenas | Trivial em volume | Inviabiliza análise de tendência; empobrece o dashboard |

Na Opção A, após o filtro setorial: **~9–14 milhões de vínculos brutos** em todo o período **[estimativa]**. Ainda é demais para 1 GB se guardado linha a linha (ver 2.6); por isso entram os mecanismos 3 e 4.

Para o **Novo CAGED**, recorte 2020–2023 (ou até a última competência fechada), com o mesmo filtro CNAE 62/63: **~1,5–3 milhões de movimentações** no total **[estimativa]** (assumindo participação de TI nas movimentações da ordem de 2–3 %, um pouco maior que no estoque por ser um setor de alta rotatividade).

### 2.4 Mecanismo 3 — Filtro de vínculo e qualidade

| Filtro | Regra | Justificativa |
|---|---|---|
| Vínculo ativo em 31/12 | `Vínculo Ativo 31/12 = 1` para o **fato de estoque** (gap salarial, funil de liderança) | Evita contar duas vezes a mesma pessoa que trocou de emprego no ano; alinha com a definição oficial de "estoque" do PDET |
| Vínculos desligados | Mantidos **apenas em contagem agregada** (`qtd_desligados`) para a rotatividade da RAIS; não entram no cálculo salarial | Salário de quem trabalhou 2 meses distorce a média |
| Remuneração válida | `Vl Remun Média Nom > 0` | Zero indica afastamento o ano todo ou dado ausente |
| Horas válidas | `Qtd Hora Contr` entre 1 e 44 | Fora disso é erro de declaração; horas são necessárias para "gap por hora trabalhada" (exemplo explícito do guia) |
| Raça/cor e sexo informados | Registros com `Raça Cor` ∈ {9, -1} (não identificada/ignorada) **não são descartados**, mas ficam em categoria própria "Não informada" | Descartá-los enviesaria; o dashboard mostra o percentual de não-resposta como indicador de **Veracidade** |

**Efeito [estimativa]:** o filtro `Vínculo Ativo 31/12 = 1` costuma reter entre 65 % e 80 % dos vínculos do ano. Estoque de TI: **~0,8–1,2 milhão de linhas/ano**.

### 2.5 Mecanismo 4 — Agregação prévia (o que de fato vai para o PostgreSQL)

O núcleo do modelo estrela será um **fato agregado**, não microdados. Grão proposto **[proposta]**:

```
fato_vinculo_ti_agg
  grão = ano × uf × sexo × raca_cor × faixa_etaria × escolaridade
         × nivel_lideranca (derivado do CBO, seção 3.6) × divisao_cnae (62 | 63)
  medidas:
    qtd_vinculos_ativos      INTEGER     -- COUNT(*) com ativo=1
    qtd_admitidos_ano        INTEGER     -- COUNT(*) com Tipo Admissão ≠ 0
    qtd_desligados_ano       INTEGER     -- COUNT(*) com Mês Desligamento ≠ 0
    soma_remun_media_nom     NUMERIC(16,2)
    soma_horas_contr         BIGINT
    remun_media_nom          NUMERIC(12,2)  -- soma/qtd (derivável, mas guardar acelera o dashboard)
    remun_mediana_nom        NUMERIC(12,2)  -- percentil 50 calculado NO ETL (não é composável a partir de médias)
    remun_p25_nom, remun_p75_nom NUMERIC(12,2)
    remun_media_por_hora     NUMERIC(12,4)  -- soma_remun / (soma_horas × 4,345)  [regra de negócio, Etapa 5]
    soma_tempo_emprego_meses NUMERIC(16,1)
```

Por que a mediana entra no fato: o guia exige alternar entre **Média Salarial** e **Mediana**. Mediana não se recompõe a partir de agregados; logo, é calculada no ETL, no grão mais fino, com `groupby().quantile(0.5)` (Pandas) ou `percentile_approx` (PySpark), e armazenada. Quando o usuário combina filtros no dashboard (ex.: "todas as UFs do Nordeste"), a mediana exibida será a **mediana ponderada aproximada** ou a mediana do grão mais próximo — limitação que deve ser documentada na Etapa 5. Alternativa: manter também um **histograma por faixa de remuneração em SM** (`Faixa Remun Média (SM)`, 12 faixas) no fato, que permite mediana aproximada em qualquer combinação de filtros a custo baixíssimo [proposta].

**Cardinalidade máxima do fato [estimativa]:**

| Dimensão | Cardinalidade |
|---|---|
| ano | 9 |
| uf | 27 |
| sexo | 2 (+1 não informado) |
| raca_cor | 6 (+1 não informada) |
| faixa_etaria | 8 |
| escolaridade | 11 |
| nivel_lideranca | 3 |
| divisao_cnae | 2 |
| **Produto cartesiano** | **9 × 27 × 3 × 7 × 8 × 11 × 3 × 2 ≈ 2,7 milhões** (teto teórico) |
| **Linhas reais esperadas** | **~150–400 mil** (a matriz é esparsa: a maioria das combinações UF pequena × indígena × doutorado × dirigente é vazia) |

Um segundo fato, `fato_movimentacao_ti_agg` (Novo CAGED), com grão `competencia (mês) × uf × sexo × raca_cor × faixa_etaria × nivel_lideranca × divisao_cnae` e medidas `qtd_admissoes`, `qtd_desligamentos`, `saldo`, `soma_salario_admissao`, `salario_mediano_admissao`: 48 meses × 27 × 3 × 7 × 8 × 3 × 2 ≈ 1,3 milhão de teto, **~100–250 mil linhas reais [estimativa]**.

### 2.6 Amostragem estatística (camada opcional de microdados)

Além dos fatos agregados, é útil guardar uma **amostra de microdados anonimizados** para (a) drill-down até o nível de ocupação CBO específica, (b) permitir que a banca veja "linhas reais" e (c) calcular medianas exatas para combinações de filtro arbitrárias.

| Parâmetro | Proposta [proposta] |
|---|---|
| Método | **Amostragem estratificada** por `ano × uf × sexo × raca_cor`, com fração fixa por estrato, garantindo mínimo de linhas por estrato (para não perder grupos pequenos, como mulheres indígenas em Roraima) |
| Fração base | 5 % por estrato, com piso de 200 linhas/estrato (ou todas, se o estrato tiver menos que 200) |
| Semente | Fixa (`random_state=42`) para reprodutibilidade |
| Colunas mantidas | Apenas as da seção 3.2 marcadas como "Mantida" — ~18 colunas, todas já codificadas |
| Tamanho **[estimativa]** | 5 % de ~9 milhões (estoque 2015–2023) ≈ **450 mil linhas** × ~60 bytes armazenados ≈ 27 MB + índices ≈ **40–60 MB** |

A amostra nunca substitui o fato agregado como fonte dos KPIs; ela é auxiliar. Se o orçamento apertar, é a primeira coisa a ser cortada.

### 2.7 Orçamento de armazenamento no PostgreSQL **[estimativa]**

Premissas: tupla PostgreSQL tem overhead de ~24 bytes de cabeçalho + alinhamento; índices B-tree ocupam, tipicamente, 30–60 % do tamanho da tabela quando há 3–4 índices.

| Objeto | Linhas | Bytes/linha (dados + overhead) | Tabela | Índices | Total |
|---|---|---|---|---|---|
| `fato_vinculo_ti_agg` | 400 mil (teto realista) | ~110 | 44 MB | 25 MB | **~70 MB** |
| `fato_movimentacao_ti_agg` | 250 mil | ~90 | 23 MB | 12 MB | **~35 MB** |
| `amostra_vinculo_ti` (opcional) | 450 mil | ~70 | 32 MB | 20 MB | **~50 MB** |
| `dim_ocupacao` (CBO completa, com descrição) | ~2,7 mil ocupações | ~600 | 2 MB | <1 MB | **~3 MB** |
| `dim_setor` (CNAE subclasses) | ~1,3 mil | ~200 | <1 MB | <1 MB | **~1 MB** |
| `dim_localidade` (municípios) | ~5,6 mil | ~100 | <1 MB | <1 MB | **~1 MB** |
| Demais `dim_*` (sexo, raça, faixa etária, escolaridade, tempo, motivos) | <200 | — | — | — | **<1 MB** |
| Catálogo, WAL, `pg_toast`, folga | — | — | — | — | ~50 MB |
| **Total previsto** | | | | | **~210 MB (≈ 21 % do limite)** |

Margem de segurança: mesmo que as estimativas estejam erradas por um fator de 3, ficamos em ~630 MB, abaixo de 1 GB. Se o fato agregado ultrapassar 1 milhão de linhas na prática, a primeira ação é retirar `escolaridade` do grão (colapsa para 3 níveis: até médio / superior / pós) — corte de ~70 % das linhas.

### 2.8 Resumo do funil de volume **[estimativa]**

```
RAIS bruta, 9 anos                ~600 milhões de linhas   (~300 GB txt)
 └─ filtro CNAE 62/63             ~ 12 milhões             (redução ~98 %)
     └─ ativo em 31/12            ~  9 milhões
         └─ agregação             ~  0,4 milhão  → fato   (~70 MB no PostgreSQL)
         └─ amostra 5 %           ~  0,45 milhão → aux.   (~50 MB)
Novo CAGED bruto, 2020–2023       ~200 milhões de linhas
 └─ filtro CNAE 62/63             ~  3 milhões
     └─ agregação mensal          ~  0,25 milhão → fato   (~35 MB)
```

O processamento intermediário (descompactar 7z, ler em *chunks* de ~500 mil linhas com `pandas.read_csv(chunksize=…)` ou com PySpark, filtrar e acumular) acontece **fora** do PostgreSQL — em runner do GitHub Actions ou máquina local — e só o resultado reduzido é carregado. Os arquivos brutos **não** são versionados no repositório.

---

## 3. Mapeamento de Variedade e Tipagem

### 3.1 Variedade — classificação dos dados do projeto

| Classe | O que é, neste projeto | Onde vive |
|---|---|---|
| **Estruturado** | Microdados RAIS e Novo CAGED (tabelas delimitadas, esquema fixo); tabelas CNAE 2.0 e CBO 2002 (código → título); série de salário mínimo | PostgreSQL (fatos + dimensões) |
| **Semi-estruturado** | Resposta JSON da API IBGE Localidades (município aninhado em microrregião → mesorregião → UF → região); resposta JSON das APIs do BCB/SIDRA (SM, IPCA); os próprios layouts (dicionários) que serão convertidos em YAML/JSON de configuração do ETL; logs do pipeline em JSON | Parseados no ETL e "achatados" para `dim_localidade`; opcionalmente indexados no Aiven OpenSearch (logs) |
| **Não estruturado** | Texto livre da **descrição sumária de cada ocupação CBO** (parágrafos descrevendo o que o profissional faz); denominações longas de CNAE; textos de justificativa do dicionário PDET | Coluna `TEXT` em `dim_ocupacao` (busca por `ILIKE`) ou, se OpenSearch for adotado, índice textual para o drill-down "buscar ocupação" no dashboard |

### 3.2 RAIS Vínculos — tipagem coluna a coluna

Nomes de coluna conforme o cabeçalho do arquivo público (com acentos, espaços e maiúsculas). **[a confirmar no download]** para grafia exata; a lógica de tipagem não depende da grafia.

Legenda de decisão: **Mantida** = vai para a amostra e/ou para o grão do fato; **Agregada** = entra apenas como medida do fato; **Derivada** = usada para calcular outra coluna e descartada; **Descartada** = não é lida do arquivo (`usecols`).

| Coluna na origem (RAIS) | Tipo bruto no txt | Exemplo bruto | Tipo alvo (PostgreSQL) | Transformação no ETL | Decisão |
|---|---|---|---|---|---|
| `Ano` (derivado do nome do arquivo/pasta; não é coluna) | — | `2023` | `SMALLINT` | Injetado pelo ETL a partir do caminho | Mantida (grão) |
| `Vl Remun Média Nom` | string decimal com vírgula | `"3456,78"` | `NUMERIC(12,2)` | `str.replace(",", ".")` → `float` → `round(2)`; `0` vira `NULL` para fins de média | Agregada (soma, média, mediana, p25/p75) |
| `Vl Remun Dezembro Nom` | string decimal com vírgula | `"3600,00"` | `NUMERIC(12,2)` | Idem | Agregada (opcional: salário "de fim de ano" vs média) |
| `Vl Remun Média (SM)` | string decimal com vírgula | `"2,62"` | `NUMERIC(8,2)` | Idem | Agregada (normalização entre anos sem precisar de IPCA) |
| `Vl Remun Dezembro (SM)` | string decimal com vírgula | `"2,73"` | `NUMERIC(8,2)` | Idem | Descartada (redundante com a média) |
| `Faixa Remun Média (SM)` | código inteiro (1–12, 99) | `"04"` | `SMALLINT` + `dim_faixa_remun` | `astype(int)`; lookup | Mantida (histograma para mediana aproximada) |
| `Qtd Hora Contr` | inteiro | `"44"` | `SMALLINT` | `astype(int)`; validar 1–44 | Agregada (soma de horas → gap por hora) |
| `Idade` | inteiro | `"29"` | `SMALLINT` | `astype(int)` | Derivada → `faixa_etaria` (usar a coluna `Faixa Etária` oficial, se disponível; senão, binar) |
| `Faixa Etária` | código inteiro (1–8, 99) | `"04"` | `SMALLINT` + `dim_faixa_etaria` | `astype(int)`; lookup | Mantida (grão) |
| `Sexo Trabalhador` | código inteiro | `"01"` / `"1"` | `SMALLINT` + `dim_sexo` | `astype(int)`; harmonizar com CAGED (3.5) | Mantida (grão) |
| `Raça Cor` | código inteiro | `"08"` / `"8"` | `SMALLINT` + `dim_raca_cor` | `astype(int)`; harmonizar com CAGED (3.5) | Mantida (grão) |
| `CBO Ocupação 2002` | string numérica de 6 dígitos, **pode ter zero à esquerda** e valor `"0000-1"` para ignorado | `"212405"` | `CHAR(6)` (FK → `dim_ocupacao`) | **Nunca** converter para `int` (perde zero à esquerda); `str.zfill(6)`; `"0000-1"` → `NULL` | Mantida na amostra; Derivada → `nivel_lideranca` (3.6) no fato |
| `CNAE 2.0 Classe` | string numérica de 5 dígitos | `"62015"` | `CHAR(5)` (FK → `dim_setor`) | `str.zfill(5)`; **filtro:** `str[:2] in ("62","63")` aplicado na leitura de cada chunk | Derivada → `divisao_cnae` (grão) |
| `CNAE 2.0 Subclasse` | string numérica de 7 dígitos | `"6201501"` | `CHAR(7)` | `str.zfill(7)` | Mantida só na amostra (drill-down fino) |
| `CNAE 95 Classe` | string 5 dígitos (classificação antiga) | `"72100"` | — | — | Descartada (usar somente CNAE 2.0) |
| `Município` | código IBGE de **6 dígitos** (sem dígito verificador) | `"292740"` | `CHAR(6)` (FK → `dim_localidade`) | `str.zfill(6)`; UF = `str[:2]` → lookup para sigla | Derivada → `uf` (grão); mantida na amostra |
| `Mun Trab` | código IBGE 6 dígitos (município de trabalho, quando difere) | `"292740"` | — | — | Descartada |
| `Escolaridade após 2005` | código inteiro (1–11, -1) | `"09"` | `SMALLINT` + `dim_escolaridade` | `astype(int)` | Mantida (grão) |
| `Tempo Emprego` | string decimal com vírgula (**meses**) | `"37,4"` | `NUMERIC(7,1)` | `replace(",",".")` → `float` | Agregada (soma → tempo médio de casa por grupo) |
| `Faixa Tempo Emprego` | código inteiro (1–8, 99) | `"05"` | `SMALLINT` | `astype(int)` | Descartada (a contínua basta) |
| `Vínculo Ativo 31/12` | código 0/1 | `"1"` | `BOOLEAN` | `== 1`; **filtro** do fato de estoque | Derivada (filtro) + contagem |
| `Tipo Admissão` | código inteiro (0 = não admitido no ano; 1–9 tipos) | `"02"` | `SMALLINT` + `dim_tipo_admissao` | `astype(int)`; `≠ 0` → admitido no ano | Agregada (`qtd_admitidos_ano`) |
| `Mês Admissão` | inteiro 0–12 | `"03"` | `SMALLINT` | `astype(int)` | Descartada (CAGED cobre o mensal) |
| `Mês Desligamento` | inteiro 0–12 (0 = não desligado no ano) | `"00"` | `SMALLINT` | `astype(int)`; `≠ 0` → desligado no ano | Agregada (`qtd_desligados_ano`) |
| `Motivo Desligamento` | código inteiro (0 = não desligado; 10, 11, 12, 20, 21, 30, 31, … ) | `"11"` | `SMALLINT` + `dim_motivo_desligamento` | `astype(int)` | Agregada (contagem por motivo: pedido de demissão × demissão sem justa causa — relevante para "funil que vaza") |
| `Tipo Vínculo` | código inteiro (10, 15, 20, 25, 30, …) | `"10"` | `SMALLINT` + `dim_tipo_vinculo` | `astype(int)` | Mantida só na amostra; filtro opcional "somente CLT" [proposta] |
| `Tamanho Estabelecimento` | código inteiro (1–10) | `"07"` | `SMALLINT` + `dim_tamanho_estab` | `astype(int)` | Mantida na amostra; possível eixo extra de drill-down |
| `Natureza Jurídica` | código 4 dígitos | `"2062"` | `CHAR(4)` | `zfill(4)` | Descartada (fora do escopo; setor 62/63 é quase todo privado) |
| `Ind Simples` | 0/1 | `"1"` | `BOOLEAN` | `== 1` | Descartada |
| `Ind Portador Defic` / `Tipo Defic` | 0/1 e código | `"0"` | `BOOLEAN` / `SMALLINT` | — | Descartada nesta versão (possível extensão interseccional futura) |
| `Nacionalidade` | código inteiro (10 = brasileira, …) | `"10"` | `SMALLINT` | — | Descartada |
| `Ano Chegada Brasil` | inteiro | `"0"` | — | — | Descartada |
| `Ind Trab Intermitente` / `Ind Trab Parcial` | 0/1 | `"0"` | `BOOLEAN` | — | Descartada |
| `Causa Afastamento 1..3`, `Dia Ini Afast 1..3`, `Dia Fim Afast 1..3`, `Qtd Dias Afastamento` | inteiros | — | — | — | Descartadas |
| `Vl Rem Janeiro CC` … `Vl Rem Novembro CC` | string decimal com vírgula (11 colunas) | `"3456,78"` | — | — | Descartadas (a média anual basta; 11 colunas × 9 milhões de linhas é o maior "peso morto" do arquivo) |
| `Bairros SP`, `Bairros Fortaleza`, `Bairros RJ`, `Distritos SP`, `Regiões Adm DF` | códigos | — | — | — | Descartadas (granularidade abaixo de município aumenta risco de reidentificação — LGPD) |
| `IBGE Subsetor` | código | — | — | — | Descartada (CNAE 2.0 substitui) |
| `Tipo Estab`, `Tipo Estab.1` | códigos | — | — | — | Descartadas |
| `Ind CEI Vinculado` | 0/1 | — | — | — | Descartada (indicador ligado ao CEI, identificador de empregador) |

Regras transversais de tipagem no ETL:

1. Ler **tudo como `str`** (`dtype=str`) e só então converter — evita que o Pandas infira `float` em códigos com zero à esquerda e evita `int` estourar em `NaN`.
2. `usecols` restrito às colunas "Mantida/Agregada/Derivada" — reduz a memória por chunk em ~70 %.
3. Valores `-1`, `99`, `9999`, `"{ñ class}"`, `"{ñ"` (marcadores PDET de "ignorado/não classificado") → `NULL` ou categoria "Não informado", nunca zero.
4. Conversão monetária: `pd.to_numeric(s.str.replace(".", "", regex=False).str.replace(",", ".", regex=False), errors="coerce")` — o `replace(".", "")` é defensivo caso apareça separador de milhar **[a confirmar]**.

### 3.3 Novo CAGED — tipagem coluna a coluna

Nomes conforme o layout do Novo CAGED (minúsculos, acentuados) **[a confirmar no download]**.

| Coluna na origem (CAGED) | Tipo bruto | Exemplo bruto | Tipo alvo (PostgreSQL) | Transformação | Decisão |
|---|---|---|---|---|---|
| `competênciamov` | string `AAAAMM` | `"202303"` | `DATE` (dia 1 do mês) | `pd.to_datetime(s, format="%Y%m")` | Mantida (grão mensal) |
| `competênciadec` | string `AAAAMM` (competência da declaração) | `"202304"` | — | — | Descartada (usar `competênciamov`) |
| `região` | código 1–5 | `"2"` | `SMALLINT` | — | Descartada (derivar de UF via `dim_localidade`) |
| `uf` | código IBGE 2 dígitos | `"29"` | `CHAR(2)` → sigla via lookup | `zfill(2)` | Mantida (grão) |
| `município` | código IBGE 6 dígitos | `"292740"` | `CHAR(6)` | `zfill(6)` | Mantida só em amostra (se houver); fato agrega por UF |
| `seção` | letra CNAE | `"J"` | — | — | Descartada (redundante com subclasse) |
| `subclasse` | código CNAE 2.0 de 7 dígitos | `"6201501"` | `CHAR(7)` | `zfill(7)`; **filtro** `str[:2] in ("62","63")` | Derivada → `divisao_cnae` |
| `saldomovimentação` | inteiro `+1` / `-1` | `"1"` / `"-1"` | `SMALLINT` | `astype(int)` | Agregada (`SUM` = saldo; `+1` conta admissão; `-1` conta desligamento) |
| `tipomovimentação` | código inteiro (10, 20, 25, 31, 32, 33, 35, 40, 43, 45, 50, 60, 70, 80, 90, 97, 98, 99…) | `"40"` | `SMALLINT` + `dim_tipo_movimentacao` | `astype(int)` | Agregada (contagem por tipo: "desligamento a pedido" é sinal de evasão voluntária) |
| `cbo2002ocupação` | string 6 dígitos | `"212405"` | `CHAR(6)` | `zfill(6)` | Derivada → `nivel_lideranca` (3.6) |
| `categoria` | código (101 = CLT, 102 …, 111, 999…) | `"101"` | `SMALLINT` | — | Mantida em amostra; filtro opcional CLT |
| `graudeinstrução` | código inteiro (1–11, 80, 99) | `"7"` | `SMALLINT` + `dim_escolaridade` | `astype(int)`; **mapear** para os códigos da RAIS (3.5) | Mantida (grão) |
| `idade` | inteiro | `"31"` | `SMALLINT` | `astype(int)` | Derivada → `faixa_etaria` com as **mesmas faixas da RAIS** (3.5) |
| `horascontratuais` | inteiro | `"44"` | `SMALLINT` | `astype(int)` | Agregada (soma) |
| `raçacor` | código inteiro (1–6, 9) — **codificação diferente da RAIS** | `"2"` | `SMALLINT` + `dim_raca_cor` | `astype(int)`; **mapear** para código canônico (3.5) | Mantida (grão) |
| `sexo` | código inteiro (**1 = homem, 3 = mulher**, 9 = não identificado) — diferente da RAIS | `"3"` | `SMALLINT` + `dim_sexo` | **mapear** para canônico (3.5) | Mantida (grão) |
| `tipoempregador` | código | `"0"` | — | — | Descartada |
| `tipoestabelecimento` | código | `"1"` | — | — | Descartada |
| `tipodedeficiência` | código 0–6 | `"0"` | — | — | Descartada nesta versão |
| `indtrabintermitente` / `indtrabparcial` | 0/1 | `"0"` | — | — | Descartadas |
| `salário` | string decimal com vírgula (mensal, nominal) | `"4500,00"` | `NUMERIC(12,2)` | `replace(",",".")` → `float`; `<= 0` → `NULL` | Agregada (soma e mediana do salário de admissão) |
| `unidadesaláriocódigo` | código (1 = hora, 5 = mês, …) | `"5"` | `SMALLINT` | Filtrar/normalizar: só somar salários com unidade "mês" **[a confirmar códigos]** | Derivada |
| `valorsaláriofixo` | string decimal com vírgula | `"4500,00"` | — | — | Descartada (redundante com `salário`) |
| `tamestabjan` | código 1–10 | `"7"` | `SMALLINT` | — | Descartada |
| `indicadoraprendiz` | 0/1 | `"0"` | `BOOLEAN` | — | Descartada (opcional: excluir aprendizes do salário) |
| `origemdainformação` | código | `"1"` | — | — | Descartada |
| `indicadordeforadoprazo` | 0/1 | `"0"` | — | — | Descartada (o ETL já decide se lê `CAGEDFOR`) |

### 3.4 Códigos de domínio (tabelas `dim_*`)

Os domínios abaixo seguem os dicionários PDET. Os que têm asterisco (\*) precisam ser conferidos linha a linha contra o layout do ano baixado **[a confirmar no download]** — a lógica de tipagem não muda, apenas o rótulo.

**`Sexo Trabalhador` (RAIS)**

| Código | Rótulo |
|---|---|
| 1 | Masculino |
| 2 | Feminino |

**`Raça Cor` (RAIS)**

| Código | Rótulo |
|---|---|
| 1 | Indígena |
| 2 | Branca |
| 4 | Parda |
| 6 | Amarela |
| 8 | Preta |
| 9 | Não identificada |
| -1 | Ignorado \* |

**`Faixa Etária` (RAIS)**

| Código | Rótulo |
|---|---|
| 1 | 10 a 14 anos |
| 2 | 15 a 17 anos |
| 3 | 18 a 24 anos |
| 4 | 25 a 29 anos |
| 5 | 30 a 39 anos |
| 6 | 40 a 49 anos |
| 7 | 50 a 64 anos |
| 8 | 65 anos ou mais |
| 99 | Ignorado \* |

**`Escolaridade após 2005` (RAIS)**

| Código | Rótulo |
|---|---|
| 1 | Analfabeto |
| 2 | Até 5ª série incompleta do fundamental |
| 3 | 5ª série completa do fundamental |
| 4 | 6ª a 9ª série incompleta do fundamental |
| 5 | Fundamental completo |
| 6 | Médio incompleto |
| 7 | Médio completo |
| 8 | Superior incompleto |
| 9 | Superior completo |
| 10 | Mestrado |
| 11 | Doutorado |
| -1 | Ignorado \* |

**`Vínculo Ativo 31/12` (RAIS):** 0 = Não, 1 = Sim.

**`Tipo Admissão` (RAIS)** \* — 0 = Não admitido no ano; 1 = Primeiro emprego; 2 = Reemprego; 3 = Transferência com ônus; 4 = Transferência sem ônus; 5 = Reintegração; demais códigos (6–9) conferir no layout.

**`Motivo Desligamento` (RAIS)** \* — 0 = Não desligado no ano; 10 = Rescisão com justa causa por iniciativa do empregador; 11 = Rescisão sem justa causa por iniciativa do empregador; 12 = Término de contrato; 20 = Rescisão com justa causa por iniciativa do empregado; 21 = Rescisão sem justa causa por iniciativa do empregado (pedido de demissão); 30 = Transferência com ônus; 31 = Transferência sem ônus; 40 = Mudança de regime; 50 = Reforma; 60 = Falecimento; 62/63/64 = Aposentadorias; 70/80 = Outros; 90 = Ignorado. Conferir códigos completos no layout.

**`Faixa Remun Média (SM)` (RAIS)** \* — 1 = até 0,5 SM; 2 = 0,51 a 1,0; 3 = 1,01 a 1,5; 4 = 1,51 a 2,0; 5 = 2,01 a 3,0; 6 = 3,01 a 4,0; 7 = 4,01 a 5,0; 8 = 5,01 a 7,0; 9 = 7,01 a 10,0; 10 = 10,01 a 15,0; 11 = 15,01 a 20,0; 12 = mais de 20 SM; 99 = Ignorado.

**`sexo` (Novo CAGED)** \*

| Código | Rótulo |
|---|---|
| 1 | Homem |
| 3 | Mulher |
| 9 | Não identificado |

**`raçacor` (Novo CAGED)** \*

| Código | Rótulo |
|---|---|
| 1 | Branca |
| 2 | Preta |
| 3 | Parda |
| 4 | Amarela |
| 5 | Indígena |
| 6 | Não informada |
| 9 | Não identificado |

**`tipomovimentação` (Novo CAGED)** \* — 10 = Admissão por primeiro emprego; 20 = Admissão por reemprego; 25 = Admissão por contrato trabalho prazo determinado; 31 = Desligamento por demissão com justa causa; 32 = Desligamento por demissão sem justa causa; 33 = Desligamento por término de contrato; 35 = Desligamento por término de contrato prazo determinado; 40 = Desligamento a pedido; 43/45/50/60/70/80/90/97/98/99 = demais (reintegração, aposentadoria, morte, transferências, etc.) — conferir no layout.

### 3.5 Harmonização RAIS × CAGED (dimensões conformadas)

As duas bases usam **códigos diferentes para o mesmo conceito**. Para que os filtros do dashboard (Sexo, Raça/Cor, Faixa Etária) funcionem sobre os dois fatos, o ETL mapeia tudo para um **código canônico** único nas dimensões. Este mapeamento é decisão nossa **[proposta]**:

| Conceito | Canônico (`dim_*`) | Origem RAIS | Origem CAGED |
|---|---|---|---|
| Sexo: Masculino | `M` | 1 | 1 |
| Sexo: Feminino | `F` | 2 | 3 |
| Sexo: Não informado | `NI` | (ausente) | 9 |
| Raça/cor: Branca | `BRANCA` | 2 | 1 |
| Raça/cor: Preta | `PRETA` | 8 | 2 |
| Raça/cor: Parda | `PARDA` | 4 | 3 |
| Raça/cor: Amarela | `AMARELA` | 6 | 4 |
| Raça/cor: Indígena | `INDIGENA` | 1 | 5 |
| Raça/cor: Não informada | `NI` | 9, -1 | 6, 9 |
| Faixa etária | códigos 1–8 da RAIS | `Faixa Etária` direto | `idade` binada com os **mesmos cortes** (18–24, 25–29, 30–39, 40–49, 50–64, 65+) |
| Escolaridade | códigos 1–11 da RAIS | direto | `graudeinstrução` (mesma escala 1–11 no Novo CAGED; 80 e 99 → NI) \* |
| Ocupação | CBO 2002, 6 dígitos | direto | direto |
| Setor | CNAE 2.0, divisão (2 dígitos) | `CNAE 2.0 Classe[:2]` | `subclasse[:2]` |
| Localidade | UF (sigla) | `Município[:2]` → lookup | `uf` → lookup |

Além disso, na Etapa 5 será proposta a categoria analítica **"Negra" = Preta + Parda**, seguindo a convenção do IBGE, como agrupamento *adicional* (não substitui as categorias originais).

### 3.6 Regra de mapeamento do funil de liderança **[proposta]**

A CBO 2002 é hierárquica: o **primeiro dígito** é o Grande Grupo. Proposta de derivação da coluna `nivel_lideranca` a partir de `CBO Ocupação 2002` / `cbo2002ocupação`:

| `nivel_lideranca` | Regra sobre o CBO | Grandes Grupos / famílias envolvidos | Interpretação no funil |
|---|---|---|---|
| **3 – Liderança** | Primeiro dígito = `1` | GG 1 – *Membros superiores do poder público, dirigentes de organizações de interesse público e de empresas, gerentes*. Em TI, tipicamente família **1425** (Gerentes de tecnologia da informação) e **1236/1237** (Diretores de serviços de informática / de pesquisa e desenvolvimento) | Topo do funil |
| **2 – Profissional** | Primeiro dígito = `2` | GG 2 – *Profissionais das ciências e das artes*. Em TI: famílias **2122** (Engenheiros em computação), **2123** (Administradores de tecnologia da informação), **2124** (Analistas de tecnologia da informação) | Meio do funil (nível superior) |
| **1 – Técnico / demais** | Qualquer outro primeiro dígito (`3`–`9`, `0`) | GG 3 – Técnicos de nível médio (em TI: **3171** Técnicos de desenvolvimento de sistemas, **3172** Técnicos em operação de computadores); GG 4 – Trabalhadores de serviços administrativos; GG 5–9 – demais | Base do funil |
| `NULL` | CBO ausente / `"0000-1"` | — | Excluído do funil, contado em "não informado" |

Observações que devem constar na Etapa 5 (regras de negócio):

- Esta é uma **aproximação**: o GG 1 inclui dirigentes de qualquer área (RH, financeiro) que trabalham em empresas de TI. Uma variante mais estrita — "liderança **em TI**" = CBO ∈ {1425, 1236, 1237} apenas — será mantida como flag adicional (`lideranca_ti_estrita BOOLEAN`) para comparação [proposta].
- O funil será lido como **proporção**: % de mulheres (ou % de pessoas negras) em cada nível, comparado à sua proporção no nível anterior. A queda dessa proporção ao subir de nível é a métrica "vazamento do funil".
- Sem um identificador de pessoa (removido por LGPD), **não** é possível acompanhar a mesma pessoa subindo de nível; o funil é **transversal (fotografia por ano)**, não longitudinal. Essa limitação será explicitada no README.

### 3.7 Colunas PII e conformidade com a LGPD

Os arquivos públicos (`*_PUB`) do PDET já são disponibilizados **sem identificadores diretos**. Ainda assim, o ETL implementa uma **lista de bloqueio** (`drop` incondicional + assert de que nenhuma delas chegou ao banco), porque o layout muda entre anos e porque a banca avalia a "eliminação de dados sensíveis ou pessoalmente identificáveis dos microdados brutos".

| Coluna (se presente em qualquer layout) | Base | Motivo do descarte |
|---|---|---|
| `CPF` | RAIS identificada | Identificador direto da pessoa natural (art. 5º, I, LGPD) |
| `PIS` / `PIS/PASEP` / `NIS` | RAIS identificada / CAGED | Identificador direto |
| `Nome` / `Nome Trabalhador` | RAIS identificada | Identificador direto |
| `Nome Mãe` | RAIS identificada | Identificador direto |
| `Data Nascimento` | RAIS identificada / CAGED | Quase-identificador; substituído por `Faixa Etária` |
| `CNPJ Raiz` / `CNPJ/CEI` / `CEI Vinculado` / `Ind CEI Vinculado` | RAIS / CAGED | Identifica o empregador (pessoa jurídica ou pessoa física empregadora); combinado com município + CBO permite reidentificar |
| `Razão Social` / `Nome Estabelecimento` | RAIS Estab | Idem |
| `CTPS` / `Série CTPS` | RAIS identificada | Identificador direto |
| `Data Admissão` / `Data Desligamento` (dia exato) | RAIS identificada | Quase-identificador; substituído por mês |
| `Bairros SP/RJ/Fortaleza`, `Distritos SP`, `Regiões Adm DF` | RAIS pública | Granularidade sub-municipal: aumenta risco de reidentificação por cruzamento (k-anonimato) |
| `Município` (na camada **agregada**) | RAIS / CAGED | Mantido apenas na amostra e em `dim_localidade`; o fato agrega por UF, evitando células com contagem muito pequena |

Regra adicional de anonimização na saída **[proposta]:** qualquer célula do fato agregado com `qtd_vinculos_ativos < 5` terá as medidas salariais suprimidas (`NULL`) e a contagem mantida — prática de **supressão por baixa frequência**, alinhada ao princípio de minimização (art. 6º, III) e à prevenção de reidentificação de grupos muito pequenos (ex.: 1 mulher indígena dirigente em uma UF pequena).

Dados de raça/cor são **dados pessoais sensíveis** (art. 5º, II) na origem; após agregação e supressão de células pequenas, o que é armazenado são **estatísticas**, não dados pessoais — é essa a fundamentação de conformidade que constará no README.

---

## 4. Pendências a confirmar no primeiro download (checklist do Marco 1)

| # | Item | Como verificar |
|---|---|---|
| 1 ✅ | Host/caminho do FTP do PDET responde e lista `/pdet/microdados/RAIS/` e `/pdet/microdados/NOVO CAGED/` | `curl -l ftp://ftp.mtps.gov.br/pdet/microdados/` |
| 2 ✅ | Nome dos arquivos `.7z` por ano (UF até 2017, região a partir de 2018) (região vs. UF) | Listagem da pasta de cada ano 2015–2023 |
| 3 ✅ | Encoding real (RAIS Latin-1; CAGED UTF-8) (Latin-1 vs UTF-8) de RAIS e de CAGED | `file -i` / `chardet` nas primeiras linhas |
| 4 ✅ | Grafia exata (ver bloco no topo da seção 1; 2023 usa sufixo ` - Código`) dos nomes de coluna (acentos, espaços) | `head -1 arquivo.txt` |
| 5 ✅ | Separador de milhar: ausente em todos os layouts nos campos monetários | `grep -m5 '[0-9]\.[0-9]\{3\},' arquivo.txt` |
| 6 | Códigos completos de `Tipo Admissão`, `Motivo Desligamento`, `Tipo Vínculo`, `tipomovimentação`, `unidadesaláriocódigo` | Layout XLS/PDF do ano |
| 7 ✅ | Formato do valor "ignorado" em CBO (`0000-1`) e CNAE (`{ñ class}`) | `grep -c` nas colunas |
| 8 ◐ | Número real de linhas após filtro CNAE 62/63 (CAGED 2024-01: 45.970 de 3.955.239 = 1,16 %; RAIS AC/2015: 342 de 191.101 = 0,18 %; falta um ano nacional da RAIS) em **um** ano (para recalibrar todas as estimativas da seção 2) | Rodar o ETL de um único arquivo e registrar `len()` por etapa |
| 9 | Disponibilidade de download em CSV/XLS da CBO 2002 com descrição sumária | Portal CBO do MTE |
| 10 | Tamanho real ocupado no PostgreSQL após a primeira carga | `SELECT pg_size_pretty(pg_database_size(current_database()));` |

Ao concluir a pendência 8, este documento deve ser atualizado substituindo as marcas **[estimativa]** por valores medidos.

---

## 5. Resumo executivo desta etapa

- **Fontes:** RAIS Vínculos (anual, `.7z` → `.txt`/`.COMT`; três layouts: `;`+vírgula até 2022, `,`+ponto em 2023+; Latin-1; versão pública sem identificadores) e Novo CAGED (mensal, `;`, UTF-8, 2020+), ambas do PDET/MTE; secundárias: layouts PDET, CBO 2002, CNAE 2.0, API IBGE Localidades (JSON), série de salário mínimo.
- **Volume:** de ~600 milhões de linhas brutas (9 anos) para **~0,4 milhão de linhas agregadas + ~0,45 milhão de amostra**, com estimativa de **~210 MB** em PostgreSQL (≈ 21 % do limite de 1 GB), via filtro CNAE 62/63, vínculo ativo em 31/12, agregação por `ano × UF × sexo × raça × faixa etária × escolaridade × nível de liderança × divisão CNAE` e amostragem estratificada de 5 %.
- **Tipagem:** tudo lido como string; monetários `"0000001234,56"` (≤2022) ou `"1234.56"` (2023+) → `NUMERIC(12,2)`; códigos → `SMALLINT` com dimensões de lookup; CBO/CNAE/município mantidos como `CHAR(n)` com zero à esquerda; `AAAAMM` → `DATE`; `0/1` → `BOOLEAN`; RAIS e CAGED harmonizados em dimensões conformadas (sexo, raça/cor, faixa etária, escolaridade).
- **Funil de liderança [proposta]:** CBO Grande Grupo 1 = liderança; 2 = profissional; demais = técnico/base; flag estrita para 1425/1236/1237.
- **LGPD:** lista de bloqueio para CPF, PIS, nome, data de nascimento, CNPJ/CEI, CTPS, bairros/distritos; supressão de medidas em células com menos de 5 vínculos.
