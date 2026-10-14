# Etapa 2. Modelagem do Banco de Dados

**Projeto:** Diversidade na Tecnologia: Raça, Gênero e o Funil de Liderança no Setor de TI Brasileiro
**Disciplina:** Big Data e Analytics (UCSAL, 2026.2)
**Fontes:** RAIS 2025 (vínculos, anual) e Novo CAGED 2025 (movimentações, mensal). PDET/MTE
**Destino:** Aiven for PostgreSQL, Free Tier, **limite rígido de 1 GB**
**DDL:** `sql/01_schema.sql` (executável, idempotente, PostgreSQL 15+)

> **Convenção de veracidade** (a mesma da Etapa 1). **[medido]** = número obtido rodando código sobre os arquivos reais já baixados. **[extrapolado]** = projeção a partir de um número medido, com a fórmula explicitada. **[estimativa]** = ordem de grandeza a partir de premissa declarada. **[decisão]** = escolha nossa de modelagem, com justificativa.

---

## 1. O que esta etapa entrega

Três coisas, nesta ordem de importância:

1. Um **modelo estrela** com dimensões **conformadas** entre RAIS e CAGED, sem isso, os dois fatos não conversam e a taxa de rotatividade não existe.
2. Um **grão de fato escolhido por medição**, não por gosto: as quatro opções em disputa foram calculadas em linhas e em megabytes antes da escolha.
3. Uma **superfície pública com supressão de células pequenas**, para que o dashboard seja publicável sem expor indivíduo.

O DDL foi executado de verdade, em PostgreSQL 15.19 e 16.15, carregado com dados reais do CAGED e submetido a testes negativos. A seção 11 lista o que foi testado e o resultado.

---

## 2. Visão geral do modelo

Dois fatos agregados compartilhando oito dimensões conformadas (star schema com *drill-across*):

```
                         dw.dim_tempo (grão mês)
                                   │
          dw.dim_uf ───────────────┼─────────────── dw.dim_setor
       (27 UF + ND)                │              (10 subclasses CNAE)
              │                    │                      │
              │        ┌───────────┴───────────┐           │
              └────────┤   dw.fato_vinculo_ti  ├───────────┘
                       │        (RAIS)         │
   dw.dim_sexo ────────┤  estoque em 31/12     ├──────── dw.dim_faixa_etaria
   (3 linhas)          │  ~147 mil linhas/ano  │          (9 faixas)
                       └───────────┬───────────┘
   dw.dim_raca_cor ────────────────┼──────────────── dw.dim_escolaridade
   (7 linhas)                      │                     (12 degraus)
                       ┌───────────┴───────────┐
              ┌────────┤ dw.fato_movimentacao_ti├──────────┐
              │        │        (CAGED)         │          │
              │        │  fluxo mensal          │          │
              │        │  ~171 mil linhas/ano   │          │
              │        └───────────┬────────────┘          │
              │                    │                       │
       dw.dim_uf          dw.dim_nivel_lideranca      dw.dim_setor
                             (4 níveis)
                                   ▲
                                   │ rollup pelo 1º dígito do CBO
                          dw.dim_ocupacao
                        (CBO 2002, 6 dígitos)

   dw.dim_localidade (grão município) ──► dw.dim_uf      [tabela de conformação]

   publico.vw_*  ──►  views com k-anonimato (k = 5), única superfície do dashboard
```

**Doze tabelas:** 10 dimensões + 2 fatos. **Seis views públicas.** Dois esquemas: `dw` (interno) e `publico` (consumo).

Duas dimensões não são referenciadas pelos fatos e isso é intencional:

| Tabela | Grão | Papel |
|---|---|---|
| `dim_localidade` | município (~5.571 linhas) | Dá ao ETL o mapa município → UF → região e guarda o código IBGE de 7 dígitos para cruzar com malhas geográficas. Os fatos apontam para `dim_uf`, que é o **rollup** dela. |
| `dim_ocupacao` | CBO 2002, 6 dígitos (~2.500 linhas) | Dá ao ETL o mapa CBO → nível de liderança e documenta no banco a regra que define "liderança". Os fatos apontam para `dim_nivel_lideranca`, que é o **rollup** dela. |

Esse par de pares (`dim_localidade`/`dim_uf` e `dim_ocupacao`/`dim_nivel_lideranca`) é o padrão de *shrunken conformed dimension* do Kimball: a dimensão detalhada permanece no banco, a encurtada é a que o fato agregado referencia. Custo somado das duas detalhadas: menos de 2 MB. Benefício: o drill-down por município ou por CBO pode ser acrescentado depois sem redesenhar nada.

---

## 3. Decisão 1. O grão do fato

### 3.1 A pergunta

Quatro opções estavam em disputa, cruzando duas escolhas independentes:

- **Geografia:** município (~5.570 valores) ou UF (27 valores)?
- **Ocupação:** CBO completo (~690 valores observados em TI) ou nível de liderança (3 valores)?

### 3.2 Como foi medido

Não dá para decidir isso por intuição, porque o que importa não é o produto cartesiano (teto teórico) e sim **quantas células a matriz esparsa realmente ocupa**. Então medi.

Material: `data/processed/caged/2024/CAGEDMOV202401.parquet`, uma competência completa do Novo CAGED já filtrada para TI, **45.970 movimentações** [medido]. Nela: 27 UFs, 918 municípios, 687 códigos CBO distintos e as 10 subclasses CNAE de 62/63.

Para cada grão candidato, contei as células não vazias em subamostras de 5 %, 10 %, 20 %, 40 %, 70 % e 100 % e ajustei uma lei de potência `células = a · n^b`. O expoente `b` é a informação que interessa: quanto mais perto de 1, menos a agregação comprime (b = 1 significa "uma célula por registro", ou seja, microdado disfarçado).

