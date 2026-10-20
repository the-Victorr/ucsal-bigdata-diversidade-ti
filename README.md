# Diversidade na Tecnologia: Raça, Gênero e o Funil de Liderança no Setor de TI Brasileiro

Projeto prático da disciplina Big Data e Analytics, UCSAL 2026.2.

**Alunos:** Caio Oliveira Sampaio e Victor Oliveira Santana Silva

O projeto lê os microdados de emprego formal do governo federal, filtra o setor de tecnologia e carrega o resultado tratado num banco em nuvem, para responder quem chega aos cargos de chefia em TI e quanto cada grupo ganha, separando por sexo e raça/cor. Alinhamento com as ODS 5 (Igualdade de Gênero) e 18 (Igualdade Étnico-Racial).

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

## Dados utilizados

### Fonte

Microdados do PDET, o Programa de Disseminação das Estatísticas do Trabalho, ligado ao Ministério do Trabalho e Emprego. Distribuição por FTP público, sem necessidade de cadastro, sob a Lei de Acesso à Informação.

```
ftp.mtps.gov.br/pdet/microdados/RAIS/2025/
ftp.mtps.gov.br/pdet/microdados/NOVO CAGED/2025/{AAAAMM}/
```

### Identificação das bases

A **RAIS** (Relação Anual de Informações Sociais) é uma declaração obrigatória que toda empresa entrega ao governo listando seus empregados com carteira assinada. Cada linha é um vínculo de emprego. Usamos a versão de vínculos, pública, que vem sem identificação pessoal.

O **Novo CAGED** (Cadastro Geral de Empregados e Desempregados) registra as contratações e demissões de cada mês, alimentado pelo eSocial desde 2020. Cada linha é uma movimentação.

### Período

Ano-base 2025 na RAIS e as doze competências de 2025 no CAGED. É o ano mais recente publicado nas duas bases, e o mesmo intervalo nas duas permite comparar estoque com movimentação.

### Características relevantes

| | RAIS 2025 | Novo CAGED 2025 |
|---|---|---|
| Arquivos | 7 `.7z`, um por região | 12 `.7z`, um por mês |
| Tamanho | 3,6 GB compactados | 617 MB compactados |
| Linhas | 91.710.262 | 51.386.117 |
| Formato interno | `.COMT`, separador vírgula, Latin-1, decimal com ponto | `.txt`, separador `;`, UTF-8, decimal com vírgula |
| Granularidade | um vínculo de emprego por linha | uma admissão ou demissão por linha |

Três características pesaram nas decisões técnicas. A primeira é o volume: 143 milhões de linhas somadas, que descompactadas passam de 40 GB, contra 1 GB de banco disponível. A segunda é que a RAIS mudou de layout três vezes no histórico, com separador e decimal diferentes em cada geração, o que exige um leitor por período. A terceira é que as duas bases codificam as mesmas categorias com números diferentes, assunto da próxima seção.

## Tratamento realizado

### Problemas identificados na base

**Códigos que colidem entre as bases.** A RAIS numera raça/cor como 2 branca, 4 preta, 8 parda; o CAGED usa a ordem do IBGE, com 1 branca, 2 preta, 3 parda. Sexo também difere: mulher é 2 na RAIS e 3 no CAGED. Carregar os dois sem traduzir trocaria categorias sem gerar erro nenhum.

**Ausência disfarçada de número.** Os arquivos não deixam campo vazio. Escrevem `9997`, `999999`, `999997` ou textos como `{ñ class}`. Sem tratamento, esses valores entram nas médias como se fossem salário.

**Códigos que parecem número e não são.** Ocupação (CBO, 6 dígitos), ramo de atividade (CNAE, 7 dígitos) e município (IBGE, 7 dígitos) têm zero à esquerda, que some se o campo for lido como inteiro.

**Inconsistências de preenchimento.** Jornada acima de 44 horas, que não existe na lei, e jornada zero, que é campo em branco.

**Decimal com vírgula e zeros à esquerda** nos valores monetários até 2022, e decimal com ponto a partir de 2023.

### Decisões e transformações

