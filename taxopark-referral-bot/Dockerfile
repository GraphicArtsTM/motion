FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
RUN apt-get update && apt-get install -y --no-install-recommends postgresql-client \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY pyproject.toml ./
RUN pip install --upgrade pip && pip install .
COPY . .
RUN useradd --create-home --uid 10001 app && mkdir -p /backups && chown app /backups
USER app
EXPOSE 8000
CMD ["uvicorn", "src.web:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]
