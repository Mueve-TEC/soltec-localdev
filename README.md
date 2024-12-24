installar git

# Clonar el reositorio
git clone https://github.com/Mueve-TEC/soltec-localdev


# Para instalar docker

clonar repo para intalar docker 

cd docker
sudo ./install_ubuntu.sh

### Agregar el usuario personal al grupo docker 

sudo adduser <usuario> docker

### levantar el docker

docker-compose up -d


# Ingresar al navegador

localhost:8069



Para incorporar submoduleos 


git submodule add -b 16.0 http://github.com/OCA/helpdesk

para copiar donde corresponde la carpeta correspondiente al módulo ejecutar el escritp

./copy_addons.sh



# Elminiar la información de los contenedores. 
docker-compose down

docker-compose build --no-cache

# levantamos de nuevo el servicio 
docker-compose up -d




### para usar la imagen de Mueve-soltec hay que editar el archivo 



 #para listar las imagenes que tenemos generaldas

 docker image ls





dockercompose down

Ediamos docker compose.yml


# para reiniciar la base de datos -- resetear 

docker- compose down 


## para leer los volumenes. 
docker volume ls


docker-compose-up -d 


docker volume 



