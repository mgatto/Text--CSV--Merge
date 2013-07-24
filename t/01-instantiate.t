#!/usr/bin/env perl -T

use Test::More tests => 2;
use local::lib;
use lib 'lib';
use Text::CSV::Merge;

BEGIN {
}

my $merge = Text::CSV::Merge->new({
   
});
# create an object
ok( defined $merge );                # check that we got something
ok( $merge->isa('Text::CSV::Merge') );     # and it's the right class
