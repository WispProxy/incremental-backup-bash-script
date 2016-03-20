#!/bin/bash

############################################################
# ADMIN-INFO
MAIL=<your_mail>@<your_domain>

# DB-MySQL
USER=<db_user>
PASSWORD=<db_pass>
MAX_AL_PAC=512M

# SMB-SHARE
SMB_HOST=<ip_address_of_samba_share_folder>
SMB_FOLDER=/Backups/web/<ip_address_of_samba_share_folder>
SMB_USER=<samba_user>
SMB_PASS=<samba_pass>

# DIRs
BACKUP_ETC=/etc
BACKUP_WWW=/var/www
TEMPDIR=/var/backup
STORAGE=/mnt/storage

# STATIC-WAYs
IFCONFIG=/sbin/ifconfig
NETSTAT=/bin/netstat
MYSQL_SE=/usr/bin/mysql
MYSQLDUMP=/usr/bin/mysqldump
BLAKE2=/home/blake2/b2sum/b2sum
MOUNT=/bin/mount
MCIFS=/sbin/mount.cifs

# STATIC-COMMANDs
IP=$($IFCONFIG eth0 | sed -n '/inet addr:/s/^[^:]*:\([0-9\.]*\).*/\1/gp')
DATE=$(date '+%Y-%m-%d')
DISK_INFO=$(df -h)
MEM_INFO=$(free)
SSH_INFO=$($NETSTAT -penal | grep :22)
LIST=$(ls -l /var/www | egrep "data.*" | awk '{print $9}')
WDAY=$(date +%u)
MYSQL_DB_GET=$($MYSQL_SE -u$USER -p$PASSWORD -e "SHOW DATABASES;" | grep -Ev "(Database|information_schema)")
VERIFY_MOUNT=$($MOUNT | grep -o "$SMB_HOST")
EXIT=$(exit 0)

# STATIC-NAMEs
ETC_FILE="$IP-etc-$DATE"

# B2-SUMs
B2_1="$TEMPDIR/$DATE-b2sum.b2"
B2_1_TEMP="$TEMPDIR/$DATE-b2sum-temp.b2"

# INCREMENT
CTMP="$TEMPDIR/lastbackup.log"
########################################################################



#//////////////////////////////////////////////////////////////////////////#
########################################################################
#======================START BACKUP MODULE========================

#----------------------START INCREMENT MODULE------------------
if [ "$WDAY" -ne 5 ];
then
	SAVELOG="$TEMPDIR/$DATE.SMALL.log"
	TARP="-N$CTMP"
	ARCH_ETC=""
	ARCH_WWW=""
	FULL_L=""
	touch -t `cat $CTMP` $CTMP
else
	SAVELOG="$TEMPDIR/$DATE.FULL.log"
	TARP=""
	ARCH_ETC="-FULL"
	ARCH_WWW="-FULL"
	FULL_L="-FULL"
	echo `date +%Y%m%d%H%M.%S` > $CTMP
fi
#----------------------END INCREMENT MODULE--------------------

echo "---------------------START BACKUP LOG---------------------" > $SAVELOG
printf "\n" >> $SAVELOG

echo "Create folder $TEMPDIR/$DATE" >> $SAVELOG
printf "\n" >> $SAVELOG
mkdir -p $TEMPDIR/$DATE/mysqldump

#----------------------Backup sql
echo "1 - Backup databases to $TEMPDIR" >> $SAVELOG
printf "\n" >> $SAVELOG
cd $TEMPDIR/$DATE/mysqldump

for db in $MYSQL_DB_GET;
do
$MYSQLDUMP --max_allowed_packet=$MAX_AL_PAC --force --opt -u $USER -p$PASSWORD --databases $db | gzip -c > $IP-db-$db-$DATE.sql.gz
done
#----------------------End Backup sql


#----------------------Backup etc
echo "2 - Backup dir - $BACKUP_ETC" >> $SAVELOG
printf "\n" >> $SAVELOG
cd $TEMPDIR/$DATE
tar -czf $ETC_FILE$ARCH_ETC.tar.gz $TARP $BACKUP_ETC >> $SAVELOG 2>&1
#----------------------End Backup etc


#----------------------Backup www
echo "3 - Backup dir - $BACKUP_WWW" >> $SAVELOG
printf "\n" >> $SAVELOG
cd $TEMPDIR/$DATE

for i in $LIST;
do
WWW_FILE="$IP-www-$i-$DATE$ARCH_WWW.tar.gz $TARP"
echo "$IP-www-$i-$DATE$ARCH_WWW.tar.gz" >> $SAVELOG
printf "\n" >> $SAVELOG
tar -czf $WWW_FILE $BACKUP_WWW/$i >> $SAVELOG 2>&1
echo `cat $CTMP` >> $SAVELOG
done
#----------------------End Backup www

printf "\n" >> $SAVELOG
echo "---------------------END BACKUP LOG---------------------" >> $SAVELOG

#=======================END BACKUP MODULE========================
#################################################################


#--------------------------------------------------
echo "Create B2-files for $TEMPDIR/$DATE"
B2_ST_TEMP=$(find $TEMPDIR/$DATE -type f -exec $BLAKE2 -a blake2sp {} + | awk '{print $1}' > $B2_1_TEMP)
$B2_ST_TEMP
B2_ST=$($BLAKE2 -a blake2sp $B2_1_TEMP | awk '{print $1}' > $TEMPDIR/$DATE-b2sum.b2)
$B2_ST
#--------------------------------------------------

#--------------------------------------------------
echo "Mount $SMB_HOST$SMB_FOLDER to $STORAGE"
if [ "$VERIFY_MOUNT" != "$SMB_HOST" ];
then
	mkdir -p $STORAGE
	$MCIFS //$SMB_HOST$SMB_FOLDER $STORAGE -o user=$SMB_USER,pass=$SMB_PASS,codepage=cp866,iocharset=utf8,file_mode=0777
else
	echo "Mounted!"
fi
#--------------------------------------------------

#--------------------------------------------------
echo "Copy backup files, dirs and B2-file to $STORAGE"
mkdir -p $STORAGE/$DATE$FULL_L
cp -R $TEMPDIR/$DATE/* $STORAGE/$DATE$FULL_L
cp $TEMPDIR/$DATE-b2sum.b2 $STORAGE/$DATE$FULL_L
#--------------------------------------------------

OUTLOG=$(cat $SAVELOG)

#--------------------------------------------------
mail -s "OK - BACKUP SCRIPT - $IP - $DATE" "$MAIL" <<EOF
---Backup script information:

IP-address:			$IP
Date:				$DATE
Verify the B2-file:		$TEMPDIR/$DATE-b2sum.b2

Increment log output...
Name:				$SAVELOG
Output:
$OUTLOG

---Server information:

Memory info:
$MEM_INFO

Disk space info:
$DISK_INFO

SSH connects info:
$SSH_INFO
EOF
#--------------------------------------------------

#----------------------MODULE RM-------------------
echo "RM $DATE $B2_1 $B2_1_TEMP $SAVELOG in $TEMPDIR"
cd $TEMPDIR
rm -rf $DATE $B2_1 $B2_1_TEMP $SAVELOG
#----------------------END MODULE RM---------------

#----------------------START MODULE END------------
echo "END"
$EXIT
#----------------------END MODULE END--------------
#---------------------------END BIG MODULE IF-THEN---------------------------
#//////////////////////////////////////////////////////////////////////////#


