"""Read-only administrative analysis; never grants local stock operations."""
from flask_jwt_extended import get_jwt
from app.multiagente.agents import activity
from . import demand

RESOURCE=('demanda_global',(14,'/inventario-operativo/demanda-global','productos','id_producto'))


def allowed(session,action='consultar'):
    return action=='consultar' and get_jwt().get('id_perfil')==1 and any(
        row['id_opcion_menu']==14 and row.get('permisos',{}).get('consultar') for row in session['menu'])


@activity.agent('demanda')
@activity.tool('analizar_demanda_global')
def read(session,filters=None):
    return demand.read(session,filters,global_scope=True)
