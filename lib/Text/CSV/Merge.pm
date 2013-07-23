package Text::CSV::Merge;
# ABSTRACT: Merge two CSV files into a new, third CSV file.

use Modern::Perl '2010';
use Moo 1.001000;
use IO::File;
use Text::CSV_XS;
use DBI; # for DBD::CSV
use Log::Dispatch;
use autodie;
use utf8;

=head1 NAME
Text::CSV::Merge - Merge two CSV files

=head1 SYNOPSIS

=head1 DESCRIPTION

=head2 Subclassing
c<Merge> may be subclassed. In the subclass, the following properties may be overridden:

=for :list
* LC<csv_parser>
* LC<dbh>

=cut

=method
The CSV parser used internally is an immutable class property. It can be overridden in a subclass. 

The internal CSV parser is the XS version of Text::CSV: Text::CSV_XS. You may use Text::CSV::PP if you wish, but using any other parser which does not duplicate Text::CSV's API will probably not work without modifying the source of this module.

Text::CSV_XS is also used, hard-coded, as the parser for DBD::CSV. This is configurable, however, and may be made configurable by the end-user in a future release.
=cut
has +csv_parser => (
    is => 'lazy',
    builder => sub {
        Text::CSV_XS->new({ binary => 1, eol => $/ })
            or die "Cannot use CSV: " . Text::CSV_XS->error_diag();
    }
);

=method
Create reusable DBI connection to the CSV data to be merged in to base file. 

This method is overridable in a subclass. A good use of this would be to merge data into an existing CSV file from a database, or XML file. It must conform to the DBI's API, however.

DBD::CSV is a base requirement for this module.
=cut
has +dbh => (
    is => 'lazy',
    # must return only a code ref
    builder => sub {    
        DBI->connect("dbi:CSV:", undef, undef, { 
            RaiseError => 1, 
            PrintError => 1, 
            f_ext => ".csv/r", 
            # Better performance with XS
            csv_class => "Text::CSV_XS", 
            # csv_null => 1, 
        }) or die "Cannot connect: $DBI::errstr";
    }
);

=method
The CSV file into which new data will be merged.

The base file is readonly, not read-write. This prevents accidental trashing of the original data.
=cut
has base_file => (
    is => 'rw',
    required => 1,
    #allow external names to be different from class attribute
    init_arg => 'base',
    #validate it
    #isa => sub {},
    coerce => sub {
        my $base_fh = IO::File->new( $_[0], '<' ) or die "$_[0]: $!";
        $base_fh->binmode(":utf8");
        
        return $base_fh;
    }
);

=method
The CSV file used to find data to merge into C<base_file>.
=cut
# We use only the raw file name/path and do not create a FH here, unlike base_file().
has merge_file => (
    is => 'rw',
    init_arg => 'merge',
    required => 1
);

=method
The output file into which the merge results are written. I felt it imperative not to alter the original data files. I may make this a configurable option in the future, but wold likely set its default to 'false'.
=cut
has output_file => (
    is => 'rw',
    init_arg => 'output',
    # an output file name is NOT required
    required => 0,
    default => 'merged_output.csv',
    coerce => sub {
        my $output_fh = IO::File->new( $_[0], '>' ) or die "$_[0]: $!";
        $output_fh->binmode(":utf8");
        
        return $output_fh;
    }
);

=method 
The columns to be merged.

A column to be merged must exist in both C<base_file> and C<merge_file>. Other than that requirement, each file may have other columns which do not exist in the other.
=cut
has columns=> (
    is => 'rw',
    required => 1,
);    

=method 
The column/field to match rows in C<merge_file>. This column must exist in both files and be identially cased.
=cut
has search_field => (
    is => 'rw',
    required => 1,
    init_arg => 'search'
);

=method

=cut
has first_row_is_headers => (
    is => 'rw',
    required => 1,
    #validate it
    isa => sub {
        # @TODO: there's got to be a better way to do this!
        die "Must be 1 or 0" unless $_[0] =~ /'1'|'0'/ || $_[0] == 1 || $_[0] == 0;
    },
);

=method

=cut
sub BUILD {
    my $self = shift;

    use Data::Dumper;
    print Dumper($self->dbh, $self->base_file, $self->output_file);
    #die;  
}


=method 
C<merge> is the main method and is public.
=cut
sub merge {
    my $self = shift;
    
    $self->csv_parser->column_names( $self->columns );
        
    # Loop through the base file to find missing data
    #@TODO: make into $self->rows?
    my @rows;
    
    while ( my $row = $self->csv_parser->getline_hr( $self->base_file ) ) {
        # skip column names
        next if ($. == 1 and $self->first_row_is_headers);

        if ( $self->csv_parser->parse($row) ) {
            # keep a list of null columns in this row
            my @nulls;

            # might be slightly more efficient to use while()
            foreach my $key ( keys %{$row} ) {
                # which fields is this row missing?
                if ( $row->{$key} eq 'NULL' or $row->{$key} eq "" ) {
                    push @nulls, $key;

                    #$log->info("Missing data: $key for '$row->{$self->search_field}'");
                }
            }

            # make a hash of arrays
            if ( @nulls  ) {
                # search $merge_file for the missing data's row
                #
                # To get the original case for the columns, specify the column
                # names rather than using SELECT *, since it normalizes to
                # lowercase, per:
                # http://stackoverflow.com/questions/3350775/dbdcsv-returns-header-in-lower-case
                $" = ','; # reset the list separator for array interpolation to suit SQL

                my $sth = $self->dbh->prepare(
                    "select @{$self->columns} from $self->{merge_file} where $self->{search_field} = ?"
                ) or die "Cannot prepare: " . $self->dbh->errstr ();

                $sth->execute($row->{$self->search_field});
                
                while ( my $filler = $sth->fetchrow_hashref() ) {
                    foreach my $item ( @nulls ) {
                        if (exists $filler->{$item} and defined $filler->{$item} and $filler->{$item} ne "") {
                            #$log->info(
                            #    "Found Data: '$item' = '$filler->{$item}' for '$row->{$self->search_field}'"
                            #);
                            $row->{$item} = $filler->{$item};
                        } else {
                            #$log->info(
                            #    "Data not Found: '$item' for '$row->{$search_field}' $merge_file"
                            #);
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
            my $err = $self->csv_parser->error_input;
            #$log->error("Failed to parse line: $err");
        }
    }

    # Ensure we've processed to the end of the file
    $self->csv_parser->eof or $self->csv_parser->error_diag();

    # print does NOT want an actual array! Use a hash slice, instead:
    #$self->csv_parser->print($output_fh, [ @$_{@columns} ]) for @rows;
    #
    # Or, here I've switched to Text::CSV_XS's specific print_hr(), which 
    # is simply missing from the PP (Pure Perl) version.
    $self->csv_parser->print_hr($self->output_file, $_) for @rows;
};

=method
This method locally overrides a Moo built-in. I close out all file handles here, which will only occur after a call to C<merge()>.
=cut
sub DEMOLISH {
    my $self = shift;

    ## Clean up!
    $self->base_file->close();
    $self->output_file->close() or die "output.csv: $!";
}

=head1 SEE ALSO

=for :list
* L<Text::CSV_XS>
=cut

1;
