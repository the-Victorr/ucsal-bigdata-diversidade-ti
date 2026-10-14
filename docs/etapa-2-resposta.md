# Etapa 2: Unificação, Tratamento, Modelagem e Armazenamento

**Disciplina:** Big Data e Analytics, UCSAL 2026.2
**Alunos:** Caio Oliveira Sampaio e Victor Oliveira Santana Silva
**Tema:** Diversidade na Tecnologia: Raça, Gênero e o Funil de Liderança no Setor de TI Brasileiro
**Bases:** RAIS 2025 e Novo CAGED 2025 (PDET / Ministério do Trabalho e Emprego)

Na etapa 1 nós só tínhamos aberto os arquivos para ver com o que estávamos lidando. Nesta etapa rodamos tudo: baixamos as bases de 2025 inteiras, escrevemos o ETL, criamos o banco no Aiven e carregamos os dados. O banco está no ar.

No fim, lemos 143 milhões de linhas e guardamos 198 mil. O banco ocupa 43 MB do 1 GB que o plano gratuito oferece.

## 1. A base tratada

### De onde veio

As duas bases são do PDET, o setor de estatísticas do Ministério do Trabalho, e ficam num FTP público. A RAIS de 2025 vem em 7 arquivos `.7z`, um por região, somando 3,6 GB. O Novo CAGED do mesmo ano vem em 12 arquivos mensais, 617 MB no total. Os dois são dado aberto pela Lei de Acesso à Informação.

Usamos 2025 por ser o ano mais recente publicado nas duas bases. Cada linha da RAIS é um emprego que existia naquele ano; cada linha do CAGED é uma contratação ou uma demissão de um mês específico.

Os endereços exatos:

```
ftp.mtps.gov.br/pdet/microdados/RAIS/2025/
ftp.mtps.gov.br/pdet/microdados/NOVO CAGED/2025/{AAAAMM}/
```

### O que baixamos e o que sobrou

Os arquivos originais, do jeito que vieram, têm 91.710.262 linhas na RAIS e 51.386.117 no CAGED. O formato interno é diferente entre eles, e isso já tinha nos dado trabalho na etapa 1: a RAIS de 2025 usa vírgula como separador e ponto no decimal, em Latin-1, com extensão `.COMT`; o CAGED usa ponto e vírgula e vírgula no decimal, em UTF-8. Mantivemos os dois leitores que tínhamos escrito.

Depois do tratamento sobraram 37.378 linhas da RAIS e 161.058 do CAGED. O caminho inteiro:

```
143.096.379 linhas lidas dos arquivos        (RAIS 91,7 mi + CAGED 51,4 mi)
  └─ filtro CNAE 62/63, só TI     1.760.634  (1,23% do total)
      └─ limpeza e validação      1.306.010  (RAIS 696.587 + CAGED 609.423)
          └─ agregação              198.436  linhas no PostgreSQL = 43 MB
```

A RAIS caiu de 1.150.682 vínculos de TI para 696.587 porque aplicamos três filtros de qualidade. Só entra vínculo ativo em 31 de dezembro, porque quem entrou e saiu no meio do ano não faz parte do estoque daquele ano. Remuneração precisa ser maior que zero, senão a média despenca sem motivo. E a jornada tem que estar entre 1 e 44 horas, porque acima disso é erro de digitação na declaração. O CAGED quase não perdeu nada: saíram 529 registros com código de profissão inválido, de 609.952.

Os arquivos brutos ficam em `data/raw/` e não entram no repositório. Descompactados passariam de 40 GB.

### Por que decidimos assim

A decisão que manda em todas as outras é não guardar pessoa por pessoa. O banco guarda totais: para cada combinação de ano, estado, setor, nível do cargo, sexo, raça/cor, faixa etária e escolaridade, ele tem quantas pessoas são, a soma dos salários, a média, a mediana e os percentis 25 e 75. Isso resolve o limite de 1 GB e a LGPD de uma vez, porque ninguém fica sozinho numa linha.

