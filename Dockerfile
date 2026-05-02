FROM python:3.11-slim

WORKDIR /app

# Install bash (for running vault scripts)
RUN apt-get update && apt-get install -y bash git curl && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Vault data lives in a mounted volume at /data/vault
ENV VAULT_ROOT=/data/vault
ENV PYTHONUNBUFFERED=1

EXPOSE 8001

CMD ["uvicorn", "api:app", "--host", "0.0.0.0", "--port", "8001"]
