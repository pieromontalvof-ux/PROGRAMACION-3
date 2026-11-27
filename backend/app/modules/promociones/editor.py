import re
from datetime import time
from decimal import Decimal, InvalidOperation

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from app.core.extensions import db
from app.modules.promociones.repository import filas
from app.modules.auditoria.service import registrar_cambio, registrar_actividad


def formulario_promocion():
    opciones = filas(func.public.promo_formulario().table_valued('id_presentacion_venta', 'codigo', 'nombre', 'contenido', 'unidad', 'menaje', 'activo'))
    for opcion in opciones:
        opcion['contenido'] = float(opcion['contenido'])
    return {'presentaciones': opciones}, 200


def guardar_promocion(usuario, datos, identidad=None):
    if not isinstance(datos, dict):
        return {'mensaje': 'Datos invalidos'}, 400
    try:
        db.session.execute(select(func.public.promo_bloquear_catalogo()))
        anterior = None
        grupos_previos = []
        opciones_previas = []
        reposiciones_previas = []
        if identidad is not None:
            encontrados = filas(func.public.promo_bloquear_promocion(identidad).table_valued('id_promocion', 'codigo', 'nombre', 'precio', 'hora_inicio', 'hora_fin', 'activo'))
            if not encontrados:
                db.session.rollback()
                return {'mensaje': 'La promocion no existe'}, 404
            anterior = encontrados[0]
            grupos_previos = filas(func.public.promo_grupos_previos(identidad).table_valued('id_promocion_grupo', 'id_promocion', 'cantidad_elegir', 'permite_repetir'))
            opciones_previas = filas(func.public.promo_opciones_previas(identidad).table_valued('id_promocion_opcion', 'id_promocion_grupo', 'id_presentacion_venta'))
            reposiciones_previas = filas(func.public.promo_reposiciones_previas(identidad).table_valued('id_promocion', 'id_presentacion_venta'))
        nombre = datos.get('nombre')
        if not isinstance(nombre, str) or not 1 <= len(nombre.strip()) <= 150:
            raise ValueError('Ingresa un nombre de hasta 150 caracteres')
        nombre = nombre.strip()
        if db.session.execute(select(func.public.promo_nombre_existe(nombre, identidad or 0))).scalar():
            raise ValueError('Ya existe una promocion con ese nombre')
        try:
            precio = Decimal(str(datos.get('precio')))
            if not precio.is_finite() or not 0 <= precio <= Decimal('99999999.99') or precio != precio.quantize(Decimal('.01')):
                raise InvalidOperation
        except (InvalidOperation, ValueError):
            raise ValueError('Precio invalido; usa hasta dos decimales')
        activo = datos.get('activo')
        if not isinstance(activo, bool):
            raise ValueError('Estado invalido')
        inicio, fin = datos.get('hora_inicio'), datos.get('hora_fin')
        if inicio is not None or fin is not None:
            if not all(isinstance(h, str) and re.fullmatch(r'\d{2}:\d{2}', h) for h in (inicio, fin)):
                raise ValueError('Completa ambas horas con formato HH:MM')
            inicio, fin = time.fromisoformat(inicio), time.fromisoformat(fin)
            if inicio == fin:
                raise ValueError('La hora inicial y final deben ser diferentes')
        grupos = datos.get('grupos')
        if not isinstance(grupos, list) or not 1 <= len(grupos) <= 50:
            raise ValueError('Agrega entre 1 y 50 grupos')
        ids_previos = {g['id_promocion_grupo'] for g in grupos_previos}
        vistos = set()
        validos = []
        for grupo in grupos:
            if not isinstance(grupo, dict):
                raise ValueError('Grupo invalido')
            gid = grupo.get('id_promocion_grupo')
            if gid is not None and (type(gid) is not int or gid not in ids_previos or gid in vistos):
                raise ValueError('El grupo no pertenece a esta promocion o esta duplicado')
            vistos.add(gid)
            elegir, repetir, opciones = grupo.get('cantidad_elegir'), grupo.get('permite_repetir'), grupo.get('opciones')
            if type(elegir) is not int or not 1 <= elegir <= 32767 or not isinstance(repetir, bool):
                raise ValueError('Configura cuantas opciones elegir y si se pueden repetir')
            if not isinstance(opciones, list) or not 1 <= len(opciones) <= 300 or any(type(i) is not int or i <= 0 for i in opciones):
                raise ValueError('Agrega presentaciones de carta al grupo')
            if len(set(opciones)) != len(opciones):
                raise ValueError('No dupliques opciones; utiliza Permitir repetir')
            if not repetir and elegir > len(opciones):
                raise ValueError('Sin repetir, la cantidad a elegir no puede superar las opciones disponibles')
            anteriores = {o['id_presentacion_venta'] for o in opciones_previas if o['id_promocion_grupo'] == gid}
            for pid in sorted(opciones):
                presentaciones = filas(func.public.promo_bloquear_presentacion(pid).table_valued('activo'))
                if not presentaciones or (not presentaciones[0]['activo'] and pid not in anteriores):
                    raise ValueError('Selecciona presentaciones activas de la carta')
            validos.append({'id': gid, 'elegir': elegir, 'repetir': repetir, 'opciones': opciones})
        reposiciones = datos.get('reposiciones', [r['id_presentacion_venta'] for r in reposiciones_previas])
        opciones_promocion = {pid for grupo in validos for pid in grupo['opciones']}
        if not isinstance(reposiciones, list) or any(type(pid) is not int or pid <= 0 for pid in reposiciones):
            raise ValueError('Selecciona presentaciones validas para reposicion')
        if len(set(reposiciones)) != len(reposiciones) or not set(reposiciones).issubset(opciones_promocion):
            raise ValueError('Solo puedes habilitar reposicion para opciones incluidas en la promocion')
        if anterior:
            db.session.execute(select(func.public.promo_actualizar(nombre, precio, inicio, fin, activo, identidad)))
        else:
            codigo = db.session.execute(select(func.public.promo_siguiente_codigo())).scalar_one()
            if len(codigo) > 10:
                raise ValueError('No hay codigos disponibles')
            identidad = db.session.execute(select(func.public.promo_crear(codigo, nombre, precio, inicio, fin, activo))).scalar_one()
        for eliminado in ids_previos - vistos:
            db.session.execute(select(func.public.promo_eliminar_opciones(eliminado)))
            db.session.execute(select(func.public.promo_eliminar_grupo(eliminado)))
        for g in validos:
            if g['id'] is None:
                g['id'] = db.session.execute(select(func.public.promo_crear_grupo(identidad, g['elegir'], g['repetir']))).scalar_one()
            else:
                db.session.execute(select(func.public.promo_actualizar_grupo(g['elegir'], g['repetir'], g['id'])))
            db.session.execute(select(func.public.promo_quitar_opciones(g['id'], g['opciones'])))
            for pid in g['opciones']:
                db.session.execute(select(func.public.promo_crear_opcion(g['id'], pid)))
        db.session.execute(select(func.public.promo_eliminar_reposiciones(identidad)))
        for pid in reposiciones:
            db.session.execute(select(func.public.promo_crear_reposicion(identidad, pid)))
        nuevo = filas(func.public.promo_buscar(identidad).table_valued('id_promocion', 'codigo', 'nombre', 'precio', 'hora_inicio', 'hora_fin', 'activo'))[0]
        accion = 'EDITAR' if anterior else 'CREAR'
        registrar_cambio(usuario, 'PROMOCIONES', accion, 'promocion', identidad,
                         {'promocion': anterior, 'grupos': grupos_previos, 'opciones': opciones_previas,
                          'reposiciones': reposiciones_previas} if anterior else None,
                         {'promocion': nuevo, 'grupos': validos, 'reposiciones': reposiciones})
        registrar_actividad(usuario, 'PROMOCIONES', accion, identidad, f'{accion}: {nombre}')
        db.session.commit()
        return {'mensaje': 'Promocion guardada correctamente', 'id_promocion': identidad}, 200 if anterior else 201
    except ValueError as error:
        db.session.rollback()
        return {'mensaje': str(error)}, 400
    except IntegrityError:
        db.session.rollback()
        return {'mensaje': 'Datos duplicados o referencias no validas. Actualiza el formulario.'}, 409
    except Exception:
        db.session.rollback()
        raise
