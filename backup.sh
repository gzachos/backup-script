#!/bin/bash

#+-----------------------------------------------------------------------+
#|                Copyright (C) 2016 George Z. Zachos                    |
#+-----------------------------------------------------------------------+
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#
# Contact Information:
# Name: George Z. Zachos
# Email: gzzachos <at> gmail.com


# Description: This shell script backups the directories specified in the
# CONFIGURATION SECTION below by compressing and storing them. It is designed
# to be executed @midnight (same as @daily) using Cron.
#
# Example cron entry:
# @midnight /root/bin/backup.sh
#
# Details: Every "<token-uppercase>_BACKUP_DAY" a backup is taken. If no backup
# was taken the week before (Mon -> Sun) AND if no backup was taken this week,
# a backup is taken no matter what.
#
# Backups older than 4 weeks are deleted unless the total number of backups
# is less than 5 (<=4).


TIMESTAMP=$(date "+%Y-%m-%d_%H-%M-%S") # Do NOT modify!
DAYS=(Mon Tue Wed Thu Fri Sat Sun)

###################################################################
#                    CONFIGURATION SECTION                        #
###################################################################

# The configuration section is the only section you should modify,
# unless you really(!) know what you are doing!!!

# Make sure to always comply with the name format of the variables
# below. As you may have noticed, all variables related to each
# other begin with the same token (i.e. WIKI, CLOUD, ...).

# To add any additional directories to be backed up, you should only
# add three (3) new lines and modify ${TOKENS} variable. See the
# examples below to get a better understanding.

# Example of ${TOKENS} variable.
TOKENS="WIKI CLOUD"	# For any additional entry add the appropriate 
			# <token-uppercase> separating it with a space
			# character from existing tokens.

# Template - The three lines that should be added for every new directory addition.
# <token-uppercase>_BACKUPS_DIR="/path/to/dir"     # No '/' at the end of the path!
# <token-uppercase>_DIR="/path/to/another-dir"     # No '/' at the end of the path!
# <token-uppercase>_BACKUP_DAY="<weekday-3-letters>"

# Example No.1
WIKI_BACKUPS_DIR="/root/backups/wiki" # Where backup files will be saved.
WIKI_DIR="/var/www/html/wiki" # The directory that should be backed up.
WIKI_BACKUP_DAY="Sun" # The day of the week that the backup should be taken.

# Example No.2
CLOUD_BACKUPS_DIR="/root/backups/cloud"
CLOUD_DIR="/var/www/html/owncloud"
CLOUD_BACKUP_DAY="Sat"

###################################################################
#                          check_config()                         #
###################################################################

# Checks if the directory where the backups will be saved exists
# (creates it if needed), then checks if the directory to be backed 
# up exists and finally if the day for the backup to be taken
# is valid.
#
# Parameter:	$1 -> {WIKI, CLOUD, ...}
check_config () {
	BACKUPS_DIR="${1}_BACKUPS_DIR"
	DIR="${1}_DIR"
	DAY="${1}_BACKUP_DAY"

	if [ ! -d ${!BACKUPS_DIR} ]
	then
		echo "Creating...${!BACKUPS_DIR}"
		mkdir -p ${!BACKUPS_DIR}
		if [ ${?} -ne 0 ]
		then
			echo "Error creating ${!BACKUPS_DIR}!"
			echo "Script will now exit..."
			exit 1
		fi
	fi

	if [ ! -d ${!DIR} ]
	then
		echo "${!DIR}: No such directory!"
		echo "Script will now exit..."
		exit 2
	fi

	if [ "${!BACKUPS_DIR}" == "${!DIR}" ]
	then
		echo "\$${BACKUPS_DIR} and \$${DIR} are the same!"
		echo "Script will now exit..."
		exit 3
	fi

	if [ -z ${!DAY} ]
	then
		echo "The length of variable: \$${DAY} is 0 (zero)!"
		echo "Script will now exit..."
		exit 4
	fi

	FLAG="false"
	for day in "${DAYS[@]}"
	do
		if [ "${day}" == "${!DAY}" ]
		then
			FLAG="true"
		fi
	done

	if [ "${FLAG}" == "false" ]
	then
		echo "The value of the \$${DAY} variable is INVALID!"
		echo "Available options: \"Mon\", \"Tue\", \"Wed\", \"Thu\", \"Fri\", \"Sat\", \"Sun\" "
		echo "Script will now exit..."
		exit 5
	fi
}

