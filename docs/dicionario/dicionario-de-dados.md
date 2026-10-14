# Dicionário de dados

Gerado a partir dos comentários do próprio banco (`COMMENT ON`), esquema `dw`.

## dim_escolaridade

Dimensão de escolaridade CONFORMADA. Aqui as duas bases usam a mesma escada de 11 degraus: RAIS (Escolaridade Após 2005 - Código) e CAGED (graudeinstrução) vão ambas de 1=Analfabeto a 11=Doutorado completo. A conformação se resume a tratar os valores fora de 1-11 (vazios na RAIS; códigos de não identificado/não informado no CAGED), todos mapeados para o canônico 99.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `escolaridade_id` | `smallint` | não | Chave surrogate (IDENTITY SMALLINT), referenciada pelos fatos. |
| `escolaridade_codigo` | `smallint` | não | Código CANÔNICO 1-11 (escada RAIS/CAGED) e 99 para não informada. |
| `escolaridade_nome` | `text` | não | Rótulo completo, no texto das duas fontes. |
| `nome_curto` | `text` | não | Rótulo abreviado para caber em legenda e eixo de gráfico. |
| `superior_completo` | `boolean` | não | TRUE de 9 (superior completo) para cima. É o controle central do funil: compara liderança entre pessoas com a MESMA qualificação formal. |
| `pos_graduacao` | `boolean` | não | TRUE em mestrado (10) e doutorado (11). |
| `codigo_rais` | `smallint` | sim | Código equivalente na RAIS. NULL em 99: qualquer valor fora de 1-11 vira 99. |
| `codigo_caged` | `smallint` | sim | Código equivalente no CAGED. NULL em 99: o CAGED usa códigos próprios de ausência (p.ex. 80/99) que o ETL colapsa no canônico 99. |
| `ordem` | `smallint` | não | Ordem de exibição, do menor ao maior grau de instrução. |
| `criado_em` | `timestamp with time zone` | não | Auditoria: instante da primeira inserção da linha. |
| `atualizado_em` | `timestamp with time zone` | não | Auditoria: instante da última atualização da linha. |

## dim_faixa_etaria

Dimensão de faixa etária CONFORMADA pelas faixas oficiais da RAIS (1 a 8). A RAIS já traz a faixa pronta (Faixa Etária - Código); o CAGED traz apenas idade em anos inteiros, então o ETL deriva a faixa por intervalo usando idade_min/idade_max. Guardar os limites na dimensão é o que torna a derivação auditável e reproduzível.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `faixa_etaria_id` | `smallint` | não | Chave surrogate (IDENTITY SMALLINT), referenciada pelos fatos. |
| `faixa_etaria_codigo` | `smallint` | não | Código CANÔNICO 1-8 (idêntico ao da RAIS) e 9 para não informada. |
| `faixa_etaria_nome` | `text` | não | Rótulo da faixa, ex.: "30 a 39 anos". |
| `idade_min` | `smallint` | sim | Idade mínima da faixa, inclusive. NULL na faixa "não informada". |
| `idade_max` | `smallint` | sim | Idade máxima da faixa, inclusive. NULL na faixa "não informada". Regra do ETL para o CAGED: idade BETWEEN idade_min AND idade_max; idade fora de qualquer faixa cai no código 9. |
| `codigo_rais` | `smallint` | sim | Código equivalente na RAIS. Igual ao canônico por construção, mantido explícito para auditoria. |
| `ordem` | `smallint` | não | Ordem de exibição em legendas e eixos. |
| `criado_em` | `timestamp with time zone` | não | Auditoria: instante da primeira inserção da linha. |
| `atualizado_em` | `timestamp with time zone` | não | Auditoria: instante da última atualização da linha. |

## dim_localidade

