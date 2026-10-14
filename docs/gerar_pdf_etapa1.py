"""Gera o PDF da Etapa 1 (texto corrido, preto, simples) para entrega."""
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import cm
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_JUSTIFY
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer

F = "/System/Library/Fonts/Supplemental/"
pdfmetrics.registerFont(TTFont("Arial", F + "Arial.ttf"))
pdfmetrics.registerFont(TTFont("Arial-Bold", F + "Arial Bold.ttf"))
pdfmetrics.registerFontFamily("Arial", normal="Arial", bold="Arial-Bold", italic="Arial", boldItalic="Arial-Bold")

OUT = "docs/Etapa 1 - Levantamento de Parametros e Tipagem de Dados.pdf"
doc = SimpleDocTemplate(OUT, pagesize=A4, leftMargin=2.5*cm, rightMargin=2.5*cm,
                        topMargin=2.5*cm, bottomMargin=2.5*cm,
                        title="Etapa 1 - Levantamento de Parâmetros e Tipagem de Dados",
                        author="Victor Oliveira Santana Silva")

titulo = ParagraphStyle("t", fontName="Arial-Bold", fontSize=15, leading=19, spaceAfter=4)
sub = ParagraphStyle("s", fontName="Arial", fontSize=10.5, leading=14)
h = ParagraphStyle("h", fontName="Arial-Bold", fontSize=12.5, leading=16, spaceBefore=14, spaceAfter=6)
h2 = ParagraphStyle("h2", fontName="Arial-Bold", fontSize=11, leading=14, spaceBefore=8, spaceAfter=3)
p = ParagraphStyle("p", fontName="Arial", fontSize=11, leading=16, alignment=TA_JUSTIFY, spaceAfter=8)

def P(t, st=p): return Paragraph(t, st)

s = []
s.append(P("Etapa 1 — Levantamento de Parâmetros e Tipagem de Dados", titulo))
s.append(P("<b>Disciplina:</b> Big Data e Analytics — UCSAL 2026.2<br/>"
           "<b>Aluno:</b> Victor Oliveira Santana Silva<br/>"
           "<b>Tema:</b> Diversidade na Tecnologia: Raça, Gênero e o Funil de Liderança no Setor de TI Brasileiro<br/>"
           "<b>Bases utilizadas:</b> Microdados da RAIS e do Novo CAGED (PDET / Ministério do Trabalho e Emprego)", sub))
s.append(Spacer(1, 6))
s.append(P("Observação: tudo o que está descrito aqui sobre o formato dos arquivos foi verificado na prática, "
           "baixando e abrindo arquivos reais do FTP do PDET em 18/09/2026. Os números de volume final no banco "
           "são estimativas e estão indicados como tal."))

# ---------------- 1 ----------------
s.append(P("1. Identificação da Fonte", h))
s.append(P("Os microdados das duas bases são distribuídos pelo PDET (Programa de Disseminação das Estatísticas do "
           "Trabalho, do Ministério do Trabalho e Emprego) por meio de um servidor FTP público "
           "(ftp.mtps.gov.br/pdet/microdados/). O formato de origem é <b>arquivo de texto delimitado, do tipo CSV, "
           "compactado em .7z</b>. Não existe API de consulta nem arquivos Parquet na origem: o Parquet será gerado "
           "pela nossa própria camada de ingestão, depois da leitura e do filtro."))
s.append(P("A <b>RAIS</b> (Relação Anual de Informações Sociais) é anual e cada linha representa um vínculo de emprego "
           "formal. Ao abrir os arquivos, descobrimos que ela mudou de layout três vezes no período que nos interessa, "
           "e isso precisa ser tratado no ETL. De 2015 a 2017 há um arquivo .7z por estado (por exemplo, BA2015.7z), "
           "contendo um .txt com 57 colunas separadas por ponto e vírgula, codificação Latin-1, valores monetários com "
           "vírgula decimal e zeros à esquerda (exemplo: 0000001090,26) e valores ausentes escritos como “{ñ class}”. "
           "De 2018 a 2022 os arquivos passam a ser por região (por exemplo, RAIS_VINC_PUB_NORDESTE.7z), com 60 colunas, "
           "mesmo separador e codificação, e valores ausentes como 9997 ou 999999. A partir de 2023 o formato muda de novo: "
           "o arquivo interno tem extensão .COMT, 62 colunas, campos entre aspas separados por <b>vírgula</b>, decimal com "
           "<b>ponto</b> (exemplo: 2242.58), nomes de coluna com o sufixo “ - Código” e ausentes como 999997."))