| Decisão | O que fizemos | Por quê |
|---|---|---|
| Filtrar durante a leitura | Descompactar o `.7z` em fluxo, ler em blocos de 500 mil linhas e guardar só CNAE 62/63 | O arquivo descompactado passa de 40 GB e não cabe em disco |
| Ler tudo como texto | `dtype=str` e conversão explícita por coluna | Preserva o zero à esquerda dos códigos |
| Agregar antes de carregar | Guardar totais por combinação de dimensões, não pessoa por pessoa | Resolve o limite de 1 GB e a LGPD ao mesmo tempo |
| Guardar soma e contagem | Além da média, gravar `soma_remuneracao` e `qtd_com_remuneracao` | Média não é agregável entre recortes |
| Calcular mediana no ETL | Mediana, p25 e p75 saem do Pandas, não do banco | Não dá para recompor mediana a partir de dados agregados |
| Harmonizar os domínios | Traduzir RAIS e CAGED para um código canônico único | Os códigos colidem com significados diferentes |
| Traduzir na carga, por junção | O `INSERT` junta o staging com as dimensões | Código fora do domínio derruba a carga em vez de entrar errado |
| Nível de liderança derivado | Primeiro dígito da CBO: 1 chefia, 2 profissional, resto base | Permite medir o funil sem guardar a ocupação completa |
| Criar nível "Não classificado" | CBO inválido fica fora do funil | `999999` cairia em "base" e inflaria a variável do estudo |
| Suprimir células pequenas | Views públicas escondem combinações com menos de 5 pessoas | Evita reidentificação em cruzamento fino |

Os critérios de inclusão e exclusão aplicados, com a contagem de cada corte, estão no documento [Etapa 2 Criterios de Inclusao e Exclusao](Etapa%202%20Criterios%20de%20Inclusao%20e%20Exclusao%20-%20v2.pdf). Em resumo: 143.096.379 linhas lidas, 1.760.634 do setor de TI, 1.306.010 válidos depois da limpeza e 198.436 linhas agregadas no banco.

### Conferência

Comparamos entrada e saída em cada etapa. Os vínculos no banco somam 696.587, igual ao que o ETL limpou. Admissões mais demissões dão 609.423, também igual. Das 198.436 linhas agregadas, todas encontraram par nas dimensões.

## Modelagem

### Estrutura do banco

Modelo estrela, dividido em dois esquemas. O `dw` guarda 10 dimensões e 2 tabelas-fato, e é interno. O `publico` tem 6 views que aplicam a supressão de privacidade, e é o que o painel consulta.

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

| Tabela | Linhas | Tamanho | Conteúdo |
|---|---:|---:|---|
| `fato_movimentacao_ti` | 161.058 | 26 MB | admissões e demissões por mês |
| `fato_vinculo_ti` | 37.378 | 7,6 MB | estoque de empregos em 31/12 |
| `dim_tempo` | 144 | 120 kB | meses de 2015 a 2026 |
| `dim_uf` | 28 | 112 kB | estados e regiões |
| `dim_escolaridade` | 12 | 80 kB | do analfabeto ao doutorado |
| `dim_setor` | 10 | 80 kB | as 10 subclasses CNAE de TI |
| `dim_faixa_etaria` | 9 | 80 kB | de 10 a 14 até 65 ou mais |
| `dim_raca_cor` | 7 | 80 kB | ordem do IBGE |
| `dim_nivel_lideranca` | 4 | 80 kB | chefia, profissional, base, não classificado |
| `dim_sexo` | 3 | 80 kB | masculino, feminino, não identificado |
| Total | 198.436 | 43 MB | 4,2% do limite de 1 GB |

### Estratégia de organização dos dados

Escolhemos banco relacional porque o dado é tabular, tem esquema fixo e as consultas do painel são agregações com filtro cruzado. Um banco não relacional resolveria melhor busca textual ou documento aninhado, que não é o caso.

Dentro do relacional, a estrela ganha do modelo normalizado porque cada filtro do painel vira uma junção simples com uma tabela pequena, coisa que o PostgreSQL resolve rápido mesmo no plano gratuito. Como quase não há escrita depois da carga, a redundância da estrela não atrapalha.

O grão dos dois fatos é `ano ou competência × UF × subclasse CNAE × nível de liderança × sexo × raça/cor × faixa etária × escolaridade`. Testamos quatro granularidades antes de fechar essa. Todas cabiam em 1 GB, então o critério de decisão foi outro: no grão mais fino, município cruzado com ocupação específica, só 12% das linhas sobreviveriam à supressão de privacidade, contra 59,5% na escolhida.

