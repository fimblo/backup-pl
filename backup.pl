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
   - [X] remote backups
   - [ ] should be cron-friendly (logging etc)
   - [X] can be run with instruction file(s) specifying all source->dest  pairs to back up
** Less important features
   - [X] silent and verbose mode
   - [X] exclude files matching pattern
   - [ ] add --stats for SPAM verbosity
   - [ ] --one-file-system support
   - [X] support excluding multiple patterns


=cut

# Get rsync with full path
my $rsync = get_rsync_or_die();


# --------------------------------------------------
# Vars and constants

# poor man's verbosity enum
sub QUIET  {0}
sub NORMAL {1}
sub SPAM   {2}

# backup config file
my $go_cfg_file;

# Batch instructions go here.
# Arref of Arrefs. Each instruction should look like this:
#    {
#        src => srcpath,
#        dst => dstpath,
#        exclude_pat => pattern,
#        exclude_file => path/to/file
#    }
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
my $go_src;

# Destination to back up to in single-run mode
my $go_dest;

# Pattern describing files to exclude from backup in single-run mode
my $go_excl_pat;

# File containing patterns to exclude from backup
my $go_excl_file;

# --------------------------------------------------
# Get commandline arguments
my @message;
my $opts = {};
getopts('hHnv:s:d:e:E:f:', $opts);

unless (%$opts) { usage({exit => 0}) }
if (defined($opts->{h})) { usage({exit   => 0})       }
if (defined($opts->{H})) { detailed_usage_then_exit() }

if (defined($opts->{n})) { $go_dry_run   = 1          }
if (defined($opts->{f})) { $go_cfg_file  = $opts->{f} }
if (defined($opts->{v})) { $go_verbosity = $opts->{v} }
if (defined($opts->{s})) { $go_src       = $opts->{s} }
if (defined($opts->{d})) { $go_dest      = $opts->{d} }
if (defined($opts->{e})) { $go_excl_pat  = $opts->{e} }
if (defined($opts->{E})) { $go_excl_file = $opts->{E} }
$go_src =~ s|/+$||; $go_dest =~ s|/+$||;


# --------------------------------------------------
# Check which mode we run in. Single backup or batch.
my $dt = DateTime->now;
my $timestamp; # The current time, used to identify this backup session
$timestamp = join('-', $dt->ymd(''), $dt->hms('')); #YYYYMMDD-HHMMSS

