#!/bin/bash

# This script synchronizes the local git mirror repositories with github
# It iterates over all the folders in a certain directory (GIT_REPOSITORIES) and tries
# to establish if it's a git repository. If it is, it starts fetching from the git 
# remote called "origin" and updates the refs in order to synchronize the HEADS of the
# local repository.

GIT_REPOSITORIES=/data/git-repositories
LOG_PATH=/var/log/git-sync.log
CURRENT_PATH=`pwd`
RUN_DIRECTORY=/var/run/sync-git
JENKINS_URL=http://whvmescidoc5.fiz-karlsruhe.de:8484/jenkins
JENKINS_DELAY=300

# use an associative array for storing the maps between git and jenkins project names
# WARNING: don't use underscores '_' in array names, that got me in trouble!
declare -A projects 

projects[escidoc-browser]="eSciDocBrowser"
projects[escidoc-core]="eSciDocCoreTrunk"
projects[escidoc-core1.3]="eSciDocCore1.3"
projects[escidoc-core1.4]="eSciDocCore1.4"
projects[escidoc-metadata-updater]="escidoc-metadata-updater"
projects[ddb-common]="ddb-common"
projects[ddb-next]="ddb-next"
projects[ddb-registration]="ddb-registration"
projects[apd]="apd"
projects[escidoc-ng]="escidoc-ng"
projects[iais]="iais"
projects[apd-selenium]="apd-selenium"

# store the branches of the projects which should be build on jenkins when it
# changed
declare -A branches
branches[escidoc-core]="master 1.3 1.4"
branches[escidoc-browser]="master"
branches[escidoc-metadata-updater]="master"
branches[ddb-common]="master develop"
branches[ddb-next]="master develop"
branches[ddb-registration]="develop"
branches[apd]="develop"
branches[escidoc-ng]="master"
branches[iais]="develop"
branches[apd-selenium]="master"

function error {
	# send an email to admin and log to /var/log/daemon.*
    # then exit so nothing can get crushed
	logger -p daemon.err An error occured while syncing the git repositories.
	echo -e "An error has occured while syncing the git repositories. Please check the log at ${LOG_PATH} at host ${HOSTNAME}. This is a generated message.\n\nMessage text:\n$1\n" | /usr/bin/mail -s "SYNC Error" "eSciDocAdmin@fiz-karlsruhe.de" -- -r "git-sync-cronjob@whvmescidoc4.fiz-karlsruhe.de"
    exit -1
}

function trigger_jenkins {
    # trigger the build on the jenkins server
    PROJECT_NAME=${1}
    if [ ${2} != "master" ]; then
        PROJECT_NAME=${PROJECT_NAME}${2}
    fi
    if [ -z ${projects[$PROJECT_NAME]} ]; then
        echo "skipping build of unknown project $PROJECT_NAME" &>> $LOG_PATH
        return
    fi
    echo "triggering build of $PROJECT_NAME" >> $LOG_PATH
    curl -sL -w "Jenkins returned: %{http_code} for  %{url_effective}\\n" "$JENKINS_URL/job/${projects[$PROJECT_NAME]}/build?delay=${JENKINS_DELAY}sec" -o /dev/null &>> $LOG_PATH
	RETVAL=$?
	[ $RETVAL -eq 0 ] && logger -p daemon.info triggered build of $PROJECT succesfully
	[ $RETVAL -ne 0 ] && error "unable to trigger build on $JENKINS_URL for $PROJECT" 
}

# check if a valid user is running this script and ask if he knows what he's doing
if [ "$(id -u)" == 0 ]; then
    echo -ne "WARNING!\nroot user detected\nAre you sure you want to run this script as the root user [y/n]? "
    read OVERWRITE
    if [ !OVERWRITE != "y" ]; then
        exit 1
    fi
fi


# iterate over all repositories in the given path to discover the 
# git repositories in the given path
START_TIME=$SECONDS
echo "--------- `date`"  >> $LOG_PATH
for FOLDER in $GIT_REPOSITORIES/* ; do
    if [ ! -d $FOLDER ]; then
        echo "skipping regular file $FOLDER"
        continue
    fi
	
    # go into to the subdirectory and fetch from origin so the local
	# repository gets synced with origin
	cd $FOLDER
    
    # check if it's a git repo by invoking a git command and check if it's succeded
    git log -1 &> /dev/null
    if [ $? -ne 0 ]; then
        echo "skipping non git repository $FOLDER"
        continue
    fi
    
    REPO_NAME=`basename $FOLDER`
	REMOTE_URI=`git remote -v | grep -E "^origin.*\(fetch\)$" | awk '{print $2;}'` 

    echo ":: syncing git repository $REMOTE_URI" &>> $LOG_PATH
	git fetch origin &>> $LOG_PATH
	RETVAL=$?
	[ $RETVAL -eq 0 ] && logger -p daemon.info fetched successfully from $REMOTE_URI
	[ $RETVAL -ne 0 ] && error "unable to fetch from $REMOTE_URI"
	
	# and dont forget to prune old branches from the local repository
	# that have already been deleted at origin.
	git remote prune origin &>> $LOG_PATH
	RETVAL=$?
	[ $RETVAL -eq 0 ] && logger -p daemon.info pruned succesfully from $REMOTE_URI
	[ $RETVAL -ne 0 ] && error "unable to prune branches from $REMOTE_URI"

    #iterate over all the tracking branches on origin and update the corresponding refs
    #for BRANCH in `git branch -r | grep -E "^\s*origin\/" | sed "s/^\s*origin\///"` ; do
    #    echo "updating refs for branch $BRANCH" &>> $LOG_PATH
    #    git update-ref refs/heads/$BRANCH refs/remotes/origin/$BRANCH &>> $LOG_PATH
	#    RETVAL=$?
    # 	[ $RETVAL -eq 0 ] && logger -p daemon.info updated branch $BRANCH succesfully from $REMOTE_URI
	#    [ $RETVAL -ne 0 ] && error "unable to update refs for $BRANCH from $REMOTE_URI"
    #done

    #check if the branches have changed in order to be able to trigger a Jenkins rebuild
    PROJECT=`expr match $REPO_NAME '\([a-zA-Z\-]*\)'`
    for HEAD in ${branches[$PROJECT]}; do
        if [ ! -e $RUN_DIRECTORY/${PROJECT}_${HEAD}.head ]; then
            trigger_jenkins $PROJECT $HEAD
        elif [ `cat $RUN_DIRECTORY/${PROJECT}_${HEAD}.head` != `git rev-parse refs/heads/$HEAD` ]; then
            trigger_jenkins $PROJECT $HEAD
        fi
        echo `git rev-parse refs/heads/$HEAD` > $RUN_DIRECTORY/${PROJECT}_${HEAD}.head
    done
done

ELAPSED_TIME=$(($SECONDS - $START_TIME))
echo ":: sync finished in $ELAPSED_TIME seconds" &>> $LOG_PATH
cd $CURRENT_PATH
