#!/usr/bin/env perl
use strict;

=pod

* WHAT I WANT
** Features
   - [ ] code which backs up directories
   - [ ] backups are done with rsync and hard links
   - [ ] should be cron-friendly (logging etc)
   - [ ] can be run with source and dest params for single backup
   - [ ] can be run with instruction file(s) specifying all source->dest
  pairs to back up

** Less important features
   - silent and verbose mode
   - dry run mode

=end


