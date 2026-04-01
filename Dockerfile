# Usar la imagen base de Odoo v18
FROM odoo:18.0
#FROM muevetec/soltec-odoo:1.0.14-dev

# Cambiar a usuario root para instalar dependencias
USER root

# Actualizar el sistema e instalar
RUN apt-get update && \
    apt-get install -y git && \
    rm -rf /var/lib/apt/lists/*

COPY ./requirements.txt /tmp/requirements.txt

# Debian/PEP 668 bloquea pip en entorno del sistema; en contenedores se permite con este flag.
RUN pip3 install --break-system-packages -r /tmp/requirements.txt

# Copiar los módulos personalizados desde el host al contenedor
COPY --chown=odoo:odoo ./custom-addons /mnt/extra-addons

# Volver al usuario odoo
USER odoo