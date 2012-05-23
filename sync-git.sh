#!/bin/bash
GIT_REPOSITORIES=/data/git-repositories
LOG_PATH=/var/log/git-sync.log
CURRENT_PATH=`pwd`


function error {
	# send an email to admin and log to /var/log/daemon.*
	logger -p daemon.err An error occured while syncing the git repositories.
	/bin/echo "An error has occured while syncing the git repositories. Please check the log at ${LOG_PATH} at host ${HOSTNAME}. This is a generated message." | /usr/bin/mail -s "SYNC Error" "eSciDocAdmin@fiz-karlsruhe.de" -- -r "git-sync-cronjob@whvmescidoc4.fiz-kalrsruhe.de"
}

# iterate over all repositories in the given path to discover the 
# git repositories in the given path
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

	echo `date` >> $LOG_PATH
	echo "syncing folder $FOLDER" >> $LOG_PATH
	REMOTE_URI=`git remote -v | grep -E "^origin.*\(fetch\)$" | awk '{print $2;}'` 
	echo "syncing git repository $REMOTE_URI"
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
done

cd $CURRENT_PATH