| Grão | Células (n = 45.970) | Compressão | Lei ajustada | Projeção para n = 1,3 mi |
|---|---|---|---|---|
| **UF × nível de liderança** | **14.257** | **3,22×** | `9,79 · n^0,683` | **~147 mil** |
| Município × nível de liderança | 23.465 | 1,96× | `4,06 · n^0,811` | ~367 mil |
| UF × CBO completo | 29.664 | 1,55× | `2,61 · n^0,873` | ~567 mil |
| Município × CBO completo | 34.132 | 1,35× |, | ~900 mil |

[medido] as três primeiras colunas; [extrapolado] a última.

O n = 1,3 milhão é o volume estimado de vínculos de TI em um ano-base da RAIS [estimativa]: ~65 milhões de vínculos no Brasil × participação de 1,5, 2,5 % das divisões CNAE 62/63, conforme Etapa 1 §2.2. Faixa plausível: 1,0 a 1,6 milhão, o que move a projeção escolhida entre 123 mil e 170 mil linhas/ano.

> **Nota de honestidade metodológica.** A extrapolação usa a estrutura de esparsidade do CAGED porque o download da RAIS 2025 ainda estava em curso quando esta etapa foi fechada (`data/raw/rais/2025/RAIS_VINC_PUB_CENTRO_OESTE.7z` retornava "Unexpected end of archive"). As duas bases cobrem o mesmo recorte setorial, as mesmas 27 UFs e a mesma estrutura demográfica, então a forma da curva é transferível; o nível absoluto deve ser reconferido na primeira carga real. O comando de conferência está no fim de `sql/01_schema.sql`.

### 3.3 Quanto cada opção custa em disco

Aqui o número não é estimado: carreguei o fato de verdade e perguntei ao PostgreSQL [medido].

```
       relname        | tabela  | indices |  total  | linhas | bytes/linha
----------------------+---------+---------+---------+--------+------------
 fato_vinculo_ti      | 1752 kB | 1224 kB | 2976 kB |  14260 |        214
 fato_movimentacao_ti | 1248 kB | 1224 kB | 2472 kB |  14260 |        178
```

Com 214 B/linha (fato da RAIS, tabela + 4 índices) e 178 B/linha (fato do CAGED):

| Opção de grão | RAIS/ano | CAGED/ano | Carga 2025 | Horizonte RAIS 2015-25 + CAGED 2020-25 | Cabe em 1 GB? |
|---|---|---|---|---|---|
| **UF × nível** (escolhida) | 30 MB | 29 MB | **59 MB** | **~505 MB (49 %)** | **sim, com folga** |
| Município × nível | 75 MB | 48 MB | 123 MB | ~1,08 GB | não |
| UF × CBO completo | 116 MB | 60 MB | 176 MB | ~1,60 GB | não |
| Município × CBO completo | 184 MB | 70 MB | 254 MB | ~2,38 GB | não |

Somando dimensões (~2 MB) e 10 % de folga para *bloat*, WAL e catálogo, a opção escolhida fecha o horizonte completo em **~560 MB**, ou 55 % do limite. As outras três estouram antes de 2025 terminar de carregar.

### 3.4 O argumento que decide, e não é o de volume

Volume sozinho não bastaria: a carga de 2025, que é o escopo desta entrega, caberia em 1 GB em **qualquer** dos quatro grãos (254 MB no pior caso). O que elimina as opções finas é o cruzamento com a regra de supressão.

Medi, na mesma competência real, quantas movimentações ficam em células com menos de 5 registros:

| Grão | Células com ≥ 5 | Registros em células publicáveis |
|---|---|---|
| UF × nível | 16,0 % | **59,5 %** |
| Município × nível | 7,0 % | 34,7 % |
| UF × CBO | 3,5 % | 20,2 % |
| Município × CBO | 2,0 % | 12,1 % |

[medido]

A leitura é direta: **o detalhe comprado com o grão fino é exatamente o detalhe que a supressão apaga.** Pagar 1,60 GB para carregar CBO por UF e depois ter de esconder 80 % dos registros é gastar o orçamento inteiro para publicar menos. Grão mais grosso não é só mais barato, neste caso é mais informativo.

(Esses percentuais são do fato mensal do CAGED, o mais esparso dos dois: média de 3,2 movimentações por célula. No fato anual da RAIS a célula média tem ~8,8 vínculos, e a supressão morde muito menos: no teste de carga, com célula média de 9,7, foram publicadas 45 % das células e **83 % dos registros**, contra 16 % e 59 % do fato mensal.)

### 3.5 O trade-off, dito sem rodeio

**O que se perde:** análise por ocupação CBO específica ("quanto ganha uma *Gerente de Projetos de TI* preta em Pernambuco") e por município. Esses dois cortes **não existem** no fato.

**O que se mantém:**
- O drill-down pedido: região → UF → degrau do funil → sexo × raça × faixa etária × escolaridade → subclasse CNAE.
- A **subclasse CNAE** no grão, que é o corte setorial fino (Web Design ≠ Consultoria em TI ≠ Suporte técnico, e a composição de gênero e raça entre eles é achado relevante). Manter subclasse em vez de divisão custou dobrar o fato (14.257 contra 7.710 células) e foi uma escolha consciente: é a única dimensão fina que sobreviveu, e sobreviveu porque tem só 10 valores.
- A estrutura para recuperar o que foi cortado: `dim_ocupacao` e `dim_localidade` continuam no banco. Um terceiro fato estreito, `ano × município × sexo × raça` (~20 mil linhas/ano, ~5 MB/ano [extrapolado]), daria o mapa coroplético municipal sem ameaçar o orçamento. Fica registrado como extensão, fora do escopo desta etapa.

---

## 4. Decisão 2, "Não identificado" e "não informado"

**Decisão: manter como categoria própria, nunca descartar.** [decisão]

Três razões, em ordem de força:

1. **A ausência de declaração é achado, não ruído.** O tema do projeto é desigualdade racial e de gênero no setor de TI. Em quais UFs, em quais subclasses e em qual degrau do funil o empregador deixa de declarar raça/cor? Isso mede a qualidade da autodeclaração, que é parte do problema estudado. Descartar essas linhas apagaria a evidência.
2. **Descartar enviesa.** A não-declaração não é aleatória. Se ela se concentra em certos setores ou regiões, removê-la desloca todas as proporções do funil, e sem aviso.
3. **É o indicador de Veracidade do dashboard**, prometido na Etapa 1 §2.4.