s.append(P("O <b>Novo CAGED</b> é mensal e cada linha é uma movimentação (uma admissão ou um desligamento). Para cada "
           "competência existem três arquivos: CAGEDMOV (movimentações no prazo), CAGEDFOR (fora do prazo) e CAGEDEXC "
           "(exclusões). O arquivo interno é um .txt com 28 colunas separadas por ponto e vírgula, codificação UTF-8, "
           "decimal com vírgula e nomes de coluna em minúsculas com acento (competênciamov, raçacor, saldomovimentação)."))
s.append(P("Em termos de tamanho, cada ano da RAIS ocupa entre 2,4 e 3,2 GB compactado (2023 tem 3,23 GB, sendo que só "
           "o arquivo de São Paulo tem 1,02 GB), e cada ano do Novo CAGED ocupa entre 0,35 e 0,6 GB. A taxa de compressão "
           "medida é de cerca de 15 vezes, ou seja, um ano da RAIS descompactado tem cerca de 40 GB e a série completa "
           "passaria de 300 GB. Isso torna inviável guardar os dados brutos e obriga o pipeline a filtrar durante a leitura."))
s.append(P("Quanto à variedade, o projeto trabalha com os três tipos de dados. Os dados <b>estruturados</b> são os próprios "
           "microdados da RAIS e do CAGED, além das tabelas de códigos CBO 2002 e CNAE 2.0 e da série do salário mínimo. "
           "Os <b>semi-estruturados</b> são a resposta em JSON da API de Localidades do IBGE (que traz município, "
           "estado e região aninhados), os layouts oficiais em XLSX que serão convertidos em arquivos de configuração do "
           "ETL, e os logs do pipeline. O dado <b>não estruturado</b> é o texto livre com a descrição de cada ocupação "
           "da CBO, que será usado no detalhamento por ocupação no dashboard."))

# ---------------- 2 ----------------
s.append(P("2. Estratégia de Otimização de Volume (limite de 1 GB no Aiven)", h))
s.append(P("A resposta direta é que a equipe vai aplicar <b>os três recursos</b> — filtros de recorte, agregações prévias "
           "e amostragem estatística — nessa ordem de importância. O banco PostgreSQL da Aiven recebe apenas o "
           "resultado já reduzido; todo o processamento pesado acontece fora dele, em Python, na máquina de ETL."))
s.append(P("<b>Filtros de recorte.</b> O filtro mais poderoso é o setorial: só entram vínculos cuja subclasse CNAE 2.0 "
           "pertença à divisão 62 (serviços de tecnologia da informação) ou 63 (atividades de prestação de serviços de "
           "informação). Medimos esse efeito em arquivos reais: no CAGED de janeiro de 2024, das 3.955.239 movimentações, "
           "45.970 (1,16%) são de TI; na RAIS do Acre de 2015, 342 de 191.101 vínculos (0,18%). Nacionalmente estimamos "
           "que a TI represente entre 1,5% e 2,5% do emprego formal, o que já elimina cerca de 98% das linhas. O segundo "
           "filtro é temporal: RAIS de 2018 a 2023 e Novo CAGED de 2020 a 2025, cobrindo o período pós-reforma "
           "trabalhista e toda a série do Novo CAGED baseado no eSocial. O terceiro é o filtro de vínculo ativo em 31/12 "
           "para as análises de estoque, evitando contar duas vezes quem trocou de emprego no ano. Por fim, lemos apenas "
           "cerca de 20 das 60 colunas, descartando bairros, distritos, causas de afastamento e as remunerações mês a mês."))
