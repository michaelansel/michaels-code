#!/bin/bash
# Copyright 2008: Michael Ansel
# All Rights Reserved

Datestamp=$(date +%Y.%m.%d)
Timestamp=$(date +%Y.%m.%d-%H)

error=0 #Sum of all exit codes. If >0 than there was an error
manualtag= #For tagging manual database backups

NumDatabaseBackups=25
NumDailyBackups=8
NumWeeklyBackups=5

PostgresUsername=
PostgresPassword=


# Live server information
BackupDir="/backup"
JournalDir="/backup/journals"
DatabaseDumpDir="/backup/database_dumps"


# Remote host information
Remote1User=""
Remote1Host=""
Remote1BackupDir="/backup"

Remote2User=""
Remote2Host=""
Remote2BackupDir="/backup"

SSHKeyFile="/backup/remote-backup.sec"


# Offline backup Information
KeyDriveID="154b:000f" #TODO: Update with real info
BackupDriveID="04fc:0c15" #TODO: Update with real info
OfflineDir="/mnt/backup"
KeyfileDir="/mnt/keydrive"
KeyfileName="offline-backup.key" #TODO: Need to generate this key
NumWeeklyOffline=5
NumMonthlyOffline=13

BackupAlertEmail=""


hourly() {
	# Only run this on the live server
	if [ ! "`hostname`" == "FILL-ME-IN" ]
	then
		echo "This should only be run on the main server!"
		exit 1
	fi
	
	cd $BackupDir

	echo "---------------------Local copy---------------------"

	echo "------Backing up all but user data------"
	rsync -a --delete \
--progress \
		FILL-ME-IN directories to backup
		$BackupDir/Hourly
	error=$(echo "$error + $?" | bc)


	
	echo "------Combining unprocessed journals------"
	# Combine and process all un-run journals into an rsync include file
	journals=$(ls $JournalDir | grep "Journal.*static")
	echo -n "" > $JournalDir/Journal.temp
	for journal in $(echo $journals)
	do
		cat $JournalDir/$journal >> $JournalDir/Journal.temp
		error=$(echo "$error + $?" | bc)
	done

	echo "------Converting journals to rsync include file------"
	ruby $BackupDir/journal2rsync.rb $JournalDir/Journal.temp
	error=$(echo "$error + $?" | bc)
	rm $JournalDir/Journal.temp

	# Synchronize new/deleted files
	echo "------Playing journal------"
	rsync -a --delete --include-from=includes \
--progress \
		/ \
		$BackupDir/Hourly
	error=$(echo "$error + $?" | bc)



	# Copy to dev server
	echo "---------------------Remote copy---------------------"
	echo "------Copying non-user data------Remote"
	rsync -a --delete -e "ssh -i $SSHKeyFile" \
--progress \
		$BackupDir/Hourly/ \
		$Remote1User@$Remote1Host:$Remote1BackupDir/Hourly/
	error=$(echo "$error + $?" | bc)

	# Replay journal on remote server
	echo "------Playing journal------Remote"
	rsync -a --delete --include-from=includes -e "ssh -i $SSHKeyFile" \
--progress \
		/ \
		$Remote1User@$Remote1Host:$Remote1BackupDir/Hourly/
	error=$(echo "$error + $?" | bc)

	# Append include file to daily changelog
	cat $BackupDir/includes >> $BackupDir/includes.daily


### COMMIT CHANGES ###
	if [ $error -eq 0 ] ; then
		# Rename all completed journals as such
		echo "$journals" | sed -e 's/static$//' | xargs -I'{}' mv $JournalDir/'{}'static $JournalDir/'{}'complete
	
	else
		echo "There was an error! Not marking journals complete..."
	fi

	return
}