Implementação:

- `dim_raca_cor` tem as duas categorias de ausência separadas (**6 = Não informada**, **9 = Não identificada**), porque o CAGED as distingue e a RAIS não. Colapsar seria perder informação que uma das fontes oferece.
- A coluna booleana `declarada` permite juntá-las em uma consulta sem perder a distinção na tabela. `dim_sexo` tem a coluna equivalente (`declarado`).
- `dim_raca_cor.grupo_racial_ibge` agrupa as duas em `'Sem declaração'`, ao lado de `'Branca'`, `'Negra'` (pretos + pardos, critério IBGE), `'Amarela'` e `'Indígena'`.

**Uma exceção deliberada, no nível de liderança.** O código `9 = Não classificado` de `dim_nivel_lideranca` recebe os vínculos com CBO ausente ou fora do domínio da CBO 2002 e fica **fora** do funil (`degrau_funil = 99`). A regra literal do projeto, "demais dígitos = Técnico/Base", jogaria o CBO `999999` na base da pirâmide, inflando artificialmente justamente o indicador principal. Nível de liderança é a variável dependente do estudo; contaminá-la com ausência de dado é diferente de manter a ausência como categoria visível.

---

## 5. Conformação dos domínios, a parte crítica

Este é o ponto onde um erro silencioso destruiria o projeto. **Os códigos das duas bases colidem com significados diferentes.**

### 5.1 Sexo

| Significado | Código canônico | RAIS | CAGED |
|---|---|---|---|
| Masculino | 1 | 1 | 1 |
| Feminino | **2** | 2 | **3** |
| Não identificado | 9 |, | 9 |

O CAGED **não usa o código 2**. Ler o campo bruto das duas bases na mesma coluna faria toda mulher do CAGED desaparecer da contagem.

### 5.2 Raça/cor, a colisão mais grave

| Significado | Código canônico | RAIS | CAGED |
|---|---|---|---|
| Branca | 1 | **2** | **1** |
| Preta | 2 | **4** | **2** |
| Parda | 3 | **8** | **3** |
| Amarela | 4 | **6** | **4** |
| Indígena | 5 | **1** | **5** |
| Não informada | 6 |, | 6 |
| Não identificada | 9 | 9 | 9 |

Os dois domínios usam os mesmos números para coisas diferentes. Carregar os códigos brutos lado a lado trocaria **Indígena por Branca**, **Branca por Preta** e **Preta por Amarela**, e nenhum erro apareceria: nenhuma constraint seria violada, nenhum JOIN falharia, só os números estariam errados. O código canônico adotado segue a ordem do IBGE/PNAD.

### 5.3 Faixa etária

A RAIS entrega a faixa pronta (`Faixa Etária - Código`, 1 a 8). O CAGED entrega **só `idade`** em anos inteiros (observado: 14 a 93). A conformação guarda `idade_min`/`idade_max` em `dim_faixa_etaria` e o ETL deriva a faixa do CAGED por intervalo, a regra fica no banco, auditável, em vez de escondida no código.

### 5.4 Escolaridade

Aqui as bases coincidem: `Escolaridade Após 2005 - Código` (RAIS) e `graudeinstrução` (CAGED) usam a mesma escada de 11 degraus, de `1 = Analfabeto` a `11 = Doutorado completo`, confirmado nos dois arquivos reais. A conformação se resume a colapsar o que está fora de 1, 11 no canônico `99`.

### 5.5 Como a tradução fica documentada

Cada dimensão conformada guarda, em colunas próprias, o código de origem de cada base: `codigo_rais` e `codigo_caged`. Isso faz três coisas: documenta a tradução no próprio banco (a banca confere com um `SELECT`), permite ao ETL resolver o código canônico por JOIN em vez de `if/else` espalhado, e deixa o rastro para auditoria quando um layout mudar.

```sql
SELECT raca_cor_codigo, raca_cor_nome, codigo_rais, codigo_caged, grupo_racial_ibge
FROM dw.dim_raca_cor ORDER BY ordem;
```

### 5.6 Recorte setorial

As divisões CNAE 62 e 63 têm **exatamente 10 subclasses**, e todas as 10 aparecem nos microdados reais [medido]. `dim_setor` vem semeada com elas e com a hierarquia completa (subclasse → classe → grupo → divisão → seção J). Os rótulos foram conferidos contra o layout oficial do Novo CAGED (`data/layouts/`), não digitados de memória.

Um `CHECK (cnae_divisao IN ('62','63'))` transforma o filtro do ETL em garantia do banco: linha fora do recorte é **rejeitada na carga**, não descoberta na apresentação.

---

## 6. Dicionário de dados, campos e tipos

Tipos conforme a exigência da entrega. Todas as tabelas e colunas têm `COMMENT ON` no DDL; o texto abaixo é o mesmo que está no banco e pode ser lido com `\d+` no psql.

### 6.1 Regras de tipagem aplicadas

| Natureza do dado | Tipo | Por quê |
|---|---|---|
| Dinheiro (medida de célula) | `NUMERIC(12,2)` | Exato, sem erro de ponto flutuante. Nunca `FLOAT` em valor monetário. |
| Dinheiro (soma de célula) | `NUMERIC(16,2)` | Soma de milhares de salários precisa de casa a mais. |
| Código de domínio pequeno | `SMALLINT` | 2 bytes em vez de 4. Multiplicado por 8 FKs e 2,6 milhões de linhas, são ~37 MB. |
| CBO 2002 | `CHAR(6)` | Preserva zero à esquerda. Lido como número, o grande grupo 0 viraria 5 dígitos. |
| CNAE subclasse / classe / grupo / divisão | `CHAR(7)` / `CHAR(5)` / `CHAR(3)` / `CHAR(2)` | Idem, e os zeros internos (`6202300`). |
| Município | `CHAR(6)` + `CHAR(7)` | 6 dígitos é o que as duas fontes trazem (verificado) e é a chave de junção; 7 dígitos (IBGE com verificador) fica disponível para malhas geográficas. |
| UF / região | `CHAR(2)` / `CHAR(1)` | Código IBGE com zero à esquerda. |
| Competência mensal | `DATE` | Primeiro dia do mês. Permite aritmética de data e `date_trunc`, o que `AAAAMM` em texto não permite. |
| Chave surrogate | `SMALLINT`/`INTEGER` `GENERATED ALWAYS AS IDENTITY` | `ALWAYS` impede o ETL de gravar id à mão e desalinhar os fatos (testado: a inserção explícita é recusada). |

