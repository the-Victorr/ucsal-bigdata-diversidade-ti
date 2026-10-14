# Diversidade na Tecnologia: Raça, Gênero e o Funil de Liderança no Setor de TI Brasileiro

Projeto prático da disciplina Big Data e Analytics, UCSAL 2026.2.

**Alunos:** Caio Oliveira Sampaio e Victor Oliveira Santana Silva

O projeto monta um pipeline que lê os microdados de emprego formal do governo federal, filtra o setor de tecnologia e carrega o resultado tratado num banco em nuvem, para responder quem chega aos cargos de chefia em TI e quanto cada grupo ganha, separando por sexo e raça/cor.

Alinhamento com as ODS 5 (Igualdade de Gênero) e 18 (Igualdade Étnico-Racial).

## Arquitetura

```
  FTP público do PDET / Ministério do Trabalho
  RAIS 2025 (7 arquivos .7z)   Novo CAGED 2025 (12 arquivos .7z)
                     │
                     ▼
         etl/download.py        baixa com retomada
         etl/extract_filter.py  descompacta em fluxo, filtra CNAE 62/63
                     │
                     ▼
              Parquet local (data/processed/)
                     │
                     ▼
         etl/transform.py       limpa, tipa, harmoniza, agrega
                     │
                     ▼
              Parquet tratado (data/curated/)
                     │
                     ▼
         etl/load.py            carga via COPY + junção com dimensões
                     │
                     ▼
    Aiven PostgreSQL 18 (free tier, 1 GB)
      esquema dw        10 dimensões + 2 fatos
      esquema publico   6 views com supressão de privacidade
                     │
                     ▼
              Painel (etapa seguinte)
```

A infraestrutura do banco também está descrita como código em `terraform/`, usando o provider do Aiven.

## Os 5 V's aplicados a este projeto

**Volume.** As fontes somam 143 milhões de linhas e 4,2 GB compactados, o que descompactado passa de 40 GB. O banco gratuito tem 1 GB. O pipeline resolve isso filtrando o setor durante a leitura e agregando antes de carregar: 198.436 linhas e 43 MB no destino.

**Variedade.** Os microdados são estruturados, em texto delimitado. A API de Localidades do IBGE devolve JSON, que é semi-estruturado. A descrição das ocupações da CBO é texto livre, sem estrutura. Os três tipos aparecem no projeto.

**Velocidade.** A RAIS é anual e o CAGED é mensal, então o processamento é em lote. Os scripts são idempotentes e podem rodar de novo a cada publicação nova sem duplicar dado.

**Veracidade.** É onde está a maior parte do trabalho. Os arquivos trazem marcadores de ausência disfarçados de número (`9997`, `999999`, `{ñ class}`), códigos que significam coisas diferentes em cada base, e inconsistências como jornada acima de 44 horas. O ETL trata tudo isso, e a carga rejeita qualquer código que não exista na dimensão.

**Valor.** O resultado mostra o funil de liderança por raça e a diferença salarial entre grupos, inclusive controlando por escolaridade.

## Tipos de dados utilizados

| Tipo | O que é, neste projeto | Onde fica |
|---|---|---|
| Estruturado | microdados da RAIS e do CAGED, tabelas CNAE e CBO | tabelas do PostgreSQL |
| Semi-estruturado | resposta JSON da API de Localidades do IBGE, layouts em XLSX | lidos no ETL e achatados nas dimensões |
| Não estruturado | descrição textual das ocupações da CBO | coluna `TEXT` em `dim_ocupacao` |

## Banco de dados: por que relacional

Escolhemos PostgreSQL com modelo estrela. O dado é tabular e tem esquema fixo, as consultas do painel são agregações com filtro cruzado, e o volume depois da agregação é pequeno. Um banco não relacional resolveria bem busca textual ou documento aninhado, que não é o caso aqui.

Dentro do relacional, a estrela ganha do modelo normalizado porque cada filtro do painel vira uma junção simples com uma tabela pequena. Como quase não há escrita, a redundância da estrela não incomoda.

```
                      dim_tempo
                          │
   dim_uf ─────┐          │          ┌───── dim_sexo
               │          │          │
  dim_setor ───┼──  fato_vinculo_ti ─┼───── dim_raca_cor
               │          e          │
dim_nivel_ ────┤  fato_movimentacao_ ┼───── dim_faixa_etaria
  lideranca    │         ti          │
               └─────────────────────┴───── dim_escolaridade
```

Os dois fatos usam as mesmas dimensões, o que permite comparar estoque (quem está empregado) e fluxo (quem entrou e saiu) no mesmo recorte.

**Quantidade carregada:** 37.378 linhas no fato de vínculos e 161.058 no de movimentações, mais 198 linhas somadas nas dimensões. O banco ocupa 43 MB, 4,2% do limite.

O dicionário de dados completo está em [`docs/dicionario/dicionario-de-dados.md`](docs/dicionario/dicionario-de-dados.md), gerado a partir dos comentários do próprio banco.

## Regras de negócio implementadas

**Recorte do setor.** É TI quando a subclasse CNAE 2.0 do estabelecimento começa em 62 ou 63. São 10 subclasses, de desenvolvimento de software a provedores de conteúdo.

