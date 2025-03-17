#!/bin/bash
#bash script created for the Odoo v18 /v16 installation on Ubuntu 24.04 system

#Il presente script vuole effettuare una installazione di Odoo 18 OCB su un sistema Ubuntu 24.04
#Lo script è ispirato da https://gitlab.com/PNLUG/Odoo/odoo_iso/-/blob/master/build_odoo_ita.sh

#Descrizione 
#le varie fasi di installazione sono scomposte in procedure per essere facilmente identificabili e modificabili
#la sequenza di installazione e relative procedure sono:
#
#- veririca  preliminare che l'installazione sia su un sistema Ubuntu 24.04, con privilegi root
#- install_packages() : - installazione dei programmi e librerire di sistema necessari
#- create_users(): creazione dello user proprietario di odoo ($user) con relativa home in /opt, creazione dell'utente postgres ($user)
#- clone_odoo():  - download da github della versione $odoover di odoo OCB
#- clone_repos(): - download da github dei moduli OCA previsti nella variabile $ocarepos; 
#                   rimuove dal filesystem eventuali moduli in  $oca_black_list_repo per problemi con dipendenze; 
#                   aggiunge il modulo full_accounting_activation
#- create_venv(): - prepara un virtualenv per odoo, caricando anche i moduli python richiesti da tutti i repo scaricati con clone_repos()
#- create_odoo_db(): - crea due database in postgres:  ${database} e ${database}_demo con owner l'utente $user (odoo)
#- setup_config_and_log(): crea il file di configurazione per odoo in /etc/odoo partendo dal template OCB/debian/odoo.conf
#                          crea un file vuoto per i log in /var/odoo 
#                           veriica se il file di config è già esistente e se gli addon_path  già inseriti contengono già i dati da accodare
#- install_base_and_core_addons():lancia la procedura di installazione con odoo-bin, sui database  ${database}_demo e  ${database}
#                         installando:
#                         - il modulo base di Odoo
#                         - i moduli core di Odoo (OCB/addons), elencati nella variabile  $coreaddons
#                         - i moduli custom (addons/custom) , essenzialmente il full_accounting_activation
#- install_oca_addons(): rintraccia tutti i moduli di OCA (addons/OCA) scaricati precedentemente nei repo clonati con la procedura clone_repos(), 
#                         e aggiunge i retativi path nel file di configurazione
#                        
#- odoo_service_enable(): #rende il servizio odoo un daemon di system, creando un file di configurazione per systemctl e attivandolo
#
#
# sono presenti funzioni di debug (precedute dal prefisso debug_ ), utilizzate per il test dello script, 
# debug_add_single_repo()           scarica da github un singolo repo e rigenera il file di configurazione odoo
# debug_odoo_service_disable()      disabilita il servizio daemon di odoo
# debug_remove_odoo()               cancella i database installati, rimuove l'utente odoo con la relativa directory e i repo scaricati
#                                   rimuove i file di configurazione e di log
 
cat >/dev/null << EOD
La struttura delle directory qui proposta per gestire l'installazione multiversione è la seguente:

 /opt/odoo 
         |__ <VERSIONE>.0
                |__ OCB
                |  |__ addons      [core add-ons directory shipped with the source]
                |  |
                |  |__ odoo
                |     |
                |     |___ addons  [base add-ons directory]
                |
                |__ venv<VERSIONE>
                |__ addons     
                         |__OCA
                         |    |_ repo_oca_1
                         |    |_ repo_oca_2
                         |    |_ ...
                         |
                         |__ custom
                                  |_repo_custom_1
                                  |_repo_custom_2
EOD
    

# Only root can run the script. Make sure root is executing the script
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2   
   exit 1
fi 

#find which ubuntu version we are using 
UBUNTUVERSION=`lsb_release -ar 2>/dev/null | grep -i release | cut -s -f2`
if [[ $UBUNTUVERSION != "24.04" ]]; then
   echo "This installation needs Ubuntu 24.04; Found version $UBUNTUVERSION" 1>&2   
   exit 1
