# Usar la imagen base de Odoo v16
FROM odoo:16.0

# Copiar los módulos personalizados desde el host al contenedor
COPY --chown=odoo:odoo ./custom-addons /mnt/extra-addons