Os dois fatos apontam para as mesmas dimensões, o que permite comparar estoque e fluxo no mesmo recorte.

### Representação da modelagem

O DDL completo está em [`sql/01_schema.sql`](sql/01_schema.sql), com `COMMENT ON` em todas as tabelas e colunas. O dicionário de dados em [`docs/dicionario/dicionario-de-dados.md`](docs/dicionario/dicionario-de-dados.md) tem as 131 colunas e é gerado por consulta aos comentários do próprio banco.

A chave primária de cada fato é a combinação das 8 dimensões, então o banco recusa linha duplicada no mesmo recorte. Cada fato tem chave estrangeira para as 8 dimensões.

## Infraestrutura

### Serviços utilizados

| Serviço | Papel no projeto |
|---|---|
| Aiven for PostgreSQL | banco de dados gerenciado, plano gratuito |
| FTP do PDET | origem dos microdados |
| GitHub | versionamento do código e da documentação |

### Recursos provisionados

| Recurso | Configuração |
|---|---|
| Serviço | `ti-diversidade-pg` |
| Projeto Aiven | `ucsal-bigdata-2026` |
| Plano | `free-1-5gb`, com 1 GB de armazenamento |
| Nuvem e região | DigitalOcean, `sfo` |
| Versão | PostgreSQL 18 |
| Acesso | internet pública, com TLS obrigatório |
| Banco lógico | `defaultdb` (usado na carga) e `diversidade_ti` |

O provisionamento está descrito como código em [`terraform/`](terraform/), com o provider oficial do Aiven. O serviço em uso foi criado pelo painel durante esta etapa, e os arquivos reproduzem a mesma configuração, incluindo região, plano e versão.

```
terraform/main.tf                    recursos aiven_pg e aiven_pg_database
terraform/variables.tf               parâmetros, com o token marcado como sensível
terraform/outputs.tf                 host, porta e string de conexão
terraform/terraform.tfvars.example   modelo de preenchimento, sem valores reais
```

### Tecnologias empregadas

Python 3.14 com Pandas para o ETL, PyArrow para escrever Parquet, psycopg2 para a carga, 7-Zip de linha de comando para descompactar em fluxo, PostgreSQL 18 como banco, Terraform para a infraestrutura e Git para versionamento.

A leitura é feita em blocos com `pandas.read_csv(chunksize=...)`, que mantém o uso de memória constante independente do tamanho do arquivo. A carga usa `COPY` em vez de `INSERT`, o que faz diferença grande no volume que carregamos.

## Segurança das informações

Nenhuma credencial, senha, token ou chave está no repositório.

**Credenciais do banco.** Ficam em um arquivo `.env` na raiz, que está no `.gitignore` e nunca foi versionado. O [`.env.example`](.env.example) mostra quais variáveis existem, com os valores em branco. O `etl/load.py` lê a conexão com `python-dotenv` e falha com mensagem clara se alguma variável estiver faltando, em vez de tentar conectar com valor padrão.

**Token da API do Aiven.** Usado só pelo Terraform, vem de variável de ambiente (`TF_VAR_aiven_api_token`) e está declarado como `sensitive = true`, o que impede o valor de aparecer no log do `apply`. O `terraform.tfvars` real está no `.gitignore`; o repositório leva só o `.example`.

**Estado do Terraform.** Os arquivos `.tfstate` guardam credenciais em texto claro e também estão no `.gitignore`.

**Dados pessoais.** Usamos a versão pública dos microdados, que já vem sem CPF, PIS, nome e data de nascimento. O ETL ainda descarta as colunas de bairro e distrito, que funcionam como quase-identificadores quando combinadas com ocupação e faixa salarial. No banco, as tabelas com o dado completo ficam no esquema interno e as views públicas suprimem qualquer combinação com menos de 5 pessoas. O efeito é grande: das 37.378 linhas do fato de vínculos, 13.239 aparecem na view pública, e das 161.058 do fato de movimentações, 29.087.

**Separação de privilégio.** O schema cria o papel `dashboard_leitura` com permissão apenas de leitura sobre o esquema `publico`. Ele é criado sem login e sem senha de propósito, para que nenhuma credencial fique versionada; quem for usar define a senha no momento de conceder o acesso.

