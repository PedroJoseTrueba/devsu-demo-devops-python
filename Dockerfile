FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DATABASE_NAME=data/db.sqlite3

WORKDIR /app

# Install locked application dependencies and the production WSGI server.
COPY requirements.txt requirements.docker.txt ./
RUN pip install --no-cache-dir -r requirements.docker.txt

# Avoid running the application as root.
RUN groupadd --system app && useradd --system --gid app --home-dir /app app \
    && mkdir -p /app/data && chown -R app:app /app

COPY --chown=app:app api/ ./api/
COPY --chown=app:app demo/ ./demo/
COPY --chown=app:app manage.py ./manage.py

USER app
EXPOSE 8000

# The Django REST Framework router serves the API root at /api/.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/', timeout=3)" || exit 1

CMD ["gunicorn", "demo.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "2", "--access-logfile", "-"]
