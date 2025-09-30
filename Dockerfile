# Usar la imagen base de Odoo v16
#FROM odoo:16.0
FROM muevetec/soltec-odoo:1.0.8-dev

# Cambiar a usuario root para instalar dependencias
USER root

# Actualizar el sistema e instalar
RUN apt-get update && \
    apt-get install -y git && \
    rm -rf /var/lib/apt/lists/*

COPY ./requirements.txt /tmp/requirements.txt

# Instalar las dependencias de Python desde requirements.txt
RUN pip3 install -r /tmp/requirements.txt

# Copiar los módulos personalizados desde el host al contenedor
COPY --chown=odoo:odoo ./custom-addons /mnt/extra-addons

# Volver al usuario odoo
USER odoo

## Verificar que el fork de pyafipws esté instalado correctamente (opcional, para debug)
## Entrar en una terminal con la imagen andando 
# docker exec -u odoo -it soltec-localdev-retenciones-web-1 bash
## y ejecutar el siguiente comando:
# python3 -c "from pyafipws import wsfev1; import inspect; sig = inspect.signature(wsfev1.WSFEv1.CrearFactura); params = list(sig.parameters.keys()); print('Parámetros CrearFactura:', len(params)); print('✓ Fork modificado detectado en imagen Docker' if 'cond_iva_receptor' in params else '✗ Fork NO detectado en imagen Docker');"