fi    

    
# Setup Odoo variables
odoover="18"
user="odoo"
odoodir="/opt/$user"
addonsdir="$odoodir/$odoover.0/addons"
addonsocadir="$addonsdir/OCA"
addonscustomdir="$addonsdir/custom/Giuliano69"

http_port="8069"

database="contabita$odoover"
psql_password="admin"

repodirs="$odoodir/$odoover.0/OCB/addons,$odoodir/$odoover.0/OCB/odoo/addons,"      


customaddons="full_accounting_activation"
customrepos="full_accounting_activation"

#set core addons to install (core addons are located under /OCB/addons) 
coreaddons="
l10n_it
l10n_it_edi
l10n_it_edi_doi
l10n_it_edi_ndd
l10n_it_edi_sale
l10n_it_website_sale
l10n_it_withholding
l10n_it_stock_ddt
product
account
invoicing
inventory
sales
purchase
point_of_sale
pos_epson_printer
pos_discount
repair
"

#set OCA repos to download from github, and stored in /addons/OCA/
ocarepos="
l10n-italy
account-analytic
account-closing
account-financial-tools
account-financial-reporting
account-fiscal-rule
account-invoicing
account-invoice-reporting
account-payment
account-reconcile
bank-statement-import
brand
calendar
community-data-files
e-commerce
intrastat-extrastat
mis-builder
product-attribute
report-print-send
reporting-engine
sale-reporting
server-brand
server-tools
server-ux
web
website
stock-logistics-workflow
server-env
knowledge
sale-workflow
partner-contact
"


dismisseddocarepos="
account-budgeting
account-consolidation
bank-payment
business-requirement
contract
credit-control
crm
currency
data-protection
delivery-carrier
dms
ddmrp
donation
event
field-service
fleet
helpdesk
maintenance
management-system
mis-builder-contrib
odoo-pim
product-pack
product-variant
purchase-workflow
purchase-reporting
project
project-agile
project-reporting
queue
rest-framework
rma
server-auth
server-backend
stock-logistics-barcode
stock-logistics-warehouse
stock-logistics-workflow
web-api
website-cms
website-themes
commission
connector
connector-cmis
connector-ecommerce
connector-interfaces
connector-jira
connector-magento
connector-prestashop
connector-telephony
geospatial
interface-github
iot
hr
multi-company
manufacture
manufacture-reporting
margin-analysis
operating-unit
search-engine
survey
storage
stock-logistics-tracking
stock-logistics-reporting
social
timesheet
wms
"

oca_black_list_repo="
account-analytic/hr_timesheet_analytic_tag
account-financial-tools/account_asset_management/tests
"

#--------------------------------------------------
# Color variables
txtund=$(tput sgr 0 1)          # Underline
txtbld=$(tput bold)             # Bold
bldred=${txtbld}$(tput setaf 1) #  red
bldgre=${txtbld}$(tput setaf 2) #  green
bldblu=${txtbld}$(tput setaf 4) #  blue
bldwht=${txtbld}$(tput setaf 7) #  white
txtrst=$(tput sgr0)             # Reset

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
    echowhite "# Now Running:  $UPPER   "
    echoblue "# -----------------------------------------------------------------------------"
}
function install_packages()
#installazione dei programmi e librerire di sistema necessarie
{
    header_echo $FUNCNAME
    #----------------------------------------------------------------------
    #install the main dependencies:
    sudo apt install xfonts-base xfonts-75dpi build-essential libc-dev libxslt1-dev libzip-dev libldap2-dev libsasl2-dev libpq-dev python3-pip python3-setuptools python3-dev -y
    sudo apt install git python3-venv libcups2-dev postgresql -y
    sudo apt install libxmlsec1 libxmlsec1-dev xmlsec1 -y
    #sudo apt install openssh-server libjpeg8-dev liblcms2-dev libblas-dev libatlas-base-dev  curl  fontconfig libxrender1  fail2ban  libxml2-dev  zlib1g-dev    libssl-dev libffi-dev -y
    service postgresql start

    #test wkhtml already installed
    dpkg --list | grep --quiet wkhtmltox
    if [ $?  -eq 0 ]; then 
        echoblue "webkit html2pdf  già installato."
    else
        #Download and install wkhtmltopdf:
        wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_amd64.deb
        sudo dpkg -i wkhtmltox_0.12.6.1-3.jammy_amd64.deb 
        rm wkhtmltox_0.12.6.1-3.jammy_amd64.deb 
        echogreen "pkg installato"
    fi

    

    #set git account
    gitusername="your_git_username"
    git_email="your_git_email"    
    
    #Configure git:
    #git config --global user.name $git_username
    #git config --global user.email $git_email
}
#-------------------------------------------------------