### 6.2 `dw.dim_tempo`, grão mês, 144 linhas semeadas (2015-2026)

| # | Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|---|
| 1 | `tempo_id` | `integer` IDENTITY | NOT NULL | Chave surrogate (PK). |
| 2 | `data_competencia` | `date` | NOT NULL | Chave natural: 1º dia da competência. UNIQUE. |
| 3 | `ano` | `smallint` | NOT NULL | Filtro "Ano" do dashboard. |
| 4 | `mes` | `smallint` | NOT NULL | 1-12. Só tem sentido analítico no fato do CAGED. |
| 5 | `trimestre` | `smallint` | NOT NULL | 1-4. |
| 6 | `semestre` | `smallint` | NOT NULL | 1-2. |
| 7 | `ano_mes` | `char(6)` | NOT NULL | AAAAMM, igual a `competênciamov`. UNIQUE. |
| 8 | `mes_nome` | `text` | NOT NULL | Nome do mês em português (array literal, independe de `lc_time`). |
| 9 | `rotulo` | `text` | NOT NULL | Rótulo de eixo, ex.: `mar/2025`. |
| 10 | `eh_dezembro` | `boolean` | NOT NULL | Marca as linhas que recebem o snapshot da RAIS. |
| 11-12 | `criado_em`, `atualizado_em` | `timestamptz` | NOT NULL | Auditoria. |

**Convenção de duas periodicidades em uma dimensão.** O CAGED aponta para o mês da movimentação. A RAIS aponta para a linha de **dezembro** do ano-base, porque o estoque da RAIS é definido pela própria fonte em 31/12 (`Ind Vínculo Ativo 31/12`). Não é atalho: é a data de referência real do dado. Como os dois fatos são tabelas separadas, não há risco de dupla contagem; o filtro "Ano" (`dim_tempo.ano`) funciona para ambos.

### 6.3 `dw.dim_uf`. 28 linhas semeadas

| # | Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|---|
| 1 | `uf_id` | `smallint` IDENTITY | NOT NULL | PK, referenciada pelos dois fatos. |
| 2 | `uf_codigo` | `char(2)` | NOT NULL | Código IBGE. UNIQUE. `99` = não identificada. |
| 3 | `uf_sigla` | `char(2)` | NOT NULL | UNIQUE. `ND` na linha de não identificada. |
| 4 | `uf_nome` | `text` | NOT NULL | Nome da UF. |
| 5 | `regiao_codigo` | `char(1)` | NOT NULL | 1=Norte … 5=Centro-Oeste, 9=não identificada. |
| 6 | `regiao_nome` | `text` | NOT NULL | Atende ao filtro "UF/região" sem join extra. |
| 7-8 | `criado_em`, `atualizado_em` | `timestamptz` | NOT NULL | Auditoria. |

### 6.4 `dw.dim_localidade`, grão município

| # | Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|---|
| 1 | `localidade_id` | `integer` IDENTITY | NOT NULL | PK. |
| 2 | `municipio_codigo` | `char(6)` | NOT NULL | Chave de junção real (RAIS e CAGED). UNIQUE. |
| 3 | `municipio_codigo_ibge` | `char(7)` | NULL | Código IBGE com verificador, para malhas/GeoJSON. UNIQUE. |
| 4 | `municipio_nome` | `text` | NOT NULL | Nome IBGE. |
| 5 | `uf_id` | `smallint` | NOT NULL | FK → `dim_uf`. Guarda a hierarquia município → UF → região. |
| 6-7 | `criado_em`, `atualizado_em` | `timestamptz` | NOT NULL | Auditoria. |

Semeada com a linha sentinela `999999`; o resto é carregado da API IBGE Localidades pelo ETL.

### 6.5 `dw.dim_sexo`. 3 linhas semeadas

| # | Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|---|
| 1 | `sexo_id` | `smallint` IDENTITY | NOT NULL | PK. |
| 2 | `sexo_codigo` | `smallint` | NOT NULL | Canônico: 1, 2, 9. UNIQUE. |
| 3 | `sexo_nome` | `text` | NOT NULL | Rótulo. |
| 4 | `codigo_rais` | `smallint` | NULL | Código na RAIS. |
| 5 | `codigo_caged` | `smallint` | NULL | Código no CAGED (atenção: mulher = 3). |
| 6 | `declarado` | `boolean` | NOT NULL | FALSE em "não identificado". |
| 7 | `ordem` | `smallint` | NOT NULL | Ordem de exibição. |
| 8-9 | `criado_em`, `atualizado_em` | `timestamptz` | NOT NULL | Auditoria. |

### 6.6 `dw.dim_raca_cor`. 7 linhas semeadas

| # | Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|---|
| 1 | `raca_cor_id` | `smallint` IDENTITY | NOT NULL | PK. |
| 2 | `raca_cor_codigo` | `smallint` | NOT NULL | Canônico 1-6, 9. UNIQUE. |
| 3 | `raca_cor_nome` | `text` | NOT NULL | Rótulo. |
| 4 | `grupo_racial_ibge` | `text` | NOT NULL | Branca / Negra / Amarela / Indígena / Sem declaração. |
| 5 | `codigo_rais` | `smallint` | NULL | Código na RAIS. |
| 6 | `codigo_caged` | `smallint` | NULL | Código no CAGED. |
| 7 | `declarada` | `boolean` | NOT NULL | FALSE em 6 e 9, base do indicador de Veracidade. |
| 8 | `ordem` | `smallint` | NOT NULL | Ordem de exibição. |
| 9-10 | `criado_em`, `atualizado_em` | `timestamptz` | NOT NULL | Auditoria. |

