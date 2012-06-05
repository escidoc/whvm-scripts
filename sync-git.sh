#!/bin/bash
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

    # now update the refs so that HEAD and the other branches have the right commits associated
    # from the remote repo
    if [ -e "$FOLDER/refs/remotes/origin" ]; then
        ORIGIN=`git remote -v | grep -i origin | grep -i fetch | awk '{print $2}'`
        for REF in `ls $FOLDER/refs/remotes/origin/` ; do
            echo "updating ref $REF from origin $ORIGIN" &>> $LOG_PATH 
            git update-ref refs/heads/$REF refs/remotes/origin/$REF &>> $LOG_PATH
            RETVAL=$?
	        [ $RETVAL -eq 0 ] && logger -p daemon.info synced branch $REF succesfully
        	[ $RETVAL -ne 0 ] && error
        done
    fi
done

ELAPSED_TIME=$(($SECONDS - $START_TIME))
echo ":: sync finished in $ELAPSED_TIME seconds" &>> $LOG_PATH
cd $CURRENT_PATH
