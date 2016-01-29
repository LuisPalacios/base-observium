#!/bin/bash
#
# Punto de entrada para el servicio GIT
#
# Activar el debug de este script:
# set -eux
#

# Averiguo si necesito configurar por primera vez
#
CONFIG_DONE="/.config_observium_done"
NECESITA_PRIMER_CONFIG="si"
if [ -f ${CONFIG_DONE} ] ; then
    NECESITA_PRIMER_CONFIG="no"
fi


##################################################################
#
# PREPARAR timezone
#
##################################################################
# Workaround para el Timezone, en vez de montar el fichero en modo read-only:
# 1) En el DOCKERFILE
#    RUN mkdir -p /config/tz && mv /etc/timezone /config/tz/ && ln -s /config/tz/timezone /etc/
# 2) En el Script entrypoint:
if [ -d '/config/tz' ]; then
    dpkg-reconfigure -f noninteractive tzdata
    echo "Hora actual: `date`"
fi
# 3) Al arrancar el contenedor, montar el volumen, a contiuación un ejemplo:
#     /Apps/data/tz:/config/tz
# 4) Localizar la configuración:
#     echo "Europe/Madrid" > /Apps/data/tz/timezone



##################################################################
#
# VARIABLES OBLIGATORIAS
#
##################################################################


## Contraseña del usuario root en MySQL Server
#
if [ -z "${SQL_ROOT_PASSWORD}" ]; then
    echo >&2 "error: falta la contraseña de root para MYSQL: SQL_ROOT_PASSWORD"
    exit 1
fi

## Servidor:Puerto por el que escucha el agregador de Logs (fluentd)
#
if [ -z "${FLUENTD_LINK}" ]; then
    echo >&2 "error: falta el Servidor:Puerto por el que escucha fluentd, variable: FLUENTD_LINK"
    exit 1
