#!/bin/bash
#
# ----------------------------------------------------------------------------------------------
# This shell script packages basic maintenance operation :
# - restart tomcat instance
# - deploys a war, packaged by jade (jalios continuous delivery virtual machine) 
#   to the local tomcat instance
# - prepare and test the environnement 
# - check log lines
#
# This script has been thinked for the following CG44, Solaris Template :
#   Template: cg44
#   Version: 2.8.0.RELEASE
#   Build Date: 20121105140200
# ----------------------------------------------------------------------------------------------
#
# Based on Jalios documentation :
# http://community.jalios.com/jcms/jx_67249/fr/nouveau-systeme-de-deploiement
# https://community.jalios.com/upload/docs/application/pdf/2013-03/jcms_8.0_-_manuel_dinstallation_et_dexploitation.pdf
#
# ----------------------------------------------------------------------------------------------
# Author :
# Julien BAYLE, 2013


#######################################
# Global variables
cd ~ ;
basepath=`pwd` ;
webbapps_folder="$basepath/cg44_appli/webapps" ;
scripts_folder="$basepath/scripts" ;
#logs_folder="$basepath/logs/tomcat" ;
jade_war_folder="$basepath/cg44_appli/jade/dist" ;
nfs_folder="$basepath/cg44_appli/persistentdata" ;
backup_folder="$basepath/cg44_appli/backup" ;
script_version="0.1" ;

#######################################
# script variables
operation= 
warName=
verbose=
verboseIdx=0
script_interrupted=0
store_overwrite=
show_all_infos=
tomcatworkdir=
special_environnement=
tomcattempdir=
tomcatenvname=
test_start_line=
restart=
TMP_DIR=
BACKUP_SUFFIX=
isSolaris=1
isOldSles=0;
logs_folder="$basepath/logs/tomcat";

#######################################
# Tomcat logs ignored messages
# log4j:ERROR|log4j:WARN : Log4j ERROR which is not really one
# processMessage: bad message: 1405 - Bad Leader (message normal lors de la mise à jour du noeud maître JCMS
# Attempting to load (validation|ESAPI)|Found in \'org.owasp|Loaded \'(validation|ESAPI) : INFO messages
# Use of webapp\.prop : BAD WARN message (no such file)
# org\.apache\.catalina\.startup : INFO messages
igLogs="(log4j:ERROR|log4j:WARN|Bad Leader|Attempting to load (validation|ESAPI)|Found in \'org.owasp|Loaded \'(validation|ESAPI)|IE_WRITE_RPT|ie_write_rpt|IS_WRITE_RPT|is_write_rpt|IW_WRITE_RPT|iw_write_rpt|CalendarEvent|Use of webapp\.prop|org\.apache\.catalina\.startup\.Catalina (load|start))"


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
# Test if site home page is reachable
checkIfhomePageIsReachable() {
  localurl=`readTomcatURL` || checkLastExitStatus ;
  logVerbose "Is environnement is up ($localurl) ?" ;
  
  if [ $isSolaris == "1" ]; then
    # Solaris
	check=`/usr/sfw/bin/wget -T 300 -q -O- "$localurl" | grep "data-jalios-pack-version" | wc -l` ;
  else
    # Linux
	check=`/usr/bin/wget -T 300 -q -O- "$localurl" | grep "data-jalios-pack-version" | wc -l` ;
  fi
  
  checkLastExitStatus ;

  if [ "$check" -lt "1" ] ; then
    echo "Term 'data-jalios-pack-version' not found on home page. Is this site really up ?" >&2 ;
    processCleanupAndExit -1
  fi
  logVerbose "OK, environnement is up !" ;
}