###################################################################
#                          compare_dates()                        #
###################################################################

# Compares the dates which are extracted from the two (2) timestamps
# given as function parameters.
# Return value:	'0' - if date0 = date1
#          	'1' - if date0 < date1
#          	'2' - if date0 > date1
#
# Parameters:	$1 -> Timestamp #0
#		$2 -> Timestamp #1
#
# The format of Timestamp #0 and #1 matches the template of ${TIMESTAMP}.
# i.e. 2016-06-20_11-50-20
compare_dates () {
	d0=${1::10}
	d1=${2::10}

	if [ "${d0}" \< "${d1}" ]
	then
        	return 1
	elif [ "${d0}" \> "${d1}" ]
	then
        	return 2
	fi
       	return 0
}

###################################################################
#                         timestamp_diff()                        #
###################################################################

# Calculates and returns the difference (absolute value in days) 
# between the two (2) timestamps given as function parameters.
# The result is stored in variable ${DIFF}.
#
# Parameters:   $1 -> Timestamp #0
#               $2 -> Timestamp #1
#
# The format of Timestamp #0 and #1 matches the template of ${TIMESTAMP}.
timestamp_diff () {
	date0=${1::10}
	time0=${1:(-8)}
	time0=$(echo ${time0} | tr "-" ":" | tr "_" " ")

	date1=${2::10}
	time1=${2:(-8)}
	time1=$(echo ${time1} | tr "-" ":" | tr "_" " ")

	x=$(date --date="${date0} ${time0}" +%s)
	y=$(date --date="${date1} ${time1}" +%s)

	if [ ${x} -lt ${y} ]
	then
		tmp=${x}
		x=${y}
		y=${tmp}
	fi

	DIFF=$(( (${x}-${y}) / 86400))
}

###################################################################
#                        get_prev_week()                          #
###################################################################

# Calculates the timestamp of previous week's Monday and Sunday 
# (time 00:00:00). Monday is assumed to be the first day of the week.
# The results are stored in ${MON} and ${SUN}.
#
# Addition: ${LAST_MON} holds the timestamp of the most recent Monday.
# If today is Monday, the current date will be stored in ${LAST_MON}
# (time 00:00:00).
get_prev_week () {
	SUN=$(date "+%Y-%m-%d_%H-%M-%S" --date="last Sunday")
	MON=$(date "+%Y-%m-%d_%H-%M-%S" --date="last Monday")
	LAST_MON=$(date "+%Y-%m-%d_%H-%M-%S" --date="last Monday")
	timestamp_diff ${MON} ${SUN}
	if [ ${DIFF} -eq 1 ]
	then
		MON=$(date "+%Y-%m-%d_%H-%M-%S" --date="last Monday -1 week")
	else
		LAST_MON=$(date "+%Y-%m-%d_%H-%M-%S" --date="today 00:00:00")
	fi
}

###################################################################
#                        conduct_backup()                         #
###################################################################

# Takes a backup of the ${<some-token>_DIR} directory and temporarily
# stores it in /tmp/. if the 'tar' command exits with no errors, the
# temporary file is moved to the directory held in ${<some-token>_BACKUPS_DIR}.
#
# Parameter:	$1 -> {WIKI, CLOUD, ...}
conduct_backup () {
	BACKUPS_DIR="${1}_BACKUPS_DIR"
        DIR="${1}_DIR"
	TEMPFILE="$(mktemp /tmp/backup.XXXXXX)"
	PATH_TOKENS=$(echo ${!DIR} | tr "/" " ")

	for token in ${PATH_TOKENS[@]}
	do
		continue
	done

	PATHTODIR=${!DIR/\/$token}

	echo -e "\nBacking up ${!DIR} ..."
	echo -e "This might take some time!\n"

	tar -zcf ${TEMPFILE} -C ${PATHTODIR} ./${token}
	
	if [ $? -ne 0 ]
	then
		echo "tar: Exited with errors!"
		rm ${TEMPFILE}
		echo "Script will now exit..."
		exit 3
	fi

	TOKEN_LOWERCASE=$(echo ${1} | tr '[:upper:]' '[:lower:]')	
	mv ${TEMPFILE} ${!BACKUPS_DIR}/backup_${TOKEN_LOWERCASE}_${TIMESTAMP}.tar.gz
}