s.append(P("Esses filtros são aplicados em streaming: o arquivo .7z é descompactado diretamente para a memória "
           "(sem gravar o .txt no disco), lido em blocos de 500 mil linhas com o Pandas, filtrado bloco a bloco e salvo "
           "em Parquet. Esse mecanismo já foi implementado e testado nos quatro layouts: o arquivo do CAGED de janeiro "
           "de 2024, com quase 4 milhões de linhas, foi processado em 12 segundos."))
s.append(P("<b>Agregação prévia.</b> O que vai de fato para o PostgreSQL é uma tabela-fato agregada por ano, estado, "
           "sexo, raça/cor, faixa etária, escolaridade, nível de liderança e divisão CNAE. Para cada combinação "
           "guardamos a quantidade de vínculos, a soma e a média da remuneração, a mediana e os percentis 25 e 75 "
           "(calculados no ETL, porque não é possível recompô-los depois de agregar), a média de horas contratuais e "
           "o tempo médio de emprego. Para o CAGED, uma segunda tabela-fato mensal guarda admissões, desligamentos e "
           "saldo na mesma granularidade. Esse desenho responde diretamente aos filtros cruzados exigidos no dashboard "
           "(ano, estado ou região, sexo, raça/cor e faixa etária) e ao seletor de métrica (média, mediana ou rotatividade)."))
s.append(P("<b>Amostragem estatística.</b> Como camada opcional, manteremos uma amostra estratificada de 5% dos "
           "microdados de TI (estratos por estado, sexo e raça/cor), com cerca de 18 colunas, para análises que a "
           "agregação não permite, como a distribuição salarial completa. Essa amostra é auxiliar e é a primeira coisa "
           "a ser cortada se o espaço apertar."))
s.append(P("<b>Orçamento estimado.</b> A tabela-fato da RAIS deve ficar em torno de 400 mil linhas (cerca de 70 MB com "
           "índices), a do CAGED em torno de 250 mil linhas (cerca de 35 MB), a amostra em cerca de 50 MB e as tabelas "
           "de dimensão (ocupações, setores, municípios, sexo, raça, faixas) em menos de 10 MB. Somando catálogo do banco "
           "e folga, a previsão é de aproximadamente 210 MB, ou seja, cerca de 21% do limite de 1 GB. Mesmo que as "
           "estimativas estejam erradas por um fator de três, ainda ficamos abaixo do limite. Como plano de contingência, "
           "a escolaridade pode ser retirada da granularidade, o que reduz em cerca de 70% o número de linhas."))

# ---------------- 3 ----------------
s.append(P("3. Mapeamento de Variedade e Tipagem", h))
s.append(P("A regra geral do ETL é <b>ler todas as colunas como texto</b> e converter cada uma explicitamente. Isso é "
           "necessário porque os códigos têm zeros à esquerda (que seriam perdidos se lidos como número) e porque os "
           "valores ausentes são representados por números “mágicos” como 9997, 999997 e 999999, ou por textos como "
           "“{ñ class}”, que precisam virar nulo. As principais conversões são descritas a seguir."))
s.append(P("Colunas monetárias da RAIS", h2))
s.append(P("As colunas Vl Remun Média Nom, Vl Remun Dezembro Nom e Vl Remun Média (SM) chegam como texto. Até 2022 vêm "
           "com zeros à esquerda e vírgula decimal (0000001090,26); em 2023 vêm com ponto decimal (2242.58). O ETL "
           "troca a vírgula por ponto apenas nos layouts antigos, converte para número e arredonda para duas casas, "
           "gravando como NUMERIC(12,2) no PostgreSQL. Remuneração igual a zero é tratada como nula para o cálculo de "
           "médias. No CAGED, as colunas salário e valorsaláriofixo (exemplo: 1394,24) e horascontratuais (44,00) "
           "recebem o mesmo tratamento, com destino NUMERIC(12,2) e NUMERIC(5,2)."))