#######################################
# Check environnement
checkIfLeader() {

  checkIfhomePageIsReachable ;
  
  # Go to "read only" mode if this node is the master node and stop JSYNC replication
  logVerbose "Does this node is the leader note for this cluster ?" ;
  cp "$scripts_folder/cg_deploy_jcms_api.jsp" "$webbapps_folder/ROOT/admin/" ;
  
  if [ $isSolaris == "1" ]; then
    # Solaris
	  updateModebuffer=`/usr/sfw/bin/wget -T 1 -q -O- "$localurl/admin/cg_deploy_jcms_api.jsp?mode=isolate_and_update_node_if_master"` ;
  else
    # Linux
	  updateModebuffer=`/usr/bin/wget -T 1 -q -O- "$localurl/admin/cg_deploy_jcms_api.jsp?mode=isolate_and_update_node_if_master"` ;
  fi
  
  checkLastExitStatus ;

  isLeader=`echo "$updateModebuffer" | grep "leader:true" | wc -l` ;
  checkLastExitStatus ;
  if [ "$isLeader" == "0" ] ;
  then
    echo "Not the leader node, no update required for this node" >&2 ;
    processCleanupAndExit -1 ;
  else
    logVerbose "This node is the leader node, continuing update" ;
  fi

  isReadOnly=`echo "$updateModebuffer" | grep "write:false" | wc -l` ;
  checkLastExitStatus ;
  if [ "$isReadOnly" == "0" ] ;
  then
    echo "Node is still in Write mode !" >&2 ;
    processCleanupAndExit -1 ;
  else
    logVerbose "Node is now in -read only- mode, continuing update" ;
  fi

  isJyncOff=`echo "$updateModebuffer" | grep "mode:single_node_isolated" | wc -l` ;
  checkLastExitStatus ;
  if [ "$isJyncOff" == "0" ] ;
  then
    echo "JSYNC is still active, cannot update this node !" >&2 ;
    processCleanupAndExit -1 ;
  else
    logVerbose "JSYNC is now inactive for this node, ready for update" ;
  fi
  
}

#######################################
# Convenient method to get current
# catalina.out line count
#
getCurrentCalinaOutLineCount() {
  if [ -f $logs_folder/catalina.out ]; then
  	catalina_line_count=`cat $logs_folder/catalina.out | wc -l` ;
  	catalina_line_count=`expr $catalina_line_count + 0` ;
  	echo "$catalina_line_count" ;
  else
    echo "0" ;
  fi
}

