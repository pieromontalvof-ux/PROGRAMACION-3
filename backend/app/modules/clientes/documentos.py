import re

FORMATOS = {
    'DNI': r'[0-9]{8}',
    'RUC': r'[0-9]{11}',
    'CE': r'[A-Za-z0-9]{1,20}',
    'PASAPORTE': r'[A-Za-z0-9]{1,30}',
}
CODIGOS_SUNAT = {'DNI': '1', 'RUC': '6', 'CE': '4', 'PASAPORTE': '7'}


def documento_valido(tipo, numero):
    return isinstance(tipo, str) and tipo in FORMATOS and isinstance(numero, str) and bool(
        re.fullmatch(FORMATOS[tipo], numero)
    )


def inferir_persona(tipo, numero):
    if not documento_valido(tipo, numero):
        return None
    if tipo != 'RUC' or numero.startswith(('10', '15')):
        return 'NATURAL'
    if numero.startswith('20'):
        return 'JURIDICA'
    return None
