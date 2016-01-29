# Introducción

Este repositorio alberga un *contenedor Docker* para "[Observium](http://www.observium.org/)". Lo tienes automatizado en el registry hub de Docker [luispa/base-observium](https://registry.hub.docker.com/u/luispa/base-observium/) con los fuentes en GitHub: [base-observium](https://github.com/LuisPalacios/base-observium). En mi caso estoy usando este contenedor en combinación con otros. Consulta este [apunte técnico sobre varios servicios en contenedores Docker](http://www.luispa.com/?p=172) para acceder a otros contenedores Docker y sus fuentes en GitHub.


## Ficheros

* **Dockerfile**: Para crear la base de servicio.
* **do.sh**: Programa que se ejecuta al arrancar el contenedor y lo configura
* **000-default.conf**: Fichero de configuración Apache
* **crontab.txt**: Configuración crontab para Observium (polls, discoveries...)
* **mysql_wait_ready**: Script que utilizo desde do.sh para esperar que mysql termine de arrancar


## Instalación

### desde Docker

Para usar esta imagen desde el registry de docker hub

    $ docker pull luispa/base-observium

### manualmente

Si prefieres crear la imagen de forma manual en tu sistema, primero clónala desde Github para luego ejecutar el build

    $ git clone https://github.com/LuisPalacios/base-observium.git
    $ docker build -t luispa/base-observium ./


# Personalización

La primera vez que arranques el contenedor el script do.sh analizará si es necesario instalar Observium y configurar todo lo necesario. Si por el contrario encuentra una estructura ya existente entonces la utilizará.


### Volúmenes

Directorios persistente que utiliza este contenedor. Deben apuntar a un directorio de tu HOST.

- "(Directorio HOST raíz)/observium/mysql:/var/lib/mysql"
- "(Directorio HOST raíz)/observium:/opt/observium"
- "(Directorio HOST raíz)/tz:/config/tz"

Un ejemplo donde he colocado todo debajo de /Apps/data (en mi Host)

- "/Apps/data/observium/mysql:/var/lib/mysql"
- "/Apps/data/observium/opt:/opt"
- "/Apps/data/tz:/config/tz"

Antes de arrancar el contenedor es necesario crear al menos estos directorios.

    $ mkdir -p /Apps/data/observium/mysql
    $ mkdir -p /Apps/data/observium/opt

Para que el timezone te funcione bien, crea el directorio /Apps/data/tz y dentro de él crear el fichero timezone.

    $ mkdir -p /Apps/data/tz
    $ echo "Europe/Madrid" > /config/tz/timezone


Los directorios anteriores debes montarlos con la opción -v (arranque manual) o bien usando fig, a continuación un ejemplo:


### Ejemplo de configuración fig.yml

    observium:
      image: luispa/base-observium

    environment:
      MAIL_TO:             "tu_usuario@dominio.com"
      DB_USER:             "obsera"
      DB_PASS:             "observapass"
      OBSERVIUM_USER:      "mi_admin"
      OBSERVIUM_PASS:      "observador"
      SQL_ROOT_PASSWORD:   "superpassword"

    expose:
      - "80"

    ports:
      - "22002:3306"

    volumes:
      - "/Apps/data/observium/mysql:/var/lib/mysql"
      - "/Apps/data/observium/opt:/opt"
      - "/Apps/data/tz:/config/tz"

    command: /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf



### Ejecución con fig


Un ejemplo de ejecución con fig sería ejecutar lo siguiente en el directorio donde está el fichero fig.yml anterior:

    $ fig up -d
    :


### Configuración adicional

Una vez que ejecutas el contenedor podrás acceder vía Web al mismo, usar el usuario "OBERSVIUM_USER" y su contraseña para configurarlo.

Tienes la alternativa de "entrar" con una shell en el contenedor y ejecutar algunos comandos manualmente para acelerar el descubrimiento y configuraión inicial. Por ejemplo:

    $ docker ps -a | grpe -i observium  (localizo el ID del contenedor)
    $ docker exec -it 42567234bef8 bash

    root@42567234bef8:/opt/observium#      <== Ya estás dentro del contenedor


Añadir un usuario y dispositivo adicionales:

root@42567234bef8:/opt/observium# ./adduser.php <username> <password> <level>

Añadir un dispositivo

root@42567234bef8:/opt/observium# ./add_device.php <hostname> <community> v2c

Realizar el Discovery y Poll iniciales

root@42567234bef8:/opt/observium# ./discovery.php -h all
root@42567234bef8:/opt/observium# ./poller.php -h all
