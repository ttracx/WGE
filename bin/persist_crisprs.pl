#!/usr/bin/perl

use strict;
use warnings;

use Pod::Usage;
use Getopt::Long;

use DBI;
use Data::Dumper;
use YAML::Any qw( LoadFile );
use Try::Tiny;
use Log::Log4perl qw( :easy );
use WGE::Util::PersistCrisprs;

#
# TODO: 
    #test this and its associated module actually work.
    #update the Pod
#

#techncially these should be in caps as they're global
my ( $crispr_yaml_file, $bed_file, $species );
my ( $db_cutoff, $log_level, $commit ) = ( 5000, $DEBUG, 0 );
GetOptions(
    "help"               => sub { pod2usage( 1 ) },
    "man"                => sub { pod2usage( 2 ) },
    "trace"              => sub { $log_level = $TRACE },
    "quiet"              => sub { $log_level = $WARN },
    "species=s"          => sub { my ( $name, $val ) = @_; $species = ucfirst(lc $val); },
    "crispr-yaml-file=s" => \$crispr_yaml_file,
    "bed-file=s"         => \$bed_file,
    "max-offs=i"         => \$db_cutoff,
    "commit!"            => \$commit, #default is to NOT commit anything.
) or die pod2usage( 2 );

die pod2usage( 2 ) unless $species and $crispr_yaml_file and $bed_file;

Log::Log4perl->easy_init( $log_level );

INFO "Maximum allowed off targets is $db_cutoff";
INFO "Note: not committing data (dry run)" unless $commit;

die "Commit is: $commit";

#remove this later obviously
$ENV{WGE_REST_CLIENT_CONFIG} ||= '/nfs/team87/farm3_lims2_vms/conf/wge-live-rest-client.conf';

my $p = WGE::Util::PersistCrisprs->new_with_config( 
    species          => $species,
    bed_file         => $bed_file,
    crispr_yaml_file => $crispr_yaml_file,
    max_offs         => $db_cutoff,
    dry_run          => !$commit, #dry run is the opposite of commit. duh
);

$p->execute;

1;

__END__

=head1 NAME

persist_wge.pl - add off target information to crisprs in wge

=head1 SYNOPSIS

persist_wge.pl [options]

    --species            mouse or human
    --bed-file           bed file containing *valid* off targets
    --crispr-yaml-file   crispr yaml file linking seq names from the bed file to db ids
    --commit             whether or not to persist. default is false. [optional]
    --max-offs           the maximum number of off targets per crispr, default is 5000 [optional]
    --help               show this dialog
    --quiet              reduce logging
    --trace              more logging

Example usage:

persist_crisprs.pl --species human --crispr-yaml-file crisprs.yaml --bed-file CBX1_5.valid.subsection.bed --commit
persist_crisprs.pl --species human --crispr-yaml-file crisprs.yaml --bed-file CBX1_5.valid.subsection.bed --max-offs 5000

=head1 DESCRIPTION

All sites within the off target are grouped by crispr, and if the the number
of off-targets for a crispr doesn't exceed max-offs _every_ off target will be persisted,
as well as a summary string.
If there are more than max-offs only the summary will be persisted for that crispr.

The database works best with the total number of off targets in the bed file being under 200k

=head AUTHOR

Alex Hodgkins

=cut