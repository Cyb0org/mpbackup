#!/bin/bash
# Copyright (c) 2015, Michał Pena <cyb0org@gmail.com>
# Licence: ISC
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

# btrfs mount point for backups
BACKUP_DIR="/var/backups/mpbackup"
# mpbackup host config location
BACKUP_HOSTS="${BACKUP_DIR}/mpbackup-hosts.conf"
# how many simultaneous backups can be run
MAX_BACKUPS=2
# how many backups will be keeped
BACKUPS_COUNT_MAX=30
# print what mpbackup do
VERBOSE_ECHO="yes"
# syslog what mpbackup do
SYSLOG_ECHO="no"
# simulate execution
SIMULATION="no"
# always run filesystem sync after rsync is done
ALWAYS_SYNC="yes"
# inform only about rsync - VERBOSE_ECHO or SYSLOG_ECHO must be set!
ONLY_ECHO_RSYNC="yes"

########## DON'T MAKE ANY CHANGES BELOW!!! ##########

# HOST / SHARE / DATE / data

# check config permissions
check_config()
{
	PERMISSIONS=`stat -c '%a' ${BACKUP_HOSTS}`
	if [ "${PERMISSIONS:2:1}" != "0" ]; then
		verbose_echo "Config file is world-readable! You have passwords there! Do following:"
		verbose_echo "chmod 600 ${BACKUP_HOSTS}"
		exit 0
	fi
	if [ "${SIMULATION}" = "yes" ]; then
		verbose_echo "WARNING! SIMULATION MODE ENABLED! BACKUPS WON'T BE MADE!"
	fi
}

# check if there's a backup already and prepare to make one
prepare_backup()
{
	# there's not even a dir for that host!
	if [ ! -d "${SHAREDIR}" ]; then
		verbose_echo "New backup - creating '${SHAREDIR}'"
		# create it
		mkdir -p ${SHAREDIR}
		# create subvolume - you wouldn't guess it, right?
		create_subvolume
		RSYNC_SECRETS="${BACKUP_DIR}/${HOST_ALIAS}/rsyncd.secrets"
		touch ${RSYNC_SECRETS}
		chmod 600 ${RSYNC_SECRETS}
		echo ${PASSWORD} > ${RSYNC_SECRETS}
	else
		get_last_backup_date

		# oh... it's backup that should be complete... is it?
		is_backup_complete

		if [ "${BACKUP_COMPLETE}" = "yes" ]; then
			verbose_echo "Last backup is complete."

			# it is! but is it up to date?
			if [ "${DATE}" = "${LAST_BACKUP_DATE}" ]; then
				verbose_echo "Backup for current date is complete. Won't do now anything more for this host."
				# it is! move along... there's nothing to see here...
				MAKE_BACKUP="no"
			else
				verbose_echo "Last backup is not up to date."
				# it isn't! create snapshot from previous backup
				create_snapshot
			fi
		else
			# it isn't! create snapshot from previous backup
			verbose_echo "Last backup is not complete."
			if [ "${DATE}" != "${LAST_BACKUP_DATE}" ]; then
				verbose_echo "Creating snapshot from last not complete backup."
				create_snapshot
			fi
		fi
	fi
}

# subvolume creation
create_subvolume()
{
	verbose_echo "Creating subvolume '${SHAREDIR}/${DATE}'"
	exec_exec btrfs subvolume create "${SHAREDIR}/${DATE}"
	NEW_BACKUP="yes"
}

# get last backup date
get_last_backup_date()
{
	LAST_BACKUP_DATE=`cd ${SHAREDIR} && ls -1trd *.log | tail -n 1 | sed 's/.log$//'`
	if [ "${LAST_BACKUP_DATE}" = "" ]; then
		verbose_echo "There's no previous backups for this host. Creating subvolume."
		create_subvolume
		if [ "$1" != "1" ]; then
			get_last_backup_date 1
		fi
	else
		verbose_echo "Last backup is from '${LAST_BACKUP_DATE}'"
	fi
}

# check if backup is complete or partial
is_backup_complete()
{
	if [ -e "${SHAREDIR}/${LAST_BACKUP_DATE}.complete" ]; then
		verbose_echo "Backup is complete."
		BACKUP_COMPLETE="yes"
	else
		verbose_echo "Backup is not complete."
		BACKUP_COMPLETE="no"
	fi
}

# create snapshot of last backup
create_snapshot()
{
	if [ "${SHAREDIR}/${DATE}" != "${SHAREDIR}/${LAST_BACKUP_DATE}" ]; then
		verbose_echo "Creating snapshot '${SHAREDIR}/${DATE}' of subvolume '${SHAREDIR}/${LAST_BACKUP_DATE}'"
		exec_exec btrfs subvolume snapshot "${SHAREDIR}/${LAST_BACKUP_DATE}" "${SHAREDIR}/${DATE}"
	fi
}