### 6.7 `dw.dim_faixa_etaria`. 9 linhas semeadas

| # | Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|---|
| 1 | `faixa_etaria_id` | `smallint` IDENTITY | NOT NULL | PK. |
| 2 | `faixa_etaria_codigo` | `smallint` | NOT NULL | Canônico 1-8 (faixas da RAIS), 9 = não informada. UNIQUE. |
| 3 | `faixa_etaria_nome` | `text` | NOT NULL | Ex.: `30 a 39 anos`. |
| 4 | `idade_min` | `smallint` | NULL | Limite inferior, inclusive. |
| 5 | `idade_max` | `smallint` | NULL | Limite superior, inclusive. Usado para derivar a faixa do CAGED. |
| 6 | `codigo_rais` | `smallint` | NULL | Código na RAIS. |
| 7 | `ordem` | `smallint` | NOT NULL | Ordem de exibição. |
| 8-9 | `criado_em`, `atualizado_em` | `timestamptz` | NOT NULL | Auditoria. |

### 6.8 `dw.dim_escolaridade`. 12 linhas semeadas

| # | Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|---|
| 1 | `escolaridade_id` | `smallint` IDENTITY | NOT NULL | PK. |
| 2 | `escolaridade_codigo` | `smallint` | NOT NULL | Canônico 1-11, 99. UNIQUE. |
| 3 | `escolaridade_nome` | `text` | NOT NULL | Rótulo completo das fontes. |
| 4 | `nome_curto` | `text` | NOT NULL | Rótulo para legenda. |
| 5 | `superior_completo` | `boolean` | NOT NULL | TRUE de 9 para cima. **Controle central do funil.** |
| 6 | `pos_graduacao` | `boolean` | NOT NULL | TRUE em mestrado e doutorado. |
| 7 | `codigo_rais` | `smallint` | NULL | Código na RAIS. |
| 8 | `codigo_caged` | `smallint` | NULL | Código no CAGED. |
| 9 | `ordem` | `smallint` | NOT NULL | Ordem crescente de instrução. |
| 10-11 | `criado_em`, `atualizado_em` | `timestamptz` | NOT NULL | Auditoria. |

### 6.9 `dw.dim_nivel_lideranca`. 4 linhas semeadas

| # | Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|---|
| 1 | `nivel_lideranca_id` | `smallint` IDENTITY | NOT NULL | PK, referenciada pelos dois fatos. |
| 2 | `nivel_lideranca_codigo` | `smallint` | NOT NULL | 1=Liderança, 2=Profissional, 3=Técnico/Base, 9=Não classificado. UNIQUE. |
| 3 | `nivel_lideranca_nome` | `text` | NOT NULL | Rótulo. |
| 4 | `descricao` | `text` | NOT NULL | Grande grupo CBO correspondente, para conferência. |
| 5 | `cbo_grandes_grupos` | `text` | NOT NULL | Dígitos que caem no nível. |
| 6 | `degrau_funil` | `smallint` | NOT NULL | Ordem no funil; 99 no "não classificado", que fica fora dele. |
| 7-8 | `criado_em`, `atualizado_em` | `timestamptz` | NOT NULL | Auditoria. |

**A regra do funil:** 1º dígito do CBO 2002 igual a **1** → Liderança (grande grupo 1: membros superiores do poder público, dirigentes e gerentes); igual a **2** → Profissional (grande grupo 2: profissionais das ciências e das artes, onde ficam as famílias 2122/2123/2124, o núcleo técnico de TI); **demais** → Técnico/Base.

### 6.10 `dw.dim_ocupacao`, grão CBO 2002

| # | Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|---|
| 1 | `ocupacao_id` | `integer` IDENTITY | NOT NULL | PK. |
| 2 | `cbo_codigo` | `char(6)` | NOT NULL | Código CBO 2002. UNIQUE, `CHECK` de 6 dígitos. |
| 3 | `cbo_titulo` | `text` | NULL | Título da ocupação, dado **não estruturado** da fonte secundária. |
| 4 | `grande_grupo` | `char(1)` | NOT NULL | 1º dígito. Origem do nível de liderança. |
| 5 | `subgrupo_principal` | `char(2)` | NOT NULL | 2 primeiros dígitos. |
| 6 | `subgrupo` | `char(3)` | NOT NULL | 3 primeiros dígitos. |
| 7 | `familia` | `char(4)` | NOT NULL | 4 primeiros dígitos (ex.: `2124`). |
| 8 | `nivel_lideranca_id` | `smallint` | NOT NULL | FK → `dim_nivel_lideranca`. **Coluna derivada.** |
| 9-10 | `criado_em`, `atualizado_em` | `timestamptz` | NOT NULL | Auditoria. |

Um `CHECK` garante que a hierarquia seja de fato prefixo do código (`grande_grupo = substring(cbo_codigo,1,1)` e assim por diante), a desnormalização não pode divergir da chave.

### 6.11 `dw.dim_setor`. 10 linhas semeadas

| # | Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|---|
| 1 | `setor_id` | `smallint` IDENTITY | NOT NULL | PK, referenciada pelos dois fatos. |
| 2 | `cnae_subclasse` | `char(7)` | NOT NULL | Subclasse CNAE 2.0. UNIQUE. |
| 3 | `subclasse_nome` | `text` | NOT NULL | Denominação oficial. |
| 4 | `cnae_classe` | `char(5)` | NOT NULL | Classe (= coluna `CNAE 2.0 Classe` da RAIS). |
| 5 | `classe_nome` | `text` | NOT NULL | Denominação oficial. |
| 6 | `cnae_grupo` | `char(3)` | NOT NULL | Grupo. |
| 7 | `cnae_divisao` | `char(2)` | NOT NULL | `62` ou `63`, `CHECK` de recorte. |
| 8 | `divisao_nome` | `text` | NOT NULL | Denominação oficial. |
| 9 | `cnae_secao` | `char(1)` | NOT NULL | Sempre `J` neste recorte. |
| 10 | `secao_nome` | `text` | NOT NULL | Informação e comunicação. |
| 11-12 | `criado_em`, `atualizado_em` | `timestamptz` | NOT NULL | Auditoria. |

