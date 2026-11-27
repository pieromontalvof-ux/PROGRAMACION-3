import os
from datetime import timedelta

from dotenv import load_dotenv

load_dotenv()


CORPORATE_EMAIL_DOMAIN = os.getenv("CORPORATE_EMAIL_DOMAIN", "barbarian.pe").strip().lower().lstrip("@") or "barbarian.pe"


class Config:
    SQLALCHEMY_DATABASE_URI = os.getenv("DATABASE_URL", "").replace('postgres://', 'postgresql://', 1) or None
    ACADESYS_API_TOKEN = os.getenv("ACADESYS_API_TOKEN", "").strip()
    INTEGRACIONES_API_TOKEN = os.getenv("INTEGRACIONES_API_TOKEN", "")
    INTEGRACIONES_API_LOCAL = os.getenv("INTEGRACIONES_API_LOCAL", "").strip()
    INTEGRACIONES_API_ORIGEN = os.getenv("INTEGRACIONES_API_ORIGEN", "Sistema externo").strip()
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SECRET_KEY = os.getenv("SECRET_KEY")
    JWT_SECRET_KEY = os.getenv("JWT_SECRET_KEY")
    JWT_ACCESS_TOKEN_EXPIRES = timedelta(hours=8)
    CORS_ORIGINS = [origin.strip() for origin in os.getenv('CORS_ORIGINS', '*').split(',') if origin.strip()]