Guardar a soma junto com a média parece redundante e não é. Média não pode ser somada. Quando o usuário troca o filtro de Bahia para Nordeste inteiro, a conta certa é somar todos os salários e dividir pelo total de pessoas; se tirássemos a média das médias de cada estado, o número sairia diferente, porque estado grande e estado pequeno pesariam igual. Sem a coluna de soma o painel mostraria valores errados em qualquer agregação.

Sobre até onde descer no detalhe, testamos quatro granularidades e contamos quantas linhas cada uma geraria. Todas cabiam no 1 GB, então o espaço não foi o critério. O que pesou foi a anonimização: no grão mais fino, município cruzado com profissão específica, apenas 12% das linhas sobreviveriam ao corte que esconde combinações com menos de 5 pessoas. Na granularidade que escolhemos, 59,5% sobrevivem. O detalhe que o grão fino dá é justamente o que a anonimização apaga depois, então não valia a pena.

Quem não declarou raça ou sexo continuou no banco como categoria própria. Num trabalho sobre desigualdade racial, a ausência de declaração diz alguma coisa, e jogar essas linhas fora mudaria os percentuais de todo mundo.

Um caso que a gente não tinha previsto na etapa 1: a regra do funil diz que o primeiro dígito da profissão define o nível, sendo 1 chefia, 2 profissional e o resto base. Só que existe código inválido nos dados, tipo `999999`. Aplicando a regra ao pé da letra ele cairia em "base" e inflaria exatamente o número que o trabalho quer medir. Criamos um nível "Não classificado" que fica fora da conta do funil.

## 2. O processo de tratamento

O código está todo no repositório, dividido assim:

```
etl/sources.py          catálogo das URLs e dos 3 layouts da RAIS
etl/download.py         download com retomada e conferência de tamanho
etl/extract_filter.py   descompacta em fluxo e filtra só TI
etl/dominios.py         códigos das duas bases e a tradução entre elas
etl/transform.py        limpeza, tipagem, harmonização e agregação
etl/load.py             carga no PostgreSQL
sql/01_schema.sql       estrutura do banco
terraform/              provisionamento do Aiven por código
```

Para rodar do zero:

```bash
python etl/download.py rais 2025
python etl/extract_filter.py rais data/raw/rais/2025/*.7z
python etl/transform.py rais data/processed/rais/2025/*.parquet
python etl/load.py --schema --fatos --stats
```

### Como o programa lida com 40 GB

A RAIS descompactada passa de 40 GB, e o arquivo de São Paulo sozinho tem 1 GB compactado. Não dá para abrir isso de uma vez. O programa manda o `.7z` direto para a memória, lê em blocos de 500 mil linhas, descarta o que não é TI e guarda o resto em Parquet. O arquivo grande nunca chega a existir no disco. São Paulo, com 25 milhões de linhas, levou 4 minutos.

Duas regras valem para todas as colunas. A primeira é ler tudo como texto e converter depois, coluna por coluna; se deixar o Pandas adivinhar, o código de profissão `012345` vira o número `12345` e o zero da frente desaparece. A segunda é tratar os marcadores de ausência: os arquivos não deixam campo vazio, escrevem `9997`, `999999` ou `{ñ class}`, e sem tratamento esses números entrariam nas médias como se fossem salário de verdade.

A tradução dos códigos acontece na hora da carga, por junção com a tabela de dimensão. Foi uma escolha deliberada, e a seção seguinte mostra por quê.

### Dois erros que quase passaram

Os dois são do tipo que não dá mensagem de erro, por isso ficam registrados aqui.

O primeiro foi o `-1`. Tínhamos colocado esse valor na lista de marcadores de ausência, porque é assim que a RAIS marca profissão inválida. Acontece que no CAGED o `-1` quer dizer desligamento. O ETL passou a descartar 47% dos registros calado, e o total continuava parecendo razoável. Só percebemos quando fomos conferir se admissões mais desligamentos batiam com o arquivo original, e não batiam.

O segundo é pior. A RAIS numera raça assim: 2 é branca, 4 é preta, 8 é parda. O CAGED e o nosso banco usam a ordem do IBGE, em que 1 é branca, 2 é preta, 3 é parda. Como os dois usam números baixos, "branca" da RAIS entrava no banco como "preta", sem erro nenhum, sem violar nenhuma regra. O que salvou foi o código 8 não existir na tabela de raças: 37% das linhas não acharam par na junção e a carga avisou. Se a tabela tivesse uma oitava posição, o trabalho inteiro estaria errado com cara de certo, e provavelmente só descobriríamos na apresentação.

