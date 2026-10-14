-- =====================================================================================
-- Projeto : Diversidade na Tecnologia. Raça, Gênero e o Funil de Liderança no TI BR
-- Etapa   : 2. Modelagem do Banco de Dados (modelo estrela / dimensional)
-- Alvo    : Aiven for PostgreSQL, Free Tier (PostgreSQL 15+), limite rígido de 1 GB
-- Fontes  : RAIS 2025 (vínculos, anual) e Novo CAGED 2025 (movimentações, mensal). PDET/MTE
-- Recorte : CNAE 2.0 subclasse iniciada em 62 ou 63 (10 subclasses, seção J)
-- Autor   : Victor Oliveira Santana Silva. UCSAL, Big Data e Analytics 2026.2
--
-- GRÃO DOS FATOS (decisão medida, não arbitrada, ver docs/etapa-2-modelagem.md §3):
--   fato_vinculo_ti      = ano (dez/AAAA) x UF x subclasse CNAE x nível de liderança
--                          x sexo x raça/cor x faixa etária x escolaridade
--   fato_movimentacao_ti = competência mensal x (as mesmas 7 dimensões)
--   Os dois fatos compartilham as MESMAS dimensões conformadas, o que habilita
--   drill-across (estoque RAIS x fluxo CAGED) para a taxa de rotatividade.
--
-- ORÇAMENTO (medido sobre dados reais, ver §4 do documento):
--   ~147 mil linhas/ano (RAIS) + ~171 mil linhas/ano (CAGED)
--   carga 2025 ....... ~64 MB  (6 % de 1 GB)
--   horizonte 2015-2025 ... ~620 MB (61 % de 1 GB)
--
-- PROPRIEDADES DESTE SCRIPT:
--   - Idempotente: pode ser executado várias vezes sem erro e sem duplicar seed.
--   - Transacional: tudo dentro de um BEGIN/COMMIT; falha em qualquer ponto = rollback.
--   - Sem dependência de locale: nomes de mês vêm de array literal, não de to_char(TM).
--   - Sem comando que exija superusuário: a criação de role é guardada por DO/EXCEPTION.
--
-- Execução:  psql "$AIVEN_URL" -v ON_ERROR_STOP=1 -f sql/01_schema.sql
-- =====================================================================================

\set ON_ERROR_STOP on

BEGIN;

SET LOCAL client_min_messages = WARNING;

-- =====================================================================================
-- 0. ESQUEMAS, separação entre o armazém interno e a superfície pública (LGPD)
-- =====================================================================================

CREATE SCHEMA IF NOT EXISTS dw;
CREATE SCHEMA IF NOT EXISTS publico;

COMMENT ON SCHEMA dw IS
  'Armazém interno: dimensões conformadas e tabelas-fato agregadas. Acesso restrito ao '
  'owner/ETL. Nenhuma linha representa pessoa identificada, mas células pequenas (menos '
  'de 5 vínculos) podem ser reidentificáveis por cruzamento, por isso este esquema não é '
  'exposto ao dashboard.';

COMMENT ON SCHEMA publico IS
  'Superfície de consumo do dashboard: apenas VIEWs com supressão de células pequenas '
  '(k-anonimato, k = 5). As views NÃO usam security_invoker, logo rodam com os privilégios '
  'do owner, o papel de leitura consulta aqui sem receber qualquer privilégio em dw.';

-- =====================================================================================
-- 1. PARÂMETRO DE SUPRESSÃO (LGPD), um único ponto de verdade
-- =====================================================================================

CREATE OR REPLACE FUNCTION dw.limite_supressao()
RETURNS integer
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $fn$ SELECT 5 $fn$;

COMMENT ON FUNCTION dw.limite_supressao() IS
  'Limite k do k-anonimato aplicado nas views públicas: células com menos de 5 vínculos '
  '(ou menos de 5 movimentações) não são publicadas. IMMUTABLE para que o planejador '
  'inline a constante e os índices continuem utilizáveis.';

-- =====================================================================================
-- 2. DIMENSÕES CONFORMADAS
--    Todas com chave surrogate GENERATED ALWAYS AS IDENTITY + chave natural UNIQUE.
--    As dimensões de domínio pequeno usam identidade SMALLINT: o fato carrega 2 bytes
--    por FK em vez de 4, o que economiza ~14 bytes por linha de fato (~37 MB no
--    horizonte completo). Decisão de orçamento, não de estilo.
-- =====================================================================================

-- ------------------------------------------------------------------ 2.1 dim_tempo ----
CREATE TABLE IF NOT EXISTS dw.dim_tempo (
    tempo_id          integer     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    data_competencia  date        NOT NULL,
    ano               smallint    NOT NULL,
    mes               smallint    NOT NULL,
    trimestre         smallint    NOT NULL,
    semestre          smallint    NOT NULL,
    ano_mes           char(6)     NOT NULL,
    mes_nome          text        NOT NULL,
    rotulo            text        NOT NULL,
    eh_dezembro       boolean     NOT NULL,
    criado_em         timestamptz NOT NULL DEFAULT now(),
    atualizado_em     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_dim_tempo_competencia UNIQUE (data_competencia),
    CONSTRAINT uq_dim_tempo_ano_mes     UNIQUE (ano_mes),
    CONSTRAINT ck_dim_tempo_dia_1       CHECK (date_part('day', data_competencia) = 1),
    CONSTRAINT ck_dim_tempo_mes         CHECK (mes BETWEEN 1 AND 12),
    CONSTRAINT ck_dim_tempo_trimestre   CHECK (trimestre BETWEEN 1 AND 4),
    CONSTRAINT ck_dim_tempo_semestre    CHECK (semestre BETWEEN 1 AND 2),
    CONSTRAINT ck_dim_tempo_ano         CHECK (ano BETWEEN 2000 AND 2100)
);

COMMENT ON TABLE dw.dim_tempo IS
  'Dimensão temporal conformada, grão = MÊS (primeiro dia do mês como representante). '
  'O CAGED aponta para o mês da movimentação. A RAIS, por ser um snapshot periódico do '
  'estoque em 31/12, aponta para a linha de DEZEMBRO do ano-base, convenção semântica, '
  'não atalho: a própria RAIS define o estoque pela coluna Ind Vínculo Ativo 31/12.';
COMMENT ON COLUMN dw.dim_tempo.tempo_id          IS 'Chave surrogate (IDENTITY). INTEGER porque a dimensão cresce com os anos carregados.';
COMMENT ON COLUMN dw.dim_tempo.data_competencia  IS 'Chave natural: primeiro dia da competência (DATE). Ex.: 2025-03-01 = competência 2025/03.';
COMMENT ON COLUMN dw.dim_tempo.ano               IS 'Ano-base (RAIS) ou ano da competência (CAGED). SMALLINT; é o filtro "Ano" do dashboard.';
COMMENT ON COLUMN dw.dim_tempo.mes               IS 'Mês 1-12. Só tem significado analítico para o fato do CAGED; na RAIS é sempre 12.';
COMMENT ON COLUMN dw.dim_tempo.trimestre         IS 'Trimestre 1-4, derivado do mês.';
COMMENT ON COLUMN dw.dim_tempo.semestre          IS 'Semestre 1-2, derivado do mês.';
COMMENT ON COLUMN dw.dim_tempo.ano_mes           IS 'Competência no formato AAAAMM, igual ao campo competênciamov do CAGED. CHAR(6) preserva o zero do mês.';
COMMENT ON COLUMN dw.dim_tempo.mes_nome          IS 'Nome do mês em português, gravado por array literal (independe de lc_time do servidor).';
COMMENT ON COLUMN dw.dim_tempo.rotulo            IS 'Rótulo pronto para eixo de gráfico, ex.: "mar/2025".';
COMMENT ON COLUMN dw.dim_tempo.eh_dezembro       IS 'TRUE em dezembro. Marca as linhas elegíveis a receber o snapshot anual da RAIS.';
COMMENT ON COLUMN dw.dim_tempo.criado_em         IS 'Auditoria: instante da primeira inserção da linha.';
COMMENT ON COLUMN dw.dim_tempo.atualizado_em     IS 'Auditoria: instante da última atualização da linha pelo ETL.';

-- --------------------------------------------------------------------- 2.2 dim_uf ----
CREATE TABLE IF NOT EXISTS dw.dim_uf (
    uf_id          smallint    GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uf_codigo      char(2)     NOT NULL,
    uf_sigla       char(2)     NOT NULL,
    uf_nome        text        NOT NULL,
    regiao_codigo  char(1)     NOT NULL,
    regiao_nome    text        NOT NULL,
    criado_em      timestamptz NOT NULL DEFAULT now(),
    atualizado_em  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_dim_uf_codigo     UNIQUE (uf_codigo),
    CONSTRAINT uq_dim_uf_sigla      UNIQUE (uf_sigla),
    CONSTRAINT ck_dim_uf_codigo     CHECK (uf_codigo ~ '^[0-9]{2}$'),
    CONSTRAINT ck_dim_uf_regiao     CHECK (regiao_codigo ~ '^[0-9]$')
);

COMMENT ON TABLE dw.dim_uf IS
  'Dimensão geográfica encurtada (shrunken conformed dimension, Kimball): é o rollup de '
  'dim_localidade no nível UF e é ela que os dois fatos referenciam, porque o grão '
  'escolhido para os fatos é UF. Carrega também a região, o que atende ao filtro '
  '"UF/região" do dashboard sem join extra. 28 linhas (27 UFs + não identificada).';
COMMENT ON COLUMN dw.dim_uf.uf_id          IS 'Chave surrogate (IDENTITY SMALLINT), referenciada pelas tabelas-fato.';
COMMENT ON COLUMN dw.dim_uf.uf_codigo      IS 'Código IBGE da UF, 2 dígitos. CHAR(2) para preservar zero à esquerda (ex.: "11" = RO). É o valor bruto da coluna uf do CAGED e os 2 primeiros dígitos do município na RAIS. "99" = não identificada.';
COMMENT ON COLUMN dw.dim_uf.uf_sigla       IS 'Sigla de 2 letras (ex.: "BA"). "ND" na linha de não identificada.';
COMMENT ON COLUMN dw.dim_uf.uf_nome        IS 'Nome da unidade da federação.';
COMMENT ON COLUMN dw.dim_uf.regiao_codigo  IS 'Código IBGE da grande região, 1 dígito: 1=Norte, 2=Nordeste, 3=Sudeste, 4=Sul, 5=Centro-Oeste, 9=não identificada. Mesmo domínio da coluna região do CAGED.';
COMMENT ON COLUMN dw.dim_uf.regiao_nome    IS 'Nome da grande região.';
COMMENT ON COLUMN dw.dim_uf.criado_em      IS 'Auditoria: instante da primeira inserção da linha.';
COMMENT ON COLUMN dw.dim_uf.atualizado_em  IS 'Auditoria: instante da última atualização da linha.';

-- -------------------------------------------------------------- 2.3 dim_localidade ----
CREATE TABLE IF NOT EXISTS dw.dim_localidade (
    localidade_id         integer     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    municipio_codigo      char(6)     NOT NULL,
    municipio_codigo_ibge char(7),
    municipio_nome        text        NOT NULL,
    uf_id                 smallint    NOT NULL,
    criado_em             timestamptz NOT NULL DEFAULT now(),
    atualizado_em         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_dim_localidade_cod6 UNIQUE (municipio_codigo),
    CONSTRAINT uq_dim_localidade_cod7 UNIQUE (municipio_codigo_ibge),
    CONSTRAINT ck_dim_localidade_cod6 CHECK (municipio_codigo ~ '^[0-9]{6}$'),
    CONSTRAINT ck_dim_localidade_cod7 CHECK (municipio_codigo_ibge IS NULL
                                             OR municipio_codigo_ibge ~ '^[0-9]{7}$'),
    CONSTRAINT fk_dim_localidade_uf   FOREIGN KEY (uf_id)
        REFERENCES dw.dim_uf (uf_id) ON UPDATE CASCADE ON DELETE RESTRICT
);