# making backup
make_backup()
{
	if [ "${MAKE_BACKUP}" = "yes" ]; then
		rsync_echo "Creating backup in '${SHAREDIR}/${DATE}'"
		# rsync stuff here
		if [ "$NEW_BACKUP" = "yes" ]; then
			# handlling of sparse file - file size 0 with virtually reserved 20GB
			RSYNC_OPTIONS="--sparse"
		else
			# transmit only changes
			RSYNC_OPTIONS="--inplace"
		fi
		exec_exec rsync --archive --human-readable --perms --xattrs --inplace --delete --delete-excluded --compress --numeric-ids --stats --password-file=${BACKUP_DIR}/${HOST_ALIAS}/rsyncd.secrets rsync://${USER}@${HOST}/${SHARE}/ ${SHAREDIR}/${DATE}/ >> ${SHAREDIR}/${DATE}.log
		# if it's complete - mark it as complete
		if [ "$?" = "0" ]; then
			rsync_echo "rsync finished successfully. Marking as complete."
			exec_exec touch "${SHAREDIR}/${DATE}.complete"
			RSYNC_DONE="yes"
		elif [ "$?" = "1" ]; then
			rsync_echo "rsync work has been interrupted. I'll better quit."
			exit 0
		else
			rsync_echo "rsync returned error '${?}'."
		fi

		if [ "${ALWAYS_SYNC}" = "yes" ]; then
			verbose_echo "Forcing filesystem sync."
			sync
		fi
	else
		verbose_echo "I won't do now any backup for '${SHAREDIR}'!"
	fi
}

rsync_echo()
{
	ECHO_RSYNC="yes"
	verbose_echo $@
}

# cool output to know what script is doing
verbose_echo()
{
	if [ \( \( "${ONLY_ECHO_RSYNC}" = "yes" \) -a \( "${ECHO_RSYNC}" = "yes" \) \) -o \( "${ONLY_ECHO_RSYNC}" = "no" \) ]; then
		if [ "${VERBOSE_ECHO}" = "yes" ]; then
			if [ "${HOST_ALIAS}" != "" ]; then
				echo `date +"%Y-%m-%d %H:%M:%S"`" ${HOST_ALIAS} [${SHARE}@${HOST}]: $@"
			else
				echo `date +"%Y-%m-%d %H:%M:%S"`" $@"
			fi
		fi
		if [ "${SYSLOG_ECHO}" = "yes" ]; then
			logger -t mpbackup "${HOST_ALIAS} [${SHARE}@${HOST}]: $@"
		fi

		ECHO_RSYNC=""
	fi
}

exec_exec()
{
	if [ "${SIMULATION}" = "no" ]; then
		$@
	else
		verbose_echo $@
	fi
}

# make sure we don't start all rsyncs together
make_lockfile()
{
	for (( i=1; i<=${MAX_BACKUPS}; i++ )); do
		lockfile-create -q -r 1 -l /var/lock/mpbackup.${i}.lock -p
		if [ "$?" = "0" ]; then
			LOCKNUMBER="${i}"
			i=`expr $MAX_BACKUPS + 1`
			verbose_echo "Lockfile nr '${LOCKNUMBER}' obtained. Max ${MAX_BACKUPS} allowed."
		fi
	done

	if [ "${LOCKNUMBER}" = "" ]; then
		verbose_echo "There's no free lockfile."
		exit 0
	fi
}

# delete subvolumes with old backups
delete_old_backups()
{
	for BACKUP_SUBVOLUMES in `cd ${SHAREDIR} && ls -1trd *.log | head -n-${BACKUPS_COUNT_MAX} | sed 's/.log$//'`; do
		verbose_echo "Removing old backups '${SHAREDIR}/${BACKUP_SUBVOLUMES}'."
		exec_exec btrfs subvolume delete ${SHAREDIR}/${BACKUP_SUBVOLUMES}
		rm -f ${SHAREDIR}/${BACKUP_SUBVOLUMES}.complete
		rm -f ${SHAREDIR}/${BACKUP_SUBVOLUMES}.log
	done
}

check_config
make_lockfile

# that's enough - just backup
for HOST_DATA in `cat ${BACKUP_HOSTS} | egrep -v '^#'`; do
	MAKE_BACKUP="yes"

	HOST_ALIAS=`echo -n ${HOST_DATA} | awk -F ':' '{print $1}'`
	USER=`echo -n ${HOST_DATA} | awk -F ':' '{print $2}'`
	PASSWORD=`echo -n ${HOST_DATA} | awk -F ':' '{print $3}'`
	HOST=`echo -n ${HOST_DATA} | awk -F ':' '{print $4}'`
	SHARE=`echo -n ${HOST_DATA} | awk -F ':' '{print $5}'`
	DATE_FORMAT=`echo -n ${HOST_DATA} | awk -F ':' '{print $6}'`
	DATE=`date +${DATE_FORMAT}`

	SHAREDIR="${BACKUP_DIR}/${HOST_ALIAS}/${SHARE}"

	lockfile-create -q -r 1 -l "/var/lock/mpbackup.${HOST_ALIAS}.${SHARE}.lock" -p
	if [ "$?" = "0" ]; then
		verbose_echo "Starting backup of ${HOST_ALIAS} (host: ${HOST}; user: ${USER}; share: ${SHARE}; date format: ${DATE_FORMAT}"
		prepare_backup
		make_backup
		delete_old_backups
		lockfile-remove -q -l "/var/lock/mpbackup.${HOST_ALIAS}.${SHARE}.lock"
		# make sure we don't make more backups than one per script run
		if [ "${RSYNC_DONE}" = "yes" ]; then
			break
		fi
	fi
done

lockfile-remove -q -l /var/lock/mpbackup.${LOCKNUMBER}.lock

exit 0