function create_users()
#creazione dello user proprietario di odoo con relativa home in /opt, creazione dell'utente postgres
{
    header_echo $FUNCNAME
    #----------------------------------------------------------------------
    #Create user %user , with home directory in /opt/odoo
    #test user $user alreadt exist or create new one
    id "$user"&>/dev/null  
    if [ $? -eq 0 ]; then 
        echoblue "Found user $user."
    else
        useradd --create-home --home-dir $odoodir --user-group  --system --shell /bin/bash $user
        echogreen "Created new user $user"
    fi

    #List database roles; Se non presente nel database, creare l'utente $user in Postgres, che sarà il proprietario dei database Odoo  
    su - postgres -c "psql  --tuples-only --command='\du' | cut --delimiter=\| --fields=1  | grep --quiet --word-regexp $user"
    if [ $? -eq 0 ]; then 
        echoblue  "Found PostresSql user $user."
    else
        su - postgres -c "createuser --createdb --no-createrole --no-superuser $user"
        #Serve mettere la pws all'utente odoo ??
        #sudo -u postgres psql -c "ALTER USER $user with PASSWORD '$psql_password';"
        #echogreen "Created PostresSql user $user with password $psql_password"
    fi
}
#-------------------------------------------------------
function clone_odoo()
#- download da github la versione $odoover di odoo OCB
{
    header_echo $FUNCNAME
    #----------------------------------------------------------------------
    mkdir -p "$odoodir/$odoover.0"
    cd "$odoodir/$odoover.0"
    
    #if we have a "backup" use it without download it from github
    if [ -d "$odoodir/$odoover.0_back" ]; then
        cp -R "$odoodir/$odoover.0_back" "$odoodir/$odoover.0"
    fi
    
    
    #clone Main Odoo code from OCB repo; or update if version $odoover already exist
    if [ ! -d "$odoodir/$odoover.0/OCB" ]; then
        echoblue "tentativo di git clone"
        git clone https://github.com/OCA/OCB.git --depth=1 --branch=$odoover.0 --single-branch $odoodir/$odoover.0/OCB
        if [ $? -ne 0 ]; then 
            echored "Failed cloning Odoo OCB Main repo, aborting"  
            exit 1
        fi
    else
        echoblue "udpate odoo branch"
        su - $user -c "git -C $odoodir/$odoover.0/OCB pull origin $odoover.0"
    fi

    echo "applyting mode and owner to cloned repository ..." 
    #recursively give directories read&execute privileges and give $user owner and group
    find "$odoodir" -type d -exec chmod 750 {}  \;
    chown -R $user:$user $odoodir
}    


#---------------------------------------------------------------