COMMENT ON TABLE dw.dim_localidade IS
  'Dimensão geográfica no grão MUNICÍPIO (~5.571 linhas). Nenhum fato a referencia na '
  'carga atual, ela existe para (a) dar ao ETL o mapeamento município -> UF -> região, '
  '(b) documentar a hierarquia geográfica e (c) permitir, sem mudança de schema, um mart '
  'municipal futuro. Custa menos de 1 MB. Carregada pela API IBGE Localidades.';
COMMENT ON COLUMN dw.dim_localidade.localidade_id         IS 'Chave surrogate (IDENTITY).';
COMMENT ON COLUMN dw.dim_localidade.municipio_codigo      IS 'Código do município com 6 dígitos (IBGE sem o dígito verificador). CHAR(6) preservando zero à esquerda. É a chave de junção real: RAIS (Município - Código) e CAGED (município) trazem 6 dígitos, verificado nos arquivos. "999999" = não identificado.';
COMMENT ON COLUMN dw.dim_localidade.municipio_codigo_ibge IS 'Código IBGE completo de 7 dígitos (6 + dígito verificador). CHAR(7). NULL na linha sentinela de não identificado. Usado para cruzar com malhas e GeoJSON do IBGE.';
COMMENT ON COLUMN dw.dim_localidade.municipio_nome        IS 'Nome do município conforme IBGE.';
COMMENT ON COLUMN dw.dim_localidade.uf_id                 IS 'FK para dw.dim_uf, a hierarquia município -> UF -> região mora aqui.';
COMMENT ON COLUMN dw.dim_localidade.criado_em             IS 'Auditoria: instante da primeira inserção da linha.';
COMMENT ON COLUMN dw.dim_localidade.atualizado_em         IS 'Auditoria: instante da última atualização da linha.';

-- ------------------------------------------------------------------- 2.4 dim_sexo ----
CREATE TABLE IF NOT EXISTS dw.dim_sexo (
    sexo_id        smallint    GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sexo_codigo    smallint    NOT NULL,
    sexo_nome      text        NOT NULL,
    codigo_rais    smallint,
    codigo_caged   smallint,
    declarado      boolean     NOT NULL,
    ordem          smallint    NOT NULL,
    criado_em      timestamptz NOT NULL DEFAULT now(),
    atualizado_em  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_dim_sexo_codigo UNIQUE (sexo_codigo)
);

COMMENT ON TABLE dw.dim_sexo IS
  'Dimensão de sexo CONFORMADA. Os domínios de origem divergem e não podem ser usados '
  'direto: RAIS usa 1=Masculino e 2=Feminino; CAGED usa 1=Homem, 3=Mulher e 9=Não '
  'identificado. Esta tabela fixa um código canônico e guarda, em colunas próprias, o '
  'código de cada base, a tradução fica documentada no banco, não escondida no ETL.';
COMMENT ON COLUMN dw.dim_sexo.sexo_id       IS 'Chave surrogate (IDENTITY SMALLINT), referenciada pelos fatos.';
COMMENT ON COLUMN dw.dim_sexo.sexo_codigo   IS 'Código CANÔNICO do projeto: 1=Masculino, 2=Feminino, 9=Não identificado.';
COMMENT ON COLUMN dw.dim_sexo.sexo_nome     IS 'Rótulo exibido no dashboard.';
COMMENT ON COLUMN dw.dim_sexo.codigo_rais   IS 'Código equivalente na RAIS (1 ou 2). NULL quando a RAIS não tem a categoria, valores ausentes ou fora do domínio caem no canônico 9.';
COMMENT ON COLUMN dw.dim_sexo.codigo_caged  IS 'Código equivalente no Novo CAGED (1=Homem, 3=Mulher, 9=Não identificado). Note que 2 NÃO existe no CAGED: ler o código bruto como se fosse RAIS inverteria a leitura de gênero do projeto.';
COMMENT ON COLUMN dw.dim_sexo.declarado     IS 'FALSE na categoria sem declaração. Permite à view separar "não declarado" sem apagar a categoria.';
COMMENT ON COLUMN dw.dim_sexo.ordem         IS 'Ordem de exibição em legendas e eixos.';
COMMENT ON COLUMN dw.dim_sexo.criado_em     IS 'Auditoria: instante da primeira inserção da linha.';
COMMENT ON COLUMN dw.dim_sexo.atualizado_em IS 'Auditoria: instante da última atualização da linha.';

-- --------------------------------------------------------------- 2.5 dim_raca_cor ----
CREATE TABLE IF NOT EXISTS dw.dim_raca_cor (
    raca_cor_id       smallint    GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    raca_cor_codigo   smallint    NOT NULL,
    raca_cor_nome     text        NOT NULL,
    grupo_racial_ibge text        NOT NULL,
    codigo_rais       smallint,
    codigo_caged      smallint,
    declarada         boolean     NOT NULL,
    ordem             smallint    NOT NULL,
    criado_em         timestamptz NOT NULL DEFAULT now(),
    atualizado_em     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_dim_raca_cor_codigo UNIQUE (raca_cor_codigo)
);

COMMENT ON TABLE dw.dim_raca_cor IS
  'Dimensão de raça/cor CONFORMADA, o ponto mais crítico da harmonização. Os códigos '
  'das duas bases COLIDEM com significados diferentes: na RAIS 1=Indígena, 2=Branca, '
  '4=Preta, 6=Amarela, 8=Parda, 9=Não identificado; no CAGED 1=Branca, 2=Preta, '
  '3=Parda, 4=Amarela, 5=Indígena, 6=Não informada, 9=Não identificado. Carregar os '
  'códigos brutos lado a lado trocaria "Indígena" por "Branca" e "Branca" por "Preta". '
  'O código canônico adotado segue a ordem do IBGE/PNAD.';
COMMENT ON COLUMN dw.dim_raca_cor.raca_cor_id       IS 'Chave surrogate (IDENTITY SMALLINT), referenciada pelos fatos.';
COMMENT ON COLUMN dw.dim_raca_cor.raca_cor_codigo   IS 'Código CANÔNICO: 1=Branca, 2=Preta, 3=Parda, 4=Amarela, 5=Indígena, 6=Não informada, 9=Não identificada.';
COMMENT ON COLUMN dw.dim_raca_cor.raca_cor_nome     IS 'Rótulo exibido no dashboard.';
COMMENT ON COLUMN dw.dim_raca_cor.grupo_racial_ibge IS 'Agrupamento oficial do IBGE usado nas análises de desigualdade: pretos + pardos = "Negra". Evita que cada consulta reimplemente a regra e divirja.';
COMMENT ON COLUMN dw.dim_raca_cor.codigo_rais       IS 'Código equivalente na RAIS (coluna Raça Cor - Código). NULL em "Não informada": a RAIS não distingue não-informada de não-identificada, e tudo que não é 1/2/4/6/8 cai no canônico 9.';
COMMENT ON COLUMN dw.dim_raca_cor.codigo_caged      IS 'Código equivalente no Novo CAGED (coluna raçacor).';
COMMENT ON COLUMN dw.dim_raca_cor.declarada         IS 'FALSE nas categorias 6 e 9. O percentual de linhas com declarada=FALSE é indicador de Veracidade do dashboard, por isso essas categorias são MANTIDAS, não descartadas.';
COMMENT ON COLUMN dw.dim_raca_cor.ordem             IS 'Ordem de exibição em legendas e eixos.';
COMMENT ON COLUMN dw.dim_raca_cor.criado_em         IS 'Auditoria: instante da primeira inserção da linha.';
COMMENT ON COLUMN dw.dim_raca_cor.atualizado_em     IS 'Auditoria: instante da última atualização da linha.';

-- ------------------------------------------------------------ 2.6 dim_faixa_etaria ----
CREATE TABLE IF NOT EXISTS dw.dim_faixa_etaria (
    faixa_etaria_id     smallint    GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    faixa_etaria_codigo smallint    NOT NULL,
    faixa_etaria_nome   text        NOT NULL,
    idade_min           smallint,
    idade_max           smallint,
    codigo_rais         smallint,
    ordem               smallint    NOT NULL,
    criado_em           timestamptz NOT NULL DEFAULT now(),
    atualizado_em       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_dim_faixa_etaria_codigo UNIQUE (faixa_etaria_codigo),
    CONSTRAINT ck_dim_faixa_etaria_limites CHECK (
        (idade_min IS NULL AND idade_max IS NULL)
        OR (idade_min IS NOT NULL AND idade_max IS NOT NULL AND idade_min <= idade_max)
    )
);

COMMENT ON TABLE dw.dim_faixa_etaria IS
  'Dimensão de faixa etária CONFORMADA pelas faixas oficiais da RAIS (1 a 8). A RAIS já '
  'traz a faixa pronta (Faixa Etária - Código); o CAGED traz apenas idade em anos '
  'inteiros, então o ETL deriva a faixa por intervalo usando idade_min/idade_max. Guardar '
  'os limites na dimensão é o que torna a derivação auditável e reproduzível.';
COMMENT ON COLUMN dw.dim_faixa_etaria.faixa_etaria_id     IS 'Chave surrogate (IDENTITY SMALLINT), referenciada pelos fatos.';
COMMENT ON COLUMN dw.dim_faixa_etaria.faixa_etaria_codigo IS 'Código CANÔNICO 1-8 (idêntico ao da RAIS) e 9 para não informada.';
COMMENT ON COLUMN dw.dim_faixa_etaria.faixa_etaria_nome   IS 'Rótulo da faixa, ex.: "30 a 39 anos".';
COMMENT ON COLUMN dw.dim_faixa_etaria.idade_min           IS 'Idade mínima da faixa, inclusive. NULL na faixa "não informada".';
COMMENT ON COLUMN dw.dim_faixa_etaria.idade_max           IS 'Idade máxima da faixa, inclusive. NULL na faixa "não informada". Regra do ETL para o CAGED: idade BETWEEN idade_min AND idade_max; idade fora de qualquer faixa cai no código 9.';
COMMENT ON COLUMN dw.dim_faixa_etaria.codigo_rais         IS 'Código equivalente na RAIS. Igual ao canônico por construção, mantido explícito para auditoria.';
COMMENT ON COLUMN dw.dim_faixa_etaria.ordem               IS 'Ordem de exibição em legendas e eixos.';
COMMENT ON COLUMN dw.dim_faixa_etaria.criado_em           IS 'Auditoria: instante da primeira inserção da linha.';
COMMENT ON COLUMN dw.dim_faixa_etaria.atualizado_em       IS 'Auditoria: instante da última atualização da linha.';

-- ------------------------------------------------------------ 2.7 dim_escolaridade ----
CREATE TABLE IF NOT EXISTS dw.dim_escolaridade (
    escolaridade_id     smallint    GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    escolaridade_codigo smallint    NOT NULL,
    escolaridade_nome   text        NOT NULL,
    nome_curto          text        NOT NULL,
    superior_completo   boolean     NOT NULL,
    pos_graduacao       boolean     NOT NULL,
    codigo_rais         smallint,
    codigo_caged        smallint,
    ordem               smallint    NOT NULL,
    criado_em           timestamptz NOT NULL DEFAULT now(),
    atualizado_em       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_dim_escolaridade_codigo UNIQUE (escolaridade_codigo)
);

COMMENT ON TABLE dw.dim_escolaridade IS
  'Dimensão de escolaridade CONFORMADA. Aqui as duas bases usam a mesma '
  'escada de 11 degraus: RAIS (Escolaridade Após 2005 - Código) e CAGED '
  '(graudeinstrução) vão ambas de 1=Analfabeto a 11=Doutorado completo. A conformação '
  'se resume a tratar os valores fora de 1-11 (vazios na RAIS; códigos de não '
  'identificado/não informado no CAGED), todos mapeados para o canônico 99.';