É por isso que a tradução é feita por junção. Código fora do domínio derruba a carga em vez de entrar quieto.

## 3. A base no banco

O banco é um PostgreSQL 18 no Aiven, plano gratuito, serviço `ti-diversidade-pg` dentro do projeto `ucsal-bigdata-2026`. A senha e o host ficam num arquivo `.env` que está no `.gitignore`.

### Como ficou organizado

Usamos modelo estrela, separado em dois esquemas. O `dw` guarda as tabelas de verdade, 10 dimensões e 2 fatos, e é interno. O `publico` tem 6 views que já aplicam o corte de privacidade, e é o que o painel vai consultar.

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

Escolhemos estrela porque o painel vai cruzar filtros de ano, estado, sexo, raça e idade ao mesmo tempo, e o usuário espera resposta na hora. Nesse modelo cada filtro é uma junção simples com uma tabela pequena, coisa que o PostgreSQL resolve rápido mesmo num plano gratuito. Um modelo normalizado deixaria tudo mais lento sem necessidade, já que não precisamos inserir dados a todo momento, só ler.

Os dois fatos apontam para as mesmas dimensões. Isso deixa comparar o estoque, quem está empregado, com o fluxo, quem entrou e saiu, usando exatamente o mesmo recorte.

### O que tem lá dentro

| Tabela | Linhas | Tamanho | O que é |
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
| Total | 198.436 | 43 MB | 4,2% do limite |

As colunas de medida do fato de vínculos são `qtd_vinculos` em `INTEGER`, `soma_remuneracao` em `NUMERIC(14,2)`, e `media_remuneracao`, `mediana_remuneracao`, `p25` e `p75` em `NUMERIC(12,2)`. Horas contratuais ficam em `NUMERIC(5,2)` e tempo de emprego em `NUMERIC(8,2)`, contado em meses. As chaves que apontam para as dimensões são `SMALLINT`, menos a de tempo, que é `INTEGER`.

Dinheiro é sempre `NUMERIC` e nunca `FLOAT`, porque `FLOAT` arredonda centavo. Nas dimensões, os códigos originais ficam como `CHAR` de tamanho fixo, com 6 dígitos para profissão e 7 para CNAE e município, para o zero da frente não sumir.

Cada fato tem chave estrangeira para as 8 dimensões, e a chave primária é a própria combinação das 8, o que faz o banco recusar linha repetida no mesmo recorte. Toda tabela e toda coluna tem `COMMENT ON`, então o dicionário de dados sai do próprio banco com uma consulta.

### A questão da LGPD

As views públicas apagam qualquer combinação com menos de 5 pessoas. Num cruzamento bem específico, um estado com uma raça num cargo de chefia, o número pode acabar apontando para uma pessoa só. O efeito é grande: das 37.378 linhas do fato de vínculos, 8.344 aparecem na view pública.

As linhas somem em vez de ficarem mascaradas. Mostrar a linha com o valor em branco já contaria que aquela combinação existe.

## Conferência

Antes de dar o trabalho por pronto, comparamos o que entrou com o que saiu. Os vínculos no banco somam 696.587, o mesmo que o ETL limpou. Admissões mais demissões dão 609.423, também igual. Das 198.436 linhas agregadas, todas acharam par nas dimensões e nenhuma ficou de fora. O saldo do CAGED de 2025 para TI deu +26.561 empregos.

Com os dados carregados já dá para ver o funil:

| Nível | Branca | Parda | Preta |
|---|---:|---:|---:|
| Chefia | 55,2% | 38,8% | 6,0% |
| Profissional | 51,5% | 40,8% | 7,7% |
| Base | 35,6% | 56,0% | 8,4% |

Pardos são a maioria na base e a minoria na chefia; com brancos acontece o contrário. A remuneração média vai de R$ 7.545 para homem branco a R$ 3.590 para mulher parda, menos da metade.