Dimensão geográfica no grão MUNICÍPIO (~5.571 linhas). Nenhum fato a referencia na carga atual, ela existe para (a) dar ao ETL o mapeamento município -> UF -> região, (b) documentar a hierarquia geográfica e (c) permitir, sem mudança de schema, um mart municipal futuro. Custa menos de 1 MB. Carregada pela API IBGE Localidades.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `localidade_id` | `integer` | não | Chave surrogate (IDENTITY). |
| `municipio_codigo` | `character(6)` | não | Código do município com 6 dígitos (IBGE sem o dígito verificador). CHAR(6) preservando zero à esquerda. É a chave de junção real: RAIS (Município - Código) e CAGED (município) trazem 6 dígitos, verificado nos arquivos. "999999" = não identificado. |
| `municipio_codigo_ibge` | `character(7)` | sim | Código IBGE completo de 7 dígitos (6 + dígito verificador). CHAR(7). NULL na linha sentinela de não identificado. Usado para cruzar com malhas e GeoJSON do IBGE. |
| `municipio_nome` | `text` | não | Nome do município conforme IBGE. |
| `uf_id` | `smallint` | não | FK para dw.dim_uf, a hierarquia município -> UF -> região mora aqui. |
| `criado_em` | `timestamp with time zone` | não | Auditoria: instante da primeira inserção da linha. |
| `atualizado_em` | `timestamp with time zone` | não | Auditoria: instante da última atualização da linha. |

## dim_nivel_lideranca

Dimensão encurtada (shrunken conformed dimension) derivada de dim_ocupacao: é o rollup do CBO 2002 pelo primeiro dígito (grande grupo) e é ela que os fatos referenciam. Existe para que o funil de liderança, a pergunta central do projeto, caiba no grão do fato: trocar o CBO completo por este nível reduz o fato de ~567 mil para ~147 mil linhas por ano da RAIS (medição em docs/etapa-2-modelagem.md §3).

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `nivel_lideranca_id` | `smallint` | não | Chave surrogate (IDENTITY SMALLINT), referenciada pelos fatos. |
| `nivel_lideranca_codigo` | `smallint` | não | Código canônico: 1=Liderança, 2=Profissional, 3=Técnico/Base, 9=Não classificado. |
| `nivel_lideranca_nome` | `text` | não | Rótulo exibido no dashboard. |
| `descricao` | `text` | não | Descrição do grande grupo CBO 2002 correspondente, para a banca conferir a regra. |
| `cbo_grandes_grupos` | `text` | não | Primeiros dígitos de CBO que caem neste nível. Regra: 1 -> Liderança, 2 -> Profissional, demais -> Técnico/Base. |
| `degrau_funil` | `smallint` | não | Ordem do degrau no funil, de cima (1 = liderança) para baixo. O código 9 recebe degrau 99 para ficar fora do funil. |
| `criado_em` | `timestamp with time zone` | não | Auditoria: instante da primeira inserção da linha. |
| `atualizado_em` | `timestamp with time zone` | não | Auditoria: instante da última atualização da linha. |

## dim_ocupacao

Dimensão de ocupação no grão CBO 2002 (6 dígitos), com a hierarquia da classificação e a coluna derivada de nível de liderança. Nenhum fato a referencia na carga atual (os fatos apontam para dim_nivel_lideranca): ela é a tabela de conformação que o ETL usa para traduzir CBO -> nível, e documenta no banco a regra que define "liderança". Custa menos de 1 MB (~2,5 mil ocupações) e mantém o drill-down por CBO disponível para um mart futuro sem mudança de schema.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `ocupacao_id` | `integer` | não | Chave surrogate (IDENTITY). |
| `cbo_codigo` | `character(6)` | não | Código CBO 2002 da ocupação, 6 dígitos. CHAR(6) para preservar zero à esquerda (ex.: "010105"), ler como número destruiria o grande grupo 0. |
| `cbo_titulo` | `text` | sim | Título da ocupação na CBO 2002. Texto livre (dado não estruturado da fonte secundária); NULL quando o código aparece nos microdados mas não na tabela oficial carregada. |
| `grande_grupo` | `character(1)` | não | 1º dígito do CBO = grande grupo. É daqui que sai o nível de liderança. |
| `subgrupo_principal` | `character(2)` | não | 2 primeiros dígitos do CBO = subgrupo principal. |
| `subgrupo` | `character(3)` | não | 3 primeiros dígitos do CBO = subgrupo. |
| `familia` | `character(4)` | não | 4 primeiros dígitos do CBO = família ocupacional (ex.: "2124" = analistas de TI). Nível natural de um drill-down futuro. |
| `nivel_lideranca_id` | `smallint` | não | FK para dw.dim_nivel_lideranca. Coluna DERIVADA: grande_grupo 1 -> Liderança, 2 -> Profissional, demais -> Técnico/Base; CBO ausente ou inválido -> Não classificado. |
| `criado_em` | `timestamp with time zone` | não | Auditoria: instante da primeira inserção da linha. |
| `atualizado_em` | `timestamp with time zone` | não | Auditoria: instante da última atualização da linha. |

