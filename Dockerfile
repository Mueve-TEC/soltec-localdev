# Usar la imagen base de Odoo v16
#FROM odoo:16.0

# Usar la imagen de Odoo del programa SOL3
FROM muevetec/soltec-odoo:1.0.15-dev

USER root

# System dependencies that change rarely: keep this layer cached as long as
# the apt list does not change.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
        libzbar0 \
        poppler-utils \
    && rm -rf /var/lib/apt/lists/*

# Python requirements change more often, so copy and install them after the
# apt layer so that code/requirements changes reuse the previous cache.
COPY ./ocr_requirements.txt /tmp/ocr_requirements.txt
RUN pip install --no-cache-dir uv \
    && uv pip install --system --no-cache -r /tmp/ocr_requirements.txt \
    && rm -f /tmp/ocr_requirements.txt

USER odoo
