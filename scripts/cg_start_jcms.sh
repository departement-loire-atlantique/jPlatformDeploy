#!/bin/bash

#================================================
# Script de demarrage de jcms, il prend en paramètre le user de l'install jcms et le chemin vers le script de démarrage
#================================================

set -eu

######################
# utils function
######################
usage() {
    echo "USAGE :  $(basename $0) -n|--name <user applicatif> -s|--script <script path>"
}

getCurrentCalinaOutLineCount() {
    if [ -f $TOMCAT_LOG_FILE ]; then
        echo $(cat $TOMCAT_LOG_FILE | wc -l)
    else
        echo "0"
    fi
}

# parsing parameters
APP_NAME=""
SCRIPT_PATH=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
    -h)
        usage
        exit 0
        ;;
    -n | --name)
        APP_NAME="$2"
        shift
        shift
        ;;
    -s | --script)
        SCRIPT_PATH="$2"
        shift
        shift
        ;;
    *)
        echo "Mauvais argument : $1"
        usage
        echo "changed=false"
        exit 1
        ;;
    esac
done

# vérification des paramètres
if [[ -z $APP_NAME ]]; then
    echo "Mauvaise utilisation du script : le <user applicatif> est obligatoire"
    usage
    echo "changed=false"
    exit 1
fi

if [[ -z $SCRIPT_PATH ]]; then
    SCRIPT_PATH="/app/$APP_NAME/scripts/cg_startTomcat.sh"
    echo "<script path> n'a pas été fourni, utilisation de la valeur par defaut : $SCRIPT_PATH"
fi

# on vérifie si tomcat est down avant de le démarrer
if [ $(ps -ef | grep $APP_NAME | grep tomcat | grep 'Bootstrap start' | wc -l) == 1 ]; then
    echo "changed=false comment='JCMS est déjà demarré, le script de demarrage n a pas été lancé!'"
    exit 1
fi

# DEBUT - cette partie s'inspire de la methode startTomcatSafely du script old/cg_update_jcms.sh
HOME="/app/$APP_NAME"
TOMCAT_LOG_FILE="/log/app/sinsr/tomcat/catalina.out"
CATALINA_COUNT_FILE="$HOME/temp/catalina_count.info"

echo "Nettoie les repertoires work et tempt de tomcat"
rm -Rf "$HOME/work/*"
rm -Rf "$HOME/temp/*"

# save catalina line count before starting
echo $(getCurrentCalinaOutLineCount) > $CATALINA_COUNT_FILE

# Start Tomcat
echo "Demarrage de tomcat en cours ..."
startTomcatLogs=$($SCRIPT_PATH)

if [ $? != "0" ]; then
    echo "$startTomcatLogs"
    echo
    echo "changed=false comment='Tomcat did not start successfully. Aborting.'" 
    exit 1
fi

# FIN
echo "changed=true comment='Done. Tomcat a demarré avec succès. Veuillez vérifier si jcms a également bien démarré'"