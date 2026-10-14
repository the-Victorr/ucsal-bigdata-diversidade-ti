"""Versão simplificada (linguagem acessível) do PDF da Etapa 1."""
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

OUT = "docs/Etapa 1 - Versao Simplificada.pdf"
doc = SimpleDocTemplate(OUT, pagesize=A4, leftMargin=2.5*cm, rightMargin=2.5*cm,
                        topMargin=2.5*cm, bottomMargin=2.5*cm,
                        title="Etapa 1 - Levantamento de Parâmetros e Tipagem de Dados (versão simplificada)",
                        author="Victor Oliveira Santana Silva")

titulo = ParagraphStyle("t", fontName="Arial-Bold", fontSize=15, leading=19, spaceAfter=4)
sub = ParagraphStyle("s", fontName="Arial", fontSize=10.5, leading=14)
h = ParagraphStyle("h", fontName="Arial-Bold", fontSize=12.5, leading=16, spaceBefore=14, spaceAfter=6)
p = ParagraphStyle("p", fontName="Arial", fontSize=11, leading=16.5, alignment=TA_JUSTIFY, spaceAfter=9)

def P(t, st=p): return Paragraph(t, st)

s = []
s.append(P("Etapa 1 — Levantamento de Parâmetros e Tipagem de Dados", titulo))
s.append(P("<b>Disciplina:</b> Big Data e Analytics — UCSAL 2026.2<br/>"
           "<b>Aluno:</b> Victor Oliveira Santana Silva<br/>"
           "<b>Tema:</b> Diversidade na Tecnologia: Raça, Gênero e o Funil de Liderança no Setor de TI Brasileiro<br/>"
           "<b>Bases de dados:</b> RAIS e Novo CAGED (Ministério do Trabalho e Emprego)", sub))
s.append(Spacer(1, 8))

s.append(P("O que é este projeto, em uma frase", h))
s.append(P("Queremos usar dados públicos do governo para responder: no setor de tecnologia do Brasil, quem chega aos "
           "cargos de chefia, quanto cada grupo ganha, e como isso muda quando olhamos separadamente para homens e "
           "mulheres, pessoas brancas, pretas, pardas, amarelas e indígenas. Antes de responder, precisamos entender de "
           "onde vêm os dados e como vamos organizá-los. É disso que trata esta primeira etapa."))

# ---------------- 1 ----------------
s.append(P("1. De onde vêm os dados e em que formato", h))
s.append(P("Usamos duas bases do Ministério do Trabalho. A <b>RAIS</b> é como uma “fotografia” anual: todo ano, cada "
           "empresa informa ao governo todos os seus empregados com carteira assinada, e cada linha da base é um desses "
           "empregos, com sexo, raça/cor, idade, escolaridade, cargo, salário, cidade e ramo da empresa. O <b>Novo "
           "CAGED</b> é como um “filme” mensal: registra cada contratação e cada demissão que aconteceu no mês, com as "
           "mesmas informações da pessoa."))
s.append(P("As duas bases ficam disponíveis para download gratuito em um servidor do governo (um FTP, que é um "
           "endereço na internet para baixar arquivos). O formato é o mais simples que existe: <b>arquivos de texto no "
           "estilo CSV</b>, em que cada linha é um registro e as colunas são separadas por um símbolo. Esses arquivos "
           "são grandes, então vêm compactados no formato .7z (parecido com um .zip). Não existe API nem formato mais "
           "moderno na origem; quem quiser usar precisa baixar, descompactar e ler."))
s.append(P("Nós baixamos e abrimos arquivos reais para conferir, e encontramos um detalhe importante: <b>a RAIS mudou "
           "de formato três vezes</b>. Até 2017 vinha um arquivo por estado; de 2018 a 2022 passou a vir um arquivo por "
           "região, com as colunas separadas por ponto e vírgula e os valores em reais escritos com vírgula (por exemplo "
           "1090,26); e a partir de 2023 mudou de novo, com as colunas separadas por vírgula e os valores escritos com "
           "ponto (2242.58), além de nomes de coluna diferentes. O CAGED, por sua vez, usa ponto e vírgula e vírgula "
           "decimal. Parece um detalhe pequeno, mas se o programa que lê os dados não souber disso, ele entende os "
           "números errado. Por isso nosso código tem um leitor específico para cada geração de arquivo."))
