# SolTec LocalDev

Entorno de desarrollo local para la imagen de _Odoo_ del programa SolTec.

Para utilizar este enterno necesitamos tener instalados **_Docker_** y **_Git_**. Para instalarlos en _Ubuntu_ o _Debian_ se puede seguir [este](#instalación) instructivo.

## Uso

Para clonar el repositorio:

```bash
git clone https://github.com/Mueve-TEC/soltec-localdev.git
cd soltec-localdev
```

### Docker Compose

En el archivo [`docker-compose.yml`](/docker-compose.yml) están configurados para correr en un mismo contenedor los siguientes servicios:

- _Odoo_ del programa SolTec.
- Base de datos _Postgres_.
- Visualizador de bases de datos _Pgadmin4_

Para crear la imagen del entorno de desarrollo ejecutamos:

```bash
docker compose build --no-cache
```

Para levantarlo localmente:

```bash
docker compose up -d
```

Luego en un navegador ingresamos a [localhost:8069](http://localhost:8069).

## Agregar módulos

Para agregar módulos de _Odoo_ a la imagen basta con copiarlos en el directorio [**`custom-addons/`**](/custom-addons/) y luego levantar nuevamente el container.

### Submodulos de _Git_

Para un mejor control de versiones, se pueden integrar los módulos de _Odoo_ directamente desde su repositorio agregandolos como submódulos de _Git_.

1. Luego agregamos los repositorios como submódulos:

```bash
cd submodules
git submodule add <link-al-repositorio>
cd ..
```

3. Ejecutamos el script para copiar el contenido necesario de los módulos al directorio [**`custom-addons/`**](/custom-addons/):

```bash
bash copy_addons.sh
```

4. Por último levantamos nuevamente el container con los módulos nuevos agregados:

```bash
docker compose up -d
```

## Trabajar en varios tickets en paralelo

Cada ticket puede correr en su propio _worktree_ de _Git_ con su propio contenedor de _Odoo_, puerto, base de datos y filestore, compartiendo el servidor _Postgres_, la red de _Docker_ y la imagen del checkout principal. Así se pueden abrir varias sesiones de _opencode_ (una por terminal) sin que se pisen el código, la base ni los puertos.

Preparación inicial (una sola vez, en el checkout principal):

```bash
make build                        # imagen soltec-localdev-odoo19:1.0
make golden-refresh SRC_DB=admin  # crea la DB golden `ticket_template`
```

Crear un ticket:

```bash
make ticket-new SLUG=fix-arca-qr
cd ../soltec-tickets/fix-arca-qr
opencode
```

`ticket-new` crea el _worktree_, la rama `19.0-<slug>` (en el superproyecto y en cada submódulo), la base `t_<slug>` clonada de la golden, un volumen de filestore propio y el contenedor _Odoo_ en un puerto libre (8100-8499). El puerto y la URL se muestran al finalizar.

Dentro del worktree, los comandos de siempre quedan apuntados al ticket:

```bash
make sync                        # submodules/ -> custom-addons/
make upgrade MODULE=l10n_ar_tax
make test MODULE=l10n_ar_tax
make ticket-logs
make ticket-dbshell
make ticket-up                   # levantar el web (y la DB principal si hace falta)
make ticket-down                 # detener el web (conserva DB y volúmenes)
```

Listar y finalizar:

```bash
make ticket-list
make ticket-done SLUG=fix-arca-qr   # KEEP=1 conserva todo; FORCE=1 omite el control de commits
```

Notas:

- El servidor _Postgres_ es el del checkout principal: si se detiene (`make down`), los tickets quedan sin base; `make ticket-up` lo vuelve a levantar.
- `make down-clean` en el checkout principal se niega a borrar los volúmenes mientras existan tickets (`FORCE=1` lo omite).
- Cada sesión debe trabajar **solo** dentro de su worktree; no editar el checkout principal.
- Si un ticket modifica el `Dockerfile`, definir `IMAGE_TAG=tkt-<slug>` en su `.env` y construir esa imagen para no pisar la compartida.
- `ticket-done` no elimina el worktree si hay commits sin pushear en los submódulos (usar `FORCE=1` para forzarlo).
- Más detalle: sección "Parallel ticket worktrees" en [`AGENTS.md`](/AGENTS.md).

## Conexión de la base de datos con _Pgadmin4_

Para un mejor manejo y visualización de las bases de datos se incluye _Pgadmin4_, para utilizarlo seguimos los siguientes pasos:

1. Con la imagen corriendo nos dirigimos a [localhost:5050](http://localhost:5050) para abrir la interfaz gráfica de _Pgadmin4_ y nos logueamos con las credenciales configuradas en el [`docker-compose.yml`](/docker-compose.yml):
   - Email Address / Username : `admin@hola.com`
   - Password: `admin`

2. Presionamos en _`Add new server`_.

3. Agregamos un nombre a la base de datos, _odoo_ por ejemplo.

4. Luego nos dirigimos al campo _`Connection`_ y completamos los siguientes campos:
   - Host name/address: `db`
   - Port: `5432`
   - Username: `odoo`
   - Password: `odoo`

5. Presionamos _`Save`_ para guardar los cambios y agregar la conexión.

## Instalación

### Git

```bash
sudo apt update && sudo apt install git
```

### Docker

#### Ubuntu

```bash
sudo bash docker/install_ubuntu.sh
```

#### Debian

```bash
sudo bash docker/install_debian.sh
```

#### Crear grupo de usuarios docker

Para no tener que agregar `sudo` a cada comando de _Docker_ que utilicemos podemos crear un grupo de usuarios docker y agregar nuestro usuario al grupo.

1. Crear el grupo docker.

```bash
sudo groupadd docker
```

2. Agregar tu usuario al grupo.

```bash
sudo usermod -aG docker $USER
```

3. Para confirmar los cambios podemos cerrar sesión y volver a abrirla o ejecutar el siguiente comando.

```bash
newgrp docker
```