daily_to_remote2() {
	# Only run this on the dev server
	if [ ! "`hostname`" == "FILL-ME-IN" ]
	then
		echo "This should only be run on the dev server!"
		exit 1
	fi
	
	cd $BackupDir

	# Build include file
	sort includes.daily | egrep -v "^([-][ ][*])$" | uniq > includes; echo "- *" >> includes

	# Copy hourly backup to office file server

	echo "---------------------Remote copy (dev -> office)---------------------"
	echo "------Copying non-user data------"
	rsync -a --delete -e "ssh -i $SSHKeyFile" \
--progress \
		$BackupDir/Daily/Daily.latest/ \
		$Remote2User@$Remote2Host:$Remote2BackupDir/Hourly/
	# The above rsync goes into the office server's Hourly folder because
	# this makes it easier to deal with the new folder creation. Once the files are
	# synced into this directory, the office server does its own copy to a versioned folder.
	# This should probably be reevaluated at some point, but it does work and is not
	# entirely inefficient (one extra copy on the office server).

	# Replay journal on remote server
	echo "------Playing journal------(dev -> office)"
	rsync -a --delete --include-from=includes -e "ssh -i $SSHKeyFile" \
--progress \
		/ \
		$Remote2User@$Remote2Host:$Remote2BackupDir/Daily/Daily.latest/
	if [ $? -eq 0 ] ; then rm includes.daily; fi
}