COMMENT ON COLUMN dw.dim_escolaridade.escolaridade_id     IS 'Chave surrogate (IDENTITY SMALLINT), referenciada pelos fatos.';
COMMENT ON COLUMN dw.dim_escolaridade.escolaridade_codigo IS 'Código CANÔNICO 1-11 (escada RAIS/CAGED) e 99 para não informada.';
COMMENT ON COLUMN dw.dim_escolaridade.escolaridade_nome   IS 'Rótulo completo, no texto das duas fontes.';
COMMENT ON COLUMN dw.dim_escolaridade.nome_curto          IS 'Rótulo abreviado para caber em legenda e eixo de gráfico.';
COMMENT ON COLUMN dw.dim_escolaridade.superior_completo   IS 'TRUE de 9 (superior completo) para cima. É o controle central do funil: compara liderança entre pessoas com a MESMA qualificação formal.';
COMMENT ON COLUMN dw.dim_escolaridade.pos_graduacao       IS 'TRUE em mestrado (10) e doutorado (11).';
COMMENT ON COLUMN dw.dim_escolaridade.codigo_rais         IS 'Código equivalente na RAIS. NULL em 99: qualquer valor fora de 1-11 vira 99.';
COMMENT ON COLUMN dw.dim_escolaridade.codigo_caged        IS 'Código equivalente no CAGED. NULL em 99: o CAGED usa códigos próprios de ausência (p.ex. 80/99) que o ETL colapsa no canônico 99.';
COMMENT ON COLUMN dw.dim_escolaridade.ordem               IS 'Ordem de exibição, do menor ao maior grau de instrução.';
COMMENT ON COLUMN dw.dim_escolaridade.criado_em           IS 'Auditoria: instante da primeira inserção da linha.';
COMMENT ON COLUMN dw.dim_escolaridade.atualizado_em       IS 'Auditoria: instante da última atualização da linha.';

-- -------------------------------------------------------- 2.8 dim_nivel_lideranca ----
CREATE TABLE IF NOT EXISTS dw.dim_nivel_lideranca (
    nivel_lideranca_id     smallint    GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nivel_lideranca_codigo smallint    NOT NULL,
    nivel_lideranca_nome   text        NOT NULL,
    descricao              text        NOT NULL,
    cbo_grandes_grupos     text        NOT NULL,
    degrau_funil           smallint    NOT NULL,
    criado_em              timestamptz NOT NULL DEFAULT now(),
    atualizado_em          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_dim_nivel_lideranca_codigo UNIQUE (nivel_lideranca_codigo)
);

COMMENT ON TABLE dw.dim_nivel_lideranca IS
  'Dimensão encurtada (shrunken conformed dimension) derivada de dim_ocupacao: é o '
  'rollup do CBO 2002 pelo primeiro dígito (grande grupo) e é ela que os fatos '
  'referenciam. Existe para que o funil de liderança, a pergunta central do projeto, '
  'caiba no grão do fato: trocar o CBO completo por este nível reduz o fato de ~567 mil '
  'para ~147 mil linhas por ano da RAIS (medição em docs/etapa-2-modelagem.md §3).';
COMMENT ON COLUMN dw.dim_nivel_lideranca.nivel_lideranca_id     IS 'Chave surrogate (IDENTITY SMALLINT), referenciada pelos fatos.';
COMMENT ON COLUMN dw.dim_nivel_lideranca.nivel_lideranca_codigo IS 'Código canônico: 1=Liderança, 2=Profissional, 3=Técnico/Base, 9=Não classificado.';
COMMENT ON COLUMN dw.dim_nivel_lideranca.nivel_lideranca_nome   IS 'Rótulo exibido no dashboard.';
COMMENT ON COLUMN dw.dim_nivel_lideranca.descricao              IS 'Descrição do grande grupo CBO 2002 correspondente, para a banca conferir a regra.';
COMMENT ON COLUMN dw.dim_nivel_lideranca.cbo_grandes_grupos     IS 'Primeiros dígitos de CBO que caem neste nível. Regra: 1 -> Liderança, 2 -> Profissional, demais -> Técnico/Base.';
COMMENT ON COLUMN dw.dim_nivel_lideranca.degrau_funil           IS 'Ordem do degrau no funil, de cima (1 = liderança) para baixo. O código 9 recebe degrau 99 para ficar fora do funil.';
COMMENT ON COLUMN dw.dim_nivel_lideranca.criado_em              IS 'Auditoria: instante da primeira inserção da linha.';
COMMENT ON COLUMN dw.dim_nivel_lideranca.atualizado_em          IS 'Auditoria: instante da última atualização da linha.';