## dim_raca_cor

Dimensão de raça/cor CONFORMADA, o ponto mais crítico da harmonização. Os códigos das duas bases COLIDEM com significados diferentes: na RAIS 1=Indígena, 2=Branca, 4=Preta, 6=Amarela, 8=Parda, 9=Não identificado; no CAGED 1=Branca, 2=Preta, 3=Parda, 4=Amarela, 5=Indígena, 6=Não informada, 9=Não identificado. Carregar os códigos brutos lado a lado trocaria "Indígena" por "Branca" e "Branca" por "Preta". O código canônico adotado segue a ordem do IBGE/PNAD.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `raca_cor_id` | `smallint` | não | Chave surrogate (IDENTITY SMALLINT), referenciada pelos fatos. |
| `raca_cor_codigo` | `smallint` | não | Código CANÔNICO: 1=Branca, 2=Preta, 3=Parda, 4=Amarela, 5=Indígena, 6=Não informada, 9=Não identificada. |
| `raca_cor_nome` | `text` | não | Rótulo exibido no dashboard. |
| `grupo_racial_ibge` | `text` | não | Agrupamento oficial do IBGE usado nas análises de desigualdade: pretos + pardos = "Negra". Evita que cada consulta reimplemente a regra e divirja. |
| `codigo_rais` | `smallint` | sim | Código equivalente na RAIS (coluna Raça Cor - Código). NULL em "Não informada": a RAIS não distingue não-informada de não-identificada, e tudo que não é 1/2/4/6/8 cai no canônico 9. |
| `codigo_caged` | `smallint` | sim | Código equivalente no Novo CAGED (coluna raçacor). |
| `declarada` | `boolean` | não | FALSE nas categorias 6 e 9. O percentual de linhas com declarada=FALSE é indicador de Veracidade do dashboard, por isso essas categorias são MANTIDAS, não descartadas. |
| `ordem` | `smallint` | não | Ordem de exibição em legendas e eixos. |
| `criado_em` | `timestamp with time zone` | não | Auditoria: instante da primeira inserção da linha. |
| `atualizado_em` | `timestamp with time zone` | não | Auditoria: instante da última atualização da linha. |

## dim_setor

Dimensão setorial conformada no grão SUBCLASSE CNAE 2.0, com a hierarquia subclasse -> classe -> grupo -> divisão -> seção. Tem exatamente 10 linhas: o recorte do projeto (divisões 62 e 63) tem 10 subclasses, e todas as 10 foram observadas nos microdados reais do CAGED. O CHECK de recorte transforma o filtro setorial do ETL em garantia do banco: linha de fora de 62/63 é rejeitada na carga, não descoberta depois.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `setor_id` | `smallint` | não | Chave surrogate (IDENTITY SMALLINT), referenciada pelos fatos. |
| `cnae_subclasse` | `character(7)` | não | Subclasse CNAE 2.0, 7 dígitos. CHAR(7) preservando zero à esquerda e os zeros internos (ex.: "6202300"). Chave natural; corresponde a CNAE 2.0 Subclasse - Codigo (RAIS) e subclasse (CAGED). |
| `subclasse_nome` | `text` | não | Denominação oficial da subclasse (CONCLA/IBGE, confirmada no layout do Novo CAGED). |
| `cnae_classe` | `character(5)` | não | Classe CNAE 2.0, 5 dígitos, mesmo conteúdo da coluna CNAE 2.0 Classe - Código da RAIS. |
| `classe_nome` | `text` | não | Denominação oficial da classe. |
| `cnae_grupo` | `character(3)` | não | Grupo CNAE 2.0, 3 dígitos (ex.: "620", "631", "639"). |
| `cnae_divisao` | `character(2)` | não | Divisão CNAE 2.0, 2 dígitos. "62" = serviços de TI; "63" = serviços de informação. Define o recorte do projeto. |
| `divisao_nome` | `text` | não | Denominação oficial da divisão. |
| `cnae_secao` | `character(1)` | não | Seção CNAE 2.0, 1 letra. Sempre "J" neste recorte, confirmado no CAGED, cuja coluna seção vem igual a J em 100 % das linhas filtradas. |
| `secao_nome` | `text` | não | Denominação oficial da seção. |
| `criado_em` | `timestamp with time zone` | não | Auditoria: instante da primeira inserção da linha. |
| `atualizado_em` | `timestamp with time zone` | não | Auditoria: instante da última atualização da linha. |

