#!/bin/sh
#
# This script is designed to perform consistent backups of
# - Selected EBS volumes (referenced by volume-id)
# - Mounted filesystems  (referenced by fully-qualified directory-path)
# - LVM volumes (referenced by VGNAME/LVNAME path-specification)
#
#
# Dependencies:
# - Generic: See the top-level README_dependencies.md for script dependencies
#
# License:
# - This script released under the Apache 2.0 OSS License
#
######################################################################

######################################
##                                  ##
## Section for variable-declaration ##
##                                  ##
######################################

#####################
# Starter Variables
#####################
PATH=/sbin:/usr/sbin:/bin:/usr/bin:/opt/AWScli/bin
WHEREAMI=`readlink -f ${0}`
SCRIPTDIR=`dirname ${WHEREAMI}`
PROGNAME=`basename ${WHEREAMI}`


#########################################
# Put the bulk of our variables into an
# external file so they can be easily
# re-used across scripts
#########################################
source ${SCRIPTDIR}/commonVars.env


####################
# SCRIPT Variables
####################
BKNAME="$(hostname -s)_${THISINSTID}-bkup-${DATESTMP}"
FIFO=/tmp/EBSfifo


######################################
##                                  ##
## Section for function-declaration ##
##                                  ##
######################################

#########################################
# Output log-data to multiple locations
#########################################
function MultiLog() {
   echo "${1}"
   logger -p local0.info -t [Flagger] "${1}"
   # DEFINE ADDITIONAL OUTPUTS, HERE
}

#################################################
# Check script invocation-method; set tag-value
#################################################
function GetInvocation() {
   tty -s
   if [ $? -eq 0 ]
   then
      CREATEMETHOD="Manually-Initiated Backup"
   elif [ $? -eq 1 ]
   then
      CREATEMETHOD="Automated Backup"
   fi
}

############################################
# Create list of filesystems to (un)freeze
############################################
function FsSpec() {
   local FSTYP=$(stat -c %F "${1}" 2> /dev/null)
   local IDX=${#FSLIST[@]}

   case ${FSTYP} in
      "directory")
         FSLIST[${IDX}]=${1}
         ;;
      "")
         MultiLog "${1} does not exist. Aborting..." >&2
         exit 1
         ;;
      *)
         MultiLog "${1} is not a directory. Aborting..." >&2
         exit 1
         ;;
   esac
}

#######################################
# Toggle set appropriate freeze-state
# on target filesystems
#######################################
function FSfreezeToggle() {
   ACTION=${1}

   case ${ACTION} in
      "freeze")
	 FRZFLAG="-f"
         ;;
      "unfreeze")
	 FRZFLAG="-u"
         ;;
      "")	# THIS SHOULD NEVER MATCH
	 MultiLog "No freeze method specified" >&2
         ;;
      *)	# THIS SHOULD NEVER MATCH
	 MultiLog "Invalid freeze method specified" >&2
         ;;
   esac

   if [ ${#FSLIST[@]} -gt 0 ]
   then
      local IDX=0
      while [ ${IDX} -lt ${#FSLIST[@]} ]
      do
         MultiLog "Attempting to ${ACTION} '${FSLIST[${IDX}]}'"
	 fsfreeze ${FRZFLAG} "${FSLIST[${IDX}]}"
	 if [ $? -ne 0 ]
	 then
	    MultiLog "${ACTION} on ${FSLIST[${IDX}]} exited abnormally" >&2
	 fi
	 IDX=$((${IDX} + 1))
      done
   else
      MultiLog "No filesystems selected for ${ACTION}" >&2
   fi
}



######################################
##                                  ##
## Section for defining main        ##
##    program function and flow     ##
##                                  ##
######################################

##################
# Option parsing
##################
OPTIONBUFR=`getopt -o v:f: --long vgname:fsname: -n ${PROGNAME} -- "$@"`
# Note the quotes around '$OPTIONBUFR': they are essential!
eval set -- "${OPTIONBUFR}"

# Parse our flagged args
while [ true ]
do
   case "$1" in
      -v|--vgname)
         # Mandatory argument. Operating in quoted mode: an
	 # empty parameter will be generated if its optional
	 # argument is not found
	 case "$2" in
	    "")
	       MultiLog "Error: option required but not specified" >&2
	       shift 2
	       exit 1
	       ;;
	    *)
               MultiLog "VG FUNCTION NOT YET IMPLEMENTED: EXITING..." >&2
	       shift 2;
               exit 1
	       ;;
	 esac
	 ;;
      -f|--fsname)
         # Mandatory argument. Operating in quoted mode: an
	 # empty parameter will be generated if its optional
	 # argument is not found
	 case "$2" in
	    "")
	       MultiLog "Error: option required but not specified" >&2
	       shift 2
	       exit 1
	       ;;
	    *) 
               FsSpec "${2}"
               shift 2;
	       ;;
	 esac
	 ;;
      --)
         shift
         break
         ;;
      *)
         MultiLog "Internal error!" >&2
         exit 1
         ;;
   esac
done

# Only after flag-parsing is done, can we set the 
# var to the unflagged consistency-group variable
CONGRP=${1:-UNDEF}

# Make sure the consistency-group is specified
if [ "${CONGRP}" = "UNDEF" ]
then
   MultiLog "No consistency-group specified. Aborting" >&2
   exit 1
fi

# Generate list of all EBSes attached to this instance
ALLVOLIDS=`aws ec2 describe-volumes \
   --filters "Name=attachment.instance-id,Values=${THISINSTID}" \
   --query "Volumes[].Attachments[].VolumeId" --output text`

COUNT=0
for VOLID in ${ALLVOLIDS}
do
   VOLIDS[${COUNT}]=$(aws ec2 describe-volumes --volume-id ${VOLID} --filters "Name=tag:Consistency Group,Values=${CONGRP}" --query "Volumes[].Attachments[].VolumeId" --output text)
   COUNT=$((${COUNT} + 1))
done


if [[ "${VOLIDS[@]}" = "" ]]
then
   MultiLog "No volumes found in the requested consistency-group [${CONGRP}]" >&2
fi

# Gonna go old school (who the heck uses named pipes in shell scripts???)
if [[ ! -p ${FIFO} ]]
then
   mkfifo ${FIFO}
fi

# Freeze any enumerated filesystems
FSfreezeToggle freeze

# Snapshot volumes
for EBS in ${VOLIDS[@]}
do
   MultiLog "Snapping EBS volume: ${EBS}"
   # Spawn off backgrounded subshells to reduce start-deltas across snap-set
   # Send our snapshot IDs to a FIFO for later use...
   ( \
      aws ec2 create-snapshot --output=text --description ${BKNAME} \
        --volume-id ${EBS} --query SnapshotId > ${FIFO}
   ) &
done

# Set our "Created By" label
GetInvocation

# Read our pipe and apply labels as IDs trickle through the fifo.
for SNAPID in `cat ${FIFO}`
do
   echo "Tagging snapshot: ${SNAPID}"
   ( \
   aws ec2 create-tags --resource ${SNAPID} --tags \
      Key="Created By",Value="${CREATEMETHOD}" ; \
   aws ec2 create-tags --resource ${SNAPID} --tags \
      Key="Name",Value="AutoBack (${THISINSTID}) $(date '+%Y-%m-%d')" ; \
   aws ec2 create-tags --resource ${SNAPID} --tags \
      Key="Snapshot Group",Value="${DATESTMP} (${THISINSTID})" ; \
   ) &
done

# Unfreeze any enumerated filesystems
echo "Unfreezing..."
FSfreezeToggle unfreeze

# Cleanup on aisle six!
rm ${FIFO}
