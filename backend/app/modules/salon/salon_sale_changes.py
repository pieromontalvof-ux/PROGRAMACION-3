"""Auditable same-day changes to internal restaurant receipts."""
from werkzeug.exceptions import Conflict

def verificar_dia(fecha, jornada, cierre, hoy):
    if fecha != hoy or jornada != hoy or cierre is not None:
        raise Conflict('Solo puedes modificar ventas de hoy y de una jornada abierta.')
