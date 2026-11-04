from dotenv import load_dotenv

load_dotenv()

from app.core.production import validate_environment
validate_environment()

from app import create_app
app = create_app()
