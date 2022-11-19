#!/usr/bin/env perl
use strict;
#no strict 'refs';

use Getopt::Std;
use DateTime;


=pod

* WHAT I WANT
** Essential Features
   - [X] code which backs up directories
   - [X] backups are done with rsync and hard links
   - [X] can be run with source and dest params for single backup
   - [X] dry run mode

** Later
   - [ ] remote backups
   - [ ] should be cron-friendly (logging etc)
   - [ ] can be run with instruction file(s) specifying all source->dest  pairs to back up
** Less important features
   - [ ] silent and verbose mode


=cut

# poor man's verbosity enum
sub QUIET  {0}
sub NORMAL {1}
sub SPAM   {2}

# might as well check very early for rsync.
my $rsync = get_rsync_or_die();



# backup config file
my $go_cfg_file = '';

# Batch instructions go here
my $go_backup = [];

# Verbosity level
# 0 = silent run
# 1 = normal. Show what I will do, then say how it went
# 2 = verbose. Do all in (1) but also how it's going
my $go_verbosity = '1';

# Do I just pretend to do stuff?
# 0 = no, do it for realz
# 1 = yes, just pretend.
my $go_dry_run = '0';

# Source to back up from in single-run mode
my $go_src = '';

# Destination to back up to in single-run mode
my $go_dest = '';


# --------------------------------------------------
# Get commandline arguments
my @message;
my $opts = {};
getopts('hHnv:s:d:f:', $opts);

unless (%$opts) { usage({exit   => 0})       }
if (defined($opts->{h})) { usage({exit   => 0})       }
if (defined($opts->{H})) { more_usage()               }

if (defined($opts->{n})) { $go_dry_run   = 1          }
if (defined($opts->{f})) { $go_cfg_file  = $opts->{f} }
if (defined($opts->{v})) { $go_verbosity = $opts->{v} }
if (defined($opts->{s})) { $go_src       = $opts->{s} }
if (defined($opts->{d})) { $go_dest      = $opts->{d} }
$go_src =~ s|/+\s*$||; $go_dest =~ s|/+\s*$||;


# --------------------------------------------------
# Check which mode we run in. Single backup or batch.
my $dt = DateTime->now;
my $timestamp; # The current time, used to identify this unique backup.
$timestamp = join('-', $dt->ymd(''), $dt->hms('')); #YYYYMMDD-HHMMSS

# if (defined($go_cfg_file)) {
#   digest_config_file($go_cfg_file);
# } else {
check_backup_couplet($go_src, $go_dest);
push @{$go_backup}, ([$go_src, $go_dest]);
#push @{$go_backup}, ([$go_src, $go_dest]);
# }








# --------------------------------------------------
# Prepare for back up
my @commands;
my @messages;
for my $bk (@$go_backup) {
  my $source_raw;        # Source provided by user
  my $source_system;     # Hostname of source
  my $source_dir;        # Directory path of $source_raw
  my $source_fs_safe;    # $source_raw with slashes replaced with dash
  my $unique_tag;        # Unique backup tag

  my $dest_raw;          # Destination provided by user
  my $real_dest;         # The actual destination - $dest_raw suffixed
                         # with tag and timestamp
  my $round = @commands;

  $source_raw = $bk->[0];
  $dest_raw   = $bk->[1];

  # Separate the (optional) user@hostname from the directory portion of
  # the Source input.
  if ($source_raw =~ m/^(.*?):(.*?)$/) {
    $source_system = $1;
    $source_dir = $2;
  } else {
    $source_system = qx/hostname/;
    chomp $source_system;
    $source_dir = $source_raw;
  }

  # Create this source's unique tag to mark the destination with This
  # way, we know where to hard link from if this source is re-used in
  # the future.
  $source_fs_safe = $source_dir;
  $source_fs_safe =~ s|/|-|g;
  $unique_tag = join ('-', $source_system, $source_fs_safe);
  $real_dest = "$dest_raw/$unique_tag/$timestamp";


  # Check if there is a previous backup inside this unique tag to hard
  # link from
  my $newest_existing_backup;
  if (-d "$dest_raw/$unique_tag") {
    opendir(my $D, "$dest_raw/$unique_tag") || die $!;
    my @d_rows = reverse sort readdir($D);
    for my $row (@d_rows) {
      if ($row =~ m|\d{8}-\d{6}|) {
        $newest_existing_backup = $row;
        last;
      }
    }
    closedir($D);
  }


  # Make unique dir if not dry run and if it doesn't exist
  unless ($go_dry_run) {
    my $tmp_dir = "$dest_raw/";
    my $msg_mkdir;
    for my $part (split('/', "$unique_tag/$timestamp")) {
      $tmp_dir .= "$part/";
      mkdir $tmp_dir;
    }
  }


  # assemble the rsync command
  my $link_dest = "--link-dest ../$newest_existing_backup";
  my $command = join (' ',
                      $rsync,
                      '-a',
                      ($go_verbosity == SPAM  ) ? '-v'       : '',
                      ($go_dry_run   == 1     ) ? '-n'       : '',
                      ($newest_existing_backup) ? $link_dest : '',
                      "$source_raw/",
                      $real_dest
                     );


  # Gather all info for the user to eyeball
  my $msg_dry_run = ($go_dry_run) ? '(dry) ' : '';
  push @messages, "Round $round $msg_dry_run$source_raw $real_dest\n";

  my $msg_recent = $newest_existing_backup;
  unless ($newest_existing_backup) {
    $msg_recent = "NO PRIOR BACKUP.";
  }
  my $msg = <<"_INFO_";
Round $round backup.pl info
Round $round
Round $round Source system: $source_system
Round $round Source dir:    $source_dir
Round $round Full source:   $source_raw
Round $round
Round $round Backup root:   $dest_raw/
Round $round Backup space:  $dest_raw/$unique_tag
Round $round Full target:   $real_dest
Round $round
Round $round Prior backup to hardlink from: $msg_recent

_INFO_
  vprint(SPAM, $msg);


  # Save the rsync command in the command queue
  push @commands, $command;
}