## dim_sexo

Dimensão de sexo CONFORMADA. Os domínios de origem divergem e não podem ser usados direto: RAIS usa 1=Masculino e 2=Feminino; CAGED usa 1=Homem, 3=Mulher e 9=Não identificado. Esta tabela fixa um código canônico e guarda, em colunas próprias, o código de cada base, a tradução fica documentada no banco, não escondida no ETL.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `sexo_id` | `smallint` | não | Chave surrogate (IDENTITY SMALLINT), referenciada pelos fatos. |
| `sexo_codigo` | `smallint` | não | Código CANÔNICO do projeto: 1=Masculino, 2=Feminino, 9=Não identificado. |
| `sexo_nome` | `text` | não | Rótulo exibido no dashboard. |
| `codigo_rais` | `smallint` | sim | Código equivalente na RAIS (1 ou 2). NULL quando a RAIS não tem a categoria, valores ausentes ou fora do domínio caem no canônico 9. |
| `codigo_caged` | `smallint` | sim | Código equivalente no Novo CAGED (1=Homem, 3=Mulher, 9=Não identificado). Note que 2 NÃO existe no CAGED: ler o código bruto como se fosse RAIS inverteria a leitura de gênero do projeto. |
| `declarado` | `boolean` | não | FALSE na categoria sem declaração. Permite à view separar "não declarado" sem apagar a categoria. |
| `ordem` | `smallint` | não | Ordem de exibição em legendas e eixos. |
| `criado_em` | `timestamp with time zone` | não | Auditoria: instante da primeira inserção da linha. |
| `atualizado_em` | `timestamp with time zone` | não | Auditoria: instante da última atualização da linha. |

## dim_tempo

Dimensão temporal conformada, grão = MÊS (primeiro dia do mês como representante). O CAGED aponta para o mês da movimentação. A RAIS, por ser um snapshot periódico do estoque em 31/12, aponta para a linha de DEZEMBRO do ano-base, convenção semântica, não atalho: a própria RAIS define o estoque pela coluna Ind Vínculo Ativo 31/12.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `tempo_id` | `integer` | não | Chave surrogate (IDENTITY). INTEGER porque a dimensão cresce com os anos carregados. |
| `data_competencia` | `date` | não | Chave natural: primeiro dia da competência (DATE). Ex.: 2025-03-01 = competência 2025/03. |
| `ano` | `smallint` | não | Ano-base (RAIS) ou ano da competência (CAGED). SMALLINT; é o filtro "Ano" do dashboard. |
| `mes` | `smallint` | não | Mês 1-12. Só tem significado analítico para o fato do CAGED; na RAIS é sempre 12. |
| `trimestre` | `smallint` | não | Trimestre 1-4, derivado do mês. |
| `semestre` | `smallint` | não | Semestre 1-2, derivado do mês. |
| `ano_mes` | `character(6)` | não | Competência no formato AAAAMM, igual ao campo competênciamov do CAGED. CHAR(6) preserva o zero do mês. |
| `mes_nome` | `text` | não | Nome do mês em português, gravado por array literal (independe de lc_time do servidor). |
| `rotulo` | `text` | não | Rótulo pronto para eixo de gráfico, ex.: "mar/2025". |
| `eh_dezembro` | `boolean` | não | TRUE em dezembro. Marca as linhas elegíveis a receber o snapshot anual da RAIS. |
| `criado_em` | `timestamp with time zone` | não | Auditoria: instante da primeira inserção da linha. |
| `atualizado_em` | `timestamp with time zone` | não | Auditoria: instante da última atualização da linha pelo ETL. |

## dim_uf

