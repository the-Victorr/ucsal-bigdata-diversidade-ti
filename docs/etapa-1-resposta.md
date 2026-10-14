# Etapa 1 — Levantamento de Parâmetros e Tipagem de Dados

**Projeto:** Diversidade na Tecnologia: Raça, Gênero e o Funil de Liderança no Setor de TI Brasileiro
**Disciplina:** Big Data e Analytics — UCSAL 2026.2
**Bases:** Microdados da RAIS e do Novo CAGED (PDET / Ministério do Trabalho e Emprego)

> Tudo que está marcado como **confirmado** foi verificado por download e inspeção real dos arquivos em 18/09/2026. O que é **estimativa** está marcado como tal.

---

## 1. Identificação da Fonte

### 1.1 Formato de origem

As duas bases são distribuídas como **arquivos de texto delimitado (CSV) compactados em `.7z`**, via FTP público do PDET (`ftp://ftp.mtps.gov.br/pdet/microdados/`). Não existe API nem Parquet na origem; o Parquet será gerado por nós na camada de ingestão.

| Base | Periodicidade | Particionamento | Arquivo interno | Delimitador | Encoding | Decimal | Marcador de nulo |
|---|---|---|---|---|---|---|---|
| **RAIS Vínculos 2015–2017** | anual | 1 `.7z` por UF (`BA2015.7z`) | `.txt`, 57 colunas | `;` | Latin-1 | vírgula, zero à esquerda (`0000001090,26`) | `{ñ c}` / `{ñ class}` |
| **RAIS Vínculos 2018–2022** | anual | 1 `.7z` por região (`RAIS_VINC_PUB_NORDESTE.7z`) | `.txt`, 60 colunas | `;` | Latin-1 | vírgula, zero à esquerda | `9997` / `999999` |
| **RAIS Vínculos 2023+** | anual | 1 `.7z` por região | `.COMT`, 62 colunas, campos entre aspas, nomes com sufixo ` - Código` | `,` | Latin-1 | **ponto** (`2242.58`) | `999997` / `999` / `999999` |
| **Novo CAGED (2020+)** | mensal | 3 `.7z` por competência: `CAGEDMOV`, `CAGEDFOR`, `CAGEDEXC` + `AAAAMM` | `.txt`, 28 colunas, nomes minúsculos com acento (`raçacor`, `saldomovimentação`) | `;` | **UTF-8** | vírgula (`1800,00`) | `9` / `99` |

Todos confirmados. Ponto de atenção: **a RAIS mudou de layout três vezes no período** — o ETL precisa de um leitor por geração (já implementado em `etl/sources.py`).

**Tamanhos reais no FTP (comprimido):** RAIS ≈ 2,4–3,2 GB por ano (ex.: 2023 = 3,23 GB, sendo SP sozinho 1,02 GB); Novo CAGED ≈ 0,35–0,6 GB por ano. A taxa de compressão observada é de ~15×, ou seja, um ano da RAIS descompactado tem ~40 GB e a série 2015–2023 teria ~350 GB — **inviável de armazenar bruto**.

### 1.2 Classificação por variedade

| Tipo | Dado | Origem |
|---|---|---|
| **Estruturado** | Microdados RAIS e CAGED; tabelas CBO 2002 e CNAE 2.0; série do salário mínimo | CSV/TXT (PDET, IBGE/CONCLA, IPEA) |
| **Semi-estruturado** | Localidades (município → UF → região) via **API IBGE Localidades**; layouts/dicionários (XLSX) convertidos para YAML de configuração do ETL; logs do pipeline | JSON / XLSX |
| **Não estruturado** | Descrição sumária textual de cada ocupação da CBO (usada no drill-down por ocupação) | texto livre |

### 1.3 Fontes secundárias

Layouts oficiais do PDET (`Layout Não-identificado Novo Caged Movimentação.xlsx` e layout RAIS), tabela CBO 2002 (MTE), estrutura CNAE 2.0 (IBGE/CONCLA), API IBGE Localidades (JSON), série histórica do salário mínimo (IPEA/BCB) para deflacionar remunerações.

---

## 2. Estratégia de Otimização de Volume (limite de 1 GB no Aiven PostgreSQL)

A resposta direta: **usaremos os três mecanismos — filtros de recorte, agregação prévia e amostragem estatística —, nesta ordem de importância.** O banco recebe apenas o resultado já reduzido; o processamento pesado ocorre fora dele.

### 2.1 Filtros de recorte (aplicados no ETL, em streaming)

