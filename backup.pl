#!/usr/bin/env perl
use strict;

=pod

* WHAT I WANT
** Essential Features
   - [X] code which backs up directories
   - [X] backups are done with rsync and hard links
   - [X] can be run with source and dest params for single backup

** Later
   - [ ] should be cron-friendly (logging etc)
   - [ ] can be run with instruction file(s) specifying all source->dest
  pairs to back up

** Less important features
   - silent and verbose mode
   - dry run mode


=cut

use Getopt::Std;
use DateTime;

my $settings = {
                # Batch instruction file
                instruction_file => '',

                # Batch instructions go here
                backup => [],

                # Verbosity level
                # 0 = silent run
                # 1 = normal. Show what I will do, then say how it went
                # 2 = verbose. Do all in (1) but also how it's going
                verbosity => '1',

                # Do I just pretend to do stuff?
                # 0 = no, do it for realz
                # 1 = yes, just pretend.
                dry_run => '0',
               };


# --------------------------------------------------
# Get commandline arguments
my @message;
my $opts = {};
usage({exit => 0}) unless getopts('hnv:s:d:f:', $opts);

if (defined($opts->{n})) { $settings->{dry_run}          = 1          }
if (defined($opts->{f})) { $settings->{instruction_file} = $opts->{f} }
if (defined($opts->{v})) { $settings->{verbosity}        = $opts->{v} }
my ($source, $dest);
if (defined($opts->{s})) { $source  = $opts->{s}                      }
if (defined($opts->{d})) { $dest = $opts->{d}                         }
if (defined($opts->{h})) { usage({exit => 0})                         }


# --------------------------------------------------
# Sanity-check commandline input

# source and destination
unless (defined($source) && defined($dest)) {
  usage({
         msg => 'Both source and destination directories needed',
         exit => 1
        });
}
for my $cons (['Source', $source], ['Destination', $dest]) {
   my $name = @$cons[0];
   my $dir = @$cons[1];
   push @message, "$name: '$dir'";

   my $msg;
   unless (-e $dir) { $msg = "$name '$dir' not found." }
   unless (-d $dir) { $msg = "$name '$dir' isn't a directory." }
   unless (-r $dir) { $msg = "$name '$dir' is not readable." }

   usage({msg => $msg, exit => 1}) if (defined($msg));
 }
$source =~ s|/$||;
$dest =~ s|/$||;
push @{$settings->{backup}}, ([$source, $dest]);
undef $source; undef $dest;

push (@message, 'Dry run mode') if ($settings->{dry_run});

# --------------------------------------------------
# Do the backup

my $dt = DateTime->now;
my $timestamp = join('-', $dt->ymd(''), $dt->hms('')); #YYYYMMDD-HHMMSS
push @message, "Timestamp: $timestamp";


# backupdir/peanut-home/20221112-231212/home/anna/...
# backupdir/peanut-home/20221112-231212/home/fimblo/...
# backupdir/peanut-mnt-data/20221112-231212/mnt/data/...
# backupdir/squash-home/20221112-231212/home/fimblo/...
# backupdir/squash-home/20221112-231212/home/git/...


my $source_system = 'peanut'; # TODO support remote backups later
$source = $settings->{backup}->[0]->[0];
$dest = $settings->{backup}->[0]->[1];

my $source_suffix = $source;
$source_suffix =~ s|/|-|g;
my $label = join ('-', $source_system, $source_suffix);
my $real_dest = "$dest/$label/$timestamp";

push @message, "Label: $label";
push @message, "Backup space: $dest/$label";
push @message, "Upcoming backup will be stored here: $real_dest";


# print status so far
print join ("\n", @message) . "\n";
@message = ();


#rsync -av --link-dest=../../backups/one source backups/two

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
push @message, "Found the most recent backup to hardlink from: $newest_existing_backup";


# mkdir -p
unless ($settings->{dry_run}) {
  my $tmp_dir = '/';
  for my $part (split('/', $real_dest)) {
    $tmp_dir .= "$part/";
    mkdir $tmp_dir unless (-d $part);
  }
}


my $o_dry_run = ($settings->{dry_run} == 1) ? '-n' : '';
my $rsync = '/usr/bin/rsync';
my $o_link_dest;
if ($newest_existing_backup) {
  $o_link_dest = "--link-dest ../$newest_existing_backup";
}
my $command = join (' ',
                    $rsync,
                    '-av',
                    $o_dry_run,
                    $o_link_dest,
                    "$source/",
                    $real_dest
                   );
push @message, "Command to run:\n$command";

# print status so far
print join ("\n", @message) . "\n";
@message = ();


# --------------------------------------------------
# run the command!
my $retval = qx/$command/;
print $retval;

# use Data::Dumper;
# print Dumper($settings);


# --------------------------------------------------
# subs

sub usage {
  my $p = shift;
  print<<"_USAGE_";
USAGE
  backup.pl  {{-s <src-dir> -d <dest-dir>}|{-f <instruction-file>}}
             [-v {0|1|2}] [-n] [-h]

    -h    usage. This text.
    -n    dry-run. Show stuff but do nothing
    -v    verbosity
          0 = silent
          1 = default
          2 = verbose

    -s <src-dir> -d <dest-dir>
          One-off mode.

          Back up src-dir to dest-dir, checking for earlier versions to
          hard link to. Then exit.

NOTE ON DESTINATION DIR STRUCTURE

  If the following holds:

  /home/user/datadir/ is where we can find the files we want to back up
  /mnt/data           is where to back the stuff up to
  mymachine           is the host where the source data is
  221117-232301       is the datetime of the backup

  Then, this script will save the files contained in /home/user/datadir/
  here: /mnt/data/mymachine--home-user-datadir/221117-232301/
_USAGE_

#   -f <instruction-file>
#         File location of backup instructions. Contents should have one
#         backup instruction per line, with source directory and
#         destination directory, whitespace separated.

  (defined($p->{msg}))  && print "$p->{msg}\n";
  (defined($p->{exit})) && exit($p->{exit});
}