Dimensão geográfica encurtada (shrunken conformed dimension, Kimball): é o rollup de dim_localidade no nível UF e é ela que os dois fatos referenciam, porque o grão escolhido para os fatos é UF. Carrega também a região, o que atende ao filtro "UF/região" do dashboard sem join extra. 28 linhas (27 UFs + não identificada).

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `uf_id` | `smallint` | não | Chave surrogate (IDENTITY SMALLINT), referenciada pelas tabelas-fato. |
| `uf_codigo` | `character(2)` | não | Código IBGE da UF, 2 dígitos. CHAR(2) para preservar zero à esquerda (ex.: "11" = RO). É o valor bruto da coluna uf do CAGED e os 2 primeiros dígitos do município na RAIS. "99" = não identificada. |
| `uf_sigla` | `character(2)` | não | Sigla de 2 letras (ex.: "BA"). "ND" na linha de não identificada. |
| `uf_nome` | `text` | não | Nome da unidade da federação. |
| `regiao_codigo` | `character(1)` | não | Código IBGE da grande região, 1 dígito: 1=Norte, 2=Nordeste, 3=Sudeste, 4=Sul, 5=Centro-Oeste, 9=não identificada. Mesmo domínio da coluna região do CAGED. |
| `regiao_nome` | `text` | não | Nome da grande região. |
| `criado_em` | `timestamp with time zone` | não | Auditoria: instante da primeira inserção da linha. |
| `atualizado_em` | `timestamp with time zone` | não | Auditoria: instante da última atualização da linha. |

## fato_movimentacao_ti

FATO 2, fluxo de movimentações do setor de TI (Novo CAGED), transacional agregado. Grão: competência MENSAL x UF x subclasse CNAE x nível de liderança x sexo x raça/cor x faixa etária x escolaridade, as mesmas dimensões conformadas do fato de estoque, o que habilita o drill-across que produz a taxa de rotatividade. Volume medido: ~14,3 mil linhas por competência, ~171 mil por ano.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `tempo_id` | `integer` | não | FK dim_tempo no grão mês: a competência da movimentação (competênciamov, AAAAMM). |
| `uf_id` | `smallint` | não | FK dim_uf. Vem direto da coluna uf do CAGED (código IBGE de 2 dígitos). |
| `setor_id` | `smallint` | não | FK dim_setor. Subclasse CNAE 2.0 do estabelecimento. |
| `nivel_lideranca_id` | `smallint` | não | FK dim_nivel_lideranca. Derivado do 1º dígito de cbo2002ocupação. |
| `sexo_id` | `smallint` | não | FK dim_sexo, já no código canônico. ATENÇÃO: aqui a tradução é obrigatória, no CAGED mulher é 3, não 2. |
| `raca_cor_id` | `smallint` | não | FK dim_raca_cor, já no código canônico. A tradução é obrigatória: os códigos do CAGED colidem com os da RAIS. |
| `faixa_etaria_id` | `smallint` | não | FK dim_faixa_etaria, derivada da coluna idade pelos limites idade_min/idade_max da dimensão (o CAGED não traz faixa pronta). |
| `escolaridade_id` | `smallint` | não | FK dim_escolaridade, traduzida de graudeinstrução. |
| `admissoes` | `integer` | não | MEDIDA aditiva: movimentações com saldomovimentação = +1 na célula. |
| `desligamentos` | `integer` | não | MEDIDA aditiva: movimentações com saldomovimentação = -1 na célula. |
| `saldo` | `integer` | não | MEDIDA aditiva: admissoes - desligamentos. Redundante e protegida por CHECK, serve para o dashboard somar saldo sem recalcular e para a carga falhar se a contagem divergir. |
| `qtd_admissoes_com_sal` | `integer` | não | MEDIDA aditiva: admissões da célula com salário declarado maior que zero. Denominador correto da média salarial de admissão. |
| `soma_salario_admissao` | `numeric(16,2)` | não | MEDIDA aditiva: soma do salário de admissão (R$, coluna salário do CAGED, que vem com vírgula decimal e é convertida no ETL). Permite média exata em qualquer filtro. |
| `media_salario_admissao` | `numeric(12,2)` | sim | MEDIDA NÃO aditiva (R$): soma_salario_admissao / qtd_admissoes_com_sal. Salário de ENTRADA, é o indicador de desigualdade na porta de entrada do setor. |
| `carregado_em` | `timestamp with time zone` | não | Auditoria da carga, por competência. |

## fato_vinculo_ti

