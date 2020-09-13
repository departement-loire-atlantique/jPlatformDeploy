#!/bin/bash
# TODO calcul du paramètre NFS en fonction de l'utilisateur et synchro optionnel des uploads
# TODO ajouter des infos en plus

# Parse Arguments
while getopts 'u:n:' OPTION
  do
    case $OPTION in
      u)    PRODLOGIN=$OPTARG ;;
      n)    NFSFOLDER=$OPTARG ;;
      [?])  usage "Invalid option -$OPTARG" ;;
      :)    usage "Option -$OPTARG requires an argument." ;;
    esac
  done
shift $(($OPTIND - 1))

TODAY=`date +'%F'`
BACKUP_SUFFIX=`date +'%F-%H%M%S'`

if [ "$PRODLOGIN" == "" ]
then
  echo "Please specify a valid production username using -u option"
  exit -1;
fi

if [ "$NFSFOLDER" == "" ]
then
  echo "Please specify a valid NFS production folder using -n option"
  exit -1;
fi

# Backup current store
mv $HOME/cg44_appli/persistentdata/data/store.xml $HOME/cg44_appli/persistentdata/data/store.xml.$BACKUP_SUFFIX

# Replace by last prod backup store
scp $PRODLOGIN@sunweb1:/global/tcsdom/$PRODLOGIN/cg44_appli/persistentdata/data/backups/store.xml.backup-$TODAY* $HOME/cg44_appli/persistentdata/data/store.xml

# Update UPLOAD
scp -r $PRODLOGIN@sunweb1:/global/nfs/$NFSFOLDER/upload $HOME/cg44_appli/persistentdata/
