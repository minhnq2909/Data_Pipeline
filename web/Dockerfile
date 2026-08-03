FROM python:3.12-slim

WORKDIR /app

COPY server.py /app/server.py
COPY static /app/static

EXPOSE 8000

CMD ["python", "server.py"]
