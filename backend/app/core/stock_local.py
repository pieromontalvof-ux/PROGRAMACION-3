from sqlalchemy import func, select

from app.core.extensions import db


def inventario_operativo_instalado():
    return bool(db.session.execute(select(func.public.inventario_operativo_instalado())).scalar())
