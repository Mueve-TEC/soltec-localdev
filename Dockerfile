# Usar la imagen base de Odoo v16
#FROM odoo:16.0

# Usar la imagen de Odoo del programa SOL3
FROM muevetec/soltec-odoo:1.0.19-dev

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    git \
    libzbar0 \
    poppler-utils \
    && rm -rf /var/lib/apt/lists/*

COPY ./ocr_requirements.txt /tmp/ocr_requirements.txt
RUN pip install --no-cache-dir uv \
    && uv pip install --system --no-cache -r /tmp/ocr_requirements.txt \
    && rm -f /tmp/ocr_requirements.txt

USER odoo
