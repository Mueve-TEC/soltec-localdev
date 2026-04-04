FROM odoo:18.0

USER root

RUN apt-get update && apt-get install git -y
RUN apt-get install python3-m2crypto -y
RUN apt-get install python3-xlrd python3-chardet python3-ofxparse -y

COPY ./requirements.txt /tmp/requirements.txt
COPY openssl.cnf /etc/ssl/openssl.cnf

RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

RUN uv pip install --system --break-system-packages -r /tmp/requirements.txt

# Parchear incompatibilidades con Python 3.12 y dar permisos al cache de pyafipws
RUN find /usr/local/lib/python3.12/dist-packages/pysimplesoap/ -name "*.py" -exec \
	sed -i 's/inspect\.getargspec/inspect.getfullargspec/g' {} \; \
	&& find /usr/local/lib/python3.12/dist-packages/pyafipws/ -name "*.py" -exec \
	sed -i 's/SafeConfigParser/RawConfigParser/g' {} \; \
	&& mkdir -p /usr/local/lib/python3.12/dist-packages/pyafipws/cache \
	&& chmod -R 777 /usr/local/lib/python3.12/dist-packages/pyafipws/cache

USER odoo

COPY --chown=odoo:odoo ./custom-addons /mnt/extra-addons