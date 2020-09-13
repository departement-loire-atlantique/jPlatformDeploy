#!/bin/bash
#
# This shell script provides easy deployement of a JCMS war into an
# existing exploded webapp directory.
#
# Usage (invoke deploy.sh -h for more information) : 
#  [stop J2EE server]
#  deploy.sh newwebapp.war targetdirectory
#  [start J2EE server]
#
# Known exit codes : 
#   0 -> OK
#   1 -> bad parameter or missing requirements => usage displayed
#   2 -> war does not contains any plugins, whereas target does. 
#  11 -> StoreMerge : bad parameter
#  12 -> StoreMerge : Error
#  13 -> StoreMerge : Conflict
#
# Requirements :
#  OS requirements :
#   - bash
#   - unzip, zipinfo
#   - mktemp, readlink, date, find, grep, cat, mv, diff ...
#  Architecture Requirements :
#   - The following directory of the webapp MUST be symbolic link :
#     - archives
#     - upload
#     - WEB-INF/data
#
#
# Implentation details : 
#  - temporary directory : $TMP_DIR/
#  - temporary dir for new webapp (unzipped) : $newWebappDir (==$TMP_DIR/webapp/)
#  - $TMP_DIR/webapp/data is moved $TMP_DIR/data.original 
#  - symlinks are created in $TMP_DIR/webapp/
#  - store is kept/overwritten/merged (backup are created if any modification is made)
#  - types directory is replaced with types from war
#  - workflows directory is replaced with workflows from war
#  - existing webapp is moved and replaced with new one 
#
#  - Rollback is implemented using second temporary script in which each command
#    necessary for the rollback are added to the script in reverse order 
#
#  Modified by Julien BAYLE in order to work on Solaris
#  - Solaris grep doesn't support -q. Solution: change grep -q to grep 2>/dev/null. 
#  - Readlink not present so a method readlink_replacement is proposed
#  - cp --no-dereference not supported, replaced by cp -r -P 
#  - unzip of the archive made quiet with "1> /dev/null"
#  - copy the custom.prop file from SVN to the webapp if not modified localy
#  - added JAVA_BIN propertie to support multiple java version environnement 
#######################################
# Robustness
set -o nounset # exit if a non initialized variable is used

#######################################
# Global variables
deploysh_revision=`expr match '$Revision: 61538 $' '\$.*:\ \(.*\) \$$'` ;
deploysh_date=`expr match '$Date: 2013-08-30 14:01:00 +0200 (Fri, 30 Aug 2013) $' '\$.*:\ \(.*\) \$$'` ;

store="keep" 
dryrun=
verbose=
verboseIdx=0
backup_dir=
log_diff=1
log_msg=

scriptInterrupted=0
rollbackAsked=0

TMP_DIR=
JAVA_CLASSPATH=
JAVA_BIN="/opt2/jdk/1.6.0/bin/"
BACKUP_SUFFIX=

# If left empty, backup were not needed
backup_store_path=
backup_types_path=
backup_workflows_path=

#######################################
# Generic Methods

