from flask import Blueprint, jsonify
from sqlalchemy import func, inspect, select

from app.core.extensions import db

health_bp = Blueprint("health", __name__)


@health_bp.get("/health")
def health():
    if db.engine.dialect.name == "sqlite":
        datos = {
            "base_datos": db.engine.url.database or ":memory:",
            "usuario": "local",
            "total_tablas": len(inspect(db.session.connection()).get_table_names()),
        }
    else:
        filas = func.public.health_estado_base().table_valued("base_datos", "usuario", "total_tablas")
        datos = db.session.execute(select(filas)).mappings().one()
    return jsonify(estado="ok", **datos)