function clone_repos()
#- download da github dei moduli OCA previsti nella variabile $ocarepos; 
# rimuove dal filesystem eventuali moduli in $oca_black_list_repo per problemi con dipendenze; aggiunge il modulo full_accounting_activation
{
    header_echo $FUNCNAME
    #----------------------------------------------------------------------
    mkdir -p "$addonsocadir"
    mkdir -p "$addonscustomdir"
                
    #git clone OCA repos; or update if already exist
    for repo in $ocarepos
    do
        if [ ! -d "$addonsocadir/$repo" ]
        then
            git clone https://github.com/OCA/$repo.git --depth=1 --branch=$odoover.0 --single-branch $addonsocadir/$repo
            if [ $? -ne 0 ]; then { 
                echored "Failed cloning repo $repo, aborting"  
                exit 1
                } 
            fi
        else
            #update git as user $user to update local repository
            su - $user -c "git -C $addonsocadir/$repo pull origin $odoover.0"
            
            if [ $? -ne 0 ]; then { 
                echored "Failed UPDATING repo $repo, aborting"  
                exit 1
                } 
            fi
        fi
    done    
    
    
    #remove OCA blacklisted repo
    for repo in $oca_black_list_repo
    do
        if [ -d "$addonsocadir/$repo" ]
        then
            rm -r "$addonsocadir/$repo"
            echored "removed blacklisted repo $addonsocadir/$repo "
        fi
    done
    
    #git clone custom repos; or update if exist
    for repo in $customrepos
    do
        if [ ! -d "$addonscustomdir/$repo" ] 
        then
            # branch: main vs master
            git clone https://github.com/Giuliano69/$repo.git --depth=1 --branch="main" --single-branch $addonscustomdir/$repo 
            if [ $? -ne 0 ]; then { 
                echored "Failed cloning repo $repo, aborting"  
                exit 1
                } 
            fi
        else
            #update git as user $user to update local repository
            su - $user -c "git -C $addonscustomdir/$repo pull origin master"
            if [ $? -ne 0 ]; then { 
                echored "Failed updating repo $repo, aborting"  
                exit 1
                } 
            fi
        fi
    done
    
    echo "applyting mode and owner to cloned repository ..." 
    #recursively give directories read&execute privileges and give $user owner and group
    find "$odoodir" -type d -exec chmod 750 {} \;
    chown -R $user:$user $addonsdir
}
#-----------------------------------------------------------------------------------------------

#-----------------------------------------------------------------------------------------------
function create_venv() 
#prepara un virtualenv per odoo, caricando anche i moduli python richiesti da tutti i repo scaricati con clone_repos()
{
    header_echo $FUNCNAME
    #----------------------------------------------------------------------
    #Create an odoo-$odoover.0 VIRTUAL ENVIRONMENT directory and activate it
    #install wheel to speed installation
    if [ ! -d "$odoodir/$odoover.0/venv$odoover" ]
    then
        python3 -m venv $odoodir/$odoover.0/venv$odoover
        #chown -R $user:$user $odoodir/$odoover.0/venv$odoover
        source $odoodir/$odoover.0/venv$odoover/bin/activate
        echogreen "new virtualenv created: $VIRTUAL_ENV"
        python3 -m pip install -U pip wheel setuptools
    else
        source $odoodir/$odoover.0/venv$odoover/bin/activate
        echored "found already existing virtualenv: $VIRTUAL_ENV"
    fi
    
    #REQUIREMENTS
    echo "####### installing ALL requirements.txt under $odoodir/$odoover.0  (OCB & Addons) ######"
    find "$odoodir/$odoover.0"  -name 'requirements.txt' -exec pip3 install -r {} \;
    
    #ownership
    chown -R $user:$user $odoodir/$odoover.0/venv$odoover
}
#-----------------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------
function create_odoo_db() 
#crea due database in postgres:  ${database} e ${database}_demo con owner l'utente $user (odoo)
{
    ## install the core addons in the oddo database
    header_echo $FUNCNAME
    #----------------------------------------------------------------------
    ## Test if databases already exist or create them
    su - $user -c "psql --list --quiet --tuples-only | cut --delimiter=\| --fields=1 | grep --quiet --word-regexp $database"
    if [ $? -eq 0 ] #found $database ?
    then
        echoblue "Found database $database. Aready present !"
    else
        ## Create database 
        su - $user -c "createdb ${database} --owner=${user}"
        ## Create database with demo data
        su - $user -c "createdb ${database}_demo --owner=${user}"
        echogreen "Created databases ${database} and  ${database}_demo  with owner=${user} "
    fi
}
#----------------------------------------------------------------------------------------
#----------------------------------------------------------------------------------------

