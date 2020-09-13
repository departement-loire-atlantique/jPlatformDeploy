#!/bin/bash

#================================================
# Script d'arrêt de jcms, il prend en paramètre le user de l'install jcms et le chemin vers le script d'arrêt
#================================================

set -eu

# utils function
usage(){
    echo "USAGE :  $(basename $0) -n|--name <user applicatif> -s|--script <script path>"
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
        -n|--name) 
            APP_NAME="$2" 
            shift
            shift
            ;;
        -j|--java) 
            J_HOME="$2" 
            shift
            shift
            ;;
        -w|--war) 
            WAR_NAME="$2" 
            shift
            shift
            ;;
        *) 
            echo "Mauvais argument : $1" >&2
            usage
            exit 1 
            ;;
    esac
    
done

# vérification des paramètres
if [[ -z $APP_NAME ]]; then
    echo "Mauvaise utilisation du script : le <user applicatif> est obligatoire" >&2
    usage
    exit 1
fi

if [[ -z $SCRIPT_PATH ]]; then
    SCRIPT_PATH="/app/$APP_NAME/scripts/cg_stopTomcat.sh"
    echo "<script path> n'a pas été fourni, utilisation de la valeur par defaut : $SCRIPT_PATH"
fi

# DEBUT

# on vérifie si tomcat est up avant de lancer le script d'arrêt
if [ $(ps -ef | grep $APP_NAME | grep tomcat | grep 'Bootstrap start' | wc -l) == 0 ]; then
    echo "JCMS est déjà arrêté !"
    exit 0
fi

echo "Arrêt de jcms en cours ..."
logs=`$SCRIPT_PATH 2>&1`
returnCode=$?
if [ $returnCode != "0" ]; then
    echo "$logs"
    echo "Tomcat ne s'est pas correctement arrêté. Veuillez vérifier." >&2
    exit $returnCode
fi

# FIN
echo "done, arrêt effectué avec succès !!"