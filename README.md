# NAME

Text::CSV::Merge - Fill in gaps in a CSV file from another CSV file

# VERSION

version 0.04

# SYNOPSIS

    my $merger = Text::CSV::Merge->new({
        base    => 'into.csv',
        merge   => 'from.csv',
        output  => 'output.csv',  # optional
        columns => [q/email name age/],
        search  => 'email',
        first_row_is_headers => 1  # optional
    });

    $merger->merge();
    

    ## Now, there is a new CSV file named 'merged_output.csv' by default, 
    #  in the same directory as the code which called C<$merger->merge();>.

# DESCRIPTION

The use case for this module is when one has two CSV files of largely the same structure. Yet, the 'from.csv' has data which 'into.csv' lacks. 

In this initial release, Text::CSV::Merge only fills in empty cells; it does not overwrite data in 'into.csv' which also exists in 'from.csv'. 

## Subclassing

Text::CSV::Merge may be subclassed. In the subclass, the following attributes may be overridden:

- `csv_parser`
- `dbh`
- `logger`

# ATTRIBUTES

## `logger`

The logger for all operations in this module.

The logger records data gaps in the base CSV file, and records which data from the merge CSV file was used fill the gaps in the base CSV file.

## `csv_parser`

The CSV parser used internally is an immutable class property. 

The internal CSV parser is the XS version of Text::CSV: Text::CSV\_XS. You may use Text::CSV::PP if you wish, but using any other parser which does not duplicate Text::CSV's API will probably not work without modifying the source of this module.

Text::CSV\_XS is also used, hard-coded, as the parser for DBD::CSV. This is configurable, however, and may be made configurable by the end-user in a future release. It can be overridden in a subclass. 

## `dbh`

Create reusable DBI connection to the CSV data to be merged in to base file. 

This method is overridable in a subclass. A good use of this would be to merge data into an existing CSV file from a database, or XML file. It must conform to the DBI's API, however.

DBD::CSV is a base requirement for this module.

## `base_file`

The CSV file into which new data will be merged.

The base file is readonly, not read-write. This prevents accidental trashing of the original data.

## `merge_file`

The CSV file used to find data to merge into `base_file`.

## `output_file`

The output file into which the merge results are written. 

I felt it imperative not to alter the original data files. I may make this a configurable option in the future, but wold likely set its default to 'false'.

## `columns`

The columns to be merged.

A column to be merged must exist in both `base_file` and `merge_file`. Other than that requirement, each file may have other columns which do not exist in the other.

## `search_field`

The column/field to match rows in `merge_file`. 

This column must exist in both files and be identically cased.

## `first_row_is_headers`

1 if the CSV files' first row are its headers; 0 if not. 

If there are no headers, then the column names supplied by the `columns` argument/property are applied to the columns in each file virtually, in numerical orders as they were passed in the list.

# METHODS

## `merge()`

Main method and is public.

`merge()` performs the actual merge of the two CSV files.

## `DEMOLISH()`

This method locally overrides a Moo built-in. 

It close out all file handles, which will only occur after a call to `merge()`.

# SEE ALSO

- [Text::CSV\_XS](http://search.cpan.org/perldoc?Text::CSV\_XS)

# AUTHOR

Michael Gatto <mgatto@lisantra.com>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Michael Gatto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