function install_base_and_core_addons() 
#installa il modulo base OCB/odoo/addons
#installa i moduli core di Odoo (OCB/addons), elencati nella variabile  $coreaddons
{
    ## install the core addons in the oddo database
    header_echo $FUNCNAME
    #----------------------------------------------------------------------
    base_addons_path="$odoodir/$odoover.0/OCB/odoo/addons"      
    core_addons_path="$odoodir/$odoover.0/OCB/addons"      
    custom_addons_path+="$addonscustomdir/"$custom_addons
    
    addons_path=${base_addons_path}","${core_addons_path}","${custom_addons_path}
    echoblue $addons_path
    setup_config_and_log  $addons_path
    

    #core addons_list to be passed to odoo-bin to install specific addons from core addons
    core_addons_list="" 
    for addon in ${coreaddons}
    do
        #check if core addon directory exist and add selected core add-ons to core_addon_list; 
        if [ -d "$odoodir/$odoover.0/OCB/addons/$addon" ]; then 
            core_addons_list+="$addon,"
        fi    
    done
    echoblue "customaddons: $customaddons"
    #append addons from custom repos list
    if [[ ! -z "$customaddons" ]]
    then
        for addon in ${customaddons}
        do
            core_addons_list+="${addon},"
        done
    fi
    #purge last "," char
    core_addons_list=${core_addons_list%,}
    core_addons_list=`echo ${core_addons_list} | sed 's/ /,/g'` 
    echoblue $core_addons_list 
    #read -p "Ready to start module initialization....Press enter to continue"

    
    su - $user -c "source $odoodir/$odoover.0/venv$odoover/bin/activate && $odoodir/$odoover.0/OCB/odoo-bin -c /etc/odoo/odoo$odoover.conf -i base,${core_addons_list} -d ${database} --without-demo=all --load-language=it_IT --stop-after-init"
    su - $user -c "source $odoodir/$odoover.0/venv$odoover/bin/activate && $odoodir/$odoover.0/OCB/odoo-bin -c /etc/odoo/odoo$odoover.conf -i base,${core_addons_list} -d ${database}_demo --load-language=it_IT --stop-after-init"
    sleep 2
    
    ## Kill process if $user process doesn't stop after initialization
    if [ $(pgrep --exact --count $user) -gt 0 ]
    then
        echored "Odoo still running... Force stop. "
        killall $user
    fi
     
    echogreen "RUNNING LOCAL ODOO INSTANCE (local config file) "
    su - $user -c "source $odoodir/$odoover.0/venv$odoover/bin/activate && $odoodir/$odoover.0/OCB/odoo-bin --config /etc/odoo/odoo$odoover.conf -d ${database}_demo,${database}"
    
    
}

#----------------------------------------------------------------------------------------

function install_oca_addons()
#installa i moduli di OCA (addons/OCA) installati precedentemente dalla procedura clone_repos(), accumulando un  directory listing delle directory dei moduli
# installa i moduli custom (addons/custom) , essenzialmente il full_accounting_activation
{
    ## install the core addons in the oddo database
    header_echo $FUNCNAME
    #----------------------------------------------------------------------
    
    # Collect:
    # - list of module name to install with with odoo-bin
    # - path to oca module's to add in odoo.config
    oca_addons_list=""
    oca_addons_path=""
    nomodule=","
    for repo in ${ocarepos}
    do
        #get  the module names inside each local cloned OCA repo; exclude/filter  directories matching 'setup' and empty directories (",")
        temp="`ls -l ${addonsocadir}/${repo} | grep ^d | awk '{print $9}' | grep --invert-match 'setup'`,"
        if [[ $temp != $nomodule ]]; then  
            oca_addons_list+=$temp
            oca_addons_path+="${addonsocadir}/${repo},"
        fi  
        echoblue "repo: $repo"
        echoblue "list: $oca_addons_list"
        echoblue "path: $oca_addons_path"
    done
    
    
    #purge last "," char
    oca_addons_list=${oca_addons_list%,}
    oca_addons_list=`echo ${oca_addons_list} | sed 's/ /,/g'`   
    oca_addons_path=${oca_addons_path%,}
    oca_addons_path=`echo ${oca_addons_path} | sed 's/ /,/g'`  
    
    echoblue "lista dei moduli da installare: $oca_addons_list"
    echogreen "----------------"
    #echoblue "da aggiungere ad addons_path:: $oca_addons_path"
    #read -p "Press Enter to continue"
    
    #update odoo.config addons_path with new modules
    setup_config_and_log  $oca_addons_path

    #echogreen "installiamo i moduli in Odoo:...."
    #read -p "Press enter to continue"
    
    #Just For now, NOT installing the modules ... install them by web interface if needed
    #su - $user -c "source $odoodir/$odoover.0/venv$odoover/bin/activate && $odoodir/$odoover.0/OCB/odoo-bin -c /etc/odoo/odoo$odoover.conf -i ${oca_addons_list} -d ${database} --without-demo=all --load-language=it_IT --stop-after-init"
    #su - $user -c "source $odoodir/$odoover.0/venv$odoover/bin/activate && $odoodir/$odoover.0/OCB/odoo-bin -c /etc/odoo/odoo$odoover.conf -i ${oca_addons_list} -d ${database}_demo --load-language=it_IT --stop-after-init"
    
    
    sleep 2
    ## Kill process if $user process doesn't stop after initialization
    if [ $(pgrep --exact --count $user) -gt 0 ]
    then
        echored "Odoo still running... Force stop. "
        killall $user
    fi
    
    #echogreen "RUNNING ODOO INSTANCE"
    #su - $user -c "source $odoodir/$odoover.0/venv$odoover/bin/activate && $odoodir/$odoover.0/OCB/odoo-bin --config /etc/odoo/odoo$odoover.conf -d ${database}_demo,${database} --logfile /var/log/odoo/odoo$odoover-server.log"
  
}


