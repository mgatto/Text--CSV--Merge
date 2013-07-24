#!/usr/bin/env perl -T

use Test::More tests => 1;
use local::lib;
use lib 'lib';

BEGIN {
    use_ok( 'Text::CSV::Merge' ) || print "Could not load Text::CSV::Merge!\n";
}


diag( "Text::CSV::Merge $Text::CSV::Merge, Perl $], $^X" );
