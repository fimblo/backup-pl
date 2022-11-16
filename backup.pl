#!/usr/bin/env perl
use strict;

=pod

* WHAT I WANT
** Essential Features
   - [ ] code which backs up directories
   - [ ] backups are done with rsync and hard links
   - [ ] can be run with source and dest params for single backup

** Later
   - [ ] should be cron-friendly (logging etc)
   - [ ] can be run with instruction file(s) specifying all source->dest
  pairs to back up

** Less important features
   - silent and verbose mode
   - dry run mode

* commandline options
{{-s <src-dir> -d <dest-dir>}|{-f <instruction-file>}}
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

  -f <instruction-file>
        File location of backup instructions. Contents should have one
        backup instruction per line, with source directory and
        destination directory, whitespace separated.


=cut

use Getopt::Std;

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


my @message;
my $opts = {};
usage({exit => 0}) unless getopts('hnv:s:d:f:', $opts);

if (defined($opts->{n})) { $settings->{dry_run}          = 1          }
if (defined($opts->{f})) { $settings->{instruction_file} = $opts->{f} }
if (defined($opts->{v})) { $settings->{verbosity}        = $opts->{v} }
my ($src, $dest);
if (defined($opts->{s})) { $src  = $opts->{s}                         }
if (defined($opts->{d})) { $dest = $opts->{d}                         }
if (defined($opts->{h})) { usage({exit => 0})                         }


# sanity check source and destination
unless (defined($src) && defined($dest)) {
  usage({
         msg => 'Both source and destination directories needed',
         exit => 1
        });
}
for my $cons (['Source', $src], ['Destination', $dest]) {
   my $name = @$cons[0];
   my $dir = @$cons[1];
   push @message, "$name: '$dir'";

   my $msg;
   unless (-e $dir) { $msg = "$name '$dir' not found." }
   unless (-d $dir) { $msg = "$name '$dir' isn't a directory." }
   unless (-r $dir) { $msg = "$name '$dir' is not readable." }

   usage({msg => $msg, exit => 1}) if (defined($msg));
 }
push @{$settings->{backup}}, ([$src, $dest]);



# print status so far
print join ("\n", @message) . "\n";




use Data::Dumper;
print Dumper($settings);

sub usage {
  my $p = shift;
  print<<"_USAGE_";
Insert usage here!
_USAGE_

  (defined($p->{msg}))  && print "$p->{msg}\n";
  (defined($p->{exit})) && exit($p->{exit});
}

