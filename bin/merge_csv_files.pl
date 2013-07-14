use Modern::Perl '2012';
use IO::File;
use Getopt::Long;
use Text::CSV_XS;
use DBI; # for DBD::CSV
use Log::Dispatch;
use autodie;
use utf8;


## Setup CSV parser
my $csv = Text::CSV_XS->new({ binary => 1, eol => $/ }) or 
    die "Cannot use CSV: " . Text::CSV->error_diag();

    
## Add logging
my $log = Log::Dispatch->new(
    outputs => [
        [ 'File', autoflush => 1, min_level => 'debug', filename => 'merge.log', newline => 1, mode => '>>' ],
        [ 'Screen', min_level => 'info', newline => 1 ],
    ],
);


## Setup Options
my $base_file;
my $merge_file;
my $output_file = 'merge.csv';
my $search_field;
my $first_row_is_headers;
my @columns;

GetOptions(
    "base=s"    => \$base_file,  # string
    "new=s"     => \$merge_file, # string
    "output=s"  => \$output_file, # string
    "columns=s" => \@columns, # list
    "search=s"  => \$search_field, # string
    "first-row-is-headers" => \$first_row_is_headers, # flag
) or die("Error in command line arguments\r\n");


# set column names for the hash; we'll use @columns more, later.
@columns = split(/,/, join(',', @columns));
$csv->column_names( @columns );

# validate that search_field is one of the columns
unless ($search_field ~~ @columns) {
    die "Search parameter: '$search_field' is not one of the columns: @columns";
}


## Open filehandles
#
# Read base file as readonly, not read-write: no trashing of the original!
my $base_fh = IO::File->new( $base_file, '<' ) or die "$base_file: $!";
$base_fh->binmode(":utf8");

# Open new file for output
my $output_fh = IO::File->new( $output_file, '>' ) or die "$output_file: $!";
$output_fh->binmode(":utf8");

## Merge rows!
my @rows;

# create reusable DBI connection to the CSV to be merged in to $base_file
my $dbh = DBI->connect("dbi:CSV:", undef, undef, { 
        RaiseError => 1, 
        PrintError => 1, 
        f_ext => ".csv/r", 
        # Better performance with XS
        csv_class => "Text::CSV_XS", 
        # csv_null => 1, 
        # FetchHashKeyName => "NAME_uc", 
    }) 
    or die "Cannot connect: $DBI::errstr";

$log->info("DBI Conncted to CSV");

# Loop through the base file to find missing data
while ( my $row = $csv->getline_hr( $base_fh ) ) {
    # skip column names
    next if ($. == 1 and $first_row_is_headers);

    if ( $csv->parse($row) ) {
        # keep a list of null column in this row
        my @nulls;

        # might be slightly more efficient to use while()
        foreach my $key ( keys %{$row} ) {
            # which fields is this row missing?
            if ( $row->{$key} eq 'NULL' or $row->{$key} eq "" ) {
                push @nulls, $key;

                $log->info("Missing data: $key for '$row->{$search_field}'");
            }
        }

        # make a hash of arrays
        if ( @nulls  ) {
            # search $to_merge_fh for the missing data's row
            #
            # To get the original case for the columns, specify the column
            # names rather than using SELECT *, since it normalizes to
            # lowercase, per:
            # http://stackoverflow.com/questions/3350775/dbdcsv-returns-header-in-lower-case
            $" = ','; # reset the list separator for array interpolation to suit SQL

            my $sth = $dbh->prepare(
                "select @columns from $merge_file where $search_field = ?"
            ) or die "Cannot prepare: " . $dbh->errstr ();

            $sth->execute($row->{$search_field});
            
            while ( my $filler = $sth->fetchrow_hashref() ) {
                foreach my $item ( @nulls ) {
                    if (exists $filler->{$item} and defined $filler->{$item} and $filler->{$item} ne "") {
                        $log->info(
                            "Found Data: '$item' = '$filler->{$item}' for '$row->{$search_field}'"
                        );

                        $row->{$item} = $filler->{$item};
                    } else {
                        $log->info(
                            "Data not Found: '$item' for '$row->{$search_field}' $merge_file"
                        );
                    }
                }
            }        
            
            # Be efficient and neat!
            $sth->finish();
        }
        
        # insert the updated row as a reference; even if not processed, the 
        # row will still appear in the final output.
        push @rows, $row;

    } else {
        my $err = $csv->error_input;

        $log->error("Failed to parse line: $err");
    }
}

# Ensure we've processed to the end of the file
$csv->eof or $csv->error_diag();

# print does NOT want an actual array! Use a hash slice, instead:
#$csv->print($output_fh, [ @$_{@columns} ]) for @rows;
#
# Or, here I've switched to Text::CSV_XS's specific print_hr(), which 
# is simply missing from the PP (Pure Perl) version.
$csv->print_hr($output_fh, $_) for @rows;


## Clean up!
$base_fh->close();
$output_fh->close() or die "output.csv: $!";

# Ensure clean exit, since some shells don't save the command in history
# without it.
exit 0;

