#!/bin/bash
BACKUP_PATH=/export/backups/whvmescidoc4-config.tar.bz2
LOG_PATH=/var/log/config-backup.log

# tar all the files iun an archive for a simple backup mechanism
/bin/tar -cjf $BACKUP_PATH -C / .git &>> $LOG_PATH

RETVAL=$?
[ $RETVAL -eq 0 ] && logger Whvmescidoc4 configuration been backed up successfully to $BACKUP_PATH

if [ $RETVAL -ne 0 ]; then
	# log the error that occuerd do /var/log/daemon.log
	# and send an email to the administrator
	/usr/bin/logger -p daemon.err Unable to generate backups from configuration.
        /bin/echo "An error has occured during backup of the whvmescidoc4 configuration. Please check the log at ${LOG_PATH} at host ${HOSTNAME}. This is a generated message." | /usr/bin/mail -s "BACKUP Error" "eSciDocAdmin@fiz-karlsruhe.de" -- -r "git-backup-cronjob@whvmescidoc4.fiz-kalrsruhe.de"
fi
