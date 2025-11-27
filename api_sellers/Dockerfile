# Dockerfile
FROM python:3.11-slim

WORKDIR /app

# Copie des requirements et installation
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# On copie le script
COPY main.py .
COPY catalog.json .

EXPOSE 8080

# On lance la boucle infinie
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]