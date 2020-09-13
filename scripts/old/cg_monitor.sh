#!/bin/bash
#
# ----------------------------------------------------------------------------------------------
# This shell script packages basic supervision operation about JCMS website :
# - agenda synchronisation : 
#   tests if synchronisation between JCMS and Ouest France data source is OK
#   usage : daily supervision
#
# ----------------------------------------------------------------------------------------------
# This script has been built for the following CG44, Solaris Template :
#   Template: cg44
#   Version: 2.8.0.RELEASE
#   Build Date: 20121105140200
# ----------------------------------------------------------------------------------------------
# Author :
# Julien BAYLE, 2014

#######################################
# Global variables
cd ~ ;
basepath=`pwd` ;
script_version="0.2" ;
feedback_positive_url="http://static.loire-atlantique.fr/infolocale/log/feedback_positive.log" ;

#######################################
# script variables
operation=

#######################################
# Convenient method
checkLastExitStatus() {
  lastCommandExitStatus=$? ;
  if [ $lastCommandExitStatus != "0" ] ; then
    # do not display message nor trigger rollback if the script was voluntarly interrupted
    if [ $script_interrupted == "0" ] ; then
      echo "Last command could not be executed correctly (exit code $lastCommandExitStatus). Aborting" >&2 ;
    fi
    processCleanupAndExit $lastCommandExitStatus
  fi
}

#######################################
# Test if agenda module is OK in all production site
checkAgendaModuleSynchronisation() {
  logVerbose "Are agendas successfully synchronised today ?" ;
  today=`date +'%Y%m%d'` || checkLastExitStatus ;
  check=`/usr/sfw/bin/wget -T 1 -q -O- "$feedback_positive_url" | grep "$today" | /usr/xpg4/bin/grep -E "(GPLA|ARCH|INST|BALADES|NUM)_PROD" | wc -l` ;
  checkLastExitStatus ;

  if [ "$check" -ne "5" ] ; then
    echo "KO - All environnements have not been successfully updated on $today ($check / 5) - Please consult $feedback_positive_url for more details" >&2 ;
    processCleanupAndExit -1
  fi
  logVerbose "OK" ;
}



#######################################
# Display shell script usage
usage() {
  if [ $# -ne 0 ]; then 
    echo "$@" >&2 ;
  fi
  printf "Usage: %s: [-hdrvit] [-w pathtowar]" $(basename $0) >&2 ;
  echo "
  -a      test agenda import
               
  Script version : $script_version
  " >&2 ;
  processCleanupAndExit 1 ;
}


#######################################
# Parse aguments
parseArgumentsAndInitEnvironnement() {

  # Parse Arguments
  while getopts 'a' OPTION
  do
    case $OPTION in
      a)    operation="AGENDA" ;;
      [?])  usage "Invalid option -$OPTARG" ;;
      :)    usage "Option -$OPTARG requires an argument." ;;

    esac
  done
  shift $(($OPTIND - 1))
  
  if [ "$operation" == "" ]
  then
    usage ;
  fi
}

#######################################
# Output verbose log message if verbose option has been specified
logVerbose() {
  if [ -n "$verbose" ]; then
    echo -e "[UPDATE $verboseIdx]" "$@" ;
    let "verboseIdx += 1" ;
  fi  
}

# Output verbose log message if show_all_infos option has been specified
logInfo() {
  if [ -n "$show_all_infos" ]; then
    echo -e "[UPDATE $verboseIdx]" "$@" ;
    let "verboseIdx += 1" ;
  fi  
}

# cleanup temp directory
processCleanupAndExit() {
  exit $1;
}


#######################################
# main entry
main() {
  
  # Parse & Check arguments as well as environements 
  parseArgumentsAndInitEnvironnement "$@" ;
 
  # RESTART
  if [ "$operation" == "AGENDA" ]; then
    logInfo "Operation : Agenda" ;
    checkAgendaModuleSynchronisation ;
  fi

  processCleanupAndExit 0;

}

main "$@" ;
