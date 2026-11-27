"""Catálogo de medidas: símbolos SI/BIPM y códigos UNECE Recommendation 20.

La migración sustituye identificadores históricos por códigos estándar sin tocar
cantidades. Una porción nunca equivale automáticamente a una pieza.
"""
from collections import defaultdict
from dataclasses import dataclass
from decimal import Decimal, DecimalException, InvalidOperation

from flask import g, has_request_context
from sqlalchemy import func, select

from app.core.extensions import db


@dataclass(frozen=True)
class Unidad:
    codigo: str
    valor: str
    nombre: str
    simbolo: str
    dimension: str
    codigo_unece: str | None
    codigo_base: str
    factor_a_base: Decimal = Decimal("1")
    simbolo_plural: str | None = None
    estandar: str | None = None

    def serializar(self):
        return {
            "codigo": self.codigo, "valor": self.codigo,
            "nombre": self.nombre, "simbolo": self.simbolo,
            "dimension": self.dimension, "codigo_unece": self.codigo_unece,
            "codigo_base": self.codigo_base,
            "factor_a_base": str(self.factor_a_base), "simbolo_plural": self.simbolo_plural,
            "estandar": self.estandar,
        }


def _leer_catalogo():
    unidades = tuple(
        Unidad(valor=fila["codigo"], **fila)
        for fila in db.session.execute(select(func.public.catalogo_unidades().table_valued('codigo', 'nombre', 'simbolo', 'dimension', 'codigo_unece', 'codigo_base', 'factor_a_base', 'simbolo_plural', 'estandar'))).mappings()
    )
    por_codigo = {unidad.codigo: unidad for unidad in unidades}
    alias = {unidad.simbolo: unidad for unidad in unidades}
    for nombre, codigo in db.session.execute(select(func.public.catalogo_unidades_alias().table_valued('alias', 'codigo'))):
        alias[nombre] = por_codigo[codigo]
    alias.update(por_codigo)
    contextos = defaultdict(set)
    for contexto, base in db.session.execute(select(func.public.catalogo_unidades_contextos().table_valued('contexto', 'codigo_base'))):
        contextos[contexto].add(base)
    return unidades, alias, contextos


def _catalogo():
    if not has_request_context():
        return _leer_catalogo()
    if "catalogo_medidas" not in g:
        g.catalogo_medidas = _leer_catalogo()
    return g.catalogo_medidas


def obtener_unidad(valor):
    return _catalogo()[1].get(valor.strip()) if isinstance(valor, str) and valor.strip() else None


def catalogo_unidades(contexto=None, solo_base=False):
    unidades, _, contextos = _catalogo()
    if contexto is not None and contexto not in contextos:
        raise ValueError("Contexto de unidades inválido")
    return [u.serializar() for u in unidades
            if (contexto is None or u.codigo_base in contextos[contexto])
            and (not solo_base or u.codigo == u.codigo_base)]


def valores_unidades(contexto, solo_base=False):
    return [u["valor"] for u in catalogo_unidades(contexto, solo_base)]


def unidad_base(valor, contexto):
    unidad = obtener_unidad(valor)
    if unidad is None or unidad.codigo_base not in _catalogo()[2].get(contexto, ()):
        raise ValueError("Selecciona una unidad válida")
    return unidad.codigo_base


def convertir_cantidad(cantidad, origen, destino):
    anterior, nueva = obtener_unidad(origen), obtener_unidad(destino)
    if anterior is None or nueva is None:
        raise ValueError("Unidad de medida desconocida")
    # Misma base, además de dimensión: porciones y piezas no son intercambiables.
    if anterior.codigo_base != nueva.codigo_base:
        raise ValueError("Las unidades no son compatibles; necesitan una equivalencia por producto")
    try:
        valor = Decimal(str(cantidad))
        if not valor.is_finite():
            raise InvalidOperation
        return valor * anterior.factor_a_base / nueva.factor_a_base
    except (DecimalException, TypeError, ValueError):
        raise ValueError("Cantidad inválida") from None


def normalizar_medida(cantidad, unidad, contexto):
    base = unidad_base(unidad, contexto)
    return convertir_cantidad(cantidad, unidad, base), base


def unidad_almacenamiento(valor):
    unidad = obtener_unidad(valor)
    if unidad is None:
        raise ValueError("Unidad desconocida")
    return unidad.codigo


def describir_medidas(datos):
    """Expone códigos estables y sus símbolos, para productos y sus presentaciones."""
    if isinstance(datos, list):
        return [describir_medidas(d) for d in datos]
    if not isinstance(datos, dict):
        return datos
    resultado = {k: describir_medidas(v) for k, v in datos.items()}
    for campo in ("unidad", "unidad_presentacion"):
        unidad = obtener_unidad(datos.get(campo))
        if unidad is not None:
            resultado[campo] = unidad.codigo
            resultado[f"{campo}_medida"] = unidad.serializar()
            if campo == "unidad" and "presentacion_compra" in datos:
                alternativa = max(
                    (otra for otra in _catalogo()[0] if otra.codigo_base == unidad.codigo_base
                     and otra.factor_a_base < unidad.factor_a_base),
                    key=lambda otra: otra.factor_a_base, default=None,
                )
                if alternativa is not None:
                    resultado["unidad_fraccion"] = alternativa.serializar()
    return resultado


def registrar_medidas_api(app):
    # Un único adaptador cubre los serializers de inventario, compras y recetas.
    # No se reescribe el contenido histórico de auditoría.
    from flask import request

    @app.after_request
    def describir_unidades_respuesta(respuesta):
        if (request.path.startswith("/api/")
                and not request.path.startswith("/api/actividades")
                and respuesta.is_json and 200 <= respuesta.status_code < 300):
            datos = respuesta.get_json()
            enriquecidos = describir_medidas(datos)
            if enriquecidos != datos:
                respuesta.set_data(app.json.dumps(enriquecidos))
        return respuesta
