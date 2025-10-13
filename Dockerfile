# Usar la imagen base de Odoo v16
#FROM odoo:16.0
FROM muevetec/soltec-odoo:1.0.8-dev

# Copiar los módulos personalizados desde el host al contenedor
# COPY --chown=odoo:odoo ./custom-addons /mnt/extra-addons