fi
fluentdHost=${FLUENTD_LINK%%:*}
fluentdPort=${FLUENTD_LINK##*:}

## Variables para crear la BD en MySQL
#
if [ -z "${DB_USER}" ]; then
    echo >&2 "error: falta la variable DB_USER"
    exit 1
fi
if [ -z "${DB_PASS}" ]; then
    echo >&2 "error: falta la variable DB_PASS"
    exit 1
fi

if [ -z "${MAIL_TO}" ]; then
    echo >&2 "error: falta la variable MAIL_TO"
    exit 1
fi

## Variables para el usuario administrador de Observium
#
if [ -z "${OBSERVIUM_USER}" ]; then
    echo >&2 "error: falta la variable OBSERVIUM_USER"
    exit 1
fi
if [ -z "${OBSERVIUM_PASS}" ]; then
    echo >&2 "error: falta la variable OBSERVIUM_PASS"
    exit 1
fi


##################################################################
#
# PREPARAR EL CONTAINER POR PRIMERA VEZ
#
##################################################################

# Necesito configurar por primera vez?
#
if [ ${NECESITA_PRIMER_CONFIG} = "si" ] ; then

	############
	#
	# Observium
	#
	############

        # Descargo Observium y lo configuro si no esta ya hecho
	cd /opt
	if [ ! -f '/opt/observium/config.php' ]; then

	    mkdir -p /opt/observium
	    cd /opt
	    wget http://www.observium.org/observium-community-latest.tar.gz
	    tar zxf observium-community-latest.tar.gz
	    cd /opt/observium
	    cp config.php.default config.php

	    # Cambio user/pass/db de la configuracion MySQL

	    sed -i "s/USERNAME/${DB_USER}/g" config.php
	    sed -i "s/PASSWORD/${DB_PASS}/g" config.php
	    sed -i "s/user@your-domain/${MAIL_TO}/g" config.php

	   # Done
	   echo "Done OBSERVIUM Install"

	fi

	############
	#
	# MySql
	#
	############

        chown -R mysql:mysql /var/lib/mysql

        # Creo la estructura MySQL si no existe...
        if [ ! -d '/var/lib/mysql/mysql' ]; then

	    # Necesito la contraseña de root, si no la tengo aborto...
            if [ -z "${SQL_ROOT_PASSWORD}" ]; then
		echo >&2 "error: MySQL no está inicializado y falta la contraseña de root, variable: SQL_ROOT_PASSWORD"
		exit 1
	    fi

            # Creo la estructura
	    mysql_install_db --user=mysql --datadir=/var/lib/mysql

	    # Creo root y borro la base de datos test
	    TEMP_FILE='/tmp/mysql-first-time.sql'

	    cat > "$TEMP_FILE" <<-EOSQL
		DELETE FROM mysql.user ;
		CREATE USER 'root'@'%' IDENTIFIED BY '${SQL_ROOT_PASSWORD}' ;
		GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION ;
		DROP DATABASE IF EXISTS test ;
		CREATE USER '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}' ;
                CREATE DATABASE observium DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci ;
                GRANT ALL PRIVILEGES ON observium.* TO '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}' ;
		FLUSH PRIVILEGES ;
	EOSQL

	   # Start the DB to populate the Observium's schema
	   /usr/sbin/mysqld --datadir=/var/lib/mysql --user=mysql &
	   mysqld_process_pid=$(echo "$(ps -C mysqld -o pid=)" | sed -e 's/^ *//g' -e 's/ *$//g')

	   # Let mysqld be ready
	   /mysql_wait_ready.sh

	   # Assign root password
	   mysqladmin -u root -h localhost password ${SQL_ROOT_PASSWORD}

	   # Prepare MySQL
	   mysql --user=root --password=${SQL_ROOT_PASSWORD} -h localhost < ${TEMP_FILE}

	   # Setup the MySQL database and insert the default schema
	   cd /opt/observium
	   ./discovery.php -u

	   # Vuelta con Observium
	   cd /opt/observium

	    # Create required directories
	    if [ ! -d '/opt/observium/logs' ]; then
		mkdir /opt/observium/logs
	    fi
	    if [ ! -d '/opt/observium/rrd' ]; then
		mkdir rrd
		chown www-data:www-data rrd
	    fi

	    # Add Initial Admin user (10=admin)
	    ./adduser.php ${OBSERVIUM_USER} ${OBSERVIUM_PASS} 10

	   # Kill MySQL
	   sleep 1
	   kill -TERM `echo ${mysqld_process_pid}`
	   sleep 3

	   # Done
	   echo "Done MySQL"

	fi

	############
	#
	# crontab
	#
	############
	crontab -r
	cp /crontab.txt /etc/cron.d/observium
	chmod 0644 /etc/cron.d/observium
	touch /var/log/cron.log


	############
	#
	# Supervisor
	#
	############
	echo "Configuro supervisord.conf"

	cat > /etc/supervisor/conf.d/supervisord.conf <<-EOSUPER
[unix_http_server]
file=/var/run/supervisor.sock 					; path to your socket file

[inet_http_server]
port = 0.0.0.0:9001								; allow to connect from web browser to supervisord

[supervisord]
logfile=/var/log/supervisor/supervisord.log 	; supervisord log file
logfile_maxbytes=50MB 							; maximum size of logfile before rotation
logfile_backups=10 								; number of backed up logfiles
loglevel=error 									; info, debug, warn, trace
pidfile=/var/run/supervisord.pid 				; pidfile location
minfds=1024 									; number of startup file descriptors
minprocs=200 									; number of process descriptors
user=root 										; default user
childlogdir=/var/log/supervisor/ 				; where child log files will live

nodaemon=false 									; run supervisord as a daemon when debugging
;nodaemon=true 									; run supervisord interactively (production)

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///var/run/supervisor.sock		; use a unix:// URL for a unix socket

# MYSQL
[program:mysql]
process_name = mysql
command=/usr/sbin/mysqld --datadir=/var/lib/mysql --user=mysql
startsecs = 0
autorestart = true
redirect_stderr=true
stdout_logfile=/opt/observium/logs/mysql.out.log
stderr_logfile=/opt/observium/logs/mysql.err.log

# APACHE
[program:apache]
process_name = apache2
command=/bin/bash -c "source /etc/apache2/envvars && exec /usr/sbin/apache2 -DFOREGROUND"
autostart=true
autorestart=true
startretries=1
startsecs=1
redirect_stderr=true
stdout_logfile=/opt/observium/logs/apache.out.log
stderr_logfile=/opt/observium/logs/apache.err.log
user=root
killasgroup=true
stopasgroup=true

# CRON
[program:cron]
command=/bin/bash -c "/usr/sbin/cron -f"
autostart=true
autorestart= true
user=root
redirect_stderr=true
stdout_logfile=/opt/observium/logs/cron.out.log
stderr_logfile=/opt/observium/logs/cron.err.log


## En caso de debug
#[program:sshd]
#process_name = sshd
#command=/usr/sbin/sshd -D
#startsecs = 0
#autorestart = true

EOSUPER

    #
    # Creo el fichero de control para que el resto de
    # ejecuciones no realice la primera configuración
    > ${CONFIG_DONE}

fi


##################################################################
#
# EJECUCIÓN DEL COMANDO SOLICITADO
#
##################################################################
#
exec $@
