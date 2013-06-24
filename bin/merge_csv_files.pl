use Modern::Perl '2012';
use IO::File;
use Getopt::Long;
use Text::CSV_XS;
use DBI;
use Log::Dispatch;
use autodie;
use utf8;


# Setup CSV parser
my $csv = Text::CSV_XS->new({ binary => 1, eol => $/ }) or
    die "Cannot use CSV: " . Text::CSV->error_diag();

# Add logging
my $log = Log::Dispatch->new(
    outputs => [
        [ 'File', autoflush => 1, min_level => 'debug', filename => 'merge.log', newline => 1, mode => '>' ],
        [ 'Screen', min_level => 'warning', newline => 1 ],
    ],
);


# Validate Options
my $base_file;
my $merge_file;
my $output_file = 'merged.csv';
GetOptions(
    "base=s"   => \$base_file,  # string
    "new=s"    => \$merge_file, # string
    "output=s" => \$output_file # string
) or die("Error in command line arguments\r\n");


# Read base file as readonly, not read-write: no trashing of the original!
my $base_fh = IO::File->new( $base_file, '<' ) or die "$base_file: $!";

# Open new file for output
my $output_fh = IO::File->new( $output_file, '>' ) or die "$output_file: $!";

# set column names for the hash; we'll use @columns more, later.
my @columns =  qw/ Email Name Gender Ethnicity State Country Institution
Department Position ResearchArea /;
$csv->column_names( @columns );


### Merge rows!
my @rows;

# create reusable DBI connection to the CSV to be merged in to $base_file
my $dbh = DBI->connect("dbi:CSV:", undef, undef, {
        RaiseError => 1,
        PrintError => 1,
        f_ext => ".csv/r",
        csv_class => "Text::CSV_XS",
        FetchHashKeyName => "NAME_lc",
    })
    or die "Cannot connect: $DBI::errstr";


while ( my $row = $csv->getline_hr( $base_fh ) ) {
    # skip column names
    next if ($. == 1);

    if ( $csv->parse($row) ) {

        # keep a list of null field names
        my @nulls;

        # might be slightly more efficient by using while()
        foreach my $key ( keys %{$row} ) {
            # which fields is this row missing?
            if ( $row->{$key} eq 'NULL' ) {
                push @nulls, $key;
            }
        }

        # make a hash of arrays
        if ( @nulls  ) {
            # search $to_merge_fh for the missing data's row
            my $sth = $dbh->prepare("select * from $merge_file where Email = ?")
                or die "Cannot prepare: " . $dbh->errstr ();

            $sth->execute($row->{'Email'});

            while ( my $filler = $sth->fetchrow_hashref() ) {
                # log if data found
                foreach my $item ( @nulls ) {
                    # why are the $filler keys all lowercased??
                    $item = lc $item;

                    if ( exists $filler->{$item} and defined $filler->{$item} and $filler->{$item} ne '' ) {
                        # Log it for future use...
                        $log->info("Found Data: '$item' = '$filler->{$item}' for '$row->{'Email'}'");

                        # insert found data back into row hash!
                        $row->{ucfirst($item)} = $filler->{$item};
                    } else {
                        # say "Missing Data: '$item' for '$row->{'Email'}' not found in $merge_file";
                    }
                }
            }

            $sth->finish();
        }

        push @rows, $row;

    } else {
        my $err = $csv->error_input;
        $log->error("Failed to parse line: $err");
    }
}
# Ensure we've processed to the end of the file
$csv->eof or $csv->error_diag();

# print does NOT want an actual array! Use a hash slice, instead:
#  [ @$_{@columns} ]) for @rows;
# Or, here I've converted to Text::CSV_XS's specific print_hr(), which oddly
# is simply missing from the PP (Pure Perl) version.
$csv->print_hr($output_fh, $_ ) for @rows;


# clean up!
$base_fh->close();
$output_fh->close() or die "output.csv: $!";