# --------------------------------------------------
# print something so user doesn't get twitchy
vprint(NORMAL, "Summary of all queued backups:\n");
vprint(NORMAL, $_) for @messages;

if ($go_dry_run) {
  my $msg_dry_run = "\n" . "- DRY RUN MODE -" x 4 ;
  $msg_dry_run .= "\n\n";
  vprint(SPAM, $msg_dry_run);
}


# --------------------------------------------------
# Do all the rsyncs
for my $command (@commands) {
  vprint(NORMAL, "$command\n");
  my $retval = qx/$command 2>&1/;
  print $retval;
}



# --------------------------------------------------
# subs

sub vprint {
  my $v_lvl = shift;
  my $msg = shift;

  if ($v_lvl <= $go_verbosity) { print $msg }
}



sub usage {
  my $p = shift;

  unless (defined($p->{no_usage})) {
    print<<"_USAGE_";
USAGE
  backup.pl  {{-s <src-dir> -d <dest-dir>}|{-f <config-file>}}
             [-v {0|1|2}] [-n] [-h] [-H]

    -h    usage. This text.
    -H    more info on this script.
    -n    dry-run. Show stuff but do nothing
    -v    verbosity
          0 = silent
          1 = default
          2 = spammy

    -s <src-dir> -d <dest-dir>
          One-off mode.

          Back up src-dir to dest-dir, checking for earlier versions to
          hard link to. Then exit.

    -f <config-file>
          File location of backup instructions. Contents should have one
          backup instruction per line, with source directory and
          destination directory, whitespace separated.

          Using this argument will override any (-s/-d) args.
_USAGE_

  }
  (defined($p->{msg}))  && print $p->{msg} . "\n";
  (defined($p->{exit})) && exit($p->{exit});
}


sub more_usage {
  print<<"_USAGE_";
NOTE ON THE BACKUP SOURCE
  The source may be local or remote. Valid examples:

  /mnt/some/directory
  myhostname:/mnt/some/dir
  user\@myhostname:/home/user/stuffs

NOTE ON THE BACKUP DESTINATION
  The destination directory must be local. This code does not support
  backing up to a remote directory.

NOTE ON DESTINATION DIR STRUCTURE
  If the following holds:

  /home/user/datadir/ is where we can find the files we want to back up
  /mnt/data           is where to back the stuff up to
  user\@server        is the host where the source data is
  221117-232301       is the datetime of the backup

  Then, this script will save the files contained in /home/user/datadir/
  here: /mnt/data/user\@server--home-user-datadir/221117-232301/

NOTE ON BACKUP CONFIG FILE FORMAT
  - Lines beginning with '#' are considered comments and are ignored
  - Empty lines are ignored
  - One command supported: BACKUP
  - All args to BACKUP are whitespace separated (tab or space)

   Example file:
   # This is a comment
   BACKUP /path/to/src         /path/to/dest
   BACKUP /path/to/another/src /path/to/dest

_USAGE_
  exit (0);
}


sub check_backup_couplet {
  my $source = shift;
  my $dest = shift;

  unless (defined($source) && defined($dest)) {
    usage({
           msg => 'Both source and destination directories needed',
           exit => 1,
           no_usage => 1
          });
  }

  # Only check destination directory, since source might be remote anyway
  my $msg;
  if (! -e $dest) { $msg = "Error: '$dest' not found.";         }
  elsif (! -d $dest) { $msg = "Error: '$dest' isn't a directory."; }
  elsif (! -r $dest) { $msg = "Error: '$dest' is not readable.";   }

  if ($msg) {
    usage({msg => $msg, exit => 1, no_usage => 1});
  }

}



sub get_rsync_or_die {
  my $retval = qx/which rsync/;
  if ($? == 0 && $retval ne '') {
    chomp $retval;
    return $retval;
  } else {
    print "One or both the commands 'which' or 'rsync' is not in your PATH\n";
    printf "System command 'which rsync' exited with value %d\n", $? >> 8;
    die;
  }
}
