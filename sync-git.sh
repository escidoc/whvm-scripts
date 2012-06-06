#!/bin/bash

# This script synchronizes the local git mirror repositories with github
# It iterates over all the folders in a certain directory (GIT_REPOSITORIES) and tries
# to establish if it's a git repository. If it is, it starts fetching from the git 
# remote called "origin" and updates the refs in order to synchronize the HEADS of the
# local repository.

GIT_REPOSITORIES=/data/git-repositories
LOG_PATH=/var/log/git-sync.log
CURRENT_PATH=`pwd`


function error {
	# send an email to admin and log to /var/log/daemon.*
	logger -p daemon.err An error occured while syncing the git repositories.
	/bin/echo "An error has occured while syncing the git repositories. Please check the log at ${LOG_PATH} at host ${HOSTNAME}. This is a generated message." | /usr/bin/mail -s "SYNC Error" "eSciDocAdmin@fiz-karlsruhe.de" -- -r "git-sync-cronjob@whvmescidoc4.fiz-kalrsruhe.de"
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

	REMOTE_URI=`git remote -v | grep -E "^origin.*\(fetch\)$" | awk '{print $2;}'` 

    echo ":: syncing git repository $REMOTE_URI" &>> $LOG_PATH
	git fetch origin &>> $LOG_PATH
	RETVAL=$?
	[ $RETVAL -eq 0 ] && logger -p daemon.info fetched successfully from $REMOTE_URI
	[ $RETVAL -ne 0 ] && error
	
	# and dont forget to prune old branches from the local repository
	# that have already been deleted at origin.
	git remote prune origin &>> $LOG_PATH
	RETVAL=$?
	[ $RETVAL -eq 0 ] && logger -p daemon.info pruned succesfully from $REMOTE_URI
	[ $RETVAL -ne 0 ] && error

    #iterate over all the tracking branches on origin and update the corresponding refs
    for BRANCH in `git branch -r | grep -E "^\s*origin\/" | sed "s/^\s*origin\///"` ; do
        echo "updating refs for branch $BRANCH" &>> $LOG_PATH
        git update-ref refs/heads/$BRANCH refs/remotes/origin/$BRANCH &>> $LOG_PATH
	    RETVAL=$?
    	[ $RETVAL -eq 0 ] && logger -p daemon.info updated branch $BRANCH succesfully from $REMOTE_URI
	    [ $RETVAL -ne 0 ] && error
    done
done

ELAPSED_TIME=$(($SECONDS - $START_TIME))
echo ":: sync finished in $ELAPSED_TIME seconds" &>> $LOG_PATH
cd $CURRENT_PATH