-- --------------------------------------------------------------- 2.9 dim_ocupacao ----
CREATE TABLE IF NOT EXISTS dw.dim_ocupacao (
    ocupacao_id        integer     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cbo_codigo         char(6)     NOT NULL,
    cbo_titulo         text,
    grande_grupo       char(1)     NOT NULL,
    subgrupo_principal char(2)     NOT NULL,
    subgrupo           char(3)     NOT NULL,
    familia            char(4)     NOT NULL,
    nivel_lideranca_id smallint    NOT NULL,
    criado_em          timestamptz NOT NULL DEFAULT now(),
    atualizado_em      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_dim_ocupacao_cbo UNIQUE (cbo_codigo),
    CONSTRAINT ck_dim_ocupacao_cbo CHECK (cbo_codigo ~ '^[0-9]{6}$'),
    CONSTRAINT ck_dim_ocupacao_hierarquia CHECK (
        grande_grupo       = substring(cbo_codigo FROM 1 FOR 1)
        AND subgrupo_principal = substring(cbo_codigo FROM 1 FOR 2)
        AND subgrupo           = substring(cbo_codigo FROM 1 FOR 3)
        AND familia            = substring(cbo_codigo FROM 1 FOR 4)
    ),
    CONSTRAINT fk_dim_ocupacao_nivel FOREIGN KEY (nivel_lideranca_id)
        REFERENCES dw.dim_nivel_lideranca (nivel_lideranca_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

COMMENT ON TABLE dw.dim_ocupacao IS
  'Dimensão de ocupação no grão CBO 2002 (6 dígitos), com a hierarquia da classificação '
  'e a coluna derivada de nível de liderança. Nenhum fato a referencia na carga atual '
  '(os fatos apontam para dim_nivel_lideranca): ela é a tabela de conformação que o ETL '
  'usa para traduzir CBO -> nível, e documenta no banco a regra que define "liderança". '
  'Custa menos de 1 MB (~2,5 mil ocupações) e mantém o drill-down por CBO disponível '
  'para um mart futuro sem mudança de schema.';
COMMENT ON COLUMN dw.dim_ocupacao.ocupacao_id        IS 'Chave surrogate (IDENTITY).';
COMMENT ON COLUMN dw.dim_ocupacao.cbo_codigo         IS 'Código CBO 2002 da ocupação, 6 dígitos. CHAR(6) para preservar zero à esquerda (ex.: "010105"), ler como número destruiria o grande grupo 0.';
COMMENT ON COLUMN dw.dim_ocupacao.cbo_titulo         IS 'Título da ocupação na CBO 2002. Texto livre (dado não estruturado da fonte secundária); NULL quando o código aparece nos microdados mas não na tabela oficial carregada.';
COMMENT ON COLUMN dw.dim_ocupacao.grande_grupo       IS '1º dígito do CBO = grande grupo. É daqui que sai o nível de liderança.';
COMMENT ON COLUMN dw.dim_ocupacao.subgrupo_principal IS '2 primeiros dígitos do CBO = subgrupo principal.';
COMMENT ON COLUMN dw.dim_ocupacao.subgrupo           IS '3 primeiros dígitos do CBO = subgrupo.';
COMMENT ON COLUMN dw.dim_ocupacao.familia            IS '4 primeiros dígitos do CBO = família ocupacional (ex.: "2124" = analistas de TI). Nível natural de um drill-down futuro.';
COMMENT ON COLUMN dw.dim_ocupacao.nivel_lideranca_id IS 'FK para dw.dim_nivel_lideranca. Coluna DERIVADA: grande_grupo 1 -> Liderança, 2 -> Profissional, demais -> Técnico/Base; CBO ausente ou inválido -> Não classificado.';
COMMENT ON COLUMN dw.dim_ocupacao.criado_em          IS 'Auditoria: instante da primeira inserção da linha.';
COMMENT ON COLUMN dw.dim_ocupacao.atualizado_em      IS 'Auditoria: instante da última atualização da linha.';

-- ------------------------------------------------------------------ 2.10 dim_setor ----
CREATE TABLE IF NOT EXISTS dw.dim_setor (
    setor_id        smallint    GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cnae_subclasse  char(7)     NOT NULL,
    subclasse_nome  text        NOT NULL,
    cnae_classe     char(5)     NOT NULL,
    classe_nome     text        NOT NULL,
    cnae_grupo      char(3)     NOT NULL,
    cnae_divisao    char(2)     NOT NULL,
    divisao_nome    text        NOT NULL,
    cnae_secao      char(1)     NOT NULL,
    secao_nome      text        NOT NULL,
    criado_em       timestamptz NOT NULL DEFAULT now(),
    atualizado_em   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_dim_setor_subclasse UNIQUE (cnae_subclasse),
    CONSTRAINT ck_dim_setor_subclasse CHECK (cnae_subclasse ~ '^[0-9]{7}$'),
    CONSTRAINT ck_dim_setor_hierarquia CHECK (
        cnae_classe     = substring(cnae_subclasse FROM 1 FOR 5)
        AND cnae_grupo  = substring(cnae_subclasse FROM 1 FOR 3)
        AND cnae_divisao = substring(cnae_subclasse FROM 1 FOR 2)
    ),
    CONSTRAINT ck_dim_setor_recorte_ti CHECK (cnae_divisao IN ('62', '63'))
);

COMMENT ON TABLE dw.dim_setor IS
  'Dimensão setorial conformada no grão SUBCLASSE CNAE 2.0, com a hierarquia subclasse '
  '-> classe -> grupo -> divisão -> seção. Tem exatamente 10 linhas: o recorte do '
  'projeto (divisões 62 e 63) tem 10 subclasses, e todas as 10 foram observadas nos '
  'microdados reais do CAGED. O CHECK de recorte transforma o filtro setorial do ETL em '
  'garantia do banco: linha de fora de 62/63 é rejeitada na carga, não descoberta depois.';
COMMENT ON COLUMN dw.dim_setor.setor_id       IS 'Chave surrogate (IDENTITY SMALLINT), referenciada pelos fatos.';
COMMENT ON COLUMN dw.dim_setor.cnae_subclasse IS 'Subclasse CNAE 2.0, 7 dígitos. CHAR(7) preservando zero à esquerda e os zeros internos (ex.: "6202300"). Chave natural; corresponde a CNAE 2.0 Subclasse - Codigo (RAIS) e subclasse (CAGED).';
COMMENT ON COLUMN dw.dim_setor.subclasse_nome IS 'Denominação oficial da subclasse (CONCLA/IBGE, confirmada no layout do Novo CAGED).';
COMMENT ON COLUMN dw.dim_setor.cnae_classe    IS 'Classe CNAE 2.0, 5 dígitos, mesmo conteúdo da coluna CNAE 2.0 Classe - Código da RAIS.';
COMMENT ON COLUMN dw.dim_setor.classe_nome    IS 'Denominação oficial da classe.';
COMMENT ON COLUMN dw.dim_setor.cnae_grupo     IS 'Grupo CNAE 2.0, 3 dígitos (ex.: "620", "631", "639").';
COMMENT ON COLUMN dw.dim_setor.cnae_divisao   IS 'Divisão CNAE 2.0, 2 dígitos. "62" = serviços de TI; "63" = serviços de informação. Define o recorte do projeto.';
COMMENT ON COLUMN dw.dim_setor.divisao_nome   IS 'Denominação oficial da divisão.';
COMMENT ON COLUMN dw.dim_setor.cnae_secao     IS 'Seção CNAE 2.0, 1 letra. Sempre "J" neste recorte, confirmado no CAGED, cuja coluna seção vem igual a J em 100 % das linhas filtradas.';
COMMENT ON COLUMN dw.dim_setor.secao_nome     IS 'Denominação oficial da seção.';
COMMENT ON COLUMN dw.dim_setor.criado_em      IS 'Auditoria: instante da primeira inserção da linha.';
COMMENT ON COLUMN dw.dim_setor.atualizado_em  IS 'Auditoria: instante da última atualização da linha.';

-- =====================================================================================
-- 3. TABELAS-FATO AGREGADAS
--    Nunca uma linha por pessoa. Duas razões, e as duas são obrigatórias:
--    (a) 1 GB, microdado de TI de um único ano da RAIS já passa do limite com índices;
--    (b) LGPD, vínculo individual com sexo + raça + idade + ocupação + município é
--        reidentificável por cruzamento, mesmo sem CPF.
--    A chave primária É o grão: nenhuma surrogate no fato. Isso economiza 8 bytes por
--    linha e, mais importante, faz o banco recusar qualquer carga que viole o grão.
-- =====================================================================================

-- ----------------------------------------------------------- 3.1 fato_vinculo_ti ----
CREATE TABLE IF NOT EXISTS dw.fato_vinculo_ti (
    tempo_id                integer  NOT NULL,
    uf_id                   smallint NOT NULL,
    setor_id                smallint NOT NULL,
    nivel_lideranca_id      smallint NOT NULL,
    sexo_id                 smallint NOT NULL,
    raca_cor_id             smallint NOT NULL,
    faixa_etaria_id         smallint NOT NULL,
    escolaridade_id         smallint NOT NULL,

    qtd_vinculos            integer       NOT NULL,
    qtd_com_remuneracao     integer       NOT NULL,
    soma_remuneracao        numeric(16,2) NOT NULL,
    media_remuneracao       numeric(12,2),
    mediana_remuneracao     numeric(12,2),
    p25_remuneracao         numeric(12,2),
    p75_remuneracao         numeric(12,2),
    soma_horas_contratuais  integer       NOT NULL,
    media_horas_contratuais numeric(5,2),
    soma_tempo_emprego      numeric(14,1) NOT NULL,
    media_tempo_emprego     numeric(7,1),

    carregado_em            timestamptz   NOT NULL DEFAULT now(),

    CONSTRAINT pk_fato_vinculo_ti PRIMARY KEY (
        tempo_id, uf_id, nivel_lideranca_id, sexo_id,
        raca_cor_id, faixa_etaria_id, escolaridade_id, setor_id
    ),
    CONSTRAINT fk_fato_vinculo_tempo FOREIGN KEY (tempo_id)
        REFERENCES dw.dim_tempo (tempo_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_fato_vinculo_uf FOREIGN KEY (uf_id)
        REFERENCES dw.dim_uf (uf_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_fato_vinculo_setor FOREIGN KEY (setor_id)
        REFERENCES dw.dim_setor (setor_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_fato_vinculo_nivel FOREIGN KEY (nivel_lideranca_id)
        REFERENCES dw.dim_nivel_lideranca (nivel_lideranca_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_fato_vinculo_sexo FOREIGN KEY (sexo_id)
        REFERENCES dw.dim_sexo (sexo_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_fato_vinculo_raca FOREIGN KEY (raca_cor_id)
        REFERENCES dw.dim_raca_cor (raca_cor_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_fato_vinculo_faixa FOREIGN KEY (faixa_etaria_id)
        REFERENCES dw.dim_faixa_etaria (faixa_etaria_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_fato_vinculo_escolaridade FOREIGN KEY (escolaridade_id)
        REFERENCES dw.dim_escolaridade (escolaridade_id) ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT ck_fato_vinculo_qtd        CHECK (qtd_vinculos > 0),
    CONSTRAINT ck_fato_vinculo_qtd_remun  CHECK (qtd_com_remuneracao BETWEEN 0 AND qtd_vinculos),
    CONSTRAINT ck_fato_vinculo_somas      CHECK (soma_remuneracao >= 0
                                                 AND soma_horas_contratuais >= 0
                                                 AND soma_tempo_emprego >= 0),
    CONSTRAINT ck_fato_vinculo_percentis  CHECK (
        p25_remuneracao IS NULL OR mediana_remuneracao IS NULL OR p75_remuneracao IS NULL
        OR (p25_remuneracao <= mediana_remuneracao
            AND mediana_remuneracao <= p75_remuneracao)
    ),
    CONSTRAINT ck_fato_vinculo_coerencia  CHECK (
        (qtd_com_remuneracao = 0 AND media_remuneracao IS NULL)
        OR (qtd_com_remuneracao > 0 AND media_remuneracao IS NOT NULL)
    )
);

COMMENT ON TABLE dw.fato_vinculo_ti IS
  'FATO 1, estoque de vínculos formais do setor de TI (RAIS), snapshot periódico anual. '
  'Grão: ano (via a linha de dezembro de dim_tempo) x UF x subclasse CNAE x nível de '
  'liderança x sexo x raça/cor x faixa etária x escolaridade. Uma linha agrega N '
  'vínculos; NÃO existe linha por pessoa. População: vínculos com Ind Vínculo Ativo '
  '31/12 = 1 e CNAE 2.0 subclasse em 62/63. Volume medido: ~147 mil linhas por ano-base.';
COMMENT ON COLUMN dw.fato_vinculo_ti.tempo_id                IS 'FK dim_tempo. Aponta sempre para a competência de DEZEMBRO do ano-base, porque o estoque da RAIS é medido em 31/12.';
COMMENT ON COLUMN dw.fato_vinculo_ti.uf_id                   IS 'FK dim_uf. UF do município do vínculo (2 primeiros dígitos de Município - Código).';
COMMENT ON COLUMN dw.fato_vinculo_ti.setor_id                IS 'FK dim_setor. Subclasse CNAE 2.0 do estabelecimento.';
COMMENT ON COLUMN dw.fato_vinculo_ti.nivel_lideranca_id      IS 'FK dim_nivel_lideranca. Derivado do 1º dígito do CBO 2002 Ocupação - Código.';
COMMENT ON COLUMN dw.fato_vinculo_ti.sexo_id                 IS 'FK dim_sexo, já no código canônico (RAIS 1/2 traduzidos).';
COMMENT ON COLUMN dw.fato_vinculo_ti.raca_cor_id             IS 'FK dim_raca_cor, já no código canônico (RAIS 1/2/4/6/8/9 traduzidos).';
COMMENT ON COLUMN dw.fato_vinculo_ti.faixa_etaria_id         IS 'FK dim_faixa_etaria. Vem direto de Faixa Etária - Código.';
COMMENT ON COLUMN dw.fato_vinculo_ti.escolaridade_id         IS 'FK dim_escolaridade. Vem de Escolaridade Após 2005 - Código.';
COMMENT ON COLUMN dw.fato_vinculo_ti.qtd_vinculos            IS 'MEDIDA aditiva: contagem de vínculos ativos em 31/12 na célula. É também o denominador do k-anonimato: célula com valor menor que 5 não é publicada.';
COMMENT ON COLUMN dw.fato_vinculo_ti.qtd_com_remuneracao     IS 'MEDIDA aditiva: vínculos da célula com Vl Rem Média Nom > 0, denominador correto das estatísticas salariais. Sem ele, média de médias erra em células com remuneração ausente.';
COMMENT ON COLUMN dw.fato_vinculo_ti.soma_remuneracao        IS 'MEDIDA aditiva: soma de Vl Rem Média Nom (R$). NUMERIC(16,2) porque é soma de milhares de salários. É o que permite recompor a média EXATA em qualquer combinação de filtros: SUM(soma)/SUM(qtd_com_remuneracao).';
COMMENT ON COLUMN dw.fato_vinculo_ti.media_remuneracao       IS 'MEDIDA NÃO aditiva (pré-calculada, R$): soma_remuneracao / qtd_com_remuneracao. Redundante por desenho, evita divisão em toda consulta do dashboard. NUNCA deve ser agregada com AVG() entre células.';
COMMENT ON COLUMN dw.fato_vinculo_ti.mediana_remuneracao     IS 'MEDIDA NÃO aditiva (R$): percentil 50 calculado no ETL, no grão fino. Mediana não se recompõe a partir de agregados, por isso é materializada. Em rollups, as views expõem apenas uma mediana ponderada APROXIMADA, com esse nome.';
COMMENT ON COLUMN dw.fato_vinculo_ti.p25_remuneracao         IS 'MEDIDA NÃO aditiva (R$): 1º quartil da remuneração na célula. Mede dispersão interna, teto de vidro aparece na distribuição, não na média.';
COMMENT ON COLUMN dw.fato_vinculo_ti.p75_remuneracao         IS 'MEDIDA NÃO aditiva (R$): 3º quartil da remuneração na célula.';
COMMENT ON COLUMN dw.fato_vinculo_ti.soma_horas_contratuais  IS 'MEDIDA aditiva: soma de Qtd Hora Contr (horas semanais). INTEGER porque a fonte traz horas inteiras. Permite o gap por hora trabalhada.';
COMMENT ON COLUMN dw.fato_vinculo_ti.media_horas_contratuais IS 'MEDIDA NÃO aditiva: horas semanais médias na célula. NUMERIC(5,2), o domínio válido vai de 1 a 44.';
COMMENT ON COLUMN dw.fato_vinculo_ti.soma_tempo_emprego      IS 'MEDIDA aditiva: soma de Tempo Emprego (em meses, com uma decimal na fonte).';
COMMENT ON COLUMN dw.fato_vinculo_ti.media_tempo_emprego     IS 'MEDIDA NÃO aditiva: tempo médio de emprego em meses. Proxy de retenção, complementa a rotatividade do CAGED.';
COMMENT ON COLUMN dw.fato_vinculo_ti.carregado_em            IS 'Auditoria da carga. Coluna única (sem par criado_em/atualizado_em) porque o ETL do fato é full-refresh por ano e cada timestamptz a mais custa ~21 MB no horizonte completo.';

-- ------------------------------------------------------ 3.2 fato_movimentacao_ti ----
CREATE TABLE IF NOT EXISTS dw.fato_movimentacao_ti (
    tempo_id               integer  NOT NULL,
    uf_id                  smallint NOT NULL,
    setor_id               smallint NOT NULL,
    nivel_lideranca_id     smallint NOT NULL,
    sexo_id                smallint NOT NULL,
    raca_cor_id            smallint NOT NULL,
    faixa_etaria_id        smallint NOT NULL,
    escolaridade_id        smallint NOT NULL,

    admissoes              integer       NOT NULL,
    desligamentos          integer       NOT NULL,
    saldo                  integer       NOT NULL,
    qtd_admissoes_com_sal  integer       NOT NULL,
    soma_salario_admissao  numeric(16,2) NOT NULL,
    media_salario_admissao numeric(12,2),

    carregado_em           timestamptz   NOT NULL DEFAULT now(),

    CONSTRAINT pk_fato_movimentacao_ti PRIMARY KEY (
        tempo_id, uf_id, nivel_lideranca_id, sexo_id,
        raca_cor_id, faixa_etaria_id, escolaridade_id, setor_id
    ),
    CONSTRAINT fk_fato_mov_tempo FOREIGN KEY (tempo_id)
        REFERENCES dw.dim_tempo (tempo_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_fato_mov_uf FOREIGN KEY (uf_id)
        REFERENCES dw.dim_uf (uf_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_fato_mov_setor FOREIGN KEY (setor_id)
        REFERENCES dw.dim_setor (setor_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_fato_mov_nivel FOREIGN KEY (nivel_lideranca_id)
        REFERENCES dw.dim_nivel_lideranca (nivel_lideranca_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_fato_mov_sexo FOREIGN KEY (sexo_id)
        REFERENCES dw.dim_sexo (sexo_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_fato_mov_raca FOREIGN KEY (raca_cor_id)
        REFERENCES dw.dim_raca_cor (raca_cor_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_fato_mov_faixa FOREIGN KEY (faixa_etaria_id)
        REFERENCES dw.dim_faixa_etaria (faixa_etaria_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_fato_mov_escolaridade FOREIGN KEY (escolaridade_id)
        REFERENCES dw.dim_escolaridade (escolaridade_id) ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT ck_fato_mov_nao_negativo CHECK (admissoes >= 0 AND desligamentos >= 0),
    CONSTRAINT ck_fato_mov_nao_vazio    CHECK (admissoes + desligamentos > 0),
    CONSTRAINT ck_fato_mov_saldo        CHECK (saldo = admissoes - desligamentos),
    CONSTRAINT ck_fato_mov_qtd_sal      CHECK (qtd_admissoes_com_sal BETWEEN 0 AND admissoes),
    CONSTRAINT ck_fato_mov_soma_sal     CHECK (soma_salario_admissao >= 0),
    CONSTRAINT ck_fato_mov_coerencia    CHECK (
        (qtd_admissoes_com_sal = 0 AND media_salario_admissao IS NULL)
        OR (qtd_admissoes_com_sal > 0 AND media_salario_admissao IS NOT NULL)
    )
);

COMMENT ON TABLE dw.fato_movimentacao_ti IS
  'FATO 2, fluxo de movimentações do setor de TI (Novo CAGED), transacional agregado. '
  'Grão: competência MENSAL x UF x subclasse CNAE x nível de liderança x sexo x raça/cor '
  'x faixa etária x escolaridade, as mesmas dimensões conformadas do fato de estoque, '
  'o que habilita o drill-across que produz a taxa de rotatividade. Volume medido: '
  '~14,3 mil linhas por competência, ~171 mil por ano.';
COMMENT ON COLUMN dw.fato_movimentacao_ti.tempo_id               IS 'FK dim_tempo no grão mês: a competência da movimentação (competênciamov, AAAAMM).';
COMMENT ON COLUMN dw.fato_movimentacao_ti.uf_id                  IS 'FK dim_uf. Vem direto da coluna uf do CAGED (código IBGE de 2 dígitos).';
COMMENT ON COLUMN dw.fato_movimentacao_ti.setor_id               IS 'FK dim_setor. Subclasse CNAE 2.0 do estabelecimento.';
COMMENT ON COLUMN dw.fato_movimentacao_ti.nivel_lideranca_id     IS 'FK dim_nivel_lideranca. Derivado do 1º dígito de cbo2002ocupação.';
COMMENT ON COLUMN dw.fato_movimentacao_ti.sexo_id                IS 'FK dim_sexo, já no código canônico. ATENÇÃO: aqui a tradução é obrigatória, no CAGED mulher é 3, não 2.';
COMMENT ON COLUMN dw.fato_movimentacao_ti.raca_cor_id            IS 'FK dim_raca_cor, já no código canônico. A tradução é obrigatória: os códigos do CAGED colidem com os da RAIS.';
COMMENT ON COLUMN dw.fato_movimentacao_ti.faixa_etaria_id        IS 'FK dim_faixa_etaria, derivada da coluna idade pelos limites idade_min/idade_max da dimensão (o CAGED não traz faixa pronta).';
COMMENT ON COLUMN dw.fato_movimentacao_ti.escolaridade_id        IS 'FK dim_escolaridade, traduzida de graudeinstrução.';
COMMENT ON COLUMN dw.fato_movimentacao_ti.admissoes              IS 'MEDIDA aditiva: movimentações com saldomovimentação = +1 na célula.';
COMMENT ON COLUMN dw.fato_movimentacao_ti.desligamentos          IS 'MEDIDA aditiva: movimentações com saldomovimentação = -1 na célula.';
COMMENT ON COLUMN dw.fato_movimentacao_ti.saldo                  IS 'MEDIDA aditiva: admissoes - desligamentos. Redundante e protegida por CHECK, serve para o dashboard somar saldo sem recalcular e para a carga falhar se a contagem divergir.';
COMMENT ON COLUMN dw.fato_movimentacao_ti.qtd_admissoes_com_sal  IS 'MEDIDA aditiva: admissões da célula com salário declarado maior que zero. Denominador correto da média salarial de admissão.';
COMMENT ON COLUMN dw.fato_movimentacao_ti.soma_salario_admissao  IS 'MEDIDA aditiva: soma do salário de admissão (R$, coluna salário do CAGED, que vem com vírgula decimal e é convertida no ETL). Permite média exata em qualquer filtro.';
COMMENT ON COLUMN dw.fato_movimentacao_ti.media_salario_admissao IS 'MEDIDA NÃO aditiva (R$): soma_salario_admissao / qtd_admissoes_com_sal. Salário de ENTRADA, é o indicador de desigualdade na porta de entrada do setor.';
COMMENT ON COLUMN dw.fato_movimentacao_ti.carregado_em           IS 'Auditoria da carga, por competência.';

-- =====================================================================================
-- 4. ÍNDICES, alinhados aos filtros do dashboard, e só a eles
--    A PK já cobre tempo e os prefixos (tempo, uf, nível, sexo..). Os índices abaixo
--    servem os caminhos que NÃO começam por tempo. Não há índice nas FKs de dimensões
--    minúsculas (sexo, raça, faixa, escolaridade, setor): com 3 a 11 valores distintos
--    o planejador prefere seq scan, e cada índice inútil consome parte do 1 GB.
-- =====================================================================================

CREATE INDEX IF NOT EXISTS ix_fato_vinculo_uf_tempo
    ON dw.fato_vinculo_ti (uf_id, tempo_id);
CREATE INDEX IF NOT EXISTS ix_fato_vinculo_funil
    ON dw.fato_vinculo_ti (nivel_lideranca_id, tempo_id, sexo_id, raca_cor_id);
CREATE INDEX IF NOT EXISTS ix_fato_vinculo_demografia
    ON dw.fato_vinculo_ti (sexo_id, raca_cor_id, tempo_id);

COMMENT ON INDEX dw.ix_fato_vinculo_uf_tempo    IS 'Serve o filtro UF/região isolado e o mapa por UF.';
COMMENT ON INDEX dw.ix_fato_vinculo_funil       IS 'Serve a consulta central do projeto: composição do funil de liderança por sexo e raça ao longo do tempo.';
COMMENT ON INDEX dw.ix_fato_vinculo_demografia  IS 'Serve os cortes de gap salarial que partem de sexo e raça sem fixar UF.';

CREATE INDEX IF NOT EXISTS ix_fato_mov_uf_tempo
    ON dw.fato_movimentacao_ti (uf_id, tempo_id);
CREATE INDEX IF NOT EXISTS ix_fato_mov_funil
    ON dw.fato_movimentacao_ti (nivel_lideranca_id, tempo_id, sexo_id, raca_cor_id);
CREATE INDEX IF NOT EXISTS ix_fato_mov_demografia
    ON dw.fato_movimentacao_ti (sexo_id, raca_cor_id, tempo_id);

COMMENT ON INDEX dw.ix_fato_mov_uf_tempo        IS 'Serve o filtro UF/região na série mensal de admissões e desligamentos.';
COMMENT ON INDEX dw.ix_fato_mov_funil           IS 'Serve a rotatividade por degrau do funil (quem é desligado mais rápido).';
COMMENT ON INDEX dw.ix_fato_mov_demografia      IS 'Serve os cortes de rotatividade que partem de sexo e raça.';

CREATE INDEX IF NOT EXISTS ix_dim_tempo_ano        ON dw.dim_tempo (ano);
CREATE INDEX IF NOT EXISTS ix_dim_uf_regiao        ON dw.dim_uf (regiao_codigo);
CREATE INDEX IF NOT EXISTS ix_dim_localidade_uf    ON dw.dim_localidade (uf_id);
CREATE INDEX IF NOT EXISTS ix_dim_ocupacao_nivel   ON dw.dim_ocupacao (nivel_lideranca_id);
CREATE INDEX IF NOT EXISTS ix_dim_ocupacao_familia ON dw.dim_ocupacao (familia);

COMMENT ON INDEX dw.ix_dim_tempo_ano        IS 'Filtro "Ano" do dashboard: resolve na dimensão antes de tocar o fato.';
COMMENT ON INDEX dw.ix_dim_uf_regiao        IS 'Filtro por região (rollup de UF).';
COMMENT ON INDEX dw.ix_dim_localidade_uf    IS 'Índice de FK: a dimensão municipal é percorrida por UF pelo ETL.';
COMMENT ON INDEX dw.ix_dim_ocupacao_nivel   IS 'Índice de FK, usado pelo ETL ao traduzir CBO -> nível de liderança.';
COMMENT ON INDEX dw.ix_dim_ocupacao_familia IS 'Prepara o drill-down por família ocupacional CBO (4 dígitos).';

-- =====================================================================================
-- 5. SEEDS DAS DIMENSÕES DE DOMÍNIO FECHADO
--    Tudo com ON CONFLICT: reexecutar o script atualiza rótulos sem duplicar linha e
--    sem invalidar as chaves surrogate já referenciadas pelos fatos.
-- =====================================================================================

-- --------------------------------------------------------------- 5.1 dim_tempo -------
INSERT INTO dw.dim_tempo (
    data_competencia, ano, mes, trimestre, semestre, ano_mes, mes_nome, rotulo, eh_dezembro
)
SELECT g.d::date,
       EXTRACT(YEAR    FROM g.d)::smallint,
       EXTRACT(MONTH   FROM g.d)::smallint,
       EXTRACT(QUARTER FROM g.d)::smallint,
       (CASE WHEN EXTRACT(MONTH FROM g.d) <= 6 THEN 1 ELSE 2 END)::smallint,
       to_char(g.d, 'YYYYMM'),
       (ARRAY['Janeiro','Fevereiro','Março','Abril','Maio','Junho',
              'Julho','Agosto','Setembro','Outubro','Novembro','Dezembro']
       )[EXTRACT(MONTH FROM g.d)::int],
       (ARRAY['jan','fev','mar','abr','mai','jun',
              'jul','ago','set','out','nov','dez']
       )[EXTRACT(MONTH FROM g.d)::int] || '/' || to_char(g.d, 'YYYY'),
       EXTRACT(MONTH FROM g.d) = 12
FROM generate_series('2015-01-01'::timestamp, '2026-12-01'::timestamp, interval '1 month') AS g(d)
ON CONFLICT (data_competencia) DO NOTHING;

-- ------------------------------------------------------------------- 5.2 dim_uf ------
INSERT INTO dw.dim_uf (uf_codigo, uf_sigla, uf_nome, regiao_codigo, regiao_nome) VALUES
    ('11','RO','Rondônia',           '1','Norte'),
    ('12','AC','Acre',               '1','Norte'),
    ('13','AM','Amazonas',           '1','Norte'),
    ('14','RR','Roraima',            '1','Norte'),
    ('15','PA','Pará',               '1','Norte'),
    ('16','AP','Amapá',              '1','Norte'),
    ('17','TO','Tocantins',          '1','Norte'),
    ('21','MA','Maranhão',           '2','Nordeste'),
    ('22','PI','Piauí',              '2','Nordeste'),
    ('23','CE','Ceará',              '2','Nordeste'),
    ('24','RN','Rio Grande do Norte','2','Nordeste'),
    ('25','PB','Paraíba',            '2','Nordeste'),
    ('26','PE','Pernambuco',         '2','Nordeste'),
    ('27','AL','Alagoas',            '2','Nordeste'),
    ('28','SE','Sergipe',            '2','Nordeste'),
    ('29','BA','Bahia',              '2','Nordeste'),
    ('31','MG','Minas Gerais',       '3','Sudeste'),
    ('32','ES','Espírito Santo',     '3','Sudeste'),
    ('33','RJ','Rio de Janeiro',     '3','Sudeste'),
    ('35','SP','São Paulo',          '3','Sudeste'),
    ('41','PR','Paraná',             '4','Sul'),
    ('42','SC','Santa Catarina',     '4','Sul'),
    ('43','RS','Rio Grande do Sul',  '4','Sul'),
    ('50','MS','Mato Grosso do Sul', '5','Centro-Oeste'),
    ('51','MT','Mato Grosso',        '5','Centro-Oeste'),
    ('52','GO','Goiás',              '5','Centro-Oeste'),
    ('53','DF','Distrito Federal',   '5','Centro-Oeste'),
    ('99','ND','Não identificada',   '9','Não identificada')
ON CONFLICT (uf_codigo) DO UPDATE
   SET uf_sigla      = EXCLUDED.uf_sigla,
       uf_nome       = EXCLUDED.uf_nome,
       regiao_codigo = EXCLUDED.regiao_codigo,
       regiao_nome   = EXCLUDED.regiao_nome,
       atualizado_em = now();

-- ----------------------------------------------------- 5.3 dim_localidade (sentinela)
INSERT INTO dw.dim_localidade (municipio_codigo, municipio_codigo_ibge, municipio_nome, uf_id)
SELECT '999999', NULL, 'Município não identificado', u.uf_id
FROM dw.dim_uf u
WHERE u.uf_codigo = '99'
ON CONFLICT (municipio_codigo) DO NOTHING;

-- ----------------------------------------------------------------- 5.4 dim_sexo ------
INSERT INTO dw.dim_sexo (sexo_codigo, sexo_nome, codigo_rais, codigo_caged, declarado, ordem) VALUES
    (1, 'Masculino',        1,    1,    TRUE,  1),
    (2, 'Feminino',         2,    3,    TRUE,  2),
    (9, 'Não identificado', NULL, 9,    FALSE, 9)
ON CONFLICT (sexo_codigo) DO UPDATE
   SET sexo_nome     = EXCLUDED.sexo_nome,
       codigo_rais   = EXCLUDED.codigo_rais,
       codigo_caged  = EXCLUDED.codigo_caged,
       declarado     = EXCLUDED.declarado,
       ordem         = EXCLUDED.ordem,
       atualizado_em = now();

-- ------------------------------------------------------------- 5.5 dim_raca_cor ------
INSERT INTO dw.dim_raca_cor
    (raca_cor_codigo, raca_cor_nome, grupo_racial_ibge, codigo_rais, codigo_caged, declarada, ordem) VALUES
    (1, 'Branca',           'Branca',         2,    1, TRUE,  1),
    (2, 'Preta',            'Negra',          4,    2, TRUE,  2),
    (3, 'Parda',            'Negra',          8,    3, TRUE,  3),
    (4, 'Amarela',          'Amarela',        6,    4, TRUE,  4),
    (5, 'Indígena',         'Indígena',       1,    5, TRUE,  5),
    (6, 'Não informada',    'Sem declaração', NULL, 6, FALSE, 6),
    (9, 'Não identificada', 'Sem declaração', 9,    9, FALSE, 9)
ON CONFLICT (raca_cor_codigo) DO UPDATE
   SET raca_cor_nome     = EXCLUDED.raca_cor_nome,
       grupo_racial_ibge = EXCLUDED.grupo_racial_ibge,
       codigo_rais       = EXCLUDED.codigo_rais,
       codigo_caged      = EXCLUDED.codigo_caged,
       declarada         = EXCLUDED.declarada,
       ordem             = EXCLUDED.ordem,
       atualizado_em     = now();

-- ---------------------------------------------------------- 5.6 dim_faixa_etaria -----
INSERT INTO dw.dim_faixa_etaria
    (faixa_etaria_codigo, faixa_etaria_nome, idade_min, idade_max, codigo_rais, ordem) VALUES
    (1, '10 a 14 anos',    10,   14,   1,    1),
    (2, '15 a 17 anos',    15,   17,   2,    2),
    (3, '18 a 24 anos',    18,   24,   3,    3),
    (4, '25 a 29 anos',    25,   29,   4,    4),
    (5, '30 a 39 anos',    30,   39,   5,    5),
    (6, '40 a 49 anos',    40,   49,   6,    6),
    (7, '50 a 64 anos',    50,   64,   7,    7),
    (8, '65 anos ou mais', 65,   120,  8,    8),
    (9, 'Não informada',   NULL, NULL, NULL, 9)
ON CONFLICT (faixa_etaria_codigo) DO UPDATE
   SET faixa_etaria_nome = EXCLUDED.faixa_etaria_nome,
       idade_min         = EXCLUDED.idade_min,
       idade_max         = EXCLUDED.idade_max,
       codigo_rais       = EXCLUDED.codigo_rais,
       ordem             = EXCLUDED.ordem,
       atualizado_em     = now();

-- ---------------------------------------------------------- 5.7 dim_escolaridade -----
INSERT INTO dw.dim_escolaridade
    (escolaridade_codigo, escolaridade_nome, nome_curto, superior_completo, pos_graduacao,
     codigo_rais, codigo_caged, ordem) VALUES
    ( 1, 'Analfabeto',                                          'Analfabeto',      FALSE, FALSE,  1,    1,    1),
    ( 2, 'Até o 5º ano incompleto do Ensino Fundamental',        'Fund. I inc.',    FALSE, FALSE,  2,    2,    2),
    ( 3, '5º ano completo do Ensino Fundamental',                'Fund. I',         FALSE, FALSE,  3,    3,    3),
    ( 4, 'Do 6º ao 9º ano do Ensino Fundamental incompleto',     'Fund. II inc.',   FALSE, FALSE,  4,    4,    4),
    ( 5, 'Ensino Fundamental completo',                          'Fundamental',     FALSE, FALSE,  5,    5,    5),
    ( 6, 'Ensino Médio incompleto',                              'Médio inc.',      FALSE, FALSE,  6,    6,    6),
    ( 7, 'Ensino Médio completo',                                'Médio',           FALSE, FALSE,  7,    7,    7),
    ( 8, 'Educação Superior incompleta',                         'Superior inc.',   FALSE, FALSE,  8,    8,    8),
    ( 9, 'Educação Superior completa',                           'Superior',        TRUE,  FALSE,  9,    9,    9),
    (10, 'Mestrado completo',                                    'Mestrado',        TRUE,  TRUE,  10,   10,   10),
    (11, 'Doutorado completo',                                   'Doutorado',       TRUE,  TRUE,  11,   11,   11),
    (99, 'Não informada',                                        'Não informada',   FALSE, FALSE, NULL, NULL, 99)
ON CONFLICT (escolaridade_codigo) DO UPDATE
   SET escolaridade_nome = EXCLUDED.escolaridade_nome,
       nome_curto        = EXCLUDED.nome_curto,
       superior_completo = EXCLUDED.superior_completo,
       pos_graduacao     = EXCLUDED.pos_graduacao,
       codigo_rais       = EXCLUDED.codigo_rais,
       codigo_caged      = EXCLUDED.codigo_caged,
       ordem             = EXCLUDED.ordem,
       atualizado_em     = now();

-- ------------------------------------------------------ 5.8 dim_nivel_lideranca ------
INSERT INTO dw.dim_nivel_lideranca
    (nivel_lideranca_codigo, nivel_lideranca_nome, descricao, cbo_grandes_grupos, degrau_funil) VALUES
    (1, 'Liderança',
        'CBO grande grupo 1, membros superiores do poder público, dirigentes de organizações de interesse público e de empresas, gerentes',
        '1', 1),
    (2, 'Profissional',
        'CBO grande grupo 2, profissionais das ciências e das artes (inclui as famílias 2122, 2123 e 2124, núcleo técnico qualificado de TI)',
        '2', 2),
    (3, 'Técnico/Base',
        'Demais grandes grupos CBO. 0 (forças armadas e segurança), 3 (técnicos de nível médio), 4 a 9 (serviços administrativos, serviços, produção, manutenção)',
        '0,3,4,5,6,7,8,9', 3),
    (9, 'Não classificado',
        'Reservado a vínculos cujo CBO está ausente ou fora do domínio da CBO 2002 (p.ex. 999999). Fica FORA do funil para não inflar artificialmente a base da pirâmide',
        '-', 99)
ON CONFLICT (nivel_lideranca_codigo) DO UPDATE
   SET nivel_lideranca_nome = EXCLUDED.nivel_lideranca_nome,
       descricao            = EXCLUDED.descricao,
       cbo_grandes_grupos   = EXCLUDED.cbo_grandes_grupos,
       degrau_funil         = EXCLUDED.degrau_funil,
       atualizado_em        = now();

-- -------------------------------------------------------------- 5.9 dim_setor --------
-- As 10 subclasses das divisões 62 e 63. Rótulos conforme CNAE 2.0 (CONCLA/IBGE),
-- conferidos contra o layout oficial do Novo CAGED. As 10 aparecem nos microdados reais.
INSERT INTO dw.dim_setor
    (cnae_subclasse, subclasse_nome, cnae_classe, classe_nome, cnae_grupo,
     cnae_divisao, divisao_nome, cnae_secao, secao_nome) VALUES
    ('6201501','Desenvolvimento de programas de computador sob encomenda',
     '62015','Desenvolvimento de programas de computador sob encomenda','620',
     '62','Atividades dos serviços de tecnologia da informação','J','Informação e comunicação'),
    ('6201502','Web design',
     '62015','Desenvolvimento de programas de computador sob encomenda','620',
     '62','Atividades dos serviços de tecnologia da informação','J','Informação e comunicação'),
    ('6202300','Desenvolvimento e licenciamento de programas de computador customizáveis',
     '62023','Desenvolvimento e licenciamento de programas de computador customizáveis','620',
     '62','Atividades dos serviços de tecnologia da informação','J','Informação e comunicação'),
    ('6203100','Desenvolvimento e licenciamento de programas de computador não-customizáveis',
     '62031','Desenvolvimento e licenciamento de programas de computador não-customizáveis','620',
     '62','Atividades dos serviços de tecnologia da informação','J','Informação e comunicação'),
    ('6204000','Consultoria em tecnologia da informação',
     '62040','Consultoria em tecnologia da informação','620',
     '62','Atividades dos serviços de tecnologia da informação','J','Informação e comunicação'),
    ('6209100','Suporte técnico, manutenção e outros serviços em tecnologia da informação',
     '62091','Suporte técnico, manutenção e outros serviços em tecnologia da informação','620',
     '62','Atividades dos serviços de tecnologia da informação','J','Informação e comunicação'),
    ('6311900','Tratamento de dados, provedores de serviços de aplicação e serviços de hospedagem na internet',
     '63119','Tratamento de dados, provedores de serviços de aplicação e serviços de hospedagem na internet','631',
     '63','Atividades de prestação de serviços de informação','J','Informação e comunicação'),
    ('6319400','Portais, provedores de conteúdo e outros serviços de informação na internet',
     '63194','Portais, provedores de conteúdo e outros serviços de informação na internet','631',
     '63','Atividades de prestação de serviços de informação','J','Informação e comunicação'),
    ('6391700','Agências de notícias',
     '63917','Agências de notícias','639',
     '63','Atividades de prestação de serviços de informação','J','Informação e comunicação'),
    ('6399200','Outras atividades de prestação de serviços de informação não especificadas anteriormente',
     '63992','Outras atividades de prestação de serviços de informação não especificadas anteriormente','639',
     '63','Atividades de prestação de serviços de informação','J','Informação e comunicação')
ON CONFLICT (cnae_subclasse) DO UPDATE
   SET subclasse_nome = EXCLUDED.subclasse_nome,
       cnae_classe    = EXCLUDED.cnae_classe,
       classe_nome    = EXCLUDED.classe_nome,
       cnae_grupo     = EXCLUDED.cnae_grupo,
       cnae_divisao   = EXCLUDED.cnae_divisao,
       divisao_nome   = EXCLUDED.divisao_nome,
       cnae_secao     = EXCLUDED.cnae_secao,
       secao_nome     = EXCLUDED.secao_nome,
       atualizado_em  = now();

-- --------------------------------------------- 5.10 dim_ocupacao (sentinela CBO) -----
INSERT INTO dw.dim_ocupacao
    (cbo_codigo, cbo_titulo, grande_grupo, subgrupo_principal, subgrupo, familia, nivel_lideranca_id)
SELECT '999999', 'Ocupação não identificada', '9', '99', '999', '9999', n.nivel_lideranca_id
FROM dw.dim_nivel_lideranca n
WHERE n.nivel_lideranca_codigo = 9
ON CONFLICT (cbo_codigo) DO NOTHING;

-- =====================================================================================
-- 6. VIEWS PÚBLICAS, k-anonimato (k = 5)
--    Princípio: célula com menos de 5 vínculos (ou menos de 5 movimentações) NÃO sai.
--    Ela é removida da view, não apenas mascarada: publicar a linha com medida NULL
--    revelaria a EXISTÊNCIA da combinação, que é justamente o que se quer proteger
--    (ex.: "há uma mulher indígena em cargo de liderança em Web Design no Acre").
--    As views de rollup agregam o FATO e só então suprimem o RESULTADO, nunca
--    agregam a view de grão fino, o que descartaria as células pequenas e subestimaria
--    os totais.
-- =====================================================================================

DROP VIEW IF EXISTS publico.vw_rotatividade_ti   CASCADE;
DROP VIEW IF EXISTS publico.vw_gap_salarial      CASCADE;
DROP VIEW IF EXISTS publico.vw_funil_lideranca   CASCADE;
DROP VIEW IF EXISTS publico.vw_supressao_lgpd    CASCADE;
DROP VIEW IF EXISTS publico.vw_movimentacao_ti   CASCADE;
DROP VIEW IF EXISTS publico.vw_vinculo_ti        CASCADE;

-- ------------------------------------------------------------ 6.1 vw_vinculo_ti ------
CREATE VIEW publico.vw_vinculo_ti AS
SELECT t.ano,
       u.regiao_codigo,
       u.regiao_nome,
       u.uf_sigla,
       u.uf_nome,
       s.cnae_divisao,
       s.divisao_nome,
       s.cnae_subclasse,
       s.subclasse_nome,
       n.nivel_lideranca_codigo,
       n.nivel_lideranca_nome,
       n.degrau_funil,
       sx.sexo_codigo,
       sx.sexo_nome,
       r.raca_cor_codigo,
       r.raca_cor_nome,
       r.grupo_racial_ibge,
       fe.faixa_etaria_codigo,
       fe.faixa_etaria_nome,
       e.escolaridade_codigo,
       e.nome_curto AS escolaridade,
       e.superior_completo,
       f.qtd_vinculos,
       f.media_remuneracao,
       f.mediana_remuneracao,
       f.p25_remuneracao,
       f.p75_remuneracao,
       f.media_horas_contratuais,
       f.media_tempo_emprego,
       ROUND(f.soma_remuneracao
             / NULLIF(f.soma_horas_contratuais * 4.345, 0), 2) AS remuneracao_por_hora
FROM dw.fato_vinculo_ti    f
JOIN dw.dim_tempo          t  ON t.tempo_id            = f.tempo_id
JOIN dw.dim_uf             u  ON u.uf_id               = f.uf_id
JOIN dw.dim_setor          s  ON s.setor_id            = f.setor_id
JOIN dw.dim_nivel_lideranca n ON n.nivel_lideranca_id  = f.nivel_lideranca_id
JOIN dw.dim_sexo           sx ON sx.sexo_id            = f.sexo_id
JOIN dw.dim_raca_cor       r  ON r.raca_cor_id         = f.raca_cor_id
JOIN dw.dim_faixa_etaria   fe ON fe.faixa_etaria_id    = f.faixa_etaria_id
JOIN dw.dim_escolaridade   e  ON e.escolaridade_id     = f.escolaridade_id
WHERE f.qtd_vinculos >= dw.limite_supressao();

COMMENT ON VIEW publico.vw_vinculo_ti IS
  'Estoque de vínculos de TI no grão do fato, já desnormalizado e com k-anonimato: só '
  'aparecem células com 5 ou mais vínculos. Totais obtidos somando esta view são LIMITE '
  'INFERIOR do universo, para totais completos use as views de rollup, que agregam o '
  'fato antes de suprimir. O grau de perda está em publico.vw_supressao_lgpd.';
COMMENT ON COLUMN publico.vw_vinculo_ti.remuneracao_por_hora IS
  'Remuneração média por hora trabalhada: soma_remuneracao / (soma_horas_contratuais * 4,345). '
  'O fator 4,345 converte horas semanais contratuais em horas mensais (52/12).';

-- ------------------------------------------------------- 6.2 vw_movimentacao_ti ------
CREATE VIEW publico.vw_movimentacao_ti AS
SELECT t.ano,
       t.mes,
       t.ano_mes,
       t.data_competencia,
       t.rotulo AS competencia,
       u.regiao_codigo,
       u.regiao_nome,
       u.uf_sigla,
       u.uf_nome,
       s.cnae_divisao,
       s.divisao_nome,
       s.cnae_subclasse,
       s.subclasse_nome,
       n.nivel_lideranca_codigo,
       n.nivel_lideranca_nome,
       n.degrau_funil,
       sx.sexo_codigo,
       sx.sexo_nome,
       r.raca_cor_codigo,
       r.raca_cor_nome,
       r.grupo_racial_ibge,
       fe.faixa_etaria_codigo,
       fe.faixa_etaria_nome,
       e.escolaridade_codigo,
       e.nome_curto AS escolaridade,
       e.superior_completo,
       m.admissoes,
       m.desligamentos,
       m.saldo,
       m.media_salario_admissao
FROM dw.fato_movimentacao_ti m
JOIN dw.dim_tempo           t  ON t.tempo_id           = m.tempo_id
JOIN dw.dim_uf              u  ON u.uf_id              = m.uf_id
JOIN dw.dim_setor           s  ON s.setor_id           = m.setor_id
JOIN dw.dim_nivel_lideranca n  ON n.nivel_lideranca_id = m.nivel_lideranca_id
JOIN dw.dim_sexo            sx ON sx.sexo_id           = m.sexo_id
JOIN dw.dim_raca_cor        r  ON r.raca_cor_id        = m.raca_cor_id
JOIN dw.dim_faixa_etaria    fe ON fe.faixa_etaria_id   = m.faixa_etaria_id
JOIN dw.dim_escolaridade    e  ON e.escolaridade_id    = m.escolaridade_id
WHERE m.admissoes + m.desligamentos >= dw.limite_supressao();

COMMENT ON VIEW publico.vw_movimentacao_ti IS
  'Movimentações de TI no grão do fato (competência mensal), com k-anonimato sobre o '
  'total de movimentações da célula. O fato mensal é naturalmente esparso (média de ~3 '
  'movimentações por célula), então esta view é a MENOS informativa das públicas: para '
  'leitura agregada prefira publico.vw_rotatividade_ti.';

-- ------------------------------------------------------- 6.3 vw_supressao_lgpd -------
CREATE VIEW publico.vw_supressao_lgpd AS
SELECT 'fato_vinculo_ti'::text AS fato,
       t.ano,
       u.uf_sigla,
       COUNT(*)::bigint                                                            AS celulas_total,
       COUNT(*) FILTER (WHERE f.qtd_vinculos >= dw.limite_supressao())::bigint     AS celulas_publicadas,
       COUNT(*) FILTER (WHERE f.qtd_vinculos <  dw.limite_supressao())::bigint     AS celulas_suprimidas,
       SUM(f.qtd_vinculos)::bigint                                                 AS registros_total,
       COALESCE(SUM(f.qtd_vinculos) FILTER (WHERE f.qtd_vinculos <  dw.limite_supressao()), 0)::bigint
                                                                                   AS registros_suprimidos,
       ROUND(100.0 * COALESCE(SUM(f.qtd_vinculos) FILTER (WHERE f.qtd_vinculos < dw.limite_supressao()), 0)
             / NULLIF(SUM(f.qtd_vinculos), 0), 2)                                  AS pct_registros_suprimidos
FROM dw.fato_vinculo_ti f
JOIN dw.dim_tempo       t ON t.tempo_id = f.tempo_id
JOIN dw.dim_uf          u ON u.uf_id    = f.uf_id
GROUP BY t.ano, u.uf_sigla
UNION ALL
SELECT 'fato_movimentacao_ti'::text,
       t.ano,
       u.uf_sigla,
       COUNT(*)::bigint,
       COUNT(*) FILTER (WHERE m.admissoes + m.desligamentos >= dw.limite_supressao())::bigint,
       COUNT(*) FILTER (WHERE m.admissoes + m.desligamentos <  dw.limite_supressao())::bigint,
       SUM(m.admissoes + m.desligamentos)::bigint,
       COALESCE(SUM(m.admissoes + m.desligamentos)
                FILTER (WHERE m.admissoes + m.desligamentos < dw.limite_supressao()), 0)::bigint,
       ROUND(100.0 * COALESCE(SUM(m.admissoes + m.desligamentos)
                              FILTER (WHERE m.admissoes + m.desligamentos < dw.limite_supressao()), 0)
             / NULLIF(SUM(m.admissoes + m.desligamentos), 0), 2)
FROM dw.fato_movimentacao_ti m
JOIN dw.dim_tempo            t ON t.tempo_id = m.tempo_id
JOIN dw.dim_uf               u ON u.uf_id    = m.uf_id
GROUP BY t.ano, u.uf_sigla;

COMMENT ON VIEW publico.vw_supressao_lgpd IS
  'Indicador de Veracidade e de custo da proteção: por fato, ano e UF, quantas células e '
  'quantos registros ficaram fora das views de grão fino por k-anonimato. Agregado em '
  'ano x UF, onde os números são grandes, não reintroduz risco de reidentificação.';

-- ------------------------------------------------------- 6.4 vw_funil_lideranca ------
CREATE VIEW publico.vw_funil_lideranca AS
WITH base AS (
    SELECT t.ano,
           u.regiao_nome,
           u.uf_sigla,
           n.nivel_lideranca_codigo,
           n.nivel_lideranca_nome,
           n.degrau_funil,
           sx.sexo_nome,
           r.raca_cor_nome,
           r.grupo_racial_ibge,
           e.superior_completo,
           SUM(f.qtd_vinculos)                                        AS qtd_vinculos,
           SUM(f.soma_remuneracao)                                    AS soma_remuneracao,
           SUM(f.qtd_com_remuneracao)                                 AS qtd_com_remuneracao,
           SUM(f.mediana_remuneracao * f.qtd_com_remuneracao)
               FILTER (WHERE f.mediana_remuneracao IS NOT NULL)       AS soma_mediana_pond,
           SUM(f.qtd_com_remuneracao)
               FILTER (WHERE f.mediana_remuneracao IS NOT NULL)       AS peso_mediana
    FROM dw.fato_vinculo_ti     f
    JOIN dw.dim_tempo           t  ON t.tempo_id           = f.tempo_id
    JOIN dw.dim_uf              u  ON u.uf_id              = f.uf_id
    JOIN dw.dim_nivel_lideranca n  ON n.nivel_lideranca_id = f.nivel_lideranca_id
    JOIN dw.dim_sexo            sx ON sx.sexo_id           = f.sexo_id
    JOIN dw.dim_raca_cor        r  ON r.raca_cor_id        = f.raca_cor_id
    JOIN dw.dim_escolaridade    e  ON e.escolaridade_id    = f.escolaridade_id
    GROUP BY 1,2,3,4,5,6,7,8,9,10
),
com_total AS (
    -- O total do degrau é calculado ANTES da supressão, de propósito: o WHERE de um
    -- mesmo nível de consulta roda antes da window function, e filtrar primeiro faria
    -- o denominador perder as células pequenas, inflando todos os percentuais.
    SELECT b.*,
           SUM(b.qtd_vinculos) OVER (
               PARTITION BY b.ano, b.uf_sigla, b.nivel_lideranca_codigo
           ) AS total_degrau
    FROM base b
)
SELECT c.ano,
       c.regiao_nome,
       c.uf_sigla,
       c.nivel_lideranca_codigo,
       c.nivel_lideranca_nome,
       c.degrau_funil,
       c.sexo_nome,
       c.raca_cor_nome,
       c.grupo_racial_ibge,
       c.superior_completo,
       c.qtd_vinculos,
       c.total_degrau,
       ROUND(100.0 * c.qtd_vinculos / NULLIF(c.total_degrau, 0), 2)    AS pct_no_nivel,
       ROUND(c.soma_remuneracao / NULLIF(c.qtd_com_remuneracao, 0), 2) AS media_remuneracao,
       ROUND(c.soma_mediana_pond / NULLIF(c.peso_mediana, 0), 2)       AS mediana_aprox_ponderada
FROM com_total c
WHERE c.qtd_vinculos >= dw.limite_supressao();

COMMENT ON VIEW publico.vw_funil_lideranca IS
  'Consulta central do projeto: composição de cada degrau do funil (Liderança / '
  'Profissional / Técnico-Base) por sexo, raça/cor e posse de superior completo, por ano '
  'e UF. A coluna pct_no_nivel responde à pergunta do tema, que fração de cada degrau '
  'cada grupo ocupa. Agrega o fato e só então aplica o k-anonimato.';
COMMENT ON COLUMN publico.vw_funil_lideranca.total_degrau IS
  'Total de vínculos do degrau no mesmo ano e UF, somado sobre TODAS as células, '
  'inclusive as suprimidas, é o denominador correto de pct_no_nivel.';
COMMENT ON COLUMN publico.vw_funil_lideranca.pct_no_nivel IS
  'Participação do grupo (sexo x raça x escolaridade) dentro do degrau do funil, em %, '
  'calculada sobre o total do degrau no mesmo ano e UF.';
COMMENT ON COLUMN publico.vw_funil_lideranca.media_remuneracao IS
  'Média EXATA: SUM(soma_remuneracao) / SUM(qtd_com_remuneracao). Média é recomposta a '
  'partir das somas, nunca por AVG() de médias.';
COMMENT ON COLUMN publico.vw_funil_lideranca.mediana_aprox_ponderada IS
  'Mediana APROXIMADA: média das medianas das células, ponderada pelo nº de vínculos com '
  'remuneração. Mediana não é agregável; o nome da coluna carrega o aviso. A mediana '
  'exata existe só no grão do fato (publico.vw_vinculo_ti.mediana_remuneracao).';

-- ---------------------------------------------------------- 6.5 vw_gap_salarial ------
CREATE VIEW publico.vw_gap_salarial AS
WITH base AS (
    SELECT t.ano,
           u.regiao_nome,
           u.uf_sigla,
           n.nivel_lideranca_nome,
           n.degrau_funil,
           sx.sexo_nome,
           r.raca_cor_nome,
           r.grupo_racial_ibge,
           e.nome_curto AS escolaridade,
           e.ordem      AS escolaridade_ordem,
           fe.faixa_etaria_nome,
           fe.ordem     AS faixa_ordem,
           SUM(f.qtd_vinculos)        AS qtd_vinculos,
           SUM(f.qtd_com_remuneracao) AS qtd_com_remuneracao,
           SUM(f.soma_remuneracao)    AS soma_remuneracao,
           SUM(f.soma_horas_contratuais) AS soma_horas_contratuais,
           SUM(f.mediana_remuneracao * f.qtd_com_remuneracao)
               FILTER (WHERE f.mediana_remuneracao IS NOT NULL) AS soma_mediana_pond,
           SUM(f.qtd_com_remuneracao)
               FILTER (WHERE f.mediana_remuneracao IS NOT NULL) AS peso_mediana
    FROM dw.fato_vinculo_ti     f
    JOIN dw.dim_tempo           t  ON t.tempo_id           = f.tempo_id
    JOIN dw.dim_uf              u  ON u.uf_id              = f.uf_id
    JOIN dw.dim_nivel_lideranca n  ON n.nivel_lideranca_id = f.nivel_lideranca_id
    JOIN dw.dim_sexo            sx ON sx.sexo_id           = f.sexo_id
    JOIN dw.dim_raca_cor        r  ON r.raca_cor_id        = f.raca_cor_id
    JOIN dw.dim_escolaridade    e  ON e.escolaridade_id    = f.escolaridade_id
    JOIN dw.dim_faixa_etaria    fe ON fe.faixa_etaria_id   = f.faixa_etaria_id
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
)
SELECT b.ano,
       b.regiao_nome,
       b.uf_sigla,
       b.nivel_lideranca_nome,
       b.degrau_funil,
       b.sexo_nome,
       b.raca_cor_nome,
       b.grupo_racial_ibge,
       b.escolaridade,
       b.escolaridade_ordem,
       b.faixa_etaria_nome,
       b.faixa_ordem,
       b.qtd_vinculos,
       ROUND(b.soma_remuneracao / NULLIF(b.qtd_com_remuneracao, 0), 2) AS media_remuneracao,
       ROUND(b.soma_mediana_pond / NULLIF(b.peso_mediana, 0), 2)       AS mediana_aprox_ponderada,
       ROUND(b.soma_remuneracao / NULLIF(b.soma_horas_contratuais * 4.345, 0), 2)
           AS remuneracao_por_hora
FROM base b
WHERE b.qtd_vinculos >= dw.limite_supressao();

COMMENT ON VIEW publico.vw_gap_salarial IS
  'Base do gap salarial com os controles que tornam a comparação defensável: mesmo ano, '
  'mesma UF, mesmo degrau do funil, mesma escolaridade e mesma faixa etária, variando '
  'só sexo e raça/cor. Traz média exata, mediana aproximada ponderada e remuneração por '
  'hora, cobrindo as três métricas alternáveis do dashboard. k-anonimato aplicado.';
COMMENT ON COLUMN publico.vw_gap_salarial.remuneracao_por_hora IS
  'Remuneração por hora: SUM(soma_remuneracao) / (SUM(soma_horas_contratuais) * 4,345). '
  'Neutraliza diferenças de jornada contratual entre os grupos comparados.';

-- -------------------------------------------------------- 6.6 vw_rotatividade_ti -----
CREATE VIEW publico.vw_rotatividade_ti AS
WITH estoque AS (
    SELECT t.ano, f.uf_id, f.nivel_lideranca_id, f.sexo_id, f.raca_cor_id,
           SUM(f.qtd_vinculos) AS estoque_3112
    FROM dw.fato_vinculo_ti f
    JOIN dw.dim_tempo       t ON t.tempo_id = f.tempo_id
    GROUP BY 1,2,3,4,5
),
fluxo AS (
    SELECT t.ano, m.uf_id, m.nivel_lideranca_id, m.sexo_id, m.raca_cor_id,
           SUM(m.admissoes)             AS admissoes,
           SUM(m.desligamentos)         AS desligamentos,
           SUM(m.saldo)                 AS saldo,
           SUM(m.soma_salario_admissao) AS soma_salario_admissao,
           SUM(m.qtd_admissoes_com_sal) AS qtd_admissoes_com_sal
    FROM dw.fato_movimentacao_ti m
    JOIN dw.dim_tempo            t ON t.tempo_id = m.tempo_id
    GROUP BY 1,2,3,4,5
)
SELECT e.ano,
       u.regiao_nome,
       u.uf_sigla,
       n.nivel_lideranca_nome,
       n.degrau_funil,
       sx.sexo_nome,
       r.raca_cor_nome,
       r.grupo_racial_ibge,
       e.estoque_3112,
       CASE WHEN COALESCE(x.admissoes, 0) + COALESCE(x.desligamentos, 0) >= dw.limite_supressao()
            THEN x.admissoes END                        AS admissoes,
       CASE WHEN COALESCE(x.admissoes, 0) + COALESCE(x.desligamentos, 0) >= dw.limite_supressao()
            THEN x.desligamentos END                    AS desligamentos,
       CASE WHEN COALESCE(x.admissoes, 0) + COALESCE(x.desligamentos, 0) >= dw.limite_supressao()
            THEN x.saldo END                            AS saldo,
       CASE WHEN COALESCE(x.admissoes, 0) + COALESCE(x.desligamentos, 0) >= dw.limite_supressao()
            THEN ROUND(100.0 * (x.admissoes + x.desligamentos) / (2.0 * e.estoque_3112), 2) END
                                                        AS taxa_rotatividade_global,
       CASE WHEN COALESCE(x.admissoes, 0) + COALESCE(x.desligamentos, 0) >= dw.limite_supressao()
            THEN ROUND(100.0 * LEAST(x.admissoes, x.desligamentos) / e.estoque_3112, 2) END
                                                        AS taxa_rotatividade_descontada,
       CASE WHEN COALESCE(x.qtd_admissoes_com_sal, 0) >= dw.limite_supressao()
            THEN ROUND(x.soma_salario_admissao / x.qtd_admissoes_com_sal, 2) END
                                                        AS media_salario_admissao
FROM estoque e
LEFT JOIN fluxo x
       ON x.ano = e.ano
      AND x.uf_id = e.uf_id
      AND x.nivel_lideranca_id = e.nivel_lideranca_id
      AND x.sexo_id = e.sexo_id
      AND x.raca_cor_id = e.raca_cor_id
JOIN dw.dim_uf              u  ON u.uf_id              = e.uf_id
JOIN dw.dim_nivel_lideranca n  ON n.nivel_lideranca_id = e.nivel_lideranca_id
JOIN dw.dim_sexo            sx ON sx.sexo_id           = e.sexo_id
JOIN dw.dim_raca_cor        r  ON r.raca_cor_id        = e.raca_cor_id
WHERE e.estoque_3112 >= dw.limite_supressao();

COMMENT ON VIEW publico.vw_rotatividade_ti IS
  'Drill-across entre os dois fatos: estoque da RAIS (denominador) x fluxo do CAGED '
  '(numerador), no grão comum ano x UF x nível de liderança x sexo x raça/cor. Só é '
  'possível porque as dimensões são conformadas, se cada fato usasse os códigos brutos '
  'da sua fonte, este JOIN produziria números errados sem reclamar. A direção é LEFT '
  'JOIN a partir do estoque: taxa exige denominador.';
COMMENT ON COLUMN publico.vw_rotatividade_ti.estoque_3112 IS
  'Vínculos ativos em 31/12 do ano (RAIS). Denominador das taxas e base do k-anonimato desta view.';
COMMENT ON COLUMN publico.vw_rotatividade_ti.taxa_rotatividade_global IS
  'Taxa de rotatividade global, em %: (admissões + desligamentos) / (2 x estoque). Mede o '
  'giro total de mão de obra, inclusive o causado por expansão ou retração do setor.';
COMMENT ON COLUMN publico.vw_rotatividade_ti.taxa_rotatividade_descontada IS
  'Taxa de rotatividade descontada, em %: LEAST(admissões, desligamentos) / estoque '
  '(critério DIEESE). Desconta a variação de tamanho do setor e isola a substituição de '
  'trabalhadores, é a métrica adequada para comparar grupos demográficos entre si.';
COMMENT ON COLUMN publico.vw_rotatividade_ti.media_salario_admissao IS
  'Salário médio de admissão (R$) no ano, recomposto por SUM(soma)/SUM(qtd). Suprimido '
  'quando há menos de 5 admissões com salário declarado.';

-- =====================================================================================
-- 7. PRIVILÉGIOS, o dashboard nunca toca em dw
--    As views NÃO declaram security_invoker, então em PostgreSQL 15 elas acessam as
--    tabelas-fato com os privilégios do OWNER. Conceder SELECT nas views basta: o papel
--    de leitura fica sem qualquer privilégio no esquema dw.
--    Bloco guardado: se o usuário da conexão não puder criar role (comum em serviço
--    gerenciado), o script avisa e segue, o schema não depende disso.
-- =====================================================================================

REVOKE ALL ON SCHEMA dw FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA dw FROM PUBLIC;

DO $priv$
DECLARE
    v_role text := 'dashboard_leitura';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_role) THEN
        EXECUTE format('CREATE ROLE %I NOLOGIN', v_role);
        RAISE NOTICE 'Role % criada (NOLOGIN). Defina a senha e o LOGIN fora deste script.', v_role;
    END IF;

    EXECUTE format('GRANT USAGE ON SCHEMA publico TO %I', v_role);
    EXECUTE format('GRANT SELECT ON ALL TABLES IN SCHEMA publico TO %I', v_role);
    EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA publico GRANT SELECT ON TABLES TO %I', v_role);
    EXECUTE format('REVOKE ALL ON SCHEMA dw FROM %I', v_role);
EXCEPTION
    WHEN insufficient_privilege THEN
        RAISE WARNING 'Sem privilégio para gerenciar roles; privilégios do dashboard '
                      'não aplicados. O schema e as views foram criados normalmente.';
END
$priv$;

COMMIT;

-- =====================================================================================
-- 8. PÓS-CARGA (executar FORA desta transação, depois do ETL)
--     ANALYZE dw.dim_tempo, dw.dim_uf, dw.dim_setor, dw.dim_nivel_lideranca,
--             dw.dim_sexo, dw.dim_raca_cor, dw.dim_faixa_etaria, dw.dim_escolaridade,
--             dw.fato_vinculo_ti, dw.fato_movimentacao_ti;
--
--     -- consumo real de espaço, para conferir o orçamento de 1 GB:
--     SELECT relname,
--            pg_size_pretty(pg_table_size(c.oid))    AS tabela,
--            pg_size_pretty(pg_indexes_size(c.oid))  AS indices,
--            pg_size_pretty(pg_total_relation_size(c.oid)) AS total
--     FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
--     WHERE n.nspname IN ('dw','publico') AND c.relkind = 'r'
--     ORDER BY pg_total_relation_size(c.oid) DESC;
-- =====================================================================================