s.append(P("Sobre o tamanho: um único ano da RAIS tem cerca de 3 GB compactado, e descompactado chega a uns 40 GB. "
           "Se juntássemos todos os anos, passaria de 300 GB, o que não cabe em um computador comum e muito menos no "
           "banco de dados gratuito que vamos usar. Ou seja, o problema de volume é real e precisa de estratégia."))
s.append(P("Por fim, na classificação que vimos em aula, o projeto tem os três tipos de dado. Os <b>estruturados</b> são "
           "as tabelas da RAIS e do CAGED e as tabelas de códigos de ocupação e de ramo de atividade. Os "
           "<b>semi-estruturados</b> são a resposta em JSON de uma API do IBGE que diz a qual estado e região cada "
           "município pertence, além dos arquivos de configuração e registros do nosso pipeline. O <b>não estruturado</b> é "
           "o texto livre que descreve cada profissão na tabela de ocupações, que usaremos para permitir buscas no painel."))

# ---------------- 2 ----------------
s.append(P("2. Como vamos caber em 1 GB", h))
s.append(P("O banco de dados gratuito da Aiven (PostgreSQL) só permite 1 GB de armazenamento. Como os dados brutos "
           "passam de 300 GB, a solução é <b>não guardar os dados brutos</b>: guardamos apenas o que realmente interessa "
           "para a análise, já resumido. Fazemos isso em três passos, que são justamente as três opções que o enunciado "
           "pede para especificar: filtros, agregação e amostragem."))
s.append(P("<b>Primeiro passo: filtrar.</b> Nosso tema é o setor de tecnologia, então só precisamos das empresas de TI. "
           "Cada empresa tem um código de ramo de atividade (o CNAE), e as de tecnologia são as que começam com 62 ou "
           "63. Só isso já elimina cerca de 98% das linhas, porque a TI é uma fatia pequena de todos os empregos do país "
           "(medimos: em janeiro de 2024, de quase 4 milhões de movimentações do CAGED, só 46 mil eram de TI). Também "
           "limitamos o período (RAIS de 2018 a 2023 e CAGED de 2020 a 2025) e lemos só as colunas úteis, cerca de 20 "
           "das 60 que existem. Esse filtro é aplicado “em fluxo”: o programa descompacta o arquivo e vai lendo em blocos "
           "de 500 mil linhas, guardando só as de TI, sem nunca salvar o arquivo gigante no disco. Já testamos e "
           "funciona: um arquivo de 4 milhões de linhas é processado em 12 segundos."))
s.append(P("<b>Segundo passo: agregar.</b> Depois de filtrar, ainda não guardamos pessoa por pessoa. Guardamos totais: "
           "para cada combinação de ano, estado, sexo, raça/cor, faixa etária, escolaridade e nível de cargo, guardamos "
           "quantas pessoas existem, qual o salário médio, qual o salário mediano e outros resumos. É como transformar "
           "uma lista de milhões de nomes em uma tabela de totais. Isso é suficiente para todos os gráficos e filtros que "
           "o painel precisa mostrar (filtrar por ano, estado, sexo, raça e idade, e trocar entre média, mediana e "
           "rotatividade)."))
s.append(P("<b>Terceiro passo: amostrar (opcional).</b> Para algumas análises mais detalhadas, como ver a distribuição "
           "completa dos salários, guardamos também uma amostra de 5% das pessoas de TI, escolhida de forma equilibrada "
           "entre estados, sexos e raças. Se faltar espaço, essa é a primeira parte a ser cortada."))
s.append(P("<b>Resultado esperado.</b> Nossa estimativa é que tudo isso ocupe por volta de 210 MB, ou seja, cerca de um "
           "quinto do limite de 1 GB. Mesmo que a estimativa esteja errada por três vezes, ainda cabe. E se precisar, "
           "temos um plano B: tirar a escolaridade dos totais, o que reduz o tamanho em cerca de 70%."))

