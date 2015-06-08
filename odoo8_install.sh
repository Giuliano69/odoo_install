#!/bin/bash

set -o errtrace
trap 'err_handler $?' ERR
    
# v1.0.e install odoo v8 or OCB v8 and italian localization

# this script  is free software: you can redistribute it and/or modify
#it under the terms of the GNU Affero General Public License as
#published by the Free Software Foundation, either version 3 of the
#License, or (at your option) any later version.

# credits
# http://www.theopensourcerer.com/2014/09/how-to-install-openerp-odoo-8-on-ubuntu-server-14-04-lts/
# http://wiki.odoo-italia.org/doku.php/area_tecnica/installazione/v8.0_ubuntu_14.04/odoo
# http://www.odoo-italia.org/media/kunena/attachments/598/installa.txt
# https://github.com/loftuxab/alfresco-ubuntu-install/blob/master/alfinstall.sh
# https://gist.github.com/yelizariev/2abdd91d00dddc4e4fa4

#--------------------------------------------------
#fixed parameters
#openerp
ODOO_USER="odoo"
ODOO_HOME="/opt/$ODOO_USER"

ODOO_GIT_CMD="https://www.github.com/odoo/odoo --depth 1 --branch 8.0 --single-branch"
ITALY_GIT_CMD="https://github.com/OCA/l10n-italy.git"
OCB_GIT_CMD="https://github.com/OCA/OCB --depth 1 --branch 8.0 --single-branch"
GIT_CMD=""
ODOO_INST_DIR=""
ODOO_VERSION="8.0"

ODOO_PG_PWD="dbpassword"
ODOO_ADMIN_PWD="adminpassword"
DAEMON=""


#[Note: If you want to run multiple versions of Odoo/OpenERP on the same server, 
#the way I do it is to create multiple users with the correct version number as part of the name, 
#e.g. openerp70, openerp61 etc. If you also use this when creating the Postgres users too, 
#you can have full separation of systems on the same server. I also use similarly named home directories, 
#e.g. /opt/odoo80, /opt/openerp70, /opt/openerp61 and config and start-up/shutdown files. 
#You will also need to configure different ports for each instance or else only the first will start.]
#--------------------------------------------------

# Color variables
txtund=$(tput sgr 0 1)          # Underline
txtbld=$(tput bold)             # Bold
bldred=${txtbld}$(tput setaf 1) #  red
bldgre=${txtbld}$(tput setaf 2) #  red
bldblu=${txtbld}$(tput setaf 4) #  blue
bldwht=${txtbld}$(tput setaf 7) #  white
txtrst=$(tput sgr0)             # Reset
info=${bldwht}*${txtrst}        # Feedback
pass=${bldblu}*${txtrst}
warn=${bldred}*${txtrst}
ques=${bldblu}?${txtrst}
#--------------------------------------------------
# cli functions
echoblue () {
  echo "${bldblu}$1${txtrst}"
}
echowhite () {
  echo "${bldwht}$1${txtrst}"
}
echored () {
  echo "${bldred}$1${txtrst}"
}
echogreen () {
  echo "${bldgre}$1${txtrst}"
}

function header_echo {
	UPPER=${1^^}
    echoblue "# -----------------------------------------------------------------------------"
    echowhite "# ---------------------- eseguo ora la funzione: --------  $UPPER --  "
    echoblue "# -----------------------------------------------------------------------------"
}