daily() {
	cd $BackupDir/Daily
	mkdir Daily-$Datestamp
	cd Daily-$Datestamp

	# Copy most recent Hourly backup as Daily backup
	cp -al $BackupDir/Hourly/* .

	# Update symlink to latest Daily backup
	rm $BackupDir/Daily/Daily.latest
	ln -s $BackupDir/Daily/Daily-$Datestamp $BackupDir/Daily/Daily.latest
	
	# Remove old backups
	cleanup $NumDailyBackups

	# Trigger 

	return
}

weekly() {
	unlock_backup_drive

	# Archive latest daily backup
	tar zcvf $OfflineDir/Weekly/Archive-$Datestamp.tgz $BackupDir/Daily/Daily.latest/*

	# Remove old weekly backups
	cleanup_offline $NumWeeklyOffline

	relock_backup_drive
}

monthly() {
	unlock_backup_drive

	# Copy latest weekly backup to monthly backup
	latest_weekly=$(ls /mnt/backup/Weekly/Archive-*.tgz | sort | tail -n 1)
	cp $latest_weekly /mnt/backup/Monthly/

	# Remove old monthly backups
	cleanup_offline $NumMonthlyOffline

	relock_backup_drive
}

unlock_backup_drive() {
	# Only run this on the office file server
	if [ ! "`hostname`" == "FILL-ME-IN" ]
	then
		echo "This should only be run on the office file server!"
		exit 1
	fi

	# Verify that backup drive is attached
	backup_drive_test=$(/sbin/lsusb | grep "$BackupDriveID")
	if [ -z "$backup_drive_test" ]
	then
		# No backup drive, reschedule, alert, and fail
		fail "Backup drive not found!"
	fi

	# Verify that key drive is attached
	key_drive_test=$(/sbin/lsusb | grep "$KeyDriveID")
	if [ -z "$key_drive_test" ]
	then
		# No key drive, reschedule, alert, and fail
		fail "Key drive not found!"
	fi

	# Mount key drive
	key_usb_loc=$(/sbin/lsusb | grep "$KeyDriveID" | cut -d" " -f4 | cut -d":" -f1 | bc)
	key_usb_dev=$(dmesg | grep -A 20 usb | grep -A 20 "^scsi $key_usb_loc:0:0:0:" | tail -n 20 | grep "^ sd[a-z]" | cut -d" " -f3)
	# If that couldn't find the device, try a different way (depends on how dmesg lists new devices, this is the most unstable part of the mounting process)
	if [ -z $key_usb_dev ]; then key_usb_dev=$(dmesg | grep -A 20 usb | grep -A 20 "device found at $key_usb_loc" | tail -n 20 | grep "^ sd[a-z]" | cut -d" " -f3) ; fi

	mount /dev/$key_usb_dev	$KeyfileDir

	if [ ! $? -eq 0 ]
	then
		fail "Failed to mount key drive!"
	fi

	keyfile_test=$(ls $KeyfileDir | grep "$KeyfileName" )
	if [ -z "$keyfile_test" ]
	then
		fail "Keyfile not found!"
	fi

	# Mount backup drive
	backup_usb_loc=$(/sbin/lsusb | grep "$BackupDriveID" | cut -d" " -f4 | cut -d":" -f1 | bc)
	backup_usb_dev=$(dmesg | grep -A 20 usb | grep -A 20 "^scsi $backup_usb_loc:0:0:0:" | tail -n 20 | grep "^ sd[a-z]" | cut -d" " -f3)
	# If that couldn't find the device, try a different way (depends on how dmesg lists new devices, this is the most unstable part of the mounting process)
	if [ -z $backup_usb_dev ]; then backup_usb_dev=$(dmesg | grep -A 20 usb | grep -A 20 "device found at $backup_usb_loc" | tail -n 20 | grep "^ sd[a-z]" | cut -d" " -f3) ; fi

	cryptsetup --key-file $KeyfileDir/$KeyfileName luksOpen /dev/$backup_usb_dev backup

	if [ ! $? -eq 0 ]
	then
		fail "Unable to decrypt backup drive!"
	fi

	mount /dev/mapper/backup $OfflineDir

	if [ ! $? -eq 0 ]
	then
		fail "Failed to mount backup drive!"
	fi

	### Backup drive and keyfile found, backup drive decrypted and mounted, ready for writing!
	return
}

fail() {
	message=$1
	echo "$message Failing..."
	relock_backup_drive

	# Alert backup list to failure
	sendmail $BackupAlertEmail <<EOF
Subject: URGENT: Backup FAILURE!
Hey! The backup failed on the file server!
Go make sure that both the backup drive and key drive are plugged in and turned on.
I'll try again in an hour.
Error Message: $message
EOF

	echo "Rescheduling backup to run again in 1 hour"
	at now + 1 hour <<EOF
touch $Remote2BackupDir/run.$command
EOF

	exit 1
}

relock_backup_drive() {
	# Only run this on the office file server
	if [ ! "`hostname`" == "" ]
	then
		echo "This should only be run on the office file server!"
		exit 1
	fi

	# Unmount backup drive (wait and retry once on failure)
	if [ $(cat /etc/mtab | grep -c $OfflineDir) -gt 0 ]
	then
		umount $OfflineDir
		if [ ! $? -eq 0 ]
		then
			echo "There was an error unmounting the backup drive!"
			echo "Waiting 60 seconds for pending writes then forcing..."
			sleep 60
			umount -f $OfflineDir
			if [ ! $? -eq 0 ]
			then
				sendmail $BackupAlertEmail <<EOF
Subject: SUPER URGENT BACKUP ISSUE
There was an error unmounting the backup drive. THIS MEANS OUR BACKUPS AND ENCRYPTION KEY COULD BE EXPOSED!!!!
This drive must be unmounted MANUALLY now. Please do this ASAP.
Thanks, and have a nice day!

Your friendly neighborhood security guard
EOF
			fi
		fi
	fi

	# Relock backup drive
	cryptsetup luksClose backup
	if [ ! $? -eq 0 ]
	then
		sendmail $BackupAlertEmail <<EOF
Subject: SUPER URGENT BACKUP ISSUE
There was an error locking the backup drive. THIS MEANS OUR BACKUPS AND ENCRYPTION KEY COULD BE EXPOSED!!!!
This drive must be locked MANUALLY now. Please do this ASAP.
Thanks, and have a nice day!

Your friendly neighborhood security guard
EOF
	fi

	# Unmount key drive
	if [ $(cat /etc/mtab | grep -c $KeyfileDir) -gt 0 ]
	then
		umount $KeyfileDir
		if [ ! $? -eq 0 ]
		then
			echo "There was an error unmounting the key drive!"
			echo "Waiting 60 seconds for pending writes then forcing..."
			sleep 60
			umount -f $KeyfileDir
		fi
	fi
}

cleanup() {
	echo "------Cleaning out old backups------"
	# Remove old backups (local and remote)
	maxlines=$1

	cd $BackupDir/$type

	lines=$(ls | sort | grep "$type-" | wc -l | sed -e 's/ //g')
	if test "$lines" -gt "$maxlines"
	then
		remove=$(echo "$lines - $maxlines" | bc)
		filenames=$(ls | sort | grep "$type-" | head -n $remove)
		echo "$filenames"
		echo "$filenames" | xargs -I'{}' rm -r $BackupDir/$type/'{}'
#TODO Remote cleanups?
	fi

	return
}

cleanup_offline() {
	echo "------Cleaning out old backups------"
	maxlines=$1

	cd /mnt/backup/$type
	lines=$(ls | sort | grep "Archive-" | wc -l | sed -e 's/ //g')
	if test "$lines" -gt "$maxlines"
	then
		remove=$(echo "$lines - $maxlines" | bc)
		filenames=$(ls | sort | grep "Archive-" | head -n $remove)
		echo "$filenames"
		echo "$filenames" | xargs -I'{}' rm -r /mnt/backup/$type/'{}'
	fi
}

database() {
	echo "------Dumping database------"

	cd $DatabaseDumpDir
	
	#Dump Postgres database to file
	PGUSER=$PostgresUsername
	PGPASSWORD=$PostgresPassword
	export PGUSER PGPASSWORD
	pg_dump -Ft -i -O -x -U $PGUSER sbxdb >sbxdb$manualtag.$Timestamp.pgsql.tar
	PGUSER=
	PGPASSWORD=
	export PGUSER PGPASSWORD
	echo "---Compressing---"
	gzip sbxdb.$Timestamp.pgsql.tar

	echo "------Removing old database dumps------"

	maxlines=$NumDatabaseBackups

	lines=$(ls | sort | egrep "sbxdb.*tar(\.gz)?" | wc -l | sed -e 's/ //g')
	if test "$lines" -gt "$maxlines"
	then
		remove=$(echo "$lines - $maxlines" | bc)
		filenames=$(ls | sort | egrep "sbxdb.*tar(\.gz)?" | head -n $remove)
		echo "$filenames"
		echo "$filenames" | xargs -I'{}' rm -r $DatabaseDumpDir/'{}'
	fi

	return
}

resync() {
#TODO: This needs to be verified working
	# Do a full resync of the current and backed up versions of ALL data (ignore journal)
	# NOTE: This requires almost an hour just to generate the file lists, so use sparingly.

	echo "------------Local resync------------"
	rsync -a --delete \
--progress \
		FILL-ME-IN
		$BackupDir/Hourly

	echo "------------Remote resync------------"
	rsync -a --delete -e "ssh -i $SSHKeyFile" \
--progress \
		$BackupDir/Hourly/ \
		$Remote1User@$Remote1Host:$Remote1BackupDir/Hourly/
}

cd $BackupDir
command=$1

case $command in
	"hourly")
		type="Hourly"
		database
		hourly
		;;
	"office")
		type="Hourly"
		hourly_to_remote2
		;;
	"daily")
                type="Daily"
                daily
                ;;
	"weekly")
		type="Weekly"
		weekly
		;;
	"monthly")
		type="Monthly"
		monthly
		;;
	"database")
		manualtag="-manual"
		database
		;;
	"unlock")
		unlock_backup_drive
		echo "Backup drive unlocked! Press enter to relock..."
		read its_time_to_relock
		relock_backup_drive
		;;
	"resync")
		resync
		;;
        *)
                echo "Invalid option. Please choose {hourly,daily,weekly,monthly}"
                exit
                ;;
esac
echo ""
echo ""
