#!/bin/sh
#
# The purpose of this script is to find all backups associated 
# with my instance-ID with the intent of expiring any images that
# are older than the threshold date. The script will pull the the
# instance-ID from the instance meta-data URL, then search for
# Snapshots that were previously generated by the backup scripts
# found elsewhere in this tool-set.
#
# Dependencies:
# - Generic: See the top-level README_dependencies.md for script dependencies
#
# License:
# - This script released under the Apache 2.0 OSS License
#
######################################################################
WHEREAMI=`readlink -f ${0}`
SCRIPTDIR=`dirname ${WHEREAMI}`
TARGVG=${1:-UNDEF}
TZ=zulu

# Put the bulk of our variables into an external file so they
# can be easily re-used across scripts
source ${SCRIPTDIR}/commonVars.env

# Output log-data to multiple locations
function MultiLog() {
   echo "${1}"
   logger -p local0.info -t [SnapMaint] "${1}"
}


# Grab a filtered list candidate snapshots and dump to an array
# * Filter for "Created By" equals "Automated Backup"
# * Filter for "Description" contains "<INSTANCE_ID>-bkup"
function SnapListToArray() {
   local COUNT=0
   for SNAPLIST in `aws ec2 describe-snapshots --output=text --filter \
      "Name=description,Values=*_${THISINSTID}-bkup*" --filters \
      "Name=tag:Created By,Values=Automated Backup" --query \
      "Snapshots[].{F1:SnapshotId,F2:StartTime,F3:Description}" | tr '\t' ';'`
   do
      local SNAPIDEN=$(echo ${SNAPLIST} | cut -d ";" -f 1)
      local SNAPTIME=$( date -d "`echo ${SNAPLIST} | cut -d ";" -f 2 | sed '{
         s/\....Z$//
         s/T/ /
      }'`" "+%s")
      local SNAPDESC=$(echo ${SNAPLIST} | cut -d ";" -f 3)
      local SNAPGRUP=$(echo ${SNAPDESC} | sed 's/^.*-bkup-/GROUP_/')
      FIXLIST="${SNAPIDEN};${SNAPTIME};${SNAPGRUP}"
      SNAPARRAY[${COUNT}]="${FIXLIST}"
      local COUNT=$((${COUNT} +1))
   done
}

function CheckSnapAge(){
   local COUNT=0

   while [ ${COUNT} -lt ${#SNAPARRAY[@]} ]
   do
      local SNAPIDEN=`echo ${SNAPARRAY[${COUNT}]} | cut -d ";" -f 1`
      local SNAPTIME=`echo ${SNAPARRAY[${COUNT}]} | cut -d ";" -f 2`
      local SNAPGRUP=`echo ${SNAPARRAY[${COUNT}]} | cut -d ";" -f 3`

      echo "$((${CURCTIME} - ${SNAPTIME})) -gt $((${CURCTIME} - ${EXPBEYOND}))"
      if [ $((${CURCTIME} - ${SNAPTIME})) -gt $((${CURCTIME} - ${EXPBEYOND})) ]
      then
         MultiLog "${SNAPIDEN} is older than expiry-horizon. Deleteing..."
         ## aws ec2 delete-snapshot --snapshot-id ${SNAPIDEN} 
         if [ $? -ne 0 ]
         then
            MultiLog "Deletion failed"
         else
            MultiLog "Deleted"
         fi
      else
         MultiLog "${SNAPIDEN} (${SNAPGRUP}) is younger than expiry-horizon (keeping)"
      fi

      local COUNT=$((${COUNT} +1))
   done
}

SnapListToArray
CheckSnapAge