###################################################################
#                        check_backups()                          #
###################################################################

# Does all the job.
# 	- Checks if a backup was taken this week.
#	- Checks if a any backups were taken the last 5 weeks.
#	- If today is "<token-uppercase>_BACKUP_DAY" a backup is taken.
#	- If no backups were taken this week or the preview one,
#	  a backup is taken.
#	- If the total number of backups is more than 4 (>=5),
#	  excess backups which are older than 4 weeks are deleted. 
# Parameter:	$1 -> {WIKI, CLOUD, ...}
check_backups () {
	TOKEN_LOWERCASE=$(echo ${1} | tr '[:upper:]' '[:lower:]')
	BACKUPS_DIR="${1}_BACKUPS_DIR"
	BACKUP_FILES=$(ls -1 ${!BACKUPS_DIR} | grep -E \
			"^backup_${TOKEN_LOWERCASE}_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}.tar.gz" \
			2> /dev/null | sort -r)
	BACKUP_DAY="${1}_BACKUP_DAY"
	TODAY=$(date +%a)
	FILENUM_SUM=0
	DELETED_SUM=0
	FLAG="false" # true if a backup was taken this week

	get_prev_week

	for file in ${BACKUP_FILES}
	do
		BACKUP_TIME=${file:(-26):19}
		compare_dates ${LAST_MON} ${BACKUP_TIME}
		if [ ${?} -le 1 ]
		then
			FLAG="true"
		fi
	done

	if [ "${TODAY}" == "${!BACKUP_DAY}" ] && [ "${FLAG}" == "false" ]
	then
		conduct_backup ${1}
	fi

	echo -e "\n##### $1\n"

	for week in `seq 1 5`
	do
		FILENUM=0
		echo "WEEK {${MON::10} -> ${SUN::10}}"

		for file in ${BACKUP_FILES}
		do
			BACKUP_TIME=${file:(-26):19}
			compare_dates ${BACKUP_TIME} ${SUN}
			x=${?}
			compare_dates ${BACKUP_TIME} ${MON}
			y=${?}
			if [ ${x} -le 1 ] && [ ${y} -eq 2 -o ${y} -eq 0 ]
			then
				echo -e "\t${file}"
				((FILENUM++))

				if [ ${week} -eq 5 ] && [ $((FILENUM_SUM + FILENUM)) -gt 4 ]
				then
					echo -e "\t[rm ${!BACKUPS_DIR}/${file}]"
					rm ${!BACKUPS_DIR}/${file}
					((DELETED_SUM++))
				fi	
			fi
		done

		if [ ${FILENUM} -eq 0 ]
		then
			if [ ${week} -eq 1 ] && [ "${FLAG}" == "false" ]
			then
				conduct_backup ${1}
			fi
			echo -e "\tNo backup files were found!"
		fi

		((FILENUM_SUM += FILENUM))
		MON=$(date "+%Y-%m-%d_%H-%M-%S" --date="${MON::10} -1 week")
		SUN=$(date "+%Y-%m-%d_%H-%M-%S" --date="${SUN::10} -1 week")
	done

	echo " "
	echo "===== REPORT ====="
	echo "${FILENUM_SUM} ${2} backup files were found!"
	echo "${DELETED_SUM} ${2} backup files were deleted!"
	echo "$((FILENUM_SUM-DELETED_SUM)) ${2} OLD backup files currently exist!"
}

###################################################################
#                              main()                             #
###################################################################

# For every directory (to be backed up) configuration conducts a
# configuration check and calls check_backups function.
main () {
	for tok in ${TOKENS[@]}
	do
		check_config	${tok}
		check_backups	${tok}
	done
}

main