# -----------------------------------------------------------------------------
# *****************************************************************************
# -----------------------------------------------------------------------------
function startup {
    header_echo $FUNCNAME
    #----------------------------------------------------------------------
	# Only root can run the script. Make sure root is executing the script
	if [[ $EUID -ne 0 ]]
	then
	   echo "This script must be run as root - Installation Failed" 1>&2  	   
	   ZENITYPATH=$(which zenity)
	   if [ -n $ZENITYPATH ]
	   then  #Zenity installed
		   zenity --error --text "Installation failed! You must be logged as root! " 
	   fi
	   exit 1
	fi

	echoblue "Step 1.0 verifichiamo se l'utente $ODOO_USER esiste già"
    # verifichiamo se l'utente $ODOO_USER esiste già
	ret=false
	getent passwd $ODOO_USER >/dev/null 2>&1 && ret=true
	    
	if $ret
	then  # Control will enter here if $ODOO_USER exists.
		echored "ATTENZIONE ! utente $ODOO_USER già presente; probabilemnte avete già installato Odoo"
		echored "rimuovete l'utente e la sua cartella home con il comando: sudo userdel -r $ODOO_USER"
		echored "il programma termina"
		exit 1
	else
		echoblue "Create the Odoo user that will own and run the application"
		adduser --system --home="$ODOO_HOME" --group "$ODOO_USER"
		echogreen "L'Utente $ODOO_USER è stato creato nel sistema "
		echogreen "La cartella home per $ODOO_USER è $ODOO_HOME"
	fi



	echoblue "Step 1.1 verifichiamo la distribuzione linux e la sua versione"
	#find which debian version and CPU we are using 
	LINUX_DIST=$(lsb_release --id --short) 
	DISTRIB_REL=$(lsb_release --release --short) 
	CPUTYPE=$(uname --machine) 
		
	case "$LINUX_DIST" in
		Ubuntu)
				if [ "$DISTRIB_REL" == "14.04" ]
				then
					echogreen "Distribuzione linux Ubuntu $DISTRIB_REL $CPUTYPE correttamente rilevata"
				else
					echored "Distribuzione linux Ubuntu $DISTRIB_REL  $CPUTYPE NON supportata"
					echored "il programma termina!"
					exit 1
				fi
				;;
		Debian)
				if [ "$DISTRIB_REL" == "7.8" ]
				then
					if [ "$CPUTYPE" == "armv7l" ]
					then
						echogreen "Distribuzione linux Raspian su  Pi 2 correttamente rilevata"
					else
						echored "Distribuzione linux Debian $DISTRIB_REL su CPU $CPUTYPE NON supportata"
						echored "il programma termina!"
						exit 1
					fi
				else
					echored "Distribuzione linux Debian $DISTRIB_REL NON supportata"
					echored "il programma termina!"
					exit 1
				fi
				# potremmo supportare in futuro la versione Debian 8 (Jessie) ???
				;; 
		*) 
				# altra distribuzione, non debian e non ubuntu
				echored "Distribuzione $LINUX_DIST non supportata"
				exit 1
				;;
	esac

	
	echoblue "Step 1.3 aggiorniamo i repository e i pacchetti disponibili"
	apt-get update
	apt-get upgrade --assume-yes
		  
 	echoblue "---- verifichiamo se il programma git è installato ----"
	#verifichiamo che git sia installato ed eventualmente installiamolo
	if command -v git >/dev/null 2>&1
	then # git found
		echogreen "il programma git è già installato"	
	else
		echored "il programma git NON è installato"
		echoblue "installiamo git"
		sudo apt-get install git --assume-yes
		
	fi	
	   
	   
  echoblue "Step 1.4 Abilitiamo il server ssh e samba"   
  # -------------------------- pacchetti di Samba (Windows S_tream M_essage B_lock network file system)
  apt-get install  samba system-config-samba --assume-yes
  apt-get install  samba-doc samba-doc-pdf --assume-yes

  # -------------------------- secure shell server e client
  apt-get install openssh-server --assume-yes
  apt-get install  ssh --assume-yes
  return 0
}
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
function install_postgres {
	# http://magicmonster.com/kb/db/postgres/users.html
	# http://www.postgresql.org/docs/current/static/app-createuser.html
    header_echo $FUNCNAME
    echoblue "Step 3. Install and configure the database server, PostgreSQL"
    apt-get install postgresql pgadmin3 postgresql-contrib --assume-yes
    
    #troviamo la versione installata di Posgtres
    PGVERSION=$(ls /etc/postgresql/ )  
    
    echoblue "Step 3.1 Connection settings"
    # CONNECTION settings - file: postgresql.conf
    # permettiamo che il db server, accetti connessioni da tutta la rete locale
    # sostituzione con sed, --in-place sostituzione, globale
    sed --in-place s/"#listen_addresses = 'localhost'"/"listen_addresses = '*'"/g /etc/postgresql/$PGVERSION/main/postgresql.conf
		
    echoblue "Step 3.2 Authentication settings"
    # AUTHENTICATION settings - file: pg_hba.conf
    # local peer authentication to connect to Postgres server is default
    # http://www.postgresql.org/docs/current/static/auth-methods.html
	#http://www.postgresql.org/docs/9.3/static/auth-pg-hba-conf.html    
    # Allow any user from host 192.168.0.1 to connect to all databases
	# if the user's password is correctly supplied.	
	# TYPE  DATABASE        USER            ADDRESS                 METHOD
	#host    all        all             192.168.0.1/32        md5
	
    #trasformiamo le connessioni locali con autenticazioni peer in autenticazioni password md5
    #lasciamo la autenticazione dell'utente postgress con peer, per poter usare i comandi con l'utente postgress senza digitare password di login
    sed --in-place s/"local   all             all                                     peer"/"local   all             all                                     md5"/g  /etc/postgresql/$PGVERSION/main/pg_hba.conf
	sed --in-place '/local   all             postgres                      peer/a local   all             odoo                                     md5' /etc/postgresql/$PGVERSION/main/pg_hba.conf

#TODO
    # VERIFICARE che il netnumber di rete sia quello giusto ed utilizzarlo per gestire gli authentication settings
    #IP_ADDR=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')
	#aggiungiamo la riga nella sezione "IPv4 local connections" la possibilità di connettersi con password da tutte le macchine della lan
	#sed --in-place '/# IPv4 local connections:/a host    all        all             192.168.0.1/32        md5' /etc/postgresql/$PGVERSION/main/pg_hba.conf
    
    echoblue "reloading  postgresql DB server configuration files....."
    service postgresql reload
    
    # DB USER creation
    #ci posizioniamo in una directory con permessi di scrittura prima di accedere all'utente postgres
    OLD_DIR=`pwd`
    cd /tmp
    
    echoblue "Step 3.3 creaiamo l'utente del database Postgres;"
    echoblue "Il nome utente Postgres è $ODOO_USER e la password $ODOO_PG_PWD"
		
	sudo su - postgres bash -c "psql -c \"CREATE USER $ODOO_USER WITH PASSWORD '$ODOO_PG_PWD';\""

    #l'utente creato può creare database --createdb 
    #l'utente creato non può creare nuovi ruoli --no-createrole
    #l'utente creato non può diventare superuser --no-superuser	
	sudo su - postgres bash -c "psql -c \"ALTER USER $ODOO_USER CREATEDB  NOCREATEROLE NOSUPERUSER;\""
  
	cd "$OLD_DIR"
  
  return 0
}
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
function install_python {
    header_echo $FUNCNAME
    echoblue "Step 4. installiamo i moduli python necessari con il packet manager di sistema"
    
	apt-get install python-cups python-dateutil python-decorator python-docutils python-feedparser \
	python-gdata python-geoip python-gevent python-imaging python-jinja2 python-ldap python-libxslt1 \
	python-lxml python-mako python-mock python-openid python-passlib python-psutil python-psycopg2 \
	python-pybabel python-pychart python-pydot python-pyparsing python-pypdf python-reportlab python-requests \
	python-simplejson python-tz python-unicodecsv python-unittest2 python-vatnumber python-vobject \
	python-werkzeug python-xlwt python-yaml python-pip  --assume-yes

    echoblue "installiamo psycogreen per gestire i processi concorrenti su postgress"
    #The psycogreen package enables psycopg2 to work with coroutine libraries, 
    #using asynchronous calls internally but offering a blocking interface so that regular code can run unmodified.
	pip install psycogreen
	
	#The Google Data Python Client Library provides a library and source code
	#that make it easy to access data through Google Data APIs
	echoblue "The Google data Python client library makes it easy to interact with Google services through the Google Data APIs. "
	pip install gdata

	echoblue "installiamo le dipendence less (CSS) e nodejs tramite npm"
	#npm is a package manager for JavaScript, and is the default for Node.js
	#https://github.com/less/less.js/
	apt-get install npm --assume-yes
	npm install -g less
	
	#installiamo il precompilatore lessc - Attualmente NON disponibile  per Rasberry
	# come comportarsi con Debian Jessie ?
	if [ $LINUX_DIST = "Ubuntu" ]; then
               apt-get install  node-less --assume-yes
               npm install -g  less-plugin-clean-css
    fi	


	return 0
}

# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
function install_wkhtmltopdf {
	header_echo $FUNCNAME
#https://www.odoo.com/documentation/8.0/setup/install.html#deb
#https://www.odoo.com/fr_FR/forum/help-1/question/report-to-pdf-problem-81803
#to print PDF reports, you must install wkhtmltopdf yourself: 
#the actual version of wkhtmltopdf available in debian repositories does not support headers and footers 
#so it can not be installed automatically. The RECOMMENDED version is 0.12.1 and is available 
#on the wkhtmltopdf download page, in the archive section.

# SE il paccchetto wkhtml non è installato procediamo con l'installazione della vversione 0.12.1
# attualemnte gestito solo lo scaricamento per ubuntu 14.04 versione 64 e 32 bit
if [ $(dpkg-query -W -f='${Status}' wkhtmltox 2>/dev/null | grep -c "ok installed") -eq 0 ];
then	
	case "$LINUX_DIST" in
	 Ubuntu)      
		if [ "$CPUTYPE" == "x86_64" ]
		then
			# cputype = 64 bit
			echoblue "recuperiamo il pacchetto  deb wkhtmltopdf 64 bit"
	        wget http://downloads.sourceforge.net/project/wkhtmltopdf/archive/0.12.1/wkhtmltox-0.12.1_linux-trusty-amd64.deb
	        echoblue "installiamo il pacchetto wkhtmltopdf"
	        dpkg -i wkhtmltox-0.12.1_linux-trusty-amd64.deb
	        return 0
	    elif [ "$CPUTYPE" == "i686" ]
	    then
			# cputype = 32 bit
			echoblue "recuperiamo il pacchetto  deb wkhtmltopdf 32 bit"
	        wget http://downloads.sourceforge.net/project/wkhtmltopdf/archive/0.12.1/wkhtmltox-0.12.1_linux-trusty-i386.deb
	        echoblue "installiamo il pacchetto wkhtmltopdf"
	        dpkg -i wkhtmltox-0.12.1_linux-trusty-i386.deb
	        return 0
	    fi
	    ;;
	 Debian)       
	    if [ "$CPUTYPE" = "armv7l" ]
	    then
			# ARM7 - Raspberry 
			echored "installiamo la versione 0.9. Ci saranno problemi di cattivo funzionamento con le stampe in pdf"
			#apt-get install wkhtmltopdf -y
			return 0
	    fi
	    ;;
	esac
	
