#!/bin/bash
# --------------------------------------------------
# Startup script for backup.pl
DRYRUN='-n'                                  #skipme
[[ $1 == 'nodry' ]] && DRYRUN=''             #skipme
cat $0 | grep -vE '/bin/bash|#skipme' | grep .

SOURCE=/home/fimblo/tmp/bk/source
DESTINATION=/home/fimblo/tmp/bk/backups
perl /home/fimblo/wc/github/backup-stuff/backup.pl $DRYRUN\
     -s $SOURCE \
     -d $DESTINATION
# --------------------------------------------------
