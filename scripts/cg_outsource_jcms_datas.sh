#!/bin/bash

#================================================
# Script d'externalisation des données jcms
# il prend en paramètre le user de l'install jcms
#================================================

set -eu

# utils function
usage(){
    echo "USAGE :  $(basename $0) -n|--name <user applicatif>"
}

# parsing parameters    
APP_NAME=""

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
        *) 
            echo "Mauvais argument : $1" >&2;
            usage
            echo "changed=false"
            exit 1 
            ;;
    esac
    
done

if [[ -z $APP_NAME ]]; then
    echo "Mauvaise utilisation du script" >&2;
    usage;
    echo "changed=false"
    exit 1
fi

# DEBUT
echo "Externalisation des données en cours ..."

DATA_DIR="/jcmsdata/app/$APP_NAME"
WEBAPP_ROOT_DIR="/app/$APP_NAME/webapps/ROOT" 

if [[ ! -d $DATA_DIR ]]; then
    echo "changed=false comment='ERROR - impossible d effectuer l externalisation car le dossier $DATA_DIR n existe pas !!'"
    exit 1
fi

# recopie des répertoires data si ceux-ci n'existent pas encore
if [ -d $WEBAPP_ROOT_DIR/upload ] && [ ! -d $DATA_DIR/upload ]; then
    cp -R $WEBAPP_ROOT_DIR/upload $DATA_DIR
fi
if [ -d $WEBAPP_ROOT_DIR/archives ] && [ ! -d $DATA_DIR/archives ]; then
    cp -R $WEBAPP_ROOT_DIR/archives $DATA_DIR
fi
if [ -d $WEBAPP_ROOT_DIR/WEB-INF/data ] && [ ! -d $DATA_DIR/data ]; then
    cp -R $WEBAPP_ROOT_DIR/WEB-INF/data $DATA_DIR
fi

# Si les répertoire d'externalisation n'existe pas on les crée
if [ ! -d $DATA_DIR/upload ]; then
    mkdir $DATA_DIR/upload
fi
if [ ! -d $DATA_DIR/archives ]; then
    mkdir $DATA_DIR/archives
fi
if [ ! -d $DATA_DIR/data ]; then
    mkdir $DATA_DIR/data
fi

# Ensuite on supprime les données de la webapp et on crée les liens vers les données externalisées
rm -rf $WEBAPP_ROOT_DIR/upload $WEBAPP_ROOT_DIR/archives $WEBAPP_ROOT_DIR/WEB-INF/data > /dev/null 2>&1
ln -s /jcmsdata/app/$APP_NAME/upload $WEBAPP_ROOT_DIR/upload
ln -s /jcmsdata/app/$APP_NAME/archives $WEBAPP_ROOT_DIR/archives
ln -s /jcmsdata/app/$APP_NAME/data $WEBAPP_ROOT_DIR/WEB-INF/data

# FIN
echo "changed=true comment='done, données externalisées avec succès !!'"