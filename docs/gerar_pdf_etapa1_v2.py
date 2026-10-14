"""Etapa 1, versão 2: texto reescrito em linguagem simples (após revisão com o humanizer)."""
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

OUT = "Etapa 1 Levantamento de Parâmetros e Tipagem de Dados - v2.pdf"
doc = SimpleDocTemplate(OUT, pagesize=A4, leftMargin=2.5*cm, rightMargin=2.5*cm,
                        topMargin=2.5*cm, bottomMargin=2.5*cm,
                        title="Etapa 1 - Levantamento de Parâmetros e Tipagem de Dados",
                        author="Caio Oliveira Sampaio e Victor Oliveira Santana Silva")

titulo = ParagraphStyle("t", fontName="Arial-Bold", fontSize=15, leading=19, spaceAfter=4)
sub = ParagraphStyle("s", fontName="Arial", fontSize=10.5, leading=14)
h = ParagraphStyle("h", fontName="Arial-Bold", fontSize=12.5, leading=16, spaceBefore=14, spaceAfter=6)
h2 = ParagraphStyle("h2", fontName="Arial-Bold", fontSize=11, leading=14, spaceBefore=8, spaceAfter=3)
p = ParagraphStyle("p", fontName="Arial", fontSize=11, leading=16.5, alignment=TA_JUSTIFY, spaceAfter=9)

def P(t, st=p): return Paragraph(t, st)

s = []
s.append(P("Etapa 1: Levantamento de parâmetros e tipagem de dados", titulo))
s.append(P("Disciplina: Big Data e Analytics, UCSAL 2026.2<br/>"
           "Alunos: Caio Oliveira Sampaio e Victor Oliveira Santana Silva<br/>"
           "Tema: Diversidade na Tecnologia: Raça, Gênero e o Funil de Liderança no Setor de TI Brasileiro<br/>"
           "Bases de dados: RAIS e Novo CAGED (Ministério do Trabalho e Emprego)", sub))
s.append(Spacer(1, 8))

s.append(P("O que é este projeto", h))
s.append(P("A gente quer usar dados públicos do governo pra responder uma pergunta: no setor de tecnologia do "
           "Brasil, quem chega aos cargos de chefia e quanto cada grupo ganha? E como isso muda quando olhamos "
           "separadamente pra homens e mulheres, e pra pessoas brancas, pretas, pardas, amarelas e indígenas? "
           "Antes de responder, precisamos entender de onde vêm os dados e como vamos organizá-los. Nesta etapa "
           "fizemos esse levantamento: baixamos amostras, olhamos os arquivos e planejamos o tratamento. O "
           "tratamento em si ainda vai ser feito."))

# ---------------- 1 ----------------
s.append(P("1. De onde vêm os dados e em que formato", h))
s.append(P("Usamos duas bases do Ministério do Trabalho. A RAIS é uma base anual: todo ano, cada empresa informa ao "
           "governo todos os seus empregados com carteira assinada. Cada linha é um desses empregos, com sexo, "
           "raça/cor, idade, escolaridade, cargo, salário, cidade e ramo da empresa. O CAGED é mensal e registra "
           "cada contratação e cada demissão que aconteceu no mês, com as mesmas informações da pessoa."))
s.append(P("As duas bases estão num servidor do governo, de graça, num endereço de FTP (um tipo de site feito só "
           "pra baixar arquivos). O formato é arquivo de texto no estilo CSV: cada linha é um registro e as colunas "
           "são separadas por um símbolo. Como os arquivos são grandes, eles vêm compactados em .7z, que funciona "
           "como um .zip. Não existe API nem um formato mais moderno na origem. Quem quiser usar precisa baixar, "
           "descompactar e ler."))
s.append(P("Baixamos e abrimos arquivos de verdade pra conferir isso, e descobrimos que a RAIS mudou de formato "
           "três vezes. Até 2017 vinha um arquivo por estado. De 2018 a 2022 passou a vir um arquivo por região, com "
           "as colunas separadas por ponto e vírgula e os valores em reais escritos com vírgula, tipo 1090,26. A "
           "partir de 2023 mudou de novo: as colunas passaram a ser separadas por vírgula, os valores vêm com ponto "
           "(2242.58) e os nomes das colunas são diferentes. O CAGED usa ponto e vírgula como separador e vírgula "
           "nos valores. Se o programa que lê os dados não souber disso, ele vai entender os números errado. Por isso o "
           "nosso código vai precisar de um leitor pra cada geração de arquivo."))
