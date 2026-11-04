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
COPY backend/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY backend/app ./app
COPY backend/wsgi.py backend/gunicorn.conf.py ./
COPY --from=frontend /build/dist /app/frontend/dist
RUN mkdir -p /data
EXPOSE 8080
CMD ["gunicorn", "--config", "gunicorn.conf.py", "wsgi:app"]