# ---------------- 3 ----------------
s.append(P("3. Quais colunas precisam de conversão de tipo", h))
s.append(P("Quando um arquivo de texto é lido, tudo chega como texto, inclusive os números. “Tipagem” é dizer ao "
           "sistema o que cada coluna realmente é: número, data, código ou texto. Fazemos isso com cuidado porque os "
           "arquivos do governo têm algumas pegadinhas. A principal regra é: <b>ler tudo como texto primeiro e converter "
           "coluna por coluna</b>, em vez de deixar o programa adivinhar."))
s.append(P("<b>Salários.</b> As colunas de remuneração chegam como texto, às vezes com zeros à esquerda e vírgula "
           "(“0000001090,26”), às vezes com ponto (“2242.58”), dependendo do ano. O programa limpa isso e converte para "
           "número decimal com duas casas (no banco, o tipo NUMERIC), que é o tipo certo para dinheiro. Salário igual a "
           "zero é tratado como “não informado”. O mesmo vale para o salário e as horas contratuais do CAGED."))
s.append(P("<b>Idade, horas e tempo de emprego.</b> Chegam como texto com espaços na frente (“  44”). Viram números "
           "inteiros (idade e horas) ou decimais (tempo de emprego em meses)."))
s.append(P("<b>Códigos de sexo, raça, escolaridade e faixa etária.</b> Nos arquivos eles são números que representam "
           "categorias: por exemplo, na RAIS, sexo 1 é masculino e 2 é feminino; raça/cor 2 é branca, 4 é preta, 8 é "
           "parda. Convertemos para número inteiro pequeno e criamos tabelas de apoio com o nome de cada código, para o "
           "painel mostrar “Parda” em vez de “8”. Aqui há uma pegadinha importante que descobrimos ao abrir os arquivos: "
           "<b>o CAGED usa códigos diferentes da RAIS</b> para as mesmas coisas (no CAGED, mulher é 3, e preta é 2). Se "
           "não fizermos a tradução, misturaríamos categorias. Por isso o ETL converte as duas bases para um código único "
           "antes de juntar."))
s.append(P("<b>Códigos de profissão, ramo e município.</b> A profissão (CBO, 6 dígitos), o ramo da empresa (CNAE, 7 "
           "dígitos) e o município (código do IBGE, 6 dígitos) parecem números, mas <b>não podem virar número</b>, porque "
           "alguns começam com zero e o zero seria perdido. Eles ficam como texto de tamanho fixo. A partir deles "
           "descobrimos informações derivadas: o ramo (dois primeiros dígitos do CNAE), o estado (dois primeiros dígitos "
           "do município) e o nível do cargo (primeiro dígito da profissão)."))
s.append(P("<b>Datas e sim/não.</b> No CAGED o mês chega como “202401” e vira uma data de verdade. Na RAIS, a coluna "
           "que diz se a pessoa ainda estava empregada em 31 de dezembro chega como “0” ou “1” e vira verdadeiro/falso. "
           "O ano da RAIS nem sequer é uma coluna: nós o acrescentamos a partir do nome do arquivo."))
s.append(P("<b>Valores ausentes.</b> Quando uma informação não existe, os arquivos não deixam em branco: escrevem "
           "números como 9997 ou 999999, ou textos como “{ñ class}”. Se não tratarmos, esses valores entrariam nas "
           "contas como se fossem reais. O ETL transforma todos eles em “nulo”."))
s.append(P("<b>Como definimos “liderança”.</b> O primeiro dígito do código da profissão indica o grupo: 1 são "
           "diretores e gerentes, 2 são profissionais de nível superior (analistas, desenvolvedores) e os demais são "
           "técnicos e funções de base. É com isso que montamos o “funil”: quantos entram na base, quantos chegam ao "
           "nível profissional e quantos chegam à chefia, separando por sexo e raça/cor."))
s.append(P("<b>E a LGPD?</b> A versão pública desses arquivos já vem sem CPF, nome, PIS ou data de nascimento, e "
           "conferimos isso nos cabeçalhos. Mesmo assim, descartamos as colunas de bairro (que poderiam ajudar a "
           "identificar alguém) e não mostramos no painel nenhum resultado que corresponda a menos de cinco pessoas, "
           "para que ninguém possa ser identificado por um cruzamento muito específico."))

doc.build(s)
print("gerado:", OUT)