# Display shell script usage
usage() {
  if [ $# -ne 0 ]; then 
    echo "$@" >&2 ;
  fi
  printf "Usage: %s: [-vd] [-m msg] [-b backupdir] [-s storeAction] newwebapp.war targetdir" $(basename $0) >&2 ;
  echo "
 -h            display version and this help message
 -s action     action to perform on store.xml file, from the following :
                 'keep' (default) : keep store.xml of existing webapp 
                 'overwrite'      : overwrite existing store with store from war
                 'merge'          : merge existing and new store 
                 existing store is backuped when using 'overwrite' or 'merge' 
 -b directory  backup directory : old webapp will be moved inside this directory
               once deployement has been performed. Default behavior is to leave
               webapp in same directory and simply rename the webapp directory.
 -m message    An optionnal message logged in WEB-INF/data/logs/deploy.log
               upon deployement success
 -z            Do not log webapp differences after deployement (faster)
 -v            verbose mode, display very detailed operation 
 -d            dryrun, do not perform any filesystem modification" >&2 ;
  exit 1 ;
}

# Output verbose log message if option has been specified
logVerbose() {
  if [ -n "$verbose" ]; then
    echo -e "[$verboseIdx]" "$@" ;
    let "verboseIdx += 1" ;
  fi  
}

checkLastExitStatus() {
  lastCommandExitStatus=$? ;
  if [ $lastCommandExitStatus -ne 0 ] ; then
    # do not display message nor trigger rollback if the script was voluntarly interrupted
    if [ $scriptInterrupted -eq 0 ] ; then
      echo "Last command could not be executed correctly (exit code $lastCommandExitStatus). Aborting" >&2 ;
      rollback ;
    fi
    exit $lastCommandExitStatus
  fi
}

#######################################
# Rollback methods

rollbackScriptPath=

setupRollbackScript() {  
  rollbackScriptPath="$TMP_DIR/rollback.sh" ;
  test -n "$dryrun" || touch "$rollbackScriptPath"  || checkLastExitStatus ;
}

# Add the specified command to the list of commands to be executed if 
# any failure occurs during processing.
# IMPORTANT: commmand MUST be enclosed in quotes and SHOULD NOT contain single quote !
# eg : pushRollbackCommand "ls -la \"$foobar\""
pushRollbackCommand() {
  logVerbose "Adding rollback command '$@'" ;
  
  # Command must be executed in reverse order (last in, first out)
  # therefore we prepend the command using an intermediate file.
  # Also invoke the 'checkLastRollbackExitStatus' method to check it
  # the command was successful
  echo "echo '# $@'" > "$rollbackScriptPath.tmp"  || checkLastExitStatus ;
  echo "$@" >> "$rollbackScriptPath.tmp"  || checkLastExitStatus ;
  echo "checkLastRollbackExitStatus" >> "$rollbackScriptPath.tmp"  || checkLastExitStatus ;
  
  # Add previous commands (existing content of rollback script)
  cat "$rollbackScriptPath" >> "$rollbackScriptPath.tmp"  || checkLastExitStatus ;
  mv "$rollbackScriptPath.tmp" "$rollbackScriptPath"  || checkLastExitStatus ;
}

rollback() {
  if [ $rollbackAsked -eq 1 ] ; then
    return ;
  fi
  rollbackAsked=1 ;

  echo "Deployement could not be completed : rollback all modifications ..."
  if [[ -f "$rollbackScriptPath" && -s "$rollbackScriptPath" ]]; then
  
    # Prepend shebang and required methods
    echo '#!/bin/bash
    
checkLastRollbackExitStatus() {
  lastRollbackCommandExitStatus=$? ;
  if [ $lastRollbackCommandExitStatus -ne 0 ] ; then
    exit $lastRollbackCommandExitStatus
  fi
}
' > "$rollbackScriptPath.tmp" ;
  cat "$rollbackScriptPath" >> "$rollbackScriptPath.tmp" ;
  mv "$rollbackScriptPath.tmp" "$rollbackScriptPath" ;
  
    # Log script content
    if [ -n "$verbose" ]; then
      echo "Executing rollback script '$rollbackScriptPath' :" ;
      echo "# ----------------------------------------------------------" ;
      cat "$rollbackScriptPath" ;
      echo "# ----------------------------------------------------------" ;
      echo ;
    fi

    # Execute
    bash $rollbackScriptPath
    rollbackExitStatus=$? ;
    if [ $rollbackExitStatus -ne 0 ] ; then
      echo 'ERROR !! Rollback could not be completed correctly. CHECK WEBAPP INTEGRITY !!' >&2 ;
      exit $rollbackExitStatus
    fi   
  fi;   
  echo "All modifications were rollbacked successfully."
}


#######################################
# Path manipulation utility methods

# Get the absolute path of a file or directory
# the specified file/directory MUST exists
# otherwise the specified path is return
# usage : 
#   fullpath=$( getAbsolutePath "$relativepath" )
getAbsolutePath() {
  if [ -f "$1" ]; then
    _getAbsoluteFilePath "$1";
  elif [ -d "$1" ]; then
    _getAbsoluteDirPath "$1";
  else
    echo "$1";
  fi
}

# Get the absolute path of a file
# the specified file MUST exists and MUST be a file
_getAbsoluteFilePath() {
  file=$1
  file_parent=${file%/*} ;
  if [ "$file_parent" == "$file" ]; then
    absolutepath=$PWD/$file ;
  else
    absolutepath=`cd "$file_parent"; pwd`"/$(basename $file)" ;
  fi;
  echo "$absolutepath" ;
}

# Get the absolute path of a Directory
# the specified file MUST exists and MUST be a directory
_getAbsoluteDirPath() {
  directory=$1
  absolutepath=`cd "$directory"; pwd` ;
  echo "$absolutepath" ;
}

cleanPaths() {

  # remove traling slash from path if any
  war_path=${war_path%/}
  target_dir=${target_dir%/}
  backup_dir=${backup_dir%/}
  
  # convert to absolute path
  war_path=$(getAbsolutePath "$war_path") ;
  target_dir=$(getAbsolutePath "$target_dir") ;
  backup_dir=$(getAbsolutePath "$backup_dir") ;
  logVerbose "war_path   \t= \"$war_path\"" ;
  logVerbose "target_dir \t= \"$target_dir\"" ;
  logVerbose "backup_dir \t= \"$backup_dir\"" ;

}

#######################################
# Methods used to check requirements

checkProgramExists() {
  type -P "$1" &>/dev/null
  if [ $? -ne 0 ]; then 
    usage "'$1' is required but could not be found. Aborting." ;
  fi
}

checkSymlink() {
  if [[ ! -h "$1" ]]
  then 
    usage "'$1' MUST be a symbolic link." ; 
  fi
  
  current_symlink=`readlink_replacement "$1"` ;
  if [[ "$current_symlink" != /* ]]
  then 
    usage "'$1' MUST be an absolute symbolic link. It references relative path '$current_symlink'" ; 
  fi
}

readlink_replacement() { ls -ld "$1" | sed 's/.*-> //'; }

checkRequirements() {

  # OS requirements
  checkProgramExists unzip ;
  checkProgramExists zipinfo ;
  checkProgramExists find ;
  checkProgramExists grep ;
  checkProgramExists mktemp ;
  checkProgramExists date ;
  checkProgramExists java ;

  
  # Arguments 
  if [[ "$store" != "keep" && "$store" != "overwrite" && "$store" != "merge" ]]; then
    usage "Invalid -s store action '$store'. Valid actions : 'keep', 'overwrite', 'merge'" ;
  fi
  
  # Specified war exist 
  if [ ! -f "$war_path" ]; then
    usage "Missing or invalid war file : '$war_path'" ;
  fi
  # Specified war is a valid zip file and a valid web archive
  zipinfo -1 "$war_path" 2> /dev/null | grep 2>/dev/null "^WEB-INF/web.xml$" ;
  if [ $? -ne 0 ]; then
    usage "Invalid web archive (zip is invalid or web.xml could not be found) : '$war_path'" ;
  fi
  
  # Target directory exists
  if [ ! -d "$target_dir" ]; then
    usage "Invalid target directory : '$target_dir'" ;
  fi

  # Backup directory exists (if specified)
  if [[ ! -z "$backup_dir" && ! -d "$backup_dir" ]]; then
    usage "Invalid backup directory : '$backup_dir'" ;
  fi
  
  # Webapp directories uses symlink
  checkSymlink "$target_dir/archives" ;
  checkSymlink "$target_dir/upload" ;
  checkSymlink "$target_dir/WEB-INF/data" ;
  
  # Number of plugin in zip vs number of plugin in webapp
  IFS=$'\n';
  target_plugins=$( find "$target_dir/WEB-INF/plugins/" -type d -mindepth 1 -maxdepth 1 -printf '%f\n' 2> /dev/null ) ;
  if [ -z "$target_plugins" ]; then target_plugins_nbr=0; else target_plugins_nbr=$( echo "$target_plugins" | wc -l ) ; fi
  new_plugins=$( zipinfo -1 "$war_path" 2> /dev/null | grep "^WEB-INF/plugins/[^/]*/$" | cut -d '/' -f 3 ) ;
  if [ -z "$new_plugins" ]; then new_plugins_nbr=0; else new_plugins_nbr=$( echo "$new_plugins" | wc -l ) ; fi
  unset IFS
  logVerbose "$target_plugins_nbr target_plugins : $target_plugins  " ;
  logVerbose "$new_plugins_nbr new_plugins: $new_plugins " ;
  if [[ $new_plugins_nbr -eq 0 && $target_plugins_nbr -gt 0 ]]; then
    echo "To prevent deployement mistake, you cannot deploy a war which has 0 plugin when your target webapp has at least one plugin."
    echo " Your web archive does not contains any plugin installed." >&2 ;
    echo " Your target webapp has $target_plugins_nbr plugins installed." >&2 ;
    exit 2;
  fi;
}
  
#######################################
# Parse aguments

parseArguments() {
  while getopts 'hvdb:s:m:z' OPTION
  do
    case $OPTION in
      h)    usage "deploy.sh version $deploysh_revision $deploysh_date" ;;
      d)    dryrun=1 ;;
      v)    verbose=1 ;;
      b)    backup_dir=$OPTARG ;; # backup directory
      s)    store=$OPTARG ;; # keep|overwrite|merge
      m)    log_msg=$OPTARG ;; # any log message
      z)    log_diff= ;;
      [?])  usage "Invalid option -$OPTARG" ;;
      :)    usage "Option -$OPTARG requires an argument." ;;

    esac
  done
  shift $(($OPTIND - 1))
  
  if [ $# -ne 2 ]
  then
    usage ;
  fi
  
  war_path=$1
  target_dir=$2
}

