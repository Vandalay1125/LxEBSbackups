#!/bin/sh
#
# This script is designed to simplify the addition of attachment-
#   point mapping tags to all EBSes attached to instance
#
# Dependencies:
# - commonVars.env
#
# License:
# - This script released under the Apache 2.0 OSS License
#
#
#################################################################

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


######################################
##                                  ##
## Section for defining main        ##
##    program function and flow     ##
##                                  ##
######################################

# Generate list of all EBSes attached to this instance
ALLVOLINFO=$(aws ec2 describe-volumes \
   --filters "Name=attachment.instance-id,Values=${THISINSTID}" \
   --query "Volumes[].Attachments[].{ID:VolumeId,DEV:Device}" \
   --output text | tr "\t" ";")

COUNT=0
for VOLINFO in ${ALLVOLINFO}
do
   ATTACH=$(echo ${VOLINFO} | cut -d ";" -f 1)
   VOLUME=$(echo ${VOLINFO} | cut -d ";" -f 2)
   echo "Applying attachment-point tag [${ATTACH}] to EBS ${VOLUME}"
   aws ec2 create-tags --resource ${VOLUME} --tags \
      "Key=Attachment Point,Value=${ATTACH}"
done


