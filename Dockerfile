# Usar la imagen base de Odoo v16
#FROM odoo:16.0

# Usar la imagen de Odoo del programa SOL3
FROM muevetec/soltec-odoo:1.0.15-dev

COPY ./ocr_requirements.txt /tmp/ocr_requirements.txt

USER root

RUN apt-get update && apt-get install -y git
RUN apt-get install -y libzbar0 poppler-utils
RUN pip install uv
RUN uv pip install --system -r /tmp/ocr_requirements.txt

USER odoo