## Execução

### Ferramentas e dependências

- Python 3.11 ou mais novo
- 7-Zip de linha de comando (`7zz`). No macOS, `brew install sevenzip`
- Terraform 1.5 ou mais novo, caso queira provisionar o banco por código
- Cerca de 10 GB livres em disco para os arquivos baixados
- Uma conta no Aiven com um serviço PostgreSQL

Pacotes Python: `pandas`, `pyarrow`, `psycopg2-binary` e `python-dotenv`.

### Informações necessárias para reprodução

O `.env` precisa de `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD` e `PGSSLMODE`. Esses valores vêm do painel do Aiven, na aba Overview do serviço, ou do comando `terraform output -raw service_uri`.

O Terraform precisa de `TF_VAR_aiven_api_token`, gerado em User settings → Authentication, e de `TF_VAR_aiven_project` com o nome do projeto.

### Sequência de execução

```bash
# 1. ambiente
python3 -m venv .venv
.venv/bin/pip install pandas pyarrow psycopg2-binary python-dotenv

# 2. credenciais
cp .env.example .env
# preencher com os dados do serviço

# 3. provisionar o banco, se ainda não existir
cd terraform
export TF_VAR_aiven_api_token="seu-token"
export TF_VAR_aiven_project="seu-projeto"
terraform init && terraform apply
terraform output -raw service_uri    # para preencher o .env
cd ..

# 4. baixar os microdados (demora, são 4,2 GB)
.venv/bin/python etl/download.py rais 2025
.venv/bin/python etl/download.py caged 2025

# 5. filtrar o setor de TI
.venv/bin/python etl/extract_filter.py rais  data/raw/rais/2025/*.7z
.venv/bin/python etl/extract_filter.py caged data/raw/caged/2025/*.7z

# 6. tratar e agregar
.venv/bin/python etl/transform.py rais  data/processed/rais/2025/*.parquet
.venv/bin/python etl/transform.py caged data/processed/caged/2025/*.parquet

# 7. criar as tabelas e carregar
.venv/bin/python etl/load.py --schema --fatos --stats
```

O último comando imprime quantas linhas entraram em cada tabela e quanto o banco está ocupando. As consultas de [`sql/02_consultas_exemplo.sql`](sql/02_consultas_exemplo.sql) reproduzem os resultados apresentados na documentação.

Os passos 4 e 5 podem ser pulados: a base já tratada está em `data/export/` em CSV e em `data/curated/` em Parquet, então dá para ir direto ao passo 7.

## Organização das pastas

```
etl/        scripts do pipeline
sql/        estrutura do banco e consultas de exemplo
terraform/  infraestrutura como código
docs/       dicionário de dados
data/       base tratada em CSV e Parquet
```

Os arquivos baixados e os intermediários ficam em `data/raw/` e `data/processed/`, fora do controle de versão por causa do tamanho.

## O que os dados mostram

Participação de cada grupo dentro de cada nível, na RAIS 2025:

| Nível | Branca | Parda | Preta |
|---|---:|---:|---:|
| Chefia | 55,2% | 38,8% | 6,0% |
| Profissional | 51,5% | 40,8% | 7,7% |
| Base | 35,6% | 56,0% | 8,4% |

Remuneração média entre quem tem superior completo, comparando pessoas com a mesma qualificação formal:

| | Branca | Parda | Preta |
|---|---:|---:|---:|
| Homens | R$ 11.426 | R$ 8.445 | R$ 8.174 |
| Mulheres | R$ 8.853 | R$ 6.210 | R$ 6.092 |

Uma mulher preta com diploma superior ganha 53% do que um homem branco com o mesmo diploma recebe.

## Fontes

- [Microdados da RAIS e do Novo CAGED](http://pdet.mte.gov.br/microdados-rais-e-caged), PDET / Ministério do Trabalho e Emprego
- [Classificação Nacional de Atividades Econômicas (CNAE 2.0)](https://concla.ibge.gov.br/), IBGE
- [Classificação Brasileira de Ocupações (CBO 2002)](http://www.mtecbo.gov.br/), Ministério do Trabalho e Emprego
- [API de Localidades](https://servicodados.ibge.gov.br/api/docs/localidades), IBGE
