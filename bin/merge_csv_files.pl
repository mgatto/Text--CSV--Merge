#! /usr/bin/env perl -w
# PODNAME: merge_csv_files.pl
# ABSTRACT: Command line client to Text::CSV::Merge

use Modern::Perl;
use Getopt::Long;
use Log::Dispatch;
#delete for release!
use lib '../lib';
use Text::CSV::Merge;

## Setup Options
my $base_file;
my $merge_file;
my $output_file = 'merge.csv';
my $search_field;
my $first_row_is_headers = 1;
my @columns;

GetOptions(
    "base=s"    => \$base_file,  # string
    "merge=s"     => \$merge_file, # string
    "output=s"  => \$output_file, # string
    "columns=s" => \@columns, # list
    "search=s"  => \$search_field, # string
    "first-row-is-headers" => \$first_row_is_headers, # flag
) or die("Error in command line arguments\r\n");

# set column names for the hash; we'll use @columns more, later.
@columns = split(/,/, join(',', @columns));

# validate that search_field is one of the columns
unless ($search_field ~~ @columns) {
    die "Search parameter: '$search_field' is not one of the columns: @columns";
}

## Merge rows!
my $merger = Text::CSV::Merge->new({
    base    => $base_file,
    merge   => $merge_file,
    output  => $output_file,
    columns => \@columns,
    search  => $search_field,
    first_row_is_headers => $first_row_is_headers
});

$merger->merge();

# $log->info("DBI Conncted to CSV");

# Ensure clean exit, since some shells don't save the command in history
# without it.
exit 0;