| Filtro | Regra | Efeito |
|---|---|---|
| **Setorial** | `CNAE 2.0 Subclasse` com divisão `62` (serviços de TI) ou `63` (atividades de informação) | É o filtro mais poderoso. **Medido:** no CAGED jan/2024, 45.970 de 3.955.239 movimentações (**1,16 %**) são de TI; na RAIS AC/2015, 0,18 %. Nacionalmente estimamos 1,5–2,5 % dos vínculos formais **[estimativa]** |
| **Temporal** | RAIS 2018–2023 (6 anos) + Novo CAGED 2020–2025 | Cobre o período pós-reforma trabalhista e a série completa do Novo CAGED (eSocial). 2015–2017 fica como extensão opcional |
| **Vínculo** | Para estoque: `Vínculo Ativo 31/12 = 1`; para fluxo (CAGED): todas as movimentações | Evita contar duas vezes quem trocou de emprego no ano |
| **Colunas** | `usecols` com ~20 das 60 colunas; descarte de bairros, distritos, causas de afastamento, remunerações mês a mês | Reduz ~65 % da largura antes de qualquer outra coisa |

Implementação: o `.7z` é descompactado **em streaming** (`7zz -so` → `pandas.read_csv(chunksize=500_000)`), filtrado por chunk e gravado em **Parquet (zstd)** em `data/processed/`. O TXT bruto nunca toca o disco. Validado nos quatro layouts: 3,96 mi de linhas do CAGED processadas em 12 s.

### 2.2 Agregação prévia (o que de fato vai para o PostgreSQL)

Tabela-fato agregada no grão **`ano × UF × sexo × raça/cor × faixa etária × escolaridade × nível de liderança × divisão CNAE`**, com as medidas: nº de vínculos, soma da remuneração, média, **mediana e p25/p75** (calculadas no ETL, pois não são recomponíveis depois), média de horas contratuais, tempo médio de emprego. Para o CAGED: fato mensal com admissões, desligamentos e saldo no mesmo grão.

Isso responde diretamente aos filtros cruzados exigidos no dashboard (Ano, UF/Região, Sexo, Raça/Cor, Faixa Etária) e ao seletor de métrica (média / mediana / rotatividade).

### 2.3 Amostragem estatística (camada opcional)

Amostra **estratificada de 5 %** dos microdados de TI (estratos UF × sexo × raça/cor), com ~18 colunas, para análises que a agregação não permite (distribuição salarial completa, boxplots). É auxiliar e é a primeira coisa a ser cortada se o orçamento apertar.

### 2.4 Orçamento de armazenamento **[estimativa]**

| Objeto | Linhas | Tamanho (tabela + índices) |
|---|---|---|
| `fato_vinculo_ti_agg` (RAIS) | ~400 mil | ~70 MB |
| `fato_movimentacao_ti_agg` (CAGED) | ~250 mil | ~35 MB |
| `amostra_vinculo_ti` (opcional) | ~450 mil | ~50 MB |
| Dimensões (CBO, CNAE, municípios, sexo, raça, faixas…) | < 10 mil | ~6 MB |
| Catálogo, WAL, folga | — | ~50 MB |
| **Total** | | **~210 MB (≈ 21 % do limite)** |

Mesmo errando as estimativas por um fator de 3, ficamos abaixo de 1 GB. Contingência: retirar `escolaridade` do grão (corte de ~70 % das linhas do fato).

---

## 3. Mapeamento de Variedade e Tipagem

Regra geral do ETL: **tudo é lido como `str`** (`dtype=str`) e convertido explicitamente, porque os códigos têm zero à esquerda e os marcadores de nulo são números "mágicos". As principais conversões:

### 3.1 RAIS Vínculos

| Coluna (nome 2018–2022 / 2023) | Tipo bruto | Exemplo real | Tipo alvo (PostgreSQL) | Transformação |
|---|---|---|---|---|
| `Vl Remun Média Nom` / `Vl Rem Média Nom` | string monetária | `0000001090,26` (≤2022) · `2242.58` (2023) | `NUMERIC(12,2)` | `.replace(",", ".")` só nos layouts antigos → `float` → `round(2)`; `0` → `NULL` |
| `Vl Remun Dezembro Nom` | string monetária | idem | `NUMERIC(12,2)` | idem |
| `Vl Remun Média (SM)` | string decimal | `000001,37` · `1.72` | `NUMERIC(8,2)` | idem |
| `Qtd Hora Contr` | string com espaços | `  44` | `SMALLINT` | `.strip()` → `int` |
| `Idade` | string com espaços | `  25` | `SMALLINT` | `.strip()` → `int` |
| `Tempo Emprego` | string decimal (meses) | `    14,9` · `15.4` | `NUMERIC(7,1)` | strip + vírgula→ponto → `float` |
| `Sexo Trabalhador` / `Sexo - Código` | string código | `01` · `1` | `SMALLINT` → `dim_sexo` | `int`; 1 = Masculino, 2 = Feminino |
| `Raça Cor` / `Raça Cor - Código` | string código | `08` · `2` | `SMALLINT` → `dim_raca_cor` | `int`; 1 Indígena, 2 Branca, 4 Preta, 6 Amarela, 8 Parda, 9 Não identificado |
| `CBO Ocupação 2002` | string 6 dígitos | `317110` | `CHAR(6)` → `dim_ocupacao` | `.strip().zfill(6)`; **nunca int** (preserva zero à esquerda); deriva `nivel_lideranca` pelo 1º dígito |
| `CNAE 2.0 Subclasse` | string 7 dígitos, às vezes com espaço | `" 6209100"` | `CHAR(7)` → `dim_setor` | `.strip().zfill(7)`; deriva `divisao = [:2]` |
| `Município` | string código IBGE 6 dígitos | `120050` · `999999` | `CHAR(6)` → `dim_localidade` | `999999` → `NULL`; UF = 2 primeiros dígitos |
| `Escolaridade após 2005` | string código | `07` | `SMALLINT` → `dim_escolaridade` | `int` (1 = analfabeto … 11 = doutorado) |
| `Faixa Etária` | string código | `04` | `SMALLINT` → `dim_faixa_etaria` | `int` (1 = 10–14 … 8 = 65+) |
| `Vínculo Ativo 31/12` | string `0/1` | `1` | `BOOLEAN` | `== "1"` |
| `Mês Admissão` / `Mês Desligamento` | string `00–12` | `04` | `SMALLINT` | `int`; `00` → `NULL` |
| `Motivo Desligamento`, `Tipo Admissão`, `Tipo Vínculo` | string código | `11` | `SMALLINT` → dimensões | `int`; `99`/`999` → `NULL` |
| `Ano` | **não é coluna** | — | `SMALLINT` | injetado pelo ETL a partir do caminho do arquivo |