**Nível de liderança.** Vem do primeiro dígito da CBO 2002: 1 é chefia (diretores e gerentes), 2 é profissional de nível superior (analistas, desenvolvedores), e os demais formam a base técnica. Código inválido cai num nível "Não classificado" que fica fora do funil, para não inflar a base da pirâmide.

**Estoque e fluxo.** O estoque conta só vínculos ativos em 31 de dezembro, para não contar duas vezes quem trocou de emprego no ano. O fluxo conta cada movimentação do CAGED, com admissão valendo +1 e desligamento valendo -1.

**Filtros de qualidade.** Entram apenas registros com remuneração maior que zero e jornada entre 1 e 44 horas.

**Harmonização entre as bases.** A RAIS e o CAGED usam códigos diferentes para a mesma categoria. Na RAIS, 2 é branca e mulher é 2; no CAGED, 2 é preta e mulher é 3. Tudo é convertido para um código único antes de entrar no banco.

**Média agregável.** O fato guarda a soma e a contagem junto com a média, porque média não pode ser somada entre recortes.

**Supressão por privacidade.** As views públicas escondem qualquer combinação com menos de 5 pessoas.

## O que os dados mostram

Participação de cada grupo dentro de cada nível, na RAIS 2025:

| Nível | Branca | Parda | Preta |
|---|---:|---:|---:|
| Chefia | 55,2% | 38,8% | 6,0% |
| Profissional | 51,5% | 40,8% | 7,7% |
| Base | 35,6% | 56,0% | 8,4% |

Pardos são maioria na base e minoria na chefia; com brancos acontece o contrário.

Remuneração média **entre quem tem superior completo**, ou seja, comparando pessoas com a mesma qualificação formal:

| | Branca | Parda | Preta |
|---|---:|---:|---:|
| Homens | R$ 11.426 | R$ 8.445 | R$ 8.174 |
| Mulheres | R$ 8.853 | R$ 6.210 | R$ 6.092 |

Uma mulher preta com diploma superior ganha 53% do que um homem branco com o mesmo diploma recebe. O diferencial não se explica por escolaridade.

## Como reproduzir

### Requisitos

- Python 3.11 ou mais novo
- 7-Zip de linha de comando (`7zz`). No macOS: `brew install sevenzip`
- Cerca de 10 GB livres em disco para os arquivos baixados
- Uma conta no Aiven com um serviço PostgreSQL criado

### Passo a passo

```bash
# 1. ambiente
python3 -m venv .venv
.venv/bin/pip install pandas pyarrow psycopg2-binary python-dotenv

# 2. credenciais
cp .env.example .env
# preencher PGHOST, PGPORT, PGDATABASE, PGUSER e PGPASSWORD com os dados do seu serviço

# 3. baixar os microdados (demora, são 4,2 GB)
.venv/bin/python etl/download.py rais 2025
.venv/bin/python etl/download.py caged 2025

# 4. filtrar o setor de TI
.venv/bin/python etl/extract_filter.py rais  data/raw/rais/2025/*.7z
.venv/bin/python etl/extract_filter.py caged data/raw/caged/2025/*.7z

# 5. tratar e agregar
.venv/bin/python etl/transform.py rais  data/processed/rais/2025/*.parquet
.venv/bin/python etl/transform.py caged data/processed/caged/2025/*.parquet

# 6. criar as tabelas e carregar
.venv/bin/python etl/load.py --schema --fatos --stats
```

O último comando imprime quantas linhas entraram em cada tabela e quanto o banco está ocupando.

### Provisionar o banco por código

```bash
cd terraform
export TF_VAR_aiven_api_token="seu-token"
export TF_VAR_aiven_project="seu-projeto"
terraform init
terraform apply
terraform output -raw service_uri   # string de conexão para o .env
```

## Organização das pastas

```
etl/        scripts do pipeline
sql/        estrutura do banco e consultas de exemplo
terraform/  infraestrutura como código
docs/       documentos das etapas e dicionário de dados
data/       arquivos de dados (fora do controle de versão)
```

Os arquivos baixados e os intermediários ficam em `data/raw/` e `data/processed/`, que estão no `.gitignore` por causa do tamanho. A base tratada está em `data/export/` em CSV e em `data/curated/` em Parquet.

## Segurança

As credenciais do banco ficam apenas no `.env`, que não entra no controle de versão. O `.env.example` mostra quais variáveis são necessárias, sem valores. O token do Aiven usado pelo Terraform vem de variável de ambiente.

Os microdados usados são da versão pública, que já vem sem CPF, PIS, nome e data de nascimento. O ETL ainda descarta as colunas de bairro, que funcionam como quase-identificadores, e o banco só publica combinações com 5 pessoas ou mais.

## Fontes

- [Microdados da RAIS e do Novo CAGED](http://pdet.mte.gov.br/microdados-rais-e-caged), PDET / Ministério do Trabalho e Emprego
- [Classificação Nacional de Atividades Econômicas (CNAE 2.0)](https://concla.ibge.gov.br/), IBGE
- [Classificação Brasileira de Ocupações (CBO 2002)](http://www.mtecbo.gov.br/), Ministério do Trabalho e Emprego
- [API de Localidades](https://servicodados.ibge.gov.br/api/docs/localidades), IBGE