if (defined($go_cfg_file)) {
  vprint(SPAM, "Batch mode detected. Ignoring -s, -d and -e options\n");
  vprint(SPAM, "Reading config file: '$go_cfg_file'\n");
  digest_config_file($go_cfg_file);
} else {
  vprint(SPAM, "Single-run mode detected. Checking -s, -d and -e options.\n");

  unless (defined($go_src) && defined($go_dest)) {
    usage({
           msg => 'Aborting: Both source and destination directories needed',
           exit => 1,
           no_usage => 1
          });
  }

  if (check_dir($go_dest)) {
    usage({msg => $_, exit => 1, no_usage => 1});
  }

  push @{$go_backup}, ({src => $go_src,
                        dst => $go_dest,
                        exclude_pat => $go_excl_pat,
                        exclude_file  => $go_excl_file
                       })
}





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
  my $exclude_pat;
  my $exclude_file;
  my $round = @commands;

  $source_raw   = $bk->{src};
  $dest_raw     = $bk->{dst};
  $exclude_pat  = $bk->{exclude_pat};
  $exclude_file = $bk->{exclude_file};

  # if exclude file is specified, remove any exclusion patterns
  if ($exclude_file) {
    if ($exclude_pat) {
      vprint(NORMAL, "Ignoring exclude pattern in favour of exclude file.\n");
    }
    undef $exclude_pat;
  }

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
  my $prev_backup;
  if (-d "$dest_raw/$unique_tag") {
    opendir(my $D, "$dest_raw/$unique_tag") || die $!;
    my @d_rows = reverse sort readdir($D);
    for my $row (@d_rows) {
      if ($row =~ m|\d{8}-\d{6}|) {
        $prev_backup = $row;
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


  # Assemble the rsync command
  my $exclude;
  if ($exclude_file) {
    $exclude = "--exclude-from=$exclude_file";
  } elsif ($exclude_pat) {
    $exclude =  "--exclude='$exclude_pat'";
  }
  my $link_dest = "--link-dest ../$prev_backup";
  my $command =
    join (' ',
          $rsync,
          '-a',
          ($go_verbosity == SPAM) ? '-v'       : '',
          ($prev_backup)          ? $link_dest : '',
          ($go_dry_run)           ? '-n'       : '',
          ($exclude)              ? $exclude   : '',
          "$source_raw/",
          $real_dest
         );


  # Gather all info for the user to eyeball
  my $msg_dry_run = ($go_dry_run) ? '(dry) ' : '';
  my $msg_exclude;
  my $msg_exclude_long = ':         -- none --';
  if ($exclude_file) {
    $msg_exclude = " EF:$exclude_file";
    $msg_exclude_long = " file:    '$exclude_file'";
  } elsif ($exclude_pat) {
    $msg_exclude = " E:$exclude_pat";
    $msg_exclude_long = " pattern: '$exclude_pat'";
  }
  push @messages, "Round $round ${msg_dry_run}S:${source_raw} D:${real_dest}$msg_exclude\n";

  my $msg_recent = $prev_backup;
  unless ($prev_backup) {
    $msg_recent = "NO PRIOR BACKUP.";
  }
  my $msg = <<"_INFO_";
Round $round backup.pl info
Round $round
Round $round Source system:   $source_system
Round $round Source dir:      $source_dir
Round $round Full source:     $source_raw
Round $round
Round $round Backup root:     $dest_raw/
Round $round Backup space:    $dest_raw/$unique_tag
Round $round Full target:     $real_dest
Round $round
Round $round Exclude$msg_exclude_long
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
vprint(NORMAL, "Proceeding with backups.\n");
my $round = 0;
for my $command (@commands) {
  vprint(NORMAL, "Round $round: ");
  vprint(NORMAL, "$command\n");



  my $retval = qx/$command 2>&1/;
  vprint(NORMAL, $retval);

  if ($? == 0) {
    # all good
  } elsif ($? == -1) {
    print "Round: $round, Error: failed to execute: $!\n";
    vprint(QUIET, "Rsync command: $command\n");
  } elsif ($? & 127) {
    printf "Round: $round, Error: rsync died with signal %d, %s coredump\n",
      ($? & 127),  ($? & 128) ? 'with' : 'without';
    vprint(QUIET, "Rsync command: $command\n");
  } else {
    printf "Round: $round, Error: rsync exited with value %d\n", $? >> 8;
    vprint(QUIET, "Rsync command: $command\n");
  }

  $round++;
}





# --------------------------------------------------
# subs

# printing with 0 will show on levels 0, 1 and 2 (QUIET).
# printing with 1 will show on levels 1 and 2 (NORMAL).
# printing with 2 will show only on level 2 (SPAM)
sub vprint {
  my $v_lvl = shift;
  my $msg   = shift;

  if ($v_lvl <= $go_verbosity) { print $msg }
}

sub check_dir {
  my $dir = shift;
  my $msg;
  if (! -e $dir) { $msg = "Aborting: '$dir' not found.\n";         }
  elsif (! -d $dir) { $msg = "Aborting: '$dir' isn't a directory.\n"; }
  elsif (! -r $dir) { $msg = "Aborting: '$dir' is not readable.\n";   }
  return $msg;
}


sub usage {
  my $p = shift;

  unless (defined($p->{no_usage})) {
    print<<"_USAGE_";
USAGE
  backup.pl  {{-s <src-dir> -d <dest-dir> [-e 'pattern']}|{-f <config-file>}}
             [-v {0|1|2}] [-n] [-h] [-H]

    -h    usage. This text.
    -H    more info on this script.
    -n    dry-run. Show stuff but do nothing
    -v    verbosity
          0 = silent
          1 = default
          2 = spammy

    -s <src-dir> -d <dest-dir> [-e 'pattern']
          One-off mode.

          Back up src-dir to dest-dir, checking for earlier versions to
          hard link to. Then exit.

          Optionally, -e will allow filenames matching the glob (3)
          pattern to be excluded from the backup.

     -f <config-file>
           File location of backup instructions. Using this argument
           will override any (-s/-d) args. See -H for more details.
_USAGE_



  }
  (defined($p->{msg}))  && print $p->{msg} . "\n";
  (defined($p->{exit})) && exit($p->{exit});
}


sub detailed_usage_then_exit {
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
  - See config examples in the file example-config.cfg
  - exclude patterns follow the rules specified in section
    INCLUDE/EXCLUDE PATTERN RULES in the rsync man page.

   Example file:
   # This is a comment
   BACKUP /path/to/src         /path/to/dest
   BACKUP /path/to/another/src /path/to/dest    exclude_this_pattern

_USAGE_
  exit (0);
}




sub digest_config_file {
  my $cfg_file = shift;

  open (my $FH, '<', $cfg_file) || die "Aborting: Can't open config file '$cfg_file'\n";
  my @cfg_rows = <$FH>;
  close $FH;

  my @msg;
  for (my $i = 0; $i < @cfg_rows; $i++) {
    my $line = $cfg_rows[$i];
    chomp $line;
    next if ($line !~ /./);
    next if ($line =~ /^#/);

    my ($cmd, $s, $d, $ef) = split(/\s+/, $line);
    my $cl = $i+1;
    if ($cmd ne 'BACKUP') {
      push @msg, "Line $cl: Command '$cmd' not recognised.\n";
    }
    unless ($s =~ /./) {
      push @msg, "Line $cl: Source dir missing.\n";
    }
    unless ($d =~ /./) {
      push @msg, "Line $cl: Destination dir missing.\n";
    }

    if (my $retval = check_dir($d)) {
      vprint(QUIET, "Line: $cl: ");
      usage({msg => $retval, exit => 1, no_usage => 1});
    }
    push @{$go_backup}, ({src => $s, dst => $d, exclude_file => $ef});
  }

  if (@msg) {
    print for @msg;
    print "Aborting: Run with -H for detailed info on backup config file format.\n";
    exit(1);
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
