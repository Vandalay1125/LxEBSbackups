# LxEBSbackups
This project contains a collection of scripts designed to facilitate the creation of and recovery from EBS volume snapshots for Linux-based EC2 instances

When used as intended, the scripts allow for easy creation and maintenance of EBS snapshots for server instances running on AWS.  

## Backups Using EBS Snapshots
Backups are achieved by using the [SnapByCgroup.sh](README_SnapByCgroup.sh.md) with CRON to schedule when snapshots are conducted.  The script has the ability to quiesce the file system and to snap groups of disks at the same time, referred to as "Consistency Groups".

Example System: 
* CentOS 6.7
* EBS Root Volume
* EBS Data Volume

```
Filesystem            Size  Used Avail Use% Mounted on
/dev/mapper/VolGroup00-rootVol
                      3.9G  1.1G  2.6G  31% /
tmpfs                 498M   12K  498M   1% /dev/shm
/dev/xvda1            453M   63M  367M  15% /boot
/dev/mapper/VolGroup00-varVol
                      2.0G   73M  1.8G   4% /var
/dev/mapper/VolGroup00-logVol
                      2.0G  8.3M  1.8G   1% /var/log
/dev/mapper/VolGroup00-auditVol
                      8.3G   20M  7.9G   1% /var/log/audit
/dev/mapper/VolGroup00-homeVol
                      976M  1.3M  924M   1% /home
tmpfs                 498M     0  498M   0% /tmp
/dev/mapper/VolGroup01-data
                      3.9G  8.0M  3.7G   1% /mnt/data
```
### Pre-requisites
* Functioning Git `yum install git`
* Functional AWS CLI

### Procedure
1. Tag the EBS volumes to snap following the directions [here](README_SnapByCgroup.sh.md) . In our example we added the following tag and value to both EBS volumes:

    ~~~
key = Consistency Group #this is a required value, don't modify it
value = MyGroup01 #name this whatever you want, whatever volumes share this value will be snapped together
    ~~~

2. Retrieve the SnapByCgroup.sh script 

    ~~~
cd /root
git clone <url to git repo for LxEBSbackups>
    ~~~

3. Test the script

    ~~~
/root/LxEBSbackups/SnapByCgroup.sh -f /mnt/data MyGroup01
Attempting to freeze '/mnt/data/'
Snapping EBS volume: vol-55555555
Snapping EBS volume: vol-55555556
Tagging snapshot: snap-55555557
Tagging snapshot: snap-55555558
Unfreezing...
Attempting to unfreeze '/mnt/data/'
    ~~~

4. Create a CRON job to create snapshots nightly at 1 AM

    ~~~
crontab -e
    ~~~
  
  Add this line:

    ~~~
0 01 * * * /root/LxEBSbackups/SnapByCgroup.sh -f /mnt/data MyGroup01
    ~~~

### Result
Looking in the AWS web console under EC2>Snapshots, you should now see a new snapshot for each EBS disk in the consistency group.  In this case:

Name | SnapshotID
---- | ----------
AutoBack (i-99999999) 2015-08-26 | snap-ffffffff
AutoBack (i-88888888) 2015-08-26 | snap-eeeeeeee

And every night a new set will be created.

But wait, these things are really going to start piling up.  Fear not, read on...

## Backup Snapshot Maintenance

The [maintenance script](README_MaintSnaps.sh.md) will comb through the snapshots for your instance and delete ones older than the number of days you specify.

But what if I have snapshots I created manually that I don't want deleted?  No problem, the script will only delete snapshots if the tags match those automatically set by the SnapByCgroup.sh script when run as a CRON job.  Your custom snapshots are safe.

### Prerequisites
* You completed the procedure above to create the backup snapshots

### Procedure

1. Set the how many days you want to retain snapshots in the [commonVars.env](README_commonVars.env.md) file.

2. Test the script

    ~~~
/root/LxEBSbackups/MaintSnaps.sh
Beginning stale snapshot cleanup (killing files older than 2015/08/19 @ 18:25)
    ~~~

4. Create a CRON job to delete old snapshots nightly at 5 AM

    ~~~
crontab -e
    ~~~
  
  Add this line:

    ~~~
0 05 * * * /root/LxEBSbackups/MaintSnaps.sh
    ~~~

### Result
IF there were any snapshots created by SnapByCgroup.sh run via CRON older than the number of days you set in step 1, then they should now be gone under EC2>Snapshots.  Every morning at 5 AM, older snaps will be deleted.

Note: This script will NOT delete snapshots created when running SnapByCgroup.sh manually from the command line.

## Restore from EBS Snapshot

Uh oh.  Something went horribly wrong and you need to recover from one of the snapshots you've been keeping.  Fundamentally, you will be creating new EBS volumes from the snapshots and mounting them in order to recover files or whole instances.  

There are many ways to "skin the cat".  You can perform recoveries manually using the AWS web console or you can use the RestoreByName.sh script we've created.  For more information, check [here](README_RestoreByName.sh.md).