else
	echored "pacchetto wkhtmltox già installato!"
	dpkg-query -W wkhtmltox
	return 1
fi
}
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
function create_odoo_server_conf {
	header_echo $FUNCNAME
	
	
	echoblue "creiamo il file di configurazione del server odoo ..."
	# bash here document
	cat <<- EOF_TAG > $1
[options]
addons_path = $ODOO_INST_DIR/openerp/addons,$ODOO_INST_DIR/addons,$ODOO_HOME/custom/addons
admin_passwd = $ODOO_ADMIN_PWD
auto_reload = False
csv_internal_sep = ,
data_dir = /opt/odoo/.local/share/Odoo
db_host = False
db_maxconn = 64
db_name = False
db_password = $ODOO_PG_PWD
db_port = False
db_template = template1
db_user = $ODOO_USER
dbfilter = .*
debug_mode = False
demo = {}
email_from = False
geoip_database = /usr/share/GeoIP/GeoLiteCity.dat
import_partial = 
limit_memory_hard = 2684354560
limit_memory_soft = 2147483648
limit_request = 8192
limit_time_cpu = 60
limit_time_real = 120
list_db = True
log_db = False
log_db_level = warning
log_handler = :INFO
log_level = info
logfile = False
logrotate = False
longpolling_port = 8072
max_cron_threads = 2
osv_memory_age_limit = 1.0
osv_memory_count_limit = False
pg_path = None
pidfile = False
proxy_mode = False
reportgz = False
secure_cert_file = server.cert
secure_pkey_file = server.pkey
server_wide_modules = None
smtp_password = False
smtp_port = 25
smtp_server = localhost
smtp_ssl = False
smtp_user = False
syslog = False
test_commit = False
test_enable = False
test_file = False
test_report_directory = False
timezone = False
translate_modules = ['all']
unaccent = False
without_demo = False
workers = 0
xmlrpc = True
xmlrpc_interface = 
xmlrpc_port = 8069
xmlrpcs = True
xmlrpcs_interface = 
xmlrpcs_port = 8071

EOF_TAG

echoblue "File $1 creato"

chown $ODOO_USER:$ODOO_USER $1
chmod 640 $1

}
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
function install_odooServer {
	header_echo $FUNCNAME

    echoblue "Step 5.0 Scegliamo quale versione Odoo installare "

	title="Scegliete la distrbuzione Odoo da installare"
	prompt="Sclegliente una delle seguenti versioni Odoo:"
	options=("Odoo v8 - alias OpenERP" "OCB - Odoo Comunity BackPort" )

	#testiamo se siamo in una shell in xorg e possiamo usare zenity
	if [ "$DISPLAY" ] || [ "$WAYLAND_DISPLAY" ] || [ "$MIR_SOCKET" ]
	then	#shell grafica
		while opt=$(zenity --title="$title" --text="$prompt" --list --column="Options" "${options[@]}"); do	
	        echo "value opt: $opt"           
		    case "$opt" in
		    "${options[0]}" ) 	
				zenity --info --text="Avete scelto $opt"
				GIT_CMD=$ODOO_GIT_CMD
				ODOO_INST_DIR="$ODOO_HOME/odoo8"
				break
				;;
		    "${options[1]}" ) 
				zenity --info --text="Avete scelto $opt"
				GIT_CMD=$OCB_GIT_CMD
				ODOO_INST_DIR="$ODOO_HOME/ocb8"
				break
				;;
		    *) zenity --error --text="Scelta non valida, prego riprovare.";;
		    esac
		done
	else	#modalità testuale
		#set select prompt
		PS3="$prompt"
		echo "$title"
		
		select opt in "${options[@]}" "Abbandona"; do 
		
		    case "$REPLY" in
		
		    1 ) echo "You picked $opt which is option $REPLY"
				GIT_CMD=$ODOO_GIT_CMD
				ODOO_INST_DIR="$ODOO_HOME/odoo8"
				break
				;;
		    2 ) echo "You picked $opt which is option $REPLY"
				GIT_CMD=$OCB_GIT_CMD
				ODOO_INST_DIR="$ODOO_HOME/ocb8"
				break
				;;
		
		    $(( ${#options[@]}+1 )) ) echo "Arrivederci!"; exit;;
		    *) echo "Scelta non valida, prego riprovare.";continue;;
		
		    esac
		
		done
	fi	

	DAEMON=$ODOO_INST_DIR/openerp-server
	echoblue "Step 5.1 Istalliamo  Odoo8 / OCB8 Opensever"

	
	echoblue "---- Create custom module directory ----"
	#creiamo la cartella custom/addons conterrà dei link simbolici 
	# ai moduli che ci interessa importare nell ERP
	mkdir "$ODOO_HOME/custom"
	mkdir "$ODOO_HOME/custom/addons"	
	chown -R $ODOO_USER:$ODOO_USER $ODOO_HOME/*
  
    echo "cd $ODOO_HOME"
	echo "git clone $GIT_CMD $ODOO_INST_DIR"

	cd $ODOO_HOME
	git clone $GIT_CMD $ODOO_INST_DIR

	#creiamo un nuovo file di configurazione 
	create_odoo_server_conf "$ODOO_INST_DIR/odoo-server.conf"
	
	#copiamo il file in /etc, per il servizio da lanciare all'avvio e settiamo i permessi
	cp $ODOO_INST_DIR/odoo-server.conf /etc/odoo-server.conf
	chown $ODOO_USER:$ODOO_USER /etc/odoo-server.conf
	chmod 640 /etc/odoo-server.conf

	#creiamo la directory per il log file
	mkdir /var/log/$ODOO_USER
	chown $ODOO_USER:$ODOO_USER /var/log/$ODOO_USER
		
	#aggiungiamo il percorso per il log file
	echo "logfile = /var/log/$ODOO_USER/odoo-server.log" >> /etc/odoo-server.conf
		

}
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
function install_italian_addon {
    header_echo $FUNCNAME 	
    #https://www.odoo.com/forum/help-1/question/how-do-you-install-a-module-578
    #https://www.odoo.com/forum/help-1/question/custom-modules-folder-path-29358
    
	if [ -d "$ODOO_HOME/l10n-italy" ]; then
		# Control will enter here if directory exists.
		echored "La directory con i moduli italiani esiste già.!"
		echored "Per clonare un progetto con git la directory NON deve esistere"
		echored "La installazione del modulo italiano termina"
		return 1
	fi
	    	    
    cd $ODOO_HOME       
	git clone $ITALY_GIT_CMD
	
	#create with symbolic links in addons dir for the italian modules; 	
	cd $ODOO_HOME/l10n-italy
	pwd
	for ADDON_DIR in $(ls -d */ | tr -d "/" )
		do
			if [ "$ADDON_DIR" != "__unported__" ]
			then
			echoblue "creating symbolic link: from $ODOO_HOME/l10n-italy/$ADDON_DIR to $ODOO_HOME/custom/addons/$ADDON_DIR "
			ln -s $ODOO_HOME/l10n-italy/"$ADDON_DIR"  $ODOO_HOME/custom/addons/"$ADDON_DIR"
			fi
		done			
		
	#TODO
		
	#echoblue "get other addons you like......"
	#https://github.com/yelizariev/pos-addons.git	

	#aggiornare file configurazione open-erp sulla posizione degli ulteriori add-on
	#sed --in-place s/"addons_path = "/"addons_path = your_path_here, "/g $ODOO_INST_DIR/.openerp_serverrc
	#chown -R $ODOO_USER:$ODOO_USER $ODOO_HOME/*
				
	return 0
	} 
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
function install_initscript {
	header_echo $FUNCNAME
	echoblue "Step 7. Installing the boot script"
	
	echoblue "creiamo lo script odoo-server per il lancio del servizio all'avvio sistema..."
	# bash here document
	cat <<- 'EOF_TAG1' > /etc/init.d/odoo-server
#!/bin/sh

### BEGIN INIT INFO
# Provides:             odoo-server
# Required-Start:       $remote_fs $syslog
# Required-Stop:        $remote_fs $syslog
# Should-Start:         $network
# Should-Stop:          $network
# Default-Start:        2 3 4 5
# Default-Stop:         0 1 6
# Short-Description:    Enterprise Resource Management software
# Description:          odoo is a complete ERP and CRM software.
### END INIT INFO

PATH=/bin:/sbin:/usr/bin
EOF_TAG1

echo "DAEMON=$DAEMON" >> /etc/init.d/odoo-server

cat <<- 'EOF_TAG2' >> /etc/init.d/odoo-server
NAME=odoo-server
DESC=odoo-server

# Specify the user name (Default: odoo).
USER=odoo

# Specify an alternate config file (Default: /etc/odoo-server.conf).
CONFIGFILE="/etc/odoo-server.conf"

# pidfile
PIDFILE=/var/run/$NAME.pid

# Additional options that are passed to the Daemon.
DAEMON_OPTS="-c $CONFIGFILE"

[ -x $DAEMON ] || exit 0
[ -f $CONFIGFILE ] || exit 0

checkpid() {
    [ -f $PIDFILE ] || return 1
    pid=`cat $PIDFILE`
    [ -d /proc/$pid ] && return 0
    return 1
}

case "${1}" in
        start)
                echo -n "Starting ${DESC}: "

                start-stop-daemon --start --quiet --pidfile ${PIDFILE} \
                        --chuid ${USER} --background --make-pidfile \
                        --exec ${DAEMON} -- ${DAEMON_OPTS}

                echo "${NAME}."
                ;;

        stop)
                echo -n "Stopping ${DESC}: "

                start-stop-daemon --stop --quiet --pidfile ${PIDFILE} \
                        --oknodo

                echo "${NAME}."
                ;;

        restart|force-reload)
                echo -n "Restarting ${DESC}: "

                start-stop-daemon --stop --quiet --pidfile ${PIDFILE} \
                        --oknodo
      
                sleep 1

                start-stop-daemon --start --quiet --pidfile ${PIDFILE} \
                        --chuid ${USER} --background --make-pidfile \
                        --exec ${DAEMON} -- ${DAEMON_OPTS}

                echo "${NAME}."
                ;;

        *)
                N=/etc/init.d/${NAME}
                echo "Usage: ${NAME} {start|stop|restart|force-reload}" >&2
                exit 1
                ;;
esac

exit 0
EOF_TAG2

echoblue "File /etc/init.d/odoo-server creato"

chmod 755 /etc/init.d/odoo-server
chown root: /etc/init.d/odoo-server

# il servizio verrà lanciato ad ogni riavvio
echoblue "installiamo il servizio di sistema odoo..."
update-rc.d odoo-server defaults

service odoo-server start

}

# -----------------------------------------------------------------------------
# ---------------------------MAIN PROGRAM--------------------------------------
# -----------------------------------------------------------------------------

startup
install_postgres
install_python
install_wkhtmltopdf
install_odooServer
install_italian_addon
install_initscript
exit 0