#---------------------------------------------------------------
function odoo_service_enable() 
#rende il servizio odoo un daemon di system, creando un file di configurazione per systemctl e attivandolo
{
    header_echo $FUNCNAME
    #----------------------------------------------------------------------
#https://unix.stackexchange.com/questions/206315/whats-the-difference-between-usr-lib-systemd-system-and-etc-systemd-system
# using directory /etc/systemd/system/ as table 1 in : man systemd.unit

    if [[ ! -f "/etc/systemd/system/odoo$odoover.service" ]] 
    then 
    
cat << EOF >  /etc/systemd/system/odoo$odoover.service
[Unit]
Description=Odoo$odoover
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
SyslogIdentifier=odoo$odoover
PermissionsStartOnly=true
User=$user
Group=$user
ExecStart=/opt/odoo/$odoover.0/venv$odoover/bin/python3 /opt/odoo/$odoover.0/OCB/odoo-bin -c /etc/odoo/odoo$odoover.conf --logfile /var/log/odoo/odoo$odoover-server.log
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target    
EOF

        sudo systemctl daemon-reload
        sudo systemctl enable odoo$odoover.service
        sudo systemctl start odoo$odoover.service
        
        journalctl -u odoo$odoover
        echogreen "Odoo service enabled"
    else
        echored "/etc/odoo/odoo$odoover.conf aready present. Aborting enable service."
    fi

}