FATO 1, estoque de vínculos formais do setor de TI (RAIS), snapshot periódico anual. Grão: ano (via a linha de dezembro de dim_tempo) x UF x subclasse CNAE x nível de liderança x sexo x raça/cor x faixa etária x escolaridade. Uma linha agrega N vínculos; NÃO existe linha por pessoa. População: vínculos com Ind Vínculo Ativo 31/12 = 1 e CNAE 2.0 subclasse em 62/63. Volume medido: ~147 mil linhas por ano-base.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `tempo_id` | `integer` | não | FK dim_tempo. Aponta sempre para a competência de DEZEMBRO do ano-base, porque o estoque da RAIS é medido em 31/12. |
| `uf_id` | `smallint` | não | FK dim_uf. UF do município do vínculo (2 primeiros dígitos de Município - Código). |
| `setor_id` | `smallint` | não | FK dim_setor. Subclasse CNAE 2.0 do estabelecimento. |
| `nivel_lideranca_id` | `smallint` | não | FK dim_nivel_lideranca. Derivado do 1º dígito do CBO 2002 Ocupação - Código. |
| `sexo_id` | `smallint` | não | FK dim_sexo, já no código canônico (RAIS 1/2 traduzidos). |
| `raca_cor_id` | `smallint` | não | FK dim_raca_cor, já no código canônico (RAIS 1/2/4/6/8/9 traduzidos). |
| `faixa_etaria_id` | `smallint` | não | FK dim_faixa_etaria. Vem direto de Faixa Etária - Código. |
| `escolaridade_id` | `smallint` | não | FK dim_escolaridade. Vem de Escolaridade Após 2005 - Código. |
| `qtd_vinculos` | `integer` | não | MEDIDA aditiva: contagem de vínculos ativos em 31/12 na célula. É também o denominador do k-anonimato: célula com valor menor que 5 não é publicada. |
| `qtd_com_remuneracao` | `integer` | não | MEDIDA aditiva: vínculos da célula com Vl Rem Média Nom > 0, denominador correto das estatísticas salariais. Sem ele, média de médias erra em células com remuneração ausente. |
| `soma_remuneracao` | `numeric(16,2)` | não | MEDIDA aditiva: soma de Vl Rem Média Nom (R$). NUMERIC(16,2) porque é soma de milhares de salários. É o que permite recompor a média EXATA em qualquer combinação de filtros: SUM(soma)/SUM(qtd_com_remuneracao). |
| `media_remuneracao` | `numeric(12,2)` | sim | MEDIDA NÃO aditiva (pré-calculada, R$): soma_remuneracao / qtd_com_remuneracao. Redundante por desenho, evita divisão em toda consulta do dashboard. NUNCA deve ser agregada com AVG() entre células. |
| `mediana_remuneracao` | `numeric(12,2)` | sim | MEDIDA NÃO aditiva (R$): percentil 50 calculado no ETL, no grão fino. Mediana não se recompõe a partir de agregados, por isso é materializada. Em rollups, as views expõem apenas uma mediana ponderada APROXIMADA, com esse nome. |
| `p25_remuneracao` | `numeric(12,2)` | sim | MEDIDA NÃO aditiva (R$): 1º quartil da remuneração na célula. Mede dispersão interna, teto de vidro aparece na distribuição, não na média. |
| `p75_remuneracao` | `numeric(12,2)` | sim | MEDIDA NÃO aditiva (R$): 3º quartil da remuneração na célula. |
| `soma_horas_contratuais` | `integer` | não | MEDIDA aditiva: soma de Qtd Hora Contr (horas semanais). INTEGER porque a fonte traz horas inteiras. Permite o gap por hora trabalhada. |
| `media_horas_contratuais` | `numeric(5,2)` | sim | MEDIDA NÃO aditiva: horas semanais médias na célula. NUMERIC(5,2), o domínio válido vai de 1 a 44. |
| `soma_tempo_emprego` | `numeric(14,1)` | não | MEDIDA aditiva: soma de Tempo Emprego (em meses, com uma decimal na fonte). |
| `media_tempo_emprego` | `numeric(7,1)` | sim | MEDIDA NÃO aditiva: tempo médio de emprego em meses. Proxy de retenção, complementa a rotatividade do CAGED. |
| `carregado_em` | `timestamp with time zone` | não | Auditoria da carga. Coluna única (sem par criado_em/atualizado_em) porque o ETL do fato é full-refresh por ano e cada timestamptz a mais custa ~21 MB no horizonte completo. |