s.append(P("Sobre tamanho: um único ano da RAIS tem uns 3 GB compactado e uns 40 GB depois de descompactar. "
           "Juntando todos os anos passa de 300 GB, o que não cabe num computador comum e muito menos no banco de "
           "dados gratuito que vamos usar."))
s.append(P("Na classificação que vimos em aula, o projeto tem os três tipos de dado. Os estruturados são as tabelas "
           "da RAIS e do CAGED e as tabelas com os códigos de ocupação e de ramo de atividade. Os semi-estruturados "
           "são a resposta em JSON de uma API do IBGE, que diz a qual estado e região cada município pertence, e os "
           "arquivos de configuração e os registros do nosso pipeline. O não estruturado é o texto livre que "
           "descreve cada profissão na tabela de ocupações. Pretendemos usar esse texto pra permitir buscas no painel."))

# ---------------- 2 ----------------
s.append(P("2. Como vamos caber em 1 GB", h))
s.append(P("O banco de dados gratuito da Aiven (PostgreSQL) só permite 1 GB de armazenamento, e os dados brutos "
           "passam de 300 GB. Então vamos guardar só o que interessa pra análise, já resumido. Faremos isso em três "
           "passos, que são as três opções que o enunciado pede pra especificar: filtrar, agregar e amostrar."))
s.append(P("Filtrar", h2))
s.append(P("Nosso tema é o setor de tecnologia, então só precisamos das empresas de TI. Cada empresa tem um código "
           "de ramo de atividade, o CNAE, e as de tecnologia são as que começam com 62 ou 63. Só esse filtro deve "
           "eliminar uns 98% das linhas, porque a TI é uma fatia pequena de todos os empregos do país. Numa conferência "
           "rápida com o arquivo de janeiro de 2024, contamos que, de quase 4 milhões de movimentações do CAGED, só "
           "46 mil eram de TI. Também vamos limitar o período (RAIS de 2018 a 2023 e CAGED de 2020 a 2025) e ler só "
           "as colunas úteis, umas 20 das 60 que existem."))
s.append(P("A ideia é que esse filtro rode em fluxo: o programa descompacta o arquivo e vai lendo em blocos de 500 mil "
           "linhas, guardando só as de TI, sem nunca salvar o arquivo gigante no disco."))
s.append(P("Agregar", h2))
s.append(P("Depois de filtrar, ainda não vamos guardar pessoa por pessoa. Vamos guardar totais. Pra cada combinação de "
           "ano, estado, sexo, raça/cor, faixa etária, escolaridade e nível de cargo, guardaremos quantas pessoas existem, "
           "qual o salário médio, qual o salário mediano e alguns outros resumos. É como transformar uma lista de "
           "milhões de nomes numa tabela de totais. Isso deve bastar pra todos os gráficos e filtros que o painel precisa "
           "mostrar: filtrar por ano, estado, sexo, raça e idade, e trocar entre média, mediana e rotatividade."))
s.append(P("Amostrar (opcional)", h2))
s.append(P("Pra algumas análises mais detalhadas, como ver a distribuição completa dos salários, vamos guardar também "
           "uma amostra de 5% das pessoas de TI, escolhida de forma equilibrada entre estados, sexos e raças. Se "
           "faltar espaço, essa é a primeira parte a ser cortada."))
s.append(P("Quanto vai ocupar", h2))
s.append(P("Nossa estimativa é que tudo isso ocupe uns 210 MB, mais ou menos um quinto do limite de 1 GB. Mesmo que "
           "a estimativa esteja errada por três vezes, ainda cabe. Se precisar, tiraremos a escolaridade dos totais, "
           "o que reduz o tamanho em uns 70%."))

