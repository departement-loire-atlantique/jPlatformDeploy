#!/bin/bash

#================================================
# Script pour savoir si un rollback est necessaire, il prend en paramètre le user de l'install jcms
#================================================

set -eu

######################
# utils function
######################
usage() {
    echo "USAGE :  $(basename $0) -n|--name <user applicatif>"
}

getCurrentCalinaOutLineCount() {
    if [ -f $TOMCAT_LOG_FILE ]; then
        echo $(cat $TOMCAT_LOG_FILE | wc -l)
    else
        echo "0"
    fi
}

# Check if JCMS failed to start
isJCMSready() {

    if [ ! $2 -gt $1 ]; then
        echo "$FAILED_TO_START_CODE"
    else 
        failedtostart=$(sed ''"$1,$2"'!d' "$TOMCAT_LOG_FILE" | grep "ChannelInitServlet.*is not available" | wc -l)
        if [ "$failedtostart" -gt "0" ]; then
            echo "$FAILED_TO_START_CODE"
        else
            sed ''"$1,$2"'!d' "$TOMCAT_LOG_FILE" | grep "ChannelInitServlet.*is ready" | wc -l
        fi
    fi
}

checkIfhomePageIsReachable() {

    check=$(/usr/bin/wget -T 300 -q -O- "$1" | grep "data-jalios-pack-version" | wc -l)
    if [ "$check" -lt "1" ]; then
        echo "Il n y a pas data-jalios-pack-version dans la page d accueil. Verifier si JCMS a vraiment bien demarré ?" >&2
    else
        echo "OK, environnement is up !"
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
    *)
        echo "Mauvais argument : $1" >&2
        usage
        echo "changed=true"
        exit 1
        ;;
    esac
done

# vérification des paramètres
if [[ -z $APP_NAME ]]; then
    echo "Mauvaise utilisation du script : le <user applicatif> est obligatoire" >&2
    usage
    echo "changed=false"
    exit 1
fi

# on vérifie si tomcat est up avant de tester s'il faut faire le rollback
if [ $(ps -ef | grep $APP_NAME | grep tomcat | grep 'Bootstrap start' | wc -l) == 0 ]; then
    echo "changed=false comment='JCMS n est pas demarré, veuillez d abord le démarrer avant de faire le test!'"
    exit 1
fi

# DEBUT - cette partie s'inspire de la methode startTomcatSafely du script old/cg_update_jcms.sh
HOME="/app/$APP_NAME"
TOMCAT_LOG_FILE="/log/app/$APP_NAME/tomcat/catalina.out"
CATALINA_COUNT_FILE="$HOME/temp/catalina_count.info"
FAILED_TO_START_CODE="-1"

echo "vérifier si jcms a bien démarré. En cours ..."

if [ ! -f $CATALINA_COUNT_FILE ]; then
    echo "changed=false comment='$CATALINA_COUNT_FILE must be present but not'"
    exit 1
fi

# Init catalina log cursor
initial_line_count=$(expr $(cat $CATALINA_COUNT_FILE) + 1)
previous_line_count=$initial_line_count

# Set time out : 30 minutes max for tomcat start
maxAttemps=180
currentAttemps=0

# Wait for startup process is complete and check errors in catalina.out
isStarted=0
sleep 10
while [ $isStarted == "0" ]; do
    currentAttemps=$(expr $currentAttemps + 1)

    if [ "$currentAttemps" == "$maxAttemps" ]; then
        echo "changed=true comment='Tomcat did not start successfully before the time out. Need rollback.'"
        exit 1
    fi

    current_line_count=$(getCurrentCalinaOutLineCount)

    isStarted=$(isJCMSready $previous_line_count $current_line_count)

    if [ "$isStarted" == "$FAILED_TO_START_CODE" ]; then
        echo "changed=true comment='JCMS has failed to start. Need rollback!'"
        exit 1
    fi

    sleep 10
    previous_line_count=$(expr $current_line_count + 1)
done

# FIN
localurl=$(cat "$HOME/webapps/ROOT/WEB-INF/data/custom.prop" | grep "site.private.url" | sed 's/site\.private\.url: //')
if [ "$localurl" == "" ]; then
    echo "changed=true comment='le fichier custom.prop incomplet. Propriété site.private.url absent. Rollback requis'"
    exit 1
fi
echo "Local url = $localurl"
homepagecheck=$(checkIfhomePageIsReachable $localurl 2>&1)
echo "changed=false comment='$homepagecheck'"