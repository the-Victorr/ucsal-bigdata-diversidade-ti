"""
Domínios (códigos -> rótulos) das duas bases e a harmonização entre elas.

A RAIS e o Novo CAGED usam códigos DIFERENTES para as mesmas categorias.
Exemplo: mulher é 2 na RAIS e 3 no CAGED; preta é 4 na RAIS e 2 no CAGED.
Tudo é convertido para um código canônico antes de qualquer junção.
"""
from __future__ import annotations

# ---------------------------------------------------------------- canônicos
SEXO = {1: "Masculino", 2: "Feminino", 9: "Não identificado"}

# Canônico do data warehouse: ordem do IBGE. NÃO é o código da RAIS.
RACA_COR = {
    1: "Branca",
    2: "Preta",
    3: "Parda",
    4: "Amarela",
    5: "Indígena",
    6: "Não informada",
    9: "Não identificada",
}

FAIXA_ETARIA = {
    1: "10 a 14 anos", 2: "15 a 17 anos", 3: "18 a 24 anos", 4: "25 a 29 anos",
    5: "30 a 39 anos", 6: "40 a 49 anos", 7: "50 a 64 anos", 8: "65 anos ou mais",
}

ESCOLARIDADE = {
    1: "Analfabeto", 2: "Até 5ª incompleto", 3: "5ª completo fundamental",
    4: "6ª a 9ª fundamental", 5: "Fundamental completo", 6: "Médio incompleto",
    7: "Médio completo", 8: "Superior incompleto", 9: "Superior completo",
    10: "Mestrado", 11: "Doutorado",
}

NIVEL_LIDERANCA = {1: "Liderança", 2: "Profissional", 3: "Técnico/Base"}

# ---------------------------------------------------------------- de -> para
# A RAIS usa a ordem dela: 1=Indígena, 2=Branca, 4=Preta, 6=Amarela, 8=Parda.
# Os números colidem com o canônico com OUTRO significado, então a tradução é
# obrigatória: sem ela, "Branca" da RAIS entraria como "Preta" sem erro nenhum.
SEXO_RAIS = {"1": 1, "2": 2}
RACA_RAIS = {"1": 5, "2": 1, "4": 2, "6": 4, "8": 3, "9": 9}

# O CAGED já segue a ordem do IBGE; só o sexo difere (mulher é 3).
SEXO_CAGED = {"1": 1, "3": 2, "9": 9}
RACA_CAGED = {"1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "9": 9}

# CAGED: grau de instrução tem 11 níveis com ordem diferente da RAIS.
ESCOLARIDADE_CAGED = {
    "1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6,
    "7": 7, "8": 8, "9": 9, "10": 10, "11": 11, "80": 9, "99": None,
}

# Valores que significam "ausente" nos arquivos do PDET.
# Atenção: "-1" NÃO entra aqui. No CAGED ele é um valor legítimo (desligamento).
# O "-1" só é ausência dentro do código da CBO, tratado em para_codigo().
NULOS = {
    "", "99", "999", "9997", "99999", "999999", "999997", "9999999",
    "{ñ c}", "{ñ class}", "{ñ cl", "0000-1", "nan", "None",
}


def nivel_lideranca(cbo) -> int | None:
    """Grande grupo da CBO 2002: 1 = liderança, 2 = profissional, resto = base."""
    if not isinstance(cbo, str) or not cbo or not cbo[0].isdigit():
        return None
    d = int(cbo[0])
    if d == 1:
        return 1
    if d == 2:
        return 2
    return 3


def faixa_etaria_de_idade(idade) -> int | None:
    """Converte idade em anos para o mesmo código de faixa usado pela RAIS."""
    try:
        i = int(idade)
    except (TypeError, ValueError):
        return None
    if i < 10:
        return None
    for limite, cod in ((14, 1), (17, 2), (24, 3), (29, 4), (39, 5), (49, 6), (64, 7)):
        if i <= limite:
            return cod
    return 8