#######################################
# Convenient method to check tomcat
# logs quickly
checkTomcatLogsBetweenLines() {
  
  if [ $# != "2" ]; then
    echo "checkTomcatLogsBetweenLines takes two arguments !" >&2 ;
    processCleanupAndExit -1 ;
  fi

  from_line_count=$1 ;
  to_line_count=$2 ;

  # Count line by message type during Tomcat startup process
  if [ -f $logs_folder/catalina.out ]; then
	if [ $isSolaris == "1" ]; then
		# Solaris
		fatalcount=`sed ''"$from_line_count,$to_line_count"'!d' $logs_folder/catalina.out | grep "FATAL"  | /usr/xpg4/bin/grep -v -E "$igLogs" | wc -l` || checkLastExitStatus ;
		errorcount=`sed ''"$from_line_count,$to_line_count"'!d' $logs_folder/catalina.out | grep "ERROR" | /usr/xpg4/bin/grep -v -E "$igLogs" | wc -l` || checkLastExitStatus ;
		exceptioncount=`sed ''"$from_line_count,$to_line_count"'!d' $logs_folder/catalina.out | grep "Exception" | /usr/xpg4/bin/grep -v -E "$igLogs" |  wc -l` || checkLastExitStatus ; 
		warncount=`sed ''"$from_line_count,$to_line_count"'!d' $logs_folder/catalina.out | grep "WARN" | /usr/xpg4/bin/grep -v -E "$igLogs" |  wc -l` || checkLastExitStatus ;
		infocount=`sed ''"$from_line_count,$to_line_count"'!d' $logs_folder/catalina.out | grep "INFO" | wc -l` || checkLastExitStatus ;
	else
		# Linux
		fatalcount=`sed ''"$from_line_count,$to_line_count"'!d' $logs_folder/catalina.out | grep "FATAL"  | /usr/bin/grep -v -E "$igLogs" | wc -l` || checkLastExitStatus ;
		errorcount=`sed ''"$from_line_count,$to_line_count"'!d' $logs_folder/catalina.out | grep "ERROR" | /usr/bin/grep -v -E "$igLogs" | wc -l` || checkLastExitStatus ;
		exceptioncount=`sed ''"$from_line_count,$to_line_count"'!d' $logs_folder/catalina.out | grep "Exception" | /usr/bin/grep -v -E "$igLogs" |  wc -l` || checkLastExitStatus ; 
		warncount=`sed ''"$from_line_count,$to_line_count"'!d' $logs_folder/catalina.out | grep "WARN" | /usr/bin/grep -v -E "$igLogs" |  wc -l` || checkLastExitStatus ;
		infocount=`sed ''"$from_line_count,$to_line_count"'!d' $logs_folder/catalina.out | grep "INFO" | wc -l` || checkLastExitStatus ;
	fi
	
  
    if [ "$fatalcount" -gt "0" -o "$errorcount" -gt "0" -o "$exceptioncount" -gt "0" -o "$warncount" -gt "0" ];  then
      echo "Tomcat logs contains bad news : $fatalcount FATAL, $errorcount ERROR, $exceptioncount exception(s), $warncount WARN !" >&2 ;
      processCleanupAndExit -1 ;
    else
      logVerbose "Tomcat logs contains $fatalcount FATAL, $errorcount ERROR, $exceptioncount exception(s), $warncount WARN and $infocount INFO" ;
    fi
  else
    echo "Catalina.out is not readable... please check if tomcat has really started successfully" >&2 ;
    processCleanupAndExit -1 ;
  fi
}

#######################################
# Convenient method to review tomcat
# logs quickly
viewTomcatLogsBetweenLines() {
  
  if [ $# != "2" ]; then
    echo "checkTomcatLogsBetweenLines takes two arguments !" >&2 ;
    processCleanupAndExit -1 ;
  fi

  from_line_count=$1 ;
  to_line_count=$2 ;

  if [[ -n "$verbose" && -f $logs_folder/catalina.out ]]; then   
    if [ -n "$show_all_infos" ]; then
      sed ''"$from_line_count,$to_line_count"'!d' "$logs_folder/catalina.out" ;
    else
		if [ $isSolaris == "1" ]; then
			# Solaris
			sed ''"$from_line_count,$to_line_count"'!d' "$logs_folder/catalina.out" | grep -v "INFO" | grep -v "Rhino" | /usr/xpg4/bin/grep -v -E "$igLogs" ; 
		else
			# Linux
			sed ''"$from_line_count,$to_line_count"'!d' "$logs_folder/catalina.out" | grep -v "INFO" | grep -v "Rhino" | /usr/bin/grep -v -E "$igLogs" ; 
		fi
    fi
  fi
}

#######################################
# Convenient method to check is JCMS
# is ready (returns 1) 
# or has failed to start (returns 500)
# or if JCMS is still starting (returns 0)
isJCMSready() {

  if [ $# != "2" ]; then
    echo "isJCMSready takes two arguments !" >&2 ;
    processCleanupAndExit -1 ;
  fi
  
  # Check if JCMS failed to start
  if [ -f $logs_folder/catalina.out ]; then  
    failedtostart=`sed ''"$1,$2"'!d' "$logs_folder/catalina.out" | grep "ChannelInitServlet.*is not available" | wc -l` ;
    if [ "$failedtostart" -gt "0" ]; then
      echo "500" ;
    else
      sed ''"$1,$2"'!d' "$logs_folder/catalina.out" | grep "ChannelInitServlet.*is ready" | wc -l ;
    fi
  else
    echo "0"
  fi
}

#######################################
# Start Tomcat
#
# clear tomcat word directory
# echoes catalina.out to the console during the startup process
# counts messages by type (warn, error, ...)
# validates if restart succeed
startTomcatSafely() {

  # Clear tomcat work directory
  logInfo "Clearing tomcat work directory (rm -Rf $tomcatworkdir/*)"
  rm -Rf "$tomcatworkdir/*"
  logVerbose "Tomcat work directory cleared"

  # Clear tomcat temp directory
  logInfo "Clearing tomcat temp directory (rm -Rf $tomcattempdir/*)"
  rm -Rf "$tomcattempdir/*"
  logVerbose "Tomcat temp directory cleared"
  
  # Init catalina log cursor
  initial_line_count=`getCurrentCalinaOutLineCount` ;
  previous_line_count=$initial_line_count ;

  # Set time out : 30 minutes max for tomcat start
  maxAttemps=180 
  currentAttemps=0

  # Set local URL
  echo "Set local URL..."
  localurl=`readTomcatURL` || checkLastExitStatus ;
  echo "local URL set !"

  # Start Tomcat
  logVerbose "Starting tomcat server ($localurl)" ;
  
  
  if [ $isSolaris == "1" ] || [ $isOldSles == "1" ]; then
    # Solaris ou ancien env SLES 
  startTomcatLogs=`$scripts_folder/cg_startTomcat.ksh`
  else
    # Linux
  startTomcatLogs=`$scripts_folder/cg_startTomcat.sh`
  fi

  
  if [ $? != "0" ]; then
    echo "$startTomcatLogs" ;
    echo "Tomcat did not start successfully. Aborting." >&2 ;
    processCleanupAndExit -1 ;
  fi
  logVerbose "Tomcat server has been started successfully, JCMS is starting..."

  # Wait for startup process is complete and check errors in catalina.out
  isStarted=0 ;
  until [ $isStarted == "1" -o $isStarted == "500" ];
  do
    logInfo "--- $localurl is not responding yet, sleeping for 10 seconds and watching for errors ($currentAttemps / $maxAttemps)" ;
    currentAttemps=`expr $currentAttemps + 1` || checkLastExitStatus ;

    if [ "$currentAttemps" == "$maxAttemps" ] ;
    then
      echo "Tomcat did not start successfully before the time out. Please check message logs ! Aborting." >&2 ;
      processCleanupAndExit -1 ;
    fi
    
    # Print last lines to console
    current_line_count=`getCurrentCalinaOutLineCount` ;
    if [ -n "$verbose" ]; then   
      viewTomcatLogsBetweenLines $previous_line_count $current_line_count
    fi
    
    sleep 10 ;
    isStarted=`isJCMSready $previous_line_count $current_line_count`;
    
    if [ "$isStarted" == "500" ];  then
      echo "JCMS has failed to start" >&2 ;
    fi
    
    previous_line_count=`expr $current_line_count + 1` || checkLastExitStatus ;
  done

  checkIfhomePageIsReachable ;

  current_line_count=`getCurrentCalinaOutLineCount` ;  
  logVerbose "Line count for catalina.out before startup : $initial_line_count" ;
  logVerbose "Line count for catalina.out after startup : $current_line_count" ;
  echo "$current_line_count" > "$webbapps_folder/ROOT/WEB-INF/jalios/catalina_count.txt" ;
  logInfo "Line count for catalina.out after startup saved in $webbapps_folder/ROOT/WEB-INF/jalios/catalina_count.txt" ;

  checkTomcatLogsBetweenLines $initial_line_count $current_line_count ;
}


#######################################
# StopTomcat if running
# 08/2019 : les commandes et les tests sont différents selon que l'on est sur Solaris, anciens SLES et nouveaux SLES
stopTomcat() {
  
  logVerbose "Stopping Tomcat server..." ;

  if [ $isSolaris == "1" ]; then
    # Solaris
  stopTomcatLogs=`$scripts_folder/cg_stopTomcat.ksh`
  else
    # Linux
  stopTomcatLogs=`$scripts_folder/cg_stopTomcat.sh`
  fi
  if [ $? != "0" ]; then
  	  logVerbose "Tomcat not running !" ;
  	  
  	  if [ $isSolaris == "1" ] || [ $isOldSles == "1" ]; then
      	notrunning=`echo $stopTomcatLogs | grep "Instance is not running" | wc -l` || checkLastExitStatus ;
      else
      	logVerbose "Nouvel env SLES" ;
      	notrunning=`echo $stopTomcatLogs | grep "Running state is unknown" | wc -l` || checkLastExitStatus ;
      fi
      
      
      notrunning=`expr $notrunning + 0` || checkLastExitStatus ;
      logVerbose "Not running : $notrunning" ;
      if [ "$notrunning" != "1" ]; then
         echo "$stopTomcatLogs" ;
         echo "Tomcat did not stop successfully. Aborting." >&2 ;
         processCleanupAndExit -1 ;
      fi
  fi
  logVerbose "Tomcat server has been stopped successfully"
}

#######################################
# Assert that Tomcat process is stopped
assertTomcatIsNotRunning() {
  tomcatStatusLogs=`$basepath/$tomcatenvname/bin/tcruntime-ctl.sh status` || checkLastExitStatus ;
  notrunning=`echo $tomcatStatusLogs | grep "NOT RUNNING" | wc -l` || checkLastExitStatus ;
  notrunning=`expr $notrunning + 0` || checkLastExitStatus ;
  if [ "$notrunning" != "1" ]; then
     echo "Tomcat process is running. Current operation requires Tomcat to be offline. Aborting." >&2 ;
     processCleanupAndExit -1 ;
  fi
  logVerbose "Tomcat server is not running."
}

#######################################
# Post war update actions
# (specific to CG44 deployment approach)
postWarUpdateActions() {
  
  # Publish or update build.prop 
  logVerbose "Publish or update build information file : WEB-INF/jalios/build.prop" ;
  mkdir -p "$TMP_DIR/temp" || checkLastExitStatus ;
  unzip -qq -d "$TMP_DIR/temp" "$jade_war_folder/$warName" "WEB-INF/jalios/build.prop" || checkLastExitStatus ;
  mv "$TMP_DIR/temp/WEB-INF/jalios/build.prop" "$webbapps_folder/ROOT/WEB-INF/build.prop" 2> /dev/null || checkLastExitStatus ;
  
  # Update custom.prop from SVN if needed
  logVerbose "Publish custom.prop (WEB-INF/data/custom.prop)" ;

  # custom.prop.jade : reference file (used to check if custom.prop has been modified since last deployment)
  # test is done if and only if it's not the first deployment
  if [ -f "$webbapps_folder/ROOT/WEB-INF/data/custom.prop.jade" ]; then
    diff "$webbapps_folder/ROOT/WEB-INF/data/custom.prop.jade" "$webbapps_folder/ROOT/WEB-INF/data/custom.prop" 1> /dev/null ;
    if [ $? != "0" ] ; then
      echo "Custom.prop has been modified since last deployment, theses modifications will be lost."  >&2 ;
      echo "Last custom.prop version saved to custom.prop.$BACKUP_SUFFIX"  >&2 ;
      cp "$webbapps_folder/ROOT/WEB-INF/data/custom.prop" "$webbapps_folder/ROOT/WEB-INF/data/custom.prop.$BACKUP_SUFFIX" 2> /dev/null || checkLastExitStatus ;
    fi
  fi
  if [ -n "$special_environnement" ]; then
    customname="custom.prop.$special_environnement" ;
  else
    customname="custom.prop" ;
  fi
  logVerbose "Deploy using the following custom.prop file : $customname" ;
  unzip -qq  -d "$TMP_DIR/temp" "$jade_war_folder/$warName" "WEB-INF/data/$customname" || checkLastExitStatus ;
  cp "$TMP_DIR/temp/WEB-INF/data/$customname" "$webbapps_folder/ROOT/WEB-INF/data/custom.prop.jade" 2> /dev/null || checkLastExitStatus ;
  cp "$TMP_DIR/temp/WEB-INF/data/$customname" "$webbapps_folder/ROOT/WEB-INF/data/custom.prop" 2> /dev/null || checkLastExitStatus ;

  logVerbose "Keep only the tree last webapp backup directories" ;
  while [ `ls -1 "$backup_folder" | wc -l` -gt 3 ]; do
    oldest=`ls -1tr "$backup_folder" | sort -z n | head -1`
    logVerbose "Remove old backup directory : $backup_folder/$oldest" ;
    rm -rf "$backup_folder/$oldest" ;
  done
}

#######################################
# Read local tomcat URL
# (specific to CG44 deployment approach)
readTomcatURL() {
  
  # Gets local node URL for the next steps of the script
  
  if [ $isSolaris == "1" ]; then
	# Solaris
    localurl=`dos2unix -850 "$webbapps_folder/ROOT/WEB-INF/data/custom.prop" | grep "site.private.url" | sed 's/site\.private\.url: //'` ;
  else
	# Linux
    localurl=`cat "$webbapps_folder/ROOT/WEB-INF/data/custom.prop" | grep "site.private.url" | sed 's/site\.private\.url: //'` ;
  fi  
  
  if [ "$localurl" == "" ]; then
         echo "Unable to determine locale URL. Aborting." >&2 ;
         processCleanupAndExit -1 ;
  fi
  echo $localurl ; 
}

#######################################
# Update existing JCMS webapp
updateWar() {

	# Compare SVN revision for store.xml file
  curent_svn_revision=`cat "$webbapps_folder/ROOT/WEB-INF/build.prop" | grep "build.store.svn.revision" | sed 's/build\.store\.svn\.revision=//' | sed 's/\\\n//'`;
  test_svn_rev=`echo "$curent_svn_revision" | sed 's/[0-9][0-9]*/1/'`
  echo "$test_svn_rev" ;
  if [ "$test_svn_rev" != "1" ]; then
    echo "Revision number of current webapp could not be determined ($curent_svn_revision, $test_svn_rev)" >&2 ;
    echo "Please check WEB-INF/build.prop file, property build.store.svn.revision. Aborting. " >&2 ;
    processCleanupAndExit -1 ;
  fi
  logInfo "Current store SVN revision : $curent_svn_revision" ;

  mkdir -p "$TMP_DIR/temp_store_op" || checkLastExitStatus ;
  unzip -qq -d "$TMP_DIR/temp_store_op" "$jade_war_folder/$warName" "WEB-INF/jalios/build.prop" || checkLastExitStatus ;
  next_svn_revision=`cat "$TMP_DIR/temp_store_op/WEB-INF/jalios/build.prop" | grep "build.store.svn.revision" | sed 's/build\.store\.svn\.revision=//' | sed 's/\\\n//'`;
  test_svn_rev=`echo "$next_svn_revision" | sed 's/[0-9][0-9]*/1/'`
  if [ "$test_svn_rev" != "1" ]; then
    echo "Revision number of next webapp could not be determined ($next_svn_revision)" >&2 ;
    echo "Please check WEB-INF/jalios/build.prop file, property build.store.svn.revision (WAR packaged by JADE). Aborting. " >&2 ;
    processCleanupAndExit -1 ;
  fi
  logInfo "Next store SVN revision : $next_svn_revision" ;

  if [ -n "$store_overwrite" ]; then
  	storeOperation="overwrite" ;
  	logVerbose "Store will be overwriten (overwrite operation)" ;
  else
	  if [ "$next_svn_revision" -gt "$curent_svn_revision" ]; then
	    storeOperation="merge" ;
	    logVerbose "Stores will be merged, because a SVN commit has been done on the store file since last deployment" ;
	  else
	    storeOperation="keep" ;
	    logVerbose "Store will not be modified (keep operation)" ;
	  fi
  fi

  # Read a cursor from catalina.out file
  logVerbose "Deploying $warName" ;
  if [ -n "$verbose" ]; then
    $scripts_folder/cg_deploy_jcms.sh -v -z -s "$storeOperation" -m "Deploying $warName" -b "$backup_folder"  "$jade_war_folder/$warName" "$webbapps_folder/ROOT"  ;
    checkLastExitStatus ;
  else
    $scripts_folder/cg_deploy_jcms.sh -z -s "$storeOperation" -m "Deploying $warName" -b "$backup_folder"  "$jade_war_folder/$warName" "$webbapps_folder/ROOT"  ;
    checkLastExitStatus ;
  fi

  logInfo "Deployment log file available here : $webbapps_folder/ROOT/WEB-INF/data/logs/deploy.log" ;
  logInfo "Old webapps backup available here : $backup_folder" ;
  
  logVerbose "Webapp successfully updated."

  postWarUpdateActions ;
}


#######################################
# First deploy : initialiaze symbolic links in persistentdata folder
deployWarAndSymbolicLinks() {

  logVerbose "Persistent data folder not initialized : initilizing persistentdata directory and deploying OK..."

  # unzip JCMS war build by jade into  $basepath/cg44_appli/webapps/ROOT
  mv "$webbapps_folder/ROOT" "$backup_folder/ROOT.$BACKUP_SUFFIX" || checkLastExitStatus ;
  logInfo "Old ROOT folder moved to $backup_folder/ROOT.$BACKUP_SUFFIX"
  
  mkdir "$webbapps_folder/ROOT" || checkLastExitStatus ;
  unzip "$jade_war_folder/$warName" -d "$webbapps_folder/ROOT" 1> /dev/null || checkLastExitStatus ;
  logInfo "$jade_war_folder/$warName unpacked in $webbapps_folder/ROOT"

  mkdir "$nfs_folder"  || checkLastExitStatus ;
  mkdir "$nfs_folder/archives"  || checkLastExitStatus ;
  mv "$webbapps_folder/ROOT/upload" "$nfs_folder"  || checkLastExitStatus ;
  mv "$webbapps_folder/ROOT/WEB-INF/data" "$nfs_folder" || checkLastExitStatus ;
  echo "MANDATORY Please upload your latest version of 'upload' directory to the $nfs_folder/upload directory"  >&2 ;
  
  ln -s "$nfs_folder/archives" "$webbapps_folder/ROOT/archives"  || checkLastExitStatus ;
  ln -s "$nfs_folder/upload" "$webbapps_folder/ROOT/upload"  || checkLastExitStatus ;
  ln -s "$nfs_folder/data" "$webbapps_folder/ROOT/WEB-INF/data" || checkLastExitStatus ;

  logVerbose "Persistent data folder initialized successfully and war deployement done."

  postWarUpdateActions ;
}


#######################################
# Display shell script usage
usage() {
  if [ $# -ne 0 ]; then 
    echo "$@" >&2 ;
  fi
  printf "Usage: %s: [-hdrvit] [-w pathtowar]" $(basename $0) >&2 ;
  echo "
 -h            displays version and this help message
 -d            performs DEPLOY action
 -o            force store overwrite operation during DEPLOY
 -r            performs RESTART action
 -l            returns current line count for catalina.out
 -t num        checks errors in catalina.out between line num 
               and the end of the file. If num equals 0, then
               check from the last line written during the last
               reboot or deploy operation 
               (use verbose or show_all_infos modes with this option
               to get all details)
 -v            verbose mode, display detailed operation 
 -i            verbose mode, display very detailed operation 
 -t            perfoms tests and warmup after restart
 -w pathtowar  Selects the war to deploy. Default action is to deploy last war 
               built by jade and available in $jade_war_folder
 -e env        Give a specific environnement to deploy (dev1, dev2, prod, ...)
               
  Script version : $script_version
  " >&2 ;
  processCleanupAndExit 1 ;
}


#######################################
# Parse aguments
parseArgumentsAndInitEnvironnement() {

  BACKUP_SUFFIX=`date +'%F-%H%M%S'` || checkLastExitStatus ;

  # On teste si on est sous Solaris ou SLES
  osNameCmd=`uname` ;
  osName=`echo "$osNameCmd"` ;

  if [ "$osName" == "Linux" ]; then
    isSolaris="0" ;
  fi
    
  # On regarde de quel user il s'agit
  userName=`echo $USER` ;

  echo "User :  (\"$userName\")" ;


  	
  # Sur les nouveaux environnements les logs sont centralisés et ne sont plus au même endroit que sur Solaris, ni que sur les 1ers env SLES (Planet + Observatoire)
  if [ "$osName" == "Linux" ]; then
  	logs_folder="/log/app/$userName/tomcat";
    
      if [ "$userName" == "u1d88dev" ] || [ "$userName" == "u1d88pro" ] || [ "$userName" == "sobsr" ]|| [ "$userName" == "sobsp" ]; then
    	echo "Ancien environnement SLES (Planet ou Observatoire)";
    	logs_folder="$basepath/logs/tomcat";
    	isOldSles="1";
  	  fi
  fi
    

  
  # Checks if environnement is ready for a deployment
  if [ ! -d "$jade_war_folder" ]; then
    echo "Folder $jade_war_folder is missing. This environnement is not connected to a JADE project. Aborting. " >&2 ;
    processCleanupAndExit -1 ;
  fi
  if [ ! -d "$backup_folder" ]; then
    mkdir "$backup_folder" || checkLastExitStatus ; 
  fi

  # Parse Arguments
  while getopts 'hdorlt:vitw:e:' OPTION
  do
    case $OPTION in
      h)    usage "cg_deploy_jcms.sh" ;;
      d)    operation="DEPLOY" ;;
      r)    operation="RESTART" ;;
      l)    operation="CURRENT_LOG_COUNTER" ;;
      o)	  store_overwrite=1 ;;
      t)    test_start_line=$OPTARG ; operation="TEST_LOGS" ;;
      v)    verbose=1 ;;
      i)    show_all_infos=1 ;;
	    w)	  warName=$OPTARG ;; # deploy a specific war
      e)    special_environnement=$OPTARG ;;
      [?])  usage "Invalid option -$OPTARG" ;;
      :)    usage "Option -$OPTARG requires an argument." ;;

    esac
  done
  shift $(($OPTIND - 1))
  
  if [ "$operation" == "" ]
  then
    usage ;
  fi

  # If very detailled verbose mode is active, then verbose mode should be active
  if [ -n "$show_all_infos" ]; then
    verbose=1 ;
  fi

  # Create temporary work directory
  TMP_DIR=`mktemp -u -d` || TMP_DIR=`mktemp -d` ;
  logInfo "Temporary directory created (\"$TMP_DIR\")" ;

  # Determine which war to deploy (lasted war is used if no argument has been defined)
  # if not passed by argument
  if [ "$warName" == "" ]; then
    warName=`ls -1tr "$jade_war_folder" | tail -1` ;
    testWarName=`echo "$warName" | sed 's/[a-zA-Z]*[0-9\.\-]*war/1/'`
    if [ "$testWarName" != "1" ]; then
      echo "Unable to determine war name to deploy from jade releases directory $jade_war_folder." >&2 ;
      processCleanupAndExit -1 ;
    fi
  fi

  # /tcsdom/u1d68dev/cg44_appli/webapps -> /tcsdom/u1d68dev/D68dev/webapps (DEV SOLARIS ou DEV/PROD LINUX) ou /global/tcsdom/u1d68pro/D68pro/webapps (PROD SOLARIS)
  # Sous SLES 2018+, le USER est un nom en majuscules
  # extract D68dev in order to clear tomcat work directory 
  logInfo "Webapp folder : $webbapps_folder" ;
  
  # extract using DEV pattern
  tomcatenvname=`ls -l "$webbapps_folder" | sed 's/.*-> \/[0-9a-zA-Z]*\/[0-9a-zA-Z]*\///' | sed 's/\/webapps.*//'` ;
  logInfo "Tomcat envname : $tomcatenvname" ;
  
  testenvname=`echo "$tomcatenvname" | sed 's/\([A-Z]*[0-9]*[devpro]*\)/1/'` ;
  logInfo "Test envname : $testenvname" ;
    
  if [ "$testenvname" != "1" ]; then
  	# Solaris (l'arbo "/global") n'existe que sous Solaris PROD.
  	tomcatenvname=`ls -l "$webbapps_folder" | sed 's/.*-> \/global\/[0-9a-zA-Z]*\/[0-9a-zA-Z]*\///' | sed 's/\/webapps//'` ;

    testenvname=`echo "$tomcatenvname" | sed 's/D[0-9]*pro/1/'`
    if [ "$testenvname" != "1" ]; then
      echo "Unable to extract Tomcat environnement value ($tomcatenvname)" >&2 ;
      processCleanupAndExit -1 ;
    fi
  fi
  tomcatworkdir="$basepath/$tomcatenvname/work" ;
  tomcattempdir="$basepath/$tomcatenvname/temp" ;

  logInfo "Tomcat work directory = $tomcatworkdir" ;
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
  logInfo "Performing cleanup..." ;
  if [ -d "$TMP_DIR" ]; then
    rm -Rf "$TMP_DIR" || checkLastExitStatus ;
  fi
  logInfo "Temporary folder cleaned" ;

  # Delete JADE releasese except the three most recent
  nbwar=`ls -l $jade_war_folder/*.war | wc -l` ;
  if [ "$nbwar" -gt "3" ]; then
    for i in `ls $jade_war_folder | sed 's/-.*//' | uniq`; do ls -t $jade_war_folder/*.war | awk '{if(NR>3) print}' | xargs rm -f; done
    logInfo "JADE releases deleted except the three most recent" ;
  fi

  exit $1;
}


#######################################
# main entry
main() {
  
  # Parse & Check arguments as well as environements 
  echo "parseArgumentsAndInitEnvironnement..."
  parseArgumentsAndInitEnvironnement "$@" ;
 
  # RESTART
  if [ "$operation" == "RESTART" ]; then
    logInfo "Operation : Simple restart"
    stopTomcat ;  
    startTomcatSafely ;
  fi

  # DEPLOY
  if [ "$operation" == "DEPLOY" ]; then
	echo "DEPLOY..."
    stopTomcat ;  
    
    if [ -d "$nfs_folder" -a -d "$nfs_folder/data" ]; then
      # persitentdata folder is initialized, update
      updateWar ;
    else
      #TODO checkIfLeader ;
      # If persistentdata folder is not initialized, deploy as firt deployment
      deployWarAndSymbolicLinks ;
    fi

    startTomcatSafely ;
  fi

  # CURRENT_LOG_COUNTER
  if [ "$operation" == "CURRENT_LOG_COUNTER" ]; then
    echo $(getCurrentCalinaOutLineCount) ;
  fi
  
  # TEST_LOGS
  if [ "$operation" == "TEST_LOGS" ]; then
    test_end_line=`getCurrentCalinaOutLineCount` ;
    viewTomcatLogsBetweenLines $test_start_line  $test_end_line  ;
    checkTomcatLogsBetweenLines $test_start_line  $test_end_line  ;
  fi

  processCleanupAndExit 0;

}

logVerbose "TODO : ifleader + JSYNC + documentation" ;

main "$@" ;