s.append(P("Colunas numéricas inteiras", h2))
s.append(P("Qtd Hora Contr e Idade chegam com espaços à esquerda (por exemplo, “  44”); são limpas e convertidas para "
           "SMALLINT. Tempo Emprego chega como decimal em meses (“    14,9” ou “15.4”) e vira NUMERIC(7,1). "
           "No CAGED, saldomovimentação chega como texto “1” ou “-1” e vira SMALLINT, em que +1 é admissão e -1 é "
           "desligamento; idade vira SMALLINT e, a partir dela, derivamos a faixa etária com os mesmos cortes da RAIS."))
s.append(P("Códigos que viram chaves de dimensão", h2))
s.append(P("Sexo (código 1 ou 2 na RAIS), Raça Cor (1 indígena, 2 branca, 4 preta, 6 amarela, 8 parda, 9 não "
           "identificado), Escolaridade após 2005 (1 a 11), Faixa Etária (1 a 8), Motivo Desligamento, Tipo Admissão e "
           "Tipo Vínculo chegam como texto com zero à esquerda (“08”) e são convertidos para SMALLINT, ligados a tabelas "
           "de dimensão com a descrição de cada código. Um ponto importante descoberto na inspeção: <b>o CAGED usa "
           "domínios diferentes da RAIS</b>. No CAGED, sexo é 1 (homem), 3 (mulher) ou 9; e raçacor é 1 branca, "
           "2 preta, 3 parda, 4 amarela, 5 indígena, 6 não informada e 9 não identificado. O ETL harmoniza as duas "
           "bases em códigos únicos (M/F e as categorias de raça/cor) antes de carregar no banco."))
s.append(P("Códigos que devem continuar como texto", h2))
s.append(P("A ocupação CBO 2002 (6 dígitos, exemplo 317110), a subclasse CNAE 2.0 (7 dígitos, que em 2023 chega com "
           "um espaço à esquerda, como “ 6209100”) e o município IBGE (6 dígitos) nunca são convertidos para número, "
           "porque perderiam o zero à esquerda. São limpos, completados com zeros e gravados como CHAR(6), CHAR(7) e "
           "CHAR(6). A partir deles derivamos a divisão CNAE (dois primeiros dígitos), a UF (dois primeiros dígitos do "
           "município) e o nível de liderança (primeiro dígito da CBO)."))
s.append(P("Datas e indicadores", h2))
s.append(P("No CAGED, competênciamov chega como texto AAAAMM (202401) e é convertida para DATE no primeiro dia do mês. "
           "Na RAIS, Mês Admissão e Mês Desligamento chegam como “00” a “12”, viram SMALLINT e o “00” vira nulo. "
           "Vínculo Ativo 31/12 chega como “0” ou “1” e vira BOOLEAN. O ano da RAIS não é uma coluna do arquivo: ele "
           "é injetado pelo ETL a partir do nome da pasta de origem."))
s.append(P("Regra do funil de liderança", h2))
s.append(P("O nível de liderança é derivado do primeiro dígito da CBO 2002 (grande grupo): dígito 1 indica cargos de "
           "direção e gerência (por exemplo, 1425, gerentes de TI); dígito 2 indica profissionais de nível superior "
           "(por exemplo, 2124, analistas de TI); os demais dígitos indicam funções técnicas e de base (por exemplo, "
           "3171, técnicos de desenvolvimento). No CAGED de janeiro de 2024, a TI teve 4.467 movimentações no grupo 1 "
           "contra 14.837 no grupo 2; é essa proporção, cruzada com sexo e raça/cor, que se transforma no indicador "
           "de chegada à liderança."))
s.append(P("Conformidade com a LGPD", h2))
s.append(P("A versão pública dos microdados (sufixo PUB) já não contém CPF, PIS/NIS, nome, CNPJ ou data de nascimento, "
           "o que foi confirmado no cabeçalho dos arquivos. Ainda assim, o ETL descarta explicitamente as colunas de "
           "bairro e distrito, que funcionam como quase-identificadores, e o banco suprime as medidas de qualquer "
           "combinação com menos de cinco vínculos, para evitar a reidentificação de pessoas em cruzamentos muito "
           "detalhados (por exemplo, estado, raça e ocupação ao mesmo tempo)."))

doc.build(s)
print("gerado:", OUT)
