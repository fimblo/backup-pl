#!/bin/bash
# --------------------------------------------------
# Startup script for backup.pl
DRYRUN='-n'                                  #skipme
[[ $1 == 'nodry' ]] && DRYRUN=''             #skipme
cat $0 | grep -vE '/bin/bash|#skipme' | grep .

#SOURCE=peanut:/home
SOURCE=git@squash.yanson.org:/home/git
DESTINATION=/mnt/raid/backup/
perl /home/fimblo/wc/github/backup-stuff/backup.pl $DRYRUN\
     -s $SOURCE \
     -d $DESTINATION
# --------------------------------------------------
