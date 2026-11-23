FROM node:24-bookworm-slim AS frontend
WORKDIR /build
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend/ ./
ENV VITE_API_URL=/api
RUN npm run build

FROM python:3.12-slim-bookworm
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 APP_DATA_DIR=/data CORS_ORIGINS=""
WORKDIR /app/backend
RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx php8.2-cli php8.2-fpm php8.2-pgsql php8.2-mbstring php8.2-xml \
    php8.2-curl php8.2-gd php8.2-zip php8.2-bcmath php8.2-soap unzip ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer
COPY backend/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY backend/app ./app
COPY backend/scripts ./scripts
COPY backend/wsgi.py backend/gunicorn.conf.py ./
COPY services/fact_api /app/services/fact_api
RUN cd /app/services/fact_api && composer install --no-dev --prefer-dist --no-interaction --no-progress --no-scripts
COPY deploy /app/deploy
COPY database/migrations/20261118_clientes.sql database/migrations/20261120_cierres_diarios_salon.sql database/migrations/20261121_fact_api_queue.sql database/migrations/20261121_fact_api_autoscale.sql /app/database/migrations/
COPY --from=frontend /build/dist /app/frontend/dist
RUN mkdir -p /data
EXPOSE 8080
CMD ["python", "scripts/cloud_runtime.py"]