# ---------------- 3 ----------------
s.append(P("3. Quais colunas precisam de conversão de tipo", h))
s.append(P("Quando um arquivo de texto é lido, tudo chega como texto, inclusive os números. Tipagem é dizer ao "
           "sistema o que cada coluna realmente é: número, data, código ou texto. Vamos fazer isso com cuidado porque os "
           "arquivos do governo têm algumas pegadinhas. A regra principal será ler tudo como texto primeiro e converter "
           "coluna por coluna, em vez de deixar o programa adivinhar."))
s.append(P("Salários", h2))
s.append(P("As colunas de remuneração chegam como texto. Dependendo do ano, vêm com zeros à esquerda e vírgula "
           "(0000001090,26) ou com ponto (2242.58). O programa vai limpar isso e converter pra número decimal com duas "
           "casas, que no banco é o tipo NUMERIC, o tipo certo pra dinheiro. Salário igual a zero vai virar \"não "
           "informado\". O mesmo vale pro salário e pras horas contratuais do CAGED."))
s.append(P("Idade, horas e tempo de emprego", h2))
s.append(P("Chegam como texto com espaços na frente, tipo \"  44\". Vão virar números inteiros (idade e horas) ou "
           "decimais (tempo de emprego, em meses)."))
s.append(P("Códigos de sexo, raça, escolaridade e faixa etária", h2))
s.append(P("Nos arquivos, esses campos são números que representam categorias. Na RAIS, sexo 1 é masculino e 2 é "
           "feminino; raça/cor 2 é branca, 4 é preta e 8 é parda. Vamos converter pra número inteiro pequeno e criar "
           "tabelas de apoio com o nome de cada código, pra o painel mostrar \"Parda\" em vez de \"8\"."))
s.append(P("Ao abrir os arquivos, vimos que o CAGED usa códigos diferentes da RAIS pras mesmas coisas: no CAGED, "
           "mulher é 3 e preta é 2. Se não fizermos a tradução, vamos misturar categorias. Por isso o ETL vai converter as "
           "duas bases pra um código único antes de juntar."))
s.append(P("Códigos de profissão, ramo e município", h2))
s.append(P("A profissão (CBO, 6 dígitos), o ramo da empresa (CNAE, 7 dígitos) e o município (código do IBGE, "
           "6 dígitos) parecem números, mas não podem virar número, porque alguns começam com zero e o zero seria "
           "perdido. Eles vão ficar como texto de tamanho fixo. A partir deles vamos tirar outras informações: o ramo (dois "
           "primeiros dígitos do CNAE), o estado (dois primeiros dígitos do município) e o nível do cargo (primeiro "
           "dígito da profissão)."))
s.append(P("Datas e sim/não", h2))
s.append(P("No CAGED o mês chega como \"202401\" e vai virar uma data de verdade. Na RAIS, a coluna que diz se a pessoa "
           "ainda estava empregada em 31 de dezembro chega como \"0\" ou \"1\" e vai virar verdadeiro/falso. O ano da RAIS "
           "nem é uma coluna; a gente vai acrescentar a partir do nome do arquivo."))
s.append(P("Valores ausentes", h2))
s.append(P("Quando uma informação não existe, os arquivos não deixam em branco. Escrevem números como 9997 ou "
           "999999, ou textos como \"{ñ class}\". Se não tratarmos, esses valores vão entrar nas contas como se fossem "
           "reais. O ETL vai transformar todos eles em nulo."))
s.append(P("Liderança", h2))
s.append(P("O primeiro dígito do código da profissão indica o grupo: 1 são diretores e gerentes, 2 são "
           "profissionais de nível superior (analistas, desenvolvedores) e os demais são técnicos e funções de base. "
           "É com isso que vamos montar o funil: quantos entram na base, quantos chegam ao nível profissional e quantos "
           "chegam à chefia, separando por sexo e raça/cor."))
s.append(P("LGPD", h2))
s.append(P("A versão pública desses arquivos já vem sem CPF, nome, PIS ou data de nascimento, e conferimos isso nos "
           "cabeçalhos. Mesmo assim, vamos descartar as colunas de bairro, porque poderiam ajudar a identificar alguém."))

doc.build(s)
print("gerado:", OUT)
