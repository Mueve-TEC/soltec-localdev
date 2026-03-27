# Usar la imagen base de Odoo v18
FROM odoo:18.0
#FROM muevetec/soltec-odoo:1.0.14-dev

# Copiar los módulos personalizados desde el host al contenedor
# COPY --chown=odoo:odoo ./custom-addons /mnt/extra-addons