### 6.12 `dw.fato_vinculo_ti`. RAIS, estoque anual

**Grão:** ano (dezembro) × UF × subclasse CNAE × nível de liderança × sexo × raça/cor × faixa etária × escolaridade.
**População:** vínculos com `Ind Vínculo Ativo 31/12 = 1` e subclasse CNAE em 62/63.
**Volume:** ~147 mil linhas/ano [extrapolado].

| # | Coluna | Tipo | Nulo | Papel |
|---|---|---|---|---|
| 1 | `tempo_id` | `integer` | NOT NULL | FK → `dim_tempo` (sempre dezembro). |
| 2 | `uf_id` | `smallint` | NOT NULL | FK → `dim_uf`. |
| 3 | `setor_id` | `smallint` | NOT NULL | FK → `dim_setor`. |
| 4 | `nivel_lideranca_id` | `smallint` | NOT NULL | FK → `dim_nivel_lideranca`. |
| 5 | `sexo_id` | `smallint` | NOT NULL | FK → `dim_sexo`. |
| 6 | `raca_cor_id` | `smallint` | NOT NULL | FK → `dim_raca_cor`. |
| 7 | `faixa_etaria_id` | `smallint` | NOT NULL | FK → `dim_faixa_etaria`. |
| 8 | `escolaridade_id` | `smallint` | NOT NULL | FK → `dim_escolaridade`. |
| 9 | `qtd_vinculos` | `integer` | NOT NULL | Medida **aditiva**. Denominador do k-anonimato. |
| 10 | `qtd_com_remuneracao` | `integer` | NOT NULL | Medida **aditiva**. Denominador das estatísticas salariais. |
| 11 | `soma_remuneracao` | `numeric(16,2)` | NOT NULL | Medida **aditiva** (R$). |
| 12 | `media_remuneracao` | `numeric(12,2)` | NULL | **Não aditiva** (R$). Pré-calculada. |
| 13 | `mediana_remuneracao` | `numeric(12,2)` | NULL | **Não aditiva** (R$). Calculada no ETL, no grão fino. |
| 14 | `p25_remuneracao` | `numeric(12,2)` | NULL | **Não aditiva** (R$). 1º quartil. |
| 15 | `p75_remuneracao` | `numeric(12,2)` | NULL | **Não aditiva** (R$). 3º quartil. |
| 16 | `soma_horas_contratuais` | `integer` | NOT NULL | Medida **aditiva** (horas semanais). |
| 17 | `media_horas_contratuais` | `numeric(5,2)` | NULL | **Não aditiva**. Domínio válido 1-44. |
| 18 | `soma_tempo_emprego` | `numeric(14,1)` | NOT NULL | Medida **aditiva** (meses). |
| 19 | `media_tempo_emprego` | `numeric(7,1)` | NULL | **Não aditiva** (meses). Proxy de retenção. |
| 20 | `carregado_em` | `timestamptz` | NOT NULL | Auditoria da carga. |

**PK = o grão** (colunas 1-8, nessa ordem). Não há chave surrogate no fato: economiza 8 bytes/linha e, mais importante, faz o banco **recusar** qualquer carga que viole o grão (testado).

### 6.13 `dw.fato_movimentacao_ti`. CAGED, fluxo mensal

**Grão:** competência mensal × as mesmas 7 dimensões.
**Volume:** 14.260 linhas/competência [medido]; ~171 mil linhas/ano.

| # | Coluna | Tipo | Nulo | Papel |
|---|---|---|---|---|
| 1-8 | `tempo_id` … `escolaridade_id` | `integer` / `smallint` | NOT NULL | FKs, idênticas às do fato de estoque. **PK = colunas 1-8.** |
| 9 | `admissoes` | `integer` | NOT NULL | Medida **aditiva**: `saldomovimentação = +1`. |
| 10 | `desligamentos` | `integer` | NOT NULL | Medida **aditiva**: `saldomovimentação = -1`. |
| 11 | `saldo` | `integer` | NOT NULL | Medida **aditiva**. `CHECK (saldo = admissoes - desligamentos)`. |
| 12 | `qtd_admissoes_com_sal` | `integer` | NOT NULL | Medida **aditiva**. Denominador da média salarial. |
| 13 | `soma_salario_admissao` | `numeric(16,2)` | NOT NULL | Medida **aditiva** (R$). |
| 14 | `media_salario_admissao` | `numeric(12,2)` | NULL | **Não aditiva** (R$). Salário de **entrada**. |
| 15 | `carregado_em` | `timestamptz` | NOT NULL | Auditoria da carga. |

### 6.14 Por que existem colunas "soma" que a especificação não pedia

A entrega pediu `media_remuneracao`, `media_horas_contratuais`, `media_tempo_emprego` e `media_salario_admissao`. **Média não é agregável.** Quando o usuário do dashboard troca o filtro de "Bahia" para "Nordeste", a média da região **não** é a média das médias das UFs, é a soma dividida pela contagem. Sem as colunas `soma_*` e `qtd_com_remuneracao`, todo número agregado do dashboard estaria errado, com erro maior quanto mais desigual o tamanho das células.

As colunas `soma_*` foram acrescentadas por essa razão, não por completude: elas custam ~25 bytes/linha (34 MB no horizonte completo) e são a única forma de recompor a média **exata** em qualquer combinação de filtros. As `media_*` ficam como conveniência pré-calculada para o grão do fato.

**A mediana é caso aparte e não tem solução exata.** Mediana não se recompõe nem a partir de somas. Por isso é calculada no ETL no grão mais fino e materializada; em qualquer rollup, as views expõem apenas `mediana_aprox_ponderada`, média das medianas das células ponderada pelo número de vínculos. O nome da coluna carrega o aviso, e o `COMMENT` explica a limitação. Mediana exata existe só no grão do fato.

---

## 7. Índices

| Índice | Colunas | Serve a |
|---|---|---|
| `pk_fato_vinculo_ti` | grão completo, começando por `tempo_id` | Filtro por ano + prefixos (ano+UF, ano+UF+nível…). |
| `ix_fato_vinculo_uf_tempo` | `uf_id, tempo_id` | Filtro UF/região isolado; mapa por UF. |
| `ix_fato_vinculo_funil` | `nivel_lideranca_id, tempo_id, sexo_id, raca_cor_id` | A consulta central: composição do funil por sexo e raça. |
| `ix_fato_vinculo_demografia` | `sexo_id, raca_cor_id, tempo_id` | Gap salarial partindo de sexo/raça sem fixar UF. |
| *(os três últimos, espelhados em `fato_movimentacao_ti`)* | | |
| `ix_dim_tempo_ano` | `ano` | Resolve o filtro "Ano" na dimensão antes de tocar o fato. |
| `ix_dim_uf_regiao` | `regiao_codigo` | Rollup de UF para região. |

**Não há índice** nas FKs das dimensões minúsculas (sexo, raça, faixa, escolaridade, setor). Com 3 a 12 valores distintos, o planejador escolhe *seq scan* de qualquer forma, e cada índice inútil consome parte do 1 GB, os quatro índices do fato de estoque já custam 88 bytes/linha [medido], 41 % do total da tabela. Índice é orçamento, não enfeite.

---

## 8. LGPD e a superfície pública

### 8.1 Por que o fato é agregado

Duas razões independentes, e as duas são obrigatórias:

- **Volume:** microdado de TI de um único ano da RAIS, com índices, já estoura 1 GB.
- **Reidentificação:** a versão pública da RAIS não traz CPF, PIS nem CNPJ, mas uma linha com sexo + raça/cor + idade + ocupação + município + remuneração é reidentificável por cruzamento. Ausência de identificador direto não é anonimização.

Por isso **não existe linha por pessoa** em nenhum ponto do modelo. A menor unidade é uma célula que agrega N vínculos.

### 8.2 Supressão de células pequenas (k-anonimato, k = 5)

Nenhuma célula com menos de 5 vínculos (ou menos de 5 movimentações) é publicada. O limite está em um único lugar, a função `dw.limite_supressao()`, de onde as seis views o leem.

Duas escolhas de implementação que mudam o resultado:

**A célula pequena é removida, não mascarada.** Publicar a linha com a medida em `NULL` revelaria a **existência** da combinação, que é exatamente o que se quer proteger ("existe uma mulher indígena em cargo de liderança em Web Design no Acre" já é informação sobre uma pessoa). A linha sai inteira.

**As views de rollup agregam o fato e só então suprimem o resultado.** Agregar a view de grão fino já suprimida descartaria as células pequenas e **subestimaria todos os totais**. Agregar primeiro dá o número certo e continua seguro, porque o agregado é grande. O mesmo cuidado vale para o denominador de `pct_no_nivel`: ele é calculado numa CTE anterior ao filtro, porque em SQL o `WHERE` roda antes da *window function*, filtrar primeiro inflaria todos os percentuais.

### 8.3 As seis views

| View | Grão | Para que serve |
|---|---|---|
| `publico.vw_vinculo_ti` | grão do fato | Estoque desnormalizado, com remuneração por hora. |
| `publico.vw_movimentacao_ti` | grão do fato (mês) | Fluxo mensal. A mais afetada pela supressão. |
| `publico.vw_funil_lideranca` | ano × UF × nível × sexo × raça × superior completo | **A consulta central.** `pct_no_nivel` responde à pergunta do projeto. |
| `publico.vw_gap_salarial` | + escolaridade e faixa etária | Gap com controles: mesmo ano, UF, degrau, escolaridade e idade, variando só sexo e raça. |
| `publico.vw_rotatividade_ti` | ano × UF × nível × sexo × raça | **Drill-across** RAIS × CAGED. Taxas global e descontada. |
| `publico.vw_supressao_lgpd` | ano × UF | Quanto a proteção custou, indicador de Veracidade. |

### 8.4 Taxa de rotatividade, as duas definições

A view entrega as duas, porque elas respondem a perguntas diferentes:

- `taxa_rotatividade_global` = (admissões + desligamentos) / (2 × estoque). Mede o giro total, inclusive o causado por expansão ou retração do setor.
- `taxa_rotatividade_descontada` = min(admissões, desligamentos) / estoque, critério DIEESE. Desconta a variação de tamanho do setor e isola a **substituição** de trabalhadores. É a adequada para comparar grupos demográficos entre si.

Essa view só é possível porque as dimensões são conformadas. Se cada fato carregasse os códigos brutos da sua fonte, o JOIN produziria números errados **sem reclamar**, raça/cor 2 significa "Branca" na RAIS e "Preta" no CAGED.

### 8.5 Isolamento de privilégio

As tabelas-fato ficam no esquema `dw`; as views, em `publico`. As views **não** declaram `security_invoker`, então acessam `dw` com os privilégios do *owner*. Conceder `SELECT` nas views ao papel `dashboard_leitura` basta: ele fica sem nenhum privilégio em `dw`. Verificado na prática (seção 11, teste 10).

---

## 9. Orçamento de 1 GB, resumo

| Cenário | Linhas | Tabelas + índices | % de 1 GB |
|---|---|---|---|
| Carga desta entrega (RAIS 2025 + CAGED 2025) | ~318 mil | **~59 MB** | 6 % |
| + dimensões completas (município, CBO) | | ~61 MB | 6 % |
| Horizonte: RAIS 2015-2025 + CAGED 2020-2025 | ~2,65 mi | ~505 MB | 49 % |
| Idem, com 10 % de folga (bloat, WAL, catálogo) | | **~560 MB** | 55 % |

