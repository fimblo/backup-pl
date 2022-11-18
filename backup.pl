#!/usr/bin/env perl
use strict;
no strict 'refs';


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

use Getopt::Std;
use DateTime;



# backup config file
my $config_file = '';

# Batch instructions go here
my $backup = [];

# Verbosity level
# 0 = silent run
# 1 = normal. Show what I will do, then say how it went
# 2 = verbose. Do all in (1) but also how it's going
my $verbosity = '1';

# Do I just pretend to do stuff?
# 0 = no, do it for realz
# 1 = yes, just pretend.
my $dry_run = '0';

# Source to back up from in single-run mode
my $source = '';

# Destination to back up to in single-run mode
my $dest = '';


# --------------------------------------------------
# Get commandline arguments
my @message;
my $opts = {};
getopts('hHnv:s:d:f:', $opts);

unless (%$opts)          { usage({exit  => 0})       }
if (defined($opts->{h})) { usage({exit  => 0})       }
if (defined($opts->{H})) { more_usage()              }

if (defined($opts->{n})) { $dry_run     = 1          }
if (defined($opts->{f})) { $config_file = $opts->{f} }
if (defined($opts->{v})) { $verbosity   = $opts->{v} }
if (defined($opts->{s})) { $source      = $opts->{s} }
if (defined($opts->{d})) { $dest        = $opts->{d} }
$source =~ s|/+\s*$||; $dest =~ s|/+\s*$||;


# --------------------------------------------------
# Sanity-check commandline input


# source and destination
check_backup_couplet($source, $dest);
push @{$backup}, ([$source, $dest]);
undef $source; undef $dest;



# --------------------------------------------------
# Prepare for back up

my $dt = DateTime->now;
my $timestamp = join('-', $dt->ymd(''), $dt->hms('')); #YYYYMMDD-HHMMSS


my $source_raw = $backup->[0]->[0];
$dest = $backup->[0]->[1];

my $source_system;
my $source_dir;
if ($source_raw =~ m/^(.*?):(.*?)$/) {
  $source_system = $1;
  $source_dir = $2;
} else {
  $source_system = qx/hostname/;
  chomp $source_system;
  $source_dir = $source_raw;
}

print "$source_system\n";


my $source_suffix = $source_dir;
$source_suffix =~ s|/|-|g;
my $label = join ('-', $source_system, $source_suffix);
my $real_dest = "$dest/$label/$timestamp";


# Check if there is a previous backup to hardlink from
my $newest_existing_backup;
if (-d "$dest/$label") {
  opendir(my $D, "$dest/$label") || die $!;
  my @d_rows = reverse sort readdir($D);
  for my $row (@d_rows) {
    if ($row =~ m|\d{8}-\d{6}|) {
      $newest_existing_backup = $row;
      last;
    }
  }
  closedir($D);
}

# mkdir -p
unless ($dry_run) {
  my $tmp_dir = "$dest/";
  for my $part (split('/', "$label/$timestamp")) {
    $tmp_dir .= "$part/";
    mkdir $tmp_dir unless (-d $tmp_dir);
  }
}


my $o_dry_run = ($dry_run == 1) ? '-n' : '';
my $rsync = '/usr/bin/rsync';
my $o_link_dest;
if ($newest_existing_backup) {
  $o_link_dest = "--link-dest ../$newest_existing_backup";
}
my $command = join (' ',
                    $rsync,
                    '-a',
                    $o_dry_run,
                    $o_link_dest,
                    "$source_raw/",
                    $real_dest
                   );


my ($msg_recent, $msg_dry_run) = ($newest_existing_backup, '');
if ($dry_run) {
  $msg_dry_run = "- DRY RUN MODE -" x 4 ;
  $msg_dry_run .= "\n\n";
}

unless ($newest_existing_backup) {
  $msg_recent = "NO PRIOR BACKUP.";
}


print<<"_INFO_";
backup.pl info

${msg_dry_run}Source system: $source_system
Source dir:    $source_dir
Full source:   $source_raw

Backup root:   $dest/
Backup space:  $dest/$label
Full target:   $real_dest

Prior backup to hardlink from: $msg_recent

Rsync command:
$command

_INFO_


# --------------------------------------------------
# run the command!

print "Running rsync in dry-run mode\n" if ($msg_dry_run);
my $retval = qx/$command/;
print $retval;




# --------------------------------------------------
# subs

sub usage {
  my $p = shift;

  unless (defined($p->{no_usage})) {
    print<<"_USAGE_";
USAGE
  backup.pl  {{-s <src-dir> -d <dest-dir>}|{-f <instruction-file>}}
             [-v {0|1|2}] [-n] [-h] [-H]

    -h    usage. This text.
    -H    more info on this script.
    -n    dry-run. Show stuff but do nothing
    -v    verbosity
          0 = silent
          1 = default
          2 = verbose

    -s <src-dir> -d <dest-dir>
          One-off mode.

          Back up src-dir to dest-dir, checking for earlier versions to
          hard link to. Then exit.
_USAGE_

    #   -f <instruction-file>
    #         File location of backup instructions. Contents should have one
    #         backup instruction per line, with source directory and
    #         destination directory, whitespace separated.
  }
  (defined($p->{msg}))  && print $p->{msg} . "\n";
  (defined($p->{exit})) && exit($p->{exit});
}


sub more_usage {
  print<<"_USAGE_";
NOTE ON THE BACKUP SOURCE

  The source may be local or remote.

NOTE ON THE BACKUP DESTINATION

  The destination directory must be local. This code does not support
  backing up to a remote directory.

NOTE ON DESTINATION DIR STRUCTURE

  If the following holds:

  /home/user/datadir/ is where we can find the files we want to back up
  /mnt/data           is where to back the stuff up to
  mymachine           is the host where the source data is
  221117-232301       is the datetime of the backup

  Then, this script will save the files contained in /home/user/datadir/
  here: /mnt/data/mymachine--home-user-datadir/221117-232301/
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
  if    (! -e $dest) { $msg = "Error: '$dest' not found.";         }
  elsif (! -d $dest) { $msg = "Error: '$dest' isn't a directory."; }
  elsif (! -r $dest) { $msg = "Error: '$dest' is not readable.";   }

  if ($msg) {
    usage({msg => $msg, exit => 1, no_usage => 1});
  }

}
