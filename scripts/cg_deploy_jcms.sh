#!/bin/bash

#================================================
# Script de livraison de war jcms, il prend en paramètre le user de l'install jcms et le nom du war
#================================================

set -eu

# utils function
usage(){
    echo "USAGE :  $(basename $0) -n|--name <user applicatif> -j|--java <java home> -w|--war <war name>"
}

# default values
DEFAULT_J_HOME="/opt2/openjdk/jdk-11.0.5"
DEFAULT_WAR_NAME="socle.war"

# parsing parameters    
APP_NAME=""
J_HOME=""
WAR_NAME=""

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
            echo "changed=false"
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

if [[ -z $J_HOME ]]; then
    J_HOME=$DEFAULT_J_HOME
    echo "<java home> n'a pas été fourni, utilisation de la valeur par defaut : $J_HOME"
fi
if [[ -z $WAR_NAME ]]; then
    WAR_NAME=$DEFAULT_WAR_NAME
    echo "<war name> n'a pas été fourni, utilisation de la valeur par defaut : $WAR_NAME"
fi

# DEBUT
echo "Deploiement du war en cours ..."

WEBAPP_ROOT_DIR="/app/$APP_NAME/webapps/ROOT" 

# extraction du war dans la webapp racine de tomcat
cd $WEBAPP_ROOT_DIR
cp /app/$APP_NAME/temp/$WAR_NAME .
$J_HOME/bin/jar -xvf $WAR_NAME > /dev/null
rm $WAR_NAME /app/$APP_NAME/temp/$WAR_NAME
cd - > /dev/null

# Remplacer le contexte /jmcs par /44 dans le web.xml applicatif
sed -i -e 's/<url-pattern>\/jcms/<url-pattern>\/44/' $WEBAPP_ROOT_DIR/WEB-INF/web.xml

# FIN
echo "changed=true comment='done, extraction effectuée avec succès !!'"