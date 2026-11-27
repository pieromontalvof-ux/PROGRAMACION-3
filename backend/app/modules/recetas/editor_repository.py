import re

from sqlalchemy import bindparam, func, select

from app.core.extensions import db
from app.core.units import catalogo_unidades, valores_unidades


def filas(consulta, parametros=None):
    return [dict(f) for f in db.session.execute(consulta, parametros or {}).mappings().all()]


def ejecutar(consulta, parametros=None):
    return db.session.execute(consulta, parametros or {})


def opciones_check(nombre):
    definicion = ejecutar(select(func.public.receta_definicion_check(bindparam("nombre"))), {"nombre": nombre}).scalar_one()
    return re.findall(r"'([^']+)'::character varying", definicion)


def formulario():
    return {
        "tipos": opciones_check("ck_item_carta_tipo"),
        "unidades_presentacion": valores_unidades("presentacion"),
        "unidades_medida": catalogo_unidades(),
        "categorias": filas(select(func.public.receta_categorias().table_valued('id_categoria_carta', 'nombre', 'activo'))),
        "menajes": filas(select(func.public.carta_medidas_menaje(None).table_valued('id_menaje', 'nombre', 'activo', 'capacidad', 'unidad_capacidad', 'diametro_cm', 'altura_cm', 'largo_cm', 'ancho_cm', 'origen_medidas'))),
        "items": filas(select(func.public.receta_items().table_valued('id_item_carta', 'codigo', 'nombre', 'id_categoria_carta', 'tipo', 'activo'))),
        "presentaciones": filas(select(func.public.receta_presentaciones_disponibles().table_valued('id_presentacion_venta', 'id_item_carta', 'id_menaje', 'contenido', 'unidad', 'activo', 'id_receta'))),
        "productos": filas(select(func.public.produccion_productos_formulario().table_valued('id', 'codigo', 'nombre', 'unidad', 'activo'))),
        "subproductos": filas(select(func.public.receta_subproductos().table_valued('id', 'codigo', 'nombre', 'unidad', 'activo'))),
    }


def buscar_receta(id_receta):
    resultados = filas(select(func.public.receta_buscar_bloqueada(bindparam("id")).table_valued('id_receta', 'id_presentacion_venta', 'instrucciones', 'activo', 'id_item_carta', 'contenido', 'unidad', 'id_menaje', 'tipo', 'nombre', 'id_categoria_carta')), {"id": id_receta})
    return resultados[0] if resultados else None


def detalles(id_receta):
    return filas(select(func.public.receta_detalles(bindparam("id")).table_valued('id_receta_detalle', 'id_receta', 'tipo_componente', 'id_producto', 'id_subproducto', 'cantidad', 'unidad')), {"id": id_receta})


def grupo(id_presentacion):
    resultados = filas(select(func.public.receta_grupo_bloqueado(bindparam("id")).table_valued('id_grupo_salsa', 'id_presentacion_venta', 'cantidad_maxima', 'permite_repetir', 'activo')), {"id": id_presentacion})
    if not resultados:
        return None
    resultado = resultados[0]
    resultado["opciones"] = filas(select(func.public.receta_opciones_grupo(bindparam("id")).table_valued('id_grupo_salsa_opcion', 'id_grupo_salsa', 'id_producto', 'cantidad', 'unidad', 'activo')), {"id": resultado["id_grupo_salsa"]})
    return resultado


def ingrediente(tipo, identidad):
    buscar = func.public.receta_bloquear_producto if tipo == "PRODUCTO" else func.public.receta_bloquear_subproducto
    resultados = filas(select(buscar(bindparam("id")).table_valued('id', 'codigo', 'nombre', 'unidad', 'activo')), {"id": identidad})
    return resultados[0] if resultados else None


def reemplazar_detalles(id_receta, componentes):
    ejecutar(select(func.public.receta_eliminar_detalles(bindparam("id"))), {"id": id_receta})
    for c in componentes:
        ejecutar(select(func.public.receta_crear_detalle(bindparam("receta"), bindparam("tipo"), bindparam("producto"), bindparam("subproducto"), bindparam("cantidad"), bindparam("unidad"))), {"receta": id_receta, "tipo": c["tipo_componente"],
              "producto": c["id"] if c["tipo_componente"] == "PRODUCTO" else None,
              "subproducto": c["id"] if c["tipo_componente"] == "SUBPRODUCTO" else None,
              "cantidad": c["cantidad"], "unidad": c["unidad"]})


def guardar_grupo(id_presentacion, configuracion):
    if configuracion is None:
        ejecutar(select(func.public.receta_desactivar_grupo(bindparam("id"))), {"id": id_presentacion})
        return
    id_grupo = ejecutar(select(func.public.receta_guardar_grupo(bindparam("id"), bindparam("maximo"), bindparam("repetir"))), {"id": id_presentacion, "maximo": configuracion["cantidad_maxima"], "repetir": configuracion["permite_repetir"]}).scalar_one()
    ejecutar(select(func.public.receta_desactivar_opciones(bindparam("id"))), {"id": id_grupo})
    for opcion in configuracion["opciones"]:
        ejecutar(select(func.public.receta_guardar_opcion(bindparam("grupo"), bindparam("producto"), bindparam("cantidad"), bindparam("unidad"))), {"grupo": id_grupo, "producto": opcion["id"], "cantidad": opcion["cantidad"], "unidad": opcion["unidad"]})
