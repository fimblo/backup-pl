#!/bin/bash
# --------------------------------------------------
# Startup script for backup.pl
DRYRUN='-n'                                  #skipme
[[ $1 == 'nodry' ]] && DRYRUN=''             #skipme
#cat $0 | grep -vE '/bin/bash|#skipme' | grep .

#SOURCE=git@squash.yanson.org:/home/git
#SOURCE=root@squash.yanson.org:/var/www/html
#DESTINATION=/mnt/raid/backup/
# SOURCE=/home/fimblo/tmp/bk/source
# DESTINATION=/home/fimblo/tmp/bk/backups/
SOURCE=/home
DESTINATION=/mnt/raid/backup

perl /home/fimblo/wc/github/backup-stuff/backup.pl -v0  $DRYRUN\
     -s $SOURCE \
     -d $DESTINATION
# --------------------------------------------------

# root@squash.yanson.org:/home
# root@squash.yanson.org:/var/www/html

