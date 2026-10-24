# Собираем зависимости отдельно. Так в итоговом образе не будет Poetry.
FROM python:3.11-slim-bookworm AS build

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    POETRY_VIRTUALENVS_CREATE=false \
    SOURCE_DATE_EPOCH=0

WORKDIR /build

RUN pip install --no-cache-dir "poetry==2.5.1" "poetry-plugin-export==1.10.0"

COPY pyproject.toml poetry.lock README.md ./
COPY src/ src/

RUN mkdir dist \
    && poetry export --without-hashes --format requirements.txt --output dist/requirements.txt \
    && pip wheel --no-cache-dir --requirement dist/requirements.txt --wheel-dir dist/vendor \
    && poetry build --format wheel


# В рабочем образе оставляем только Python, зависимости и наше приложение.
FROM python:3.11-slim-bookworm

ENV HOST=0.0.0.0 \
    PORT=8080 \
    AUDIT_SVC_CONFIG=/etc/audit-svc/config.yaml \
    PYTHONUNBUFFERED=1

RUN groupadd --gid 10001 audit \
    && useradd --uid 10001 --gid audit --no-create-home --shell /usr/sbin/nologin audit

COPY --from=build /build/dist/ /tmp/dist/
RUN pip install --no-cache-dir --no-index --find-links /tmp/dist/vendor /tmp/dist/*.whl \
    && rm -rf /tmp/dist \
    && mkdir -p /etc/audit-svc \
    && chown audit:audit /etc/audit-svc

USER audit
EXPOSE 8080

ENTRYPOINT ["server"]