#----------------------------------------------------------------
function debug_odoo_service_disable()
#disabilita il servizio daemon di odoo
{
    header_echo $FUNCNAME
    #----------------------------------------------------------------------
    if [[ -f "/etc/systemd/system/odoo$odoover.service" ]] 
    then 
        systemctl stop odoo$odoover.service
        systemctl disable odoo$odoover.service
        #rm /etc/systemd/system/odoo$odoover.service
        systemctl daemon-reload
        systemctl reset-failed
        echogreen "odoo$odoover.service disabled"
    else
        echored "/etc/systemd/system/odoo$odoover.service not found. Abort disabling service."
    fi
}
#---------------------------------------------------------------
function debug_remove_odoo()
{
#cancella i database installati, rimuove l'utente odoo con la relativa directory e i repo scaricati
#rimuove i file di configurazione e di log
    su - postgres -c 'dropdb contabita18'
    su - postgres -c 'dropdb contabita18_demo'
    echoblue "dabased dropped"
    su - postgres -c "psql   --command='DROP USER odoo' "
    echoblue "database user dropped"
    rm -R $odoodir/$odoover.0
    rm /etc/odoo/odoo18.conf
    rm /var/log/odoo/odoo18-server.log
    echoblue "config file and log file removed"
    userdel -r $user
    echoblue "user removed"
    debug_odoo_service_disable
}
#---------------------------------------------------------------
function debug_add_single_repo()
#scarica da github un singolo repo e rigenera il file di configurazione odoo
{
    header_echo $FUNCNAME
    #----------------------------------------------------------------------
    repo=$1
    echoblue $repo
    
    #read -p "Press enter to continue"

    git clone https://github.com/OCA/$repo.git --depth=1 --branch=$odoover.0 --single-branch $addonsocadir/$repo
    
    rm "/etc/odoo/odoo$odoover.conf"
    
    echored "/etc/odoo/odoo$odoover.conf deleted"
    
    #read -p "Press enter to continue"
    setup_config_and_log
    
    install_oca_addons
}
#--------------------------------------------------------------------------
function setup_config_and_log () 
#crea il file di configurazione per odoo in /etc/odoo partendo dal template OCB/debian/odoo.conf
#crea un file vuoto per i log in /var/odoo 
# se il file di config NON esiste, imposta addons_path ad $1
# altrimenti accoda $1
{
    #----------------------------------------------------------------------
    header_echo $FUNCNAME
    newpaths=","$1
    echoblue "New addons_path passato: $1"
    
    ## Setup odoo config file if it does not exist 
    if [[ ! -f "/etc/odoo/odoo$odoover.conf" ]] 
    then 
        #config file for odoo not found. Create a newone
        mkdir -p /etc/odoo
        cp /opt/$user/$odoover.0/OCB/debian/odoo.conf /etc/odoo/odoo$odoover.conf
        echo "addons_path = $1" >> /etc/odoo/odoo$odoover.conf
        echo "http_port = $http_port"  >> /etc/odoo/odoo$odoover.conf
        #echo "logfile = /var/log/odoo/odoo$odoover-server.log"  >> /etc/odoo/odoo$odoover.conf
        chown $user:$user /etc/odoo/odoo$odoover.conf
        chmod  a+rwx,u-x,g-wx,o-rwx  /etc/odoo/odoo$odoover.conf
        #chmod 640 /etc/odoo/odoo$odoover.conf
        echogreen "/etc/odoo/odoo$odoover.conf created"
    else
        #Odoo config file alrady exists. Possile update..
        #test if $newpath is already present int configfile
        grep  $newpaths /etc/odoo/odoo$odoover.conf
        if [ $? -eq 0 ]
        then
            #path already present. No need to update.
            echo "$newpaths già presente nel file di configurazione"
        else
            #append config file line startign with "addons_path=" the newpaths; 
            #sed delimiter char is changed to ":" because $newpaths contains "/" inside
            echogreen "aggiungo $newpaths al file di configurazione di Odoo"
            sed  -i "s:^addons_path.*:& $newpaths:" /etc/odoo/odoo$odoover.conf
            chown $user:$user /etc/odoo/odoo$odoover.conf
        fi
    fi  

     ## Setup odoo log file    
    if [[ ! -f "/var/log/odoo/odoo$odoover-server.log" ]] 
    then 
        mkdir -p /var/log/odoo
        touch /var/log/odoo/odoo$odoover-server.log
        # for adm group -> https://wiki.debian.org/SystemGroups
        chown root:$user /var/log/odoo
        chmod a+rwx,g-w,o-rwx /var/log/odoo
        chown $user:adm /var/log/odoo/odoo$odoover-server.log
        #chmod 640 /var/log/odoo/odoo$odoover-server.log
        chmod  a+rwx,u-x,g-wx,o-rwx  /var/log/odoo/odoo$odoover-server.log
        echogreen "/var/log/odoo/odoo$odoover-server.log created"
    fi
}
#----------------------------------------------------------------------------------------
#00000000000000000000000000000000000000000000000000000000000000000000
#-------------------------------------------------------------------

install_packages

create_users
    
clone_odoo

clone_repos

create_venv

create_odoo_db

install_base_and_core_addons

#install_oca_addons

#odoo_service_enable




# my personal CLI command 
#su - odoo -c "/opt/odoo/18.0/venv18/bin/python3 /opt/odoo/18.0/OCB/odoo-bin -c /etc/odoo/odoo18.conf --logfile /var/log/odoo/odoo18-server.log"