#######################################
# Environement

# Define the file suffix used every time a copy is made of old data
setupBackupSuffix() {
  BACKUP_SUFFIX=`date +'%F-%H%M%S'` ;
}

# Create temporary work directory
setupTmpDir() {
  test -n "$dryrun" && TMP_DIR=`mktemp -u -d` || TMP_DIR=`mktemp -d` ;
  logVerbose "TMP_DIR \t= \"$TMP_DIR\"" ;
}

# Build Java classpath required to execute java program
setupJavaClassPath() {
  JAVA_CLASSPATH="$target_dir/WEB-INF/classes"
  IFS=$'\n';
  for jarFile in $( ls "$target_dir"/WEB-INF/lib/*.jar )
  do
   JAVA_CLASSPATH=$JAVA_CLASSPATH:"$jarFile" ; 
  done
  unset IFS
}

setupEnvironment() {
  setupBackupSuffix ;
  setupTmpDir ;
  setupJavaClassPath ;
  setupRollbackScript ;
}


#######################################
# JAVA methods

storeMerge() {
  logVerbose "Executing $JAVA_BIN/java -classpath \"$JAVA_CLASSPATH\" com.jalios.jcms.tools.StoreMerge -output \"$1\" \"$1\" \"$2\"" ;
  "$JAVA_BIN/java" -classpath "$JAVA_CLASSPATH" com.jalios.jcms.tools.StoreMerge -output "$1" "$1" "$2"
  case $? in
    0) # OK
      logVerbose "StoreMerge successful" ;
      return ;
     ;; 
    1) # Bad Parameters
      echo "Invalid parameters specified to StoreMerge" >&2 ;
      rollback ;
      exit 1 ; 
     ;; 
    2) # Error
      echo "An error occured whild processing StoreMerge, check log" >&2 ;
      rollback ;
      exit 2 ; 
     ;; 
    3) # Conflicts
      echo "Conflicts were detected while processing StoreMerge" >&2 ;
      rollback ;
      exit 3 ; 
     ;; 
    ?) # unexpected error
      echo "An unexpected error ($?) occured while invoking StoreMerge" >&2 ;
      exit $? ; 
     ;;
  esac
}

#######################################
# main processing methods

# Unzip war in temp dir
unzipWar() {  
  newWebappDir="$TMP_DIR/webapp"
  logVerbose "Unzipping war '$war_path' to tmpdir '$newWebappDir'" ;
  
  test -n "$dryrun" || mkdir "$newWebappDir" || checkLastExitStatus ;
  test -n "$dryrun" || unzip -d "$TMP_DIR/webapp" "$war_path" 1> /dev/null || checkLastExitStatus ;
}

# Recreate symlink in unzipped webapp
copySymLink() { 
  logVerbose "Recreate symlinks in new webapp '$newWebappDir'" ;
  
  logVerbose " - move archives directory (if any) \t: 'archives' to '$TMP_DIR/archives.original'" ;
  test -n "$dryrun" || mv "$newWebappDir/archives" "$TMP_DIR/archives.original" 2> /dev/null ;
  logVerbose " - link archives directory \t: 'archives' --> '`readlink_replacement \"$target_dir/archives\"`'" ;
  test -n "$dryrun" || cp -P -r "$target_dir/archives" "$newWebappDir/"  || checkLastExitStatus ;

  logVerbose " - move upload directory (if any) \t: 'upload' to '$TMP_DIR/upload.original'" ;
  test -n "$dryrun" || mv "$newWebappDir/upload" "$TMP_DIR/upload.original" 2> /dev/null ;
  logVerbose " - link upload directory \t: 'upload' --> '`readlink_replacement \"$target_dir/upload\"`'" ;
  test -n "$dryrun" || cp -P -r "$target_dir/upload" "$newWebappDir/"  || checkLastExitStatus ;
  
  logVerbose " - move data directory \t: 'WEB-INF/data' to '$TMP_DIR/data.original'" ;
  test -n "$dryrun" || mv "$newWebappDir/WEB-INF/data" "$TMP_DIR/data.original"  || checkLastExitStatus ;
  logVerbose " - link data directory \t: 'WEB-INF/data' --> '`readlink_replacement \"$target_dir/WEB-INF/data\"`'" ;
  test -n "$dryrun" || cp -P -r "$target_dir/WEB-INF/data" "$newWebappDir/WEB-INF/"  || checkLastExitStatus ;
}

# Backup store.xml before overwrite or merge
backupStoreBeforeModification() {
  backup_store_path="$target_dir/WEB-INF/data/store.xml.$BACKUP_SUFFIX" ;
  echo "[store.xml] Old 'store.xml' backuped to '$backup_store_path'" ;
  test -n "$dryrun" || cp "$target_dir/WEB-INF/data/store.xml" "$backup_store_path"  || checkLastExitStatus ;
  test -n "$dryrun" || pushRollbackCommand "mv -f \"$backup_store_path\" \"$target_dir/WEB-INF/data/store.xml\"" ; 
}

# Process Store
processStore() {
  logVerbose "Process store.xml" ;
  
  if [ "$store" == "keep" ]; then
    logVerbose "[store.xml] Keep existing store" ;
    # nothing to do
    echo "[store.xml] store unmodified ('$target_dir/WEB-INF/data/store.xml') " ;
    
  elif [ "$store" == "overwrite" ]; then
    logVerbose "[store.xml] Overwrite with new store : replace existing store.xml with new store.xml from WAR" ;
    backupStoreBeforeModification ;
    
    # Overwrite webapp store with store.xml from WAR
    test -n "$dryrun" || mv -f "$TMP_DIR/data.original/store.xml" "$newWebappDir/WEB-INF/data/store.xml"  || checkLastExitStatus ;    
    echo "[store.xml] store.xml retrieved from new war" ;
    
  elif [ "$store" == "merge" ]; then
    logVerbose "[store.xml] Merge stores" ;
    backupStoreBeforeModification ;
    
    # Invoke Store Merge
    test -n "$dryrun" || storeMerge  "$newWebappDir/WEB-INF/data/store.xml" "$TMP_DIR/data.original/store.xml" ;
    echo "[store.xml] store.xml from existing webapp and from new war merged successfully " ;
    
  fi  
}

# Process Types
processTypes() {
  logVerbose "Process types (replace existing types with new one)" ;
  
  # Backup existing types before using new one
  backup_types_path="$target_dir/WEB-INF/data/types.$BACKUP_SUFFIX" ;
  echo "[types] Old 'types' directory backuped to '$backup_types_path'" ;
  test -n "$dryrun" || mv "$newWebappDir/WEB-INF/data/types" "$backup_types_path"  || checkLastExitStatus ;
  test -n "$dryrun" || pushRollbackCommand "rm -rf \"$newWebappDir/WEB-INF/data/types\" || mv \"$backup_types_path\" \"$newWebappDir/WEB-INF/data/types\"" ; 

  # Import Types from new webapp data
  test -n "$dryrun" || mv "$TMP_DIR/data.original/types" "$newWebappDir/WEB-INF/data/types"  || checkLastExitStatus ;
}

# Process Workflow
processWorkflows() {
  logVerbose "Process workflows (replace existing worfklows with new one)" ;
  
  # Backup existing workflows before using new one
  backup_workflows_path="$target_dir/WEB-INF/data/workflows.$BACKUP_SUFFIX" ;
  echo "[workflows] Old 'workflows' directory backuped to '$backup_workflows_path'" ;
  test -n "$dryrun" || mv "$newWebappDir/WEB-INF/data/workflows" "$backup_workflows_path"  || checkLastExitStatus ;
  test -n "$dryrun" || pushRollbackCommand "rm -rf \"$newWebappDir/WEB-INF/data/workflows\" || mv \"$backup_workflows_path\" \"$newWebappDir/WEB-INF/data/workflows\"" ; 

  # Import Workflow from new webapp data
  test -n "$dryrun" || mv "$TMP_DIR/data.original/workflows" "$newWebappDir/WEB-INF/data/workflows"  || checkLastExitStatus ;
  return ;
}

# Replace the target webapp with the newly modified webapp
processDeploy() {
  logVerbose "Perform deployement (backup existing webapp and replace with new one)" ;
  
  # Backup existing webapp
  if [[ -d "$backup_dir" ]]; then
    backup_webapp_path="$backup_dir/"$(basename "$target_dir.$BACKUP_SUFFIX") ;
  else
    backup_webapp_path="$target_dir.$BACKUP_SUFFIX" ;
  fi
  echo "[webapp] Old webapp backuped to '$backup_webapp_path'" ;
  test -n "$dryrun" || mv "$target_dir" "$backup_webapp_path"  || checkLastExitStatus ; 
  test -n "$dryrun" || pushRollbackCommand "mv \"$backup_webapp_path\" \"$target_dir\"" ; 
  
  # Move new webapp to target folder
  echo "[webapp] Installing new webapp" ;
  logVerbose "[webapp] move '$newWebappDir' to '$target_dir'" ;
  test -n "$dryrun" || mv "$newWebappDir" "$target_dir"  || checkLastExitStatus ;
  test -n "$dryrun" || pushRollbackCommand "mv \"$target_dir\" \"$newWebappDir\"" ; 

  # Log information
  deploy_log_dir="$target_dir/WEB-INF/data/logs" ;
  deploy_log_file="$deploy_log_dir/deploy.log" ;
  test -n "$dryrun" || mkdir -p "$deploy_log_dir" && touch "$deploy_log_file" ;
  test -n "$dryrun" || echo `date` " - Done deploying war '$war_path'." >> "$deploy_log_file" ;
  if [[ -n "$log_msg" ]]; then
    logVerbose "Append custom log message to '$deploy_log_file'" ;
    logVerbose "$log_msg" ;
    test -n "$dryrun" || echo "$log_msg" >> "$deploy_log_file" ;
  fi
  if [[ -n "$log_diff" ]]; then
    logVerbose "Log diff between new and old webapp directories..."
    test -n "$dryrun" || diff -r "$target_dir" "$backup_webapp_path" | grep -i "docs/javadoc/" >> "$deploy_log_file" ;
  fi
  test -n "$dryrun" || echo -e "\n\n\n"  >> "$deploy_log_file" ;

  # Cleanup backup and save all information in one place : the backuped webapp directory
  logVerbose "[webapp] Remove symlinks from backuped webapp" ;
  test -n "$dryrun" || rm -f "$backup_webapp_path/archives" ;
  test -n "$dryrun" || rm -f "$backup_webapp_path/upload" ;
  test -n "$dryrun" || rm -f "$backup_webapp_path/WEB-INF/data" ;
  logVerbose "[webapp] Move backuped store, types and workflow in backuped webapp" ;
  test -n "$dryrun" || mkdir -p "$backup_webapp_path/deploy-backup" ;
  if [[ -f "$backup_store_path" ]]; then
    test -n "$dryrun" || mv "$backup_store_path" "$backup_webapp_path/deploy-backup/store.xml" ;
  fi
  if [[ -d "$backup_types_path" ]]; then
    test -n "$dryrun" || mv "$backup_types_path" "$backup_webapp_path/deploy-backup/types" ;
  fi
  if [[ -d "$backup_workflows_path" ]]; then
    test -n "$dryrun" || mv "$backup_workflows_path" "$backup_webapp_path/deploy-backup/workflows" ;
  fi

  
  echo "DONE" ;
}

# cleanup temp directory
processCleanup() {
  logVerbose "Perform cleanup" ;
  if [ -d "$TMP_DIR" ]; then
    test -n "$dryrun" || rm -rf "$TMP_DIR" ;
  fi
}

#######################################
# interrupt trap method

interruptedCallback() {
  scriptInterrupted=1 ;
  echo '' >&2 ;
  echo 'WARNING !! script was interrupted.' >&2 ;
  rollback ;
  processCleanup ;
}

#######################################
# main entry
main() {

  # Display TODO to developpers
  grep "^\s*## TODO" "$0" ;

  # Parse & Check arguments as well as environements 
  parseArguments "$@" ;
  cleanPaths ;  
  checkRequirements ;
  
  # Initialized required variables 
  setupEnvironment ;
  
  # Ensure proper rollback and cleanup 
  trap interruptedCallback SIGINT SIGTERM ;
  
  # Start unzipping war and setting up symlink
  unzipWar ;
  copySymLink ;
  
  # Update the content of the symlinked data according to options
  processStore ;
  processTypes ;
  processWorkflows ;
  
  # Replace the old webapp with the new updated one
  processDeploy ;

  # clean
  processCleanup ; 
  
  exit 0;
}

main "$@" ;