Marcadores de nulo convertidos para `NULL`: `{ñ c}`, `{ñ class}`, `9997`, `999997`, `999999`, `99`, `999`, `-1`.

### 3.2 Novo CAGED (movimentações)

| Coluna | Tipo bruto | Exemplo real | Tipo alvo | Transformação |
|---|---|---|---|---|
| `competênciamov` | string `AAAAMM` | `202401` | `DATE` | `to_datetime(format="%Y%m")` → 1º dia do mês |
| `salário` / `valorsaláriofixo` | string monetária | `1394,24` | `NUMERIC(12,2)` | vírgula→ponto → `float` |
| `horascontratuais` | string decimal | `44,00` | `NUMERIC(5,2)` | idem |
| `saldomovimentação` | string `1`/`-1` | `-1` | `SMALLINT` | `int`; +1 admissão, −1 desligamento |
| `sexo` | string código | `3` | `SMALLINT` → `dim_sexo` | **domínio diferente da RAIS**: 1 Homem, 3 Mulher, 9 Não identificado → harmonizado para M/F |
| `raçacor` | string código | `2` | `SMALLINT` → `dim_raca_cor` | **domínio diferente da RAIS**: 1 Branca, 2 Preta, 3 Parda, 4 Amarela, 5 Indígena, 6 Não informada, 9 Não identificado → harmonizado |
| `cbo2002ocupação`, `subclasse`, `município` | string código | `411010`, `8532500`, `261360` | `CHAR(6/7/6)` | `zfill`; mesmas dimensões da RAIS |
| `idade` | string | `57` | `SMALLINT` | `int`; deriva `faixa_etaria` com os cortes da RAIS |
| `graudeinstrução` | string código | `7` | `SMALLINT` → `dim_escolaridade` | mapeado para o domínio da RAIS |
| `tipomovimentação` | string código | `97`, `40`, `31` | `SMALLINT` → `dim_tipo_movimentacao` | `int` (códigos completos no layout XLSX) |

### 3.3 Regra do funil de liderança (proposta)

Derivada do 1º dígito da CBO 2002 (Grande Grupo): **`1` = liderança** (dirigentes e gerentes; ex.: 1425 gerentes de TI), **`2` = profissional** (ex.: 2124 analistas de TI), **demais = técnico/base** (ex.: 3171 técnicos de desenvolvimento). No CAGED jan/2024, TI tem 4.467 movimentações no grupo 1 contra 14.837 no grupo 2 — é essa proporção, cruzada com sexo × raça/cor, que vira o KPI "taxa de chegada à liderança".

### 3.4 LGPD

A versão pública (`PUB`) já não traz CPF, PIS/NIS, nome, CNPJ/CEI ou data de nascimento — confirmado no cabeçalho. Ainda assim o ETL descarta explicitamente bairros/distritos (quase-identificadores) e o banco suprime medidas de células com **menos de 5 vínculos** para evitar reidentificação em cruzamentos finos (UF × raça × ocupação).

---

## 4. Estado atual da ingestão

- Estrutura `data/raw/` (7z, ignorado no git) e `data/processed/` (Parquet).
- `etl/sources.py` — catálogo das URLs e dos 3 layouts.
- `etl/download.py` — download com retomada e verificação de tamanho.
- `etl/extract_filter.py` — streaming 7z → filtro CNAE 62/63 → Parquet.
- Validado com RAIS 2015 (AC), 2022 (NI), 2023 (NI) e CAGED 2024-01.
- Próximo passo: download completo de RAIS 2018–2023 + CAGED 2020–2025 (~19 GB).