Base de cálculo: 214 bytes/linha no fato de estoque e 178 bytes/linha no fato de fluxo, **medidos** em PostgreSQL com os índices criados.

A conferência contra o número real está no fim do DDL (consulta a `pg_total_relation_size`) e deve ser rodada depois da primeira carga.

---

## 10. Ordem de carga do ETL

A ordem não é opcional, as FKs a impõem:

1. `dim_tempo`, `dim_uf`, `dim_sexo`, `dim_raca_cor`, `dim_faixa_etaria`, `dim_escolaridade`, `dim_nivel_lideranca`, `dim_setor`, **já semeadas pelo DDL**.
2. `dim_localidade` (API IBGE Localidades) → depende de `dim_uf`.
3. `dim_ocupacao` (tabela CBO 2002) → depende de `dim_nivel_lideranca`.
4. `fato_vinculo_ti` e `fato_movimentacao_ti` → dependem de tudo acima.

O ETL resolve as chaves surrogate por JOIN no código canônico, nunca por id fixo no código, `GENERATED ALWAYS` recusa id explícito de propósito. O padrão validado é: agregar em Pandas no grão do fato, gravar em tabela de *staging* com os códigos canônicos e fazer `INSERT .. SELECT` com JOIN nas dimensões, usando `ON CONFLICT ON CONSTRAINT pk_.. DO UPDATE` para que recarregar uma competência seja idempotente.

---

## 11. Validação executada

O DDL não foi entregue "deve funcionar". Foi executado.

| # | Teste | Resultado |
|---|---|---|
| 1 | Execução completa em **PostgreSQL 15.19** | 12 tabelas, 6 views, 0 erro, 0 warning |
| 2 | Execução completa em **PostgreSQL 16.15** | 0 erro |
| 3 | **Idempotência**: segunda execução do mesmo arquivo | 0 erro, 0 linha duplicada nos seeds |
| 4 | Contagem dos seeds | tempo 144, UF 28, sexo 3, raça 7, faixa 9, escolaridade 12, nível 4, setor 10, conforme projetado |
| 5 | **Carga real**: CAGED 2024-01 agregado e inserido via staging + JOIN nas dimensões | 14.260 linhas; soma das movimentações preservada em **45.970**, idêntica ao microdado de origem |
| 6 | Todas as 6 views consultadas com dados | retornaram resultado coerente e o *drill-across* produziu taxas. O fato de estoque foi preenchido com um **estoque sintético** derivado do CAGED (a RAIS 2025 ainda baixava): serve para exercitar o schema e as views, **não** como resultado analítico |
| 7 | `CHECK` de recorte CNAE: inserir subclasse da divisão 61 | **rejeitado** (`ck_dim_setor_recorte_ti`) |
| 8 | `CHECK` de coerência: `saldo ≠ admissoes - desligamentos`; `p25 > mediana` | **ambos rejeitados** |
| 9 | Violação de grão (linha duplicada no fato); FK órfã; id explícito em coluna `GENERATED ALWAYS` | **os três rejeitados** |
| 10 | Conectar como `dashboard_leitura` e tentar ler `dw.fato_vinculo_ti` | **`permission denied for schema dw`**; a view pública respondeu normalmente |
| 11 | Vazamento de célula pequena na view pública | mínimo publicado = 6; nenhuma célula abaixo de 5 escapou |
| 12 | Tamanho real em disco | 214 e 178 bytes/linha (seção 3.3) |

---

## 12. Limitações conhecidas

Registradas aqui para não serem descobertas na banca:

1. **Sem CBO e sem município no fato.** Decisão da seção 3. As dimensões continuam no banco; os cortes não existem no fato.
2. **Mediana em rollup é aproximada.** Limitação matemática, não de implementação. A coluna se chama `mediana_aprox_ponderada` e o `COMMENT` explica. Mitigação possível (Etapa 5): guardar o histograma por `Faixa Rem Média (SM)`, 12 faixas, que permitiria mediana aproximada por interpolação em qualquer filtro a custo baixo.
3. **O volume da RAIS é extrapolado**, não medido, o download de 2025 estava incompleto no fechamento desta etapa. A estrutura de esparsidade vem do CAGED real; o nível absoluto precisa de reconferência na primeira carga.
4. **A supressão morde forte no fato mensal do CAGED**: 40,5 % das movimentações ficam fora da view de grão fino. Para leitura agregada o dashboard deve usar `vw_rotatividade_ti`, que agrega antes de suprimir.
5. **A RAIS não distingue raça/cor "não informada" de "não identificada"**; o CAGED distingue. As duas categorias existem no modelo, mas as linhas da RAIS caem todas em "não identificada". Comparação entre as bases nessa categoria deve usar `declarada = FALSE`, não o código isolado.
6. **O par de periodicidades em `dim_tempo`** (RAIS em dezembro, CAGED no mês da movimentação) é convenção documentada, não restrição do banco. Um filtro de mês aplicado ao fato de estoque retorna tudo em dezembro, comportamento correto, mas que pode surpreender quem não leu esta seção.

---

## 13. Como executar

```bash
# criação do schema (idempotente)
psql "$AIVEN_URL" -v ON_ERROR_STOP=1 -f sql/01_schema.sql

# conferência
psql "$AIVEN_URL" -c "\dt dw.*"
psql "$AIVEN_URL" -c "\dv publico.*"
psql "$AIVEN_URL" -c "\d+ dw.fato_vinculo_ti"   -- campos, tipos e COMMENTs

# após o ETL: ANALYZE e verificação do orçamento de 1 GB
# (consultas prontas no rodapé de sql/01_schema.sql)
```

O papel `dashboard_leitura` é criado sem `LOGIN`. Defina senha e `LOGIN` fora do script, para que nenhuma credencial fique versionada:

```sql
ALTER ROLE dashboard_leitura LOGIN PASSWORD '<definir fora do repositório>';
```
