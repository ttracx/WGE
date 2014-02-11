package WGE::Util::GenomeBrowser;
use strict;
use Data::Dumper;
use TryCatch;
use warnings FATAL => 'all';


=head1 NAME

WGE::Model::Util::GenomeBrowser

=head1 DESCRIPTION

Copied and adapted from LIMS2

=cut

use Sub::Exporter -setup => {
    exports => [ qw(
        get_region_from_params
        fetch_design_data
        crisprs_for_region
        crisprs_to_gff
        crispr_pairs_for_region
        crispr_pairs_to_gff 
        gibson_designs_for_region
        design_oligos_to_gff
    ) ]
};

use Log::Log4perl qw( :easy );

=head2 get_region_from_params

Takes schema and hashref of params (usually from catalyst request) and returns hashref
containing chromosome name and coordinates

Input params can be coordinates etc, WGE design id or exon id

af11

=cut
sub get_region_from_params{
    my $schema = shift;
    my $params = shift;
    
    my @required = qw(genome chromosome browse_start browse_end);
    my @missing_params = grep { not defined $params->{$_ } } @required;

    if (@missing_params){
        if ($params->{'design_id'}){
            # get info for initial display from design oligos...
            my $design_data = fetch_design_data($schema, $params);
    
            my ($start, $end, $chromosome, $genome);
            foreach my $oligo (@{ $design_data->{oligos} || [] }){
                $chromosome ||= $oligo->{locus}->{chr_name};
                $genome   ||= $oligo->{locus}->{assembly};
                my $oligo_start = $oligo->{locus}->{chr_start};
                my $oligo_end = $oligo->{locus}->{chr_end};

                if ($oligo_start > $oligo_end){
                    die "Was not expecting oligo start to be after oligo end";
                }

                if (not defined $start or $start > $oligo_start){
                    $start = $oligo_start;
                }

                if (not defined $end or $end < $oligo_end){
                    $end = $oligo_end;
                }
            }

            return {
                'genome'        => $genome,
                'chromosome'    => $chromosome,
                'browse_start'  => $start,
                'browse_end'    => $end,
                'design_id'     => $design_data->{id},
                'genes'         => $design_data->{assigned_genes},
            };
        }
        elsif (my $exon_id_list = $params->{'exon_id'}){
            # FIXME: crispr search form can have multiple exons selected
            # just use on of these for now
            my ($exon_id) = split ",", $exon_id_list;
            my $exon = $schema->resultset('Exon')->find({ ensembl_exon_id => $exon_id })
                or die "Could not find exon $exon_id in WGE database";

            my $genome = $exon->gene->species->default_assembly->assembly_id;

            return {
                'genes'        => $exon_id,
                'genome'       => $genome,
                'chromosome'   => $exon->chr_name,
                'browse_start' => $exon->chr_start,
                'browse_end'   => $exon->chr_end
            };
        }
    }
    else{
        # All region params provided, we just return them
        my %region = map { $_ => $params->{$_} } @required;
        if ($params->{'genes'}){
            $region{'genes'} = $params->{'genes'};
        }
        return \%region;
    }
    
    die "No region parameters, design_id or exon_id provided";
}

=head fetch_design_data

Takes schema and input params
Attempts to retrieve design_id and returns it as hash

af11

=cut
sub fetch_design_data{
    my ($schema, $params) = @_;

    my $design_id  = $params->{'design_id'};

    my $design;
    try {
        $design = $schema->c_retrieve_design( { id => $design_id } );
    }
    catch( LIMS2::Exception::Validation $e ) {
        die "Please provide a valid design id";
    } 
    catch( LIMS2::Exception::NotFound $e ) {
        die "Design $design_id not found" ;
    }

    my $design_data = $design->as_hash;
    $design_data->{assigned_genes} = join q{, }, @{ $design_data->{assigned_genes} || [] };

    DEBUG( "Design: " .Dumper($design_data) );

    return $design_data;    
}

=head2 crisprs_for_region 

Find crisprs for a specific chromosome region. The search is not design
related. The method accepts species, chromosome id, start and end coordinates.

This method is used by the browser REST api to server data for the genome browser.

dp10
=cut

sub crisprs_for_region {
    my $schema = shift;
    my $params = shift;

    # Chromosome number is looked up in the chromosomes table to get the chromosome_id
    my $species = $schema->resultset('Assembly')->find({ id => $params->{assembly_id} })->species;

    # Store species name for gff output
    $params->{species} = $species->id;

    my $crisprs_rs = $schema->resultset('Crispr')->search(
        {
            'species_id'  => $species->numerical_id,
            'chr_name'    => $params->{chromosome_number} ,
            # need all the crisprs starting with values >= start_coord
            # and whose start values are <= end_coord
            'chr_start'   => { -between => [
                $params->{start_coord},
                $params->{end_coord},
                ],
            },
        },
        {
            columns => [qw/id pam_right chr_start/],
        }
    );

    return $crisprs_rs;
}

=head crispr_pairs_for_region

Identifies pairs within the list of crisprs for the region

=cut

sub crispr_pairs_for_region {
    my $schema = shift;
    my $params = shift;

    my @crisprs = crisprs_for_region($schema, $params)->all;

    # Find pairs amongst crisprs
    my $pair_finder = WGE::Util::FindPairs->new;
    my $pairs = $pair_finder->find_pairs( \@crisprs, \@crisprs );

    return $pairs;
}


=head crisprs_for_region_as_arrayref 

Return and array of hashrefs properly inflated for the browser.
This is suitable for serialisation as JSON.

=cut

sub crisprs_for_region_as_arrayref {
    my $schema = shift;
    my $params = shift;

    my $crisprs_rs = crisprs_for_region( $schema, $params ) ;
    $crisprs_rs->result_class('DBIx::Class::ResultClass::HashRefInflator');
    my @crisprs;

    while ( my $hashref = $crisprs_rs->next ) {
        push @crisprs, $hashref;
    }

    return \@crisprs;
}

sub retrieve_chromosome_id {
    my $schema = shift;
    my $species = shift;
    my $chromosome_number = shift;

    my $chr_id = $schema->resultset('Chromosome')->find( {
            'species_id' => $species,
            'name'       => $chromosome_number,
        }
    );
    return $chr_id->id;
}

=head crisprs_to_gff

Return a reference to an array of strings.
The format of each string is standard GFF3 - that is hard tab separated fields.

=cut

sub crisprs_to_gff {
    my $crisprs_rs = shift;
    my $params = shift;

    my @crisprs_gff;

    push @crisprs_gff, "##gff-version 3";
    push @crisprs_gff, '##sequence-region lims2-region '
        . $params->{'start_coord'}
        . ' '
        . $params->{'end_coord'} ;
    push @crisprs_gff, '# Crisprs for region '
        . $params->{'species'}
        . '('
        . $params->{'assembly_id'}
        . ') '
        . $params->{'chromosome_number'}
        . ':'
        . $params->{'start_coord'}
        . '-'
        . $params->{'end_coord'} ;

        while ( my $crispr_r = $crisprs_rs->next ) {
            my %crispr_format_hash = (
                'seqid' => $params->{'chromosome_number'},
                'source' => 'LIMS2',
                'type' => 'Crispr',
                'start' => $crispr_r->chr_start,
                'end' => $crispr_r->chr_start + 22,
                'score' => '.',
                'strand' => '+' ,
#                'strand' => '.',
                'phase' => '.',
                'attributes' => 'ID='
                    . 'C_' . $crispr_r->id . ';'
                    . 'Name=' . 'LIMS2' . '-' . $crispr_r->id
                );
            my $crispr_parent_datum = prep_gff_datum( \%crispr_format_hash );
            $crispr_format_hash{'type'} = 'CDS';
            $crispr_format_hash{'attributes'} =     'ID='
                    . $crispr_r->id . ';'
                    . 'Parent=C_' . $crispr_r->id . ';'
                    . 'Name=' . 'LIMS2' . '-' . $crispr_r->id . ';'
                    . 'color=#45A825'; # greenish
            my $crispr_child_datum = prep_gff_datum( \%crispr_format_hash );
            push @crisprs_gff, $crispr_parent_datum, $crispr_child_datum ;
        }




    return \@crisprs_gff;
}


=head crispr_pairs_to_gff 
Returns an array representing a set of strings ready for 
concatenation to produce a GFF3 format file.

=cut

sub crispr_pairs_to_gff {
    my $crispr_pairs = shift;
    my $params = shift;

    my @crisprs_gff;

    push @crisprs_gff, "##gff-version 3";
    push @crisprs_gff, '##sequence-region lims2-region '
        . $params->{'start_coord'}
        . ' '
        . $params->{'end_coord'} ;
    push @crisprs_gff, '# Crispr pairs for region '
        . $params->{'species'}
        . '('
        . $params->{'assembly_id'}
        . ') '
        . $params->{'chromosome_number'}
        . ':'
        . $params->{'start_coord'}
        . '-'
        . $params->{'end_coord'} ;

        foreach my $crispr_pair (@{ $crispr_pairs || [] } ) {

            my $right = $crispr_pair->{right_crispr};
            my $left = $crispr_pair->{left_crispr};
            my $id = $left->{id}.":".$right->{id};

            my %crispr_format_hash = (
                'seqid' => $params->{'chromosome_number'},
                'source' => 'LIMS2',
                'type' => 'crispr_pair',
                'start' => $left->{chr_start},
                'end' => $right->{chr_start}+22,
                'score' => '.',
                'strand' => '+' ,
#                'strand' => '.',
                'phase' => '.',
                'attributes' => 'ID='
                    . $id . ';'
                    . 'Name=' . 'LIMS2' . '-' . $id
                );

            my $crispr_pair_parent_datum = prep_gff_datum( \%crispr_format_hash );
            
            $crispr_format_hash{'type'} = 'CDS';
            $crispr_format_hash{'end'} = $left->{chr_start}+22;
            $crispr_format_hash{'attributes'} =     'ID='
                    . $left->{id} . ';'
                    . 'Parent=' . $id . ';'
                    . 'Name=' . 'LIMS2' . '-' . $left->{id} . ';'
                    . 'color=#AA2424'; # reddish
            my $crispr_left_datum = prep_gff_datum( \%crispr_format_hash );

            $crispr_format_hash{'start'} = $right->{chr_start};
            $crispr_format_hash{'end'} = $right->{chr_start}+22;
            $crispr_format_hash{'attributes'} =     'ID='
                    . $right->{id} . ';'
                    . 'Parent=' . $id . ';'
                    . 'Name=' . 'LIMS2' . '-' . $right->{id} . ';'
                    . 'color=#1A8599'; # blueish
#            $crispr_format_hash{'attributes'} = $crispr_r->pair_id;
            my $crispr_right_datum = prep_gff_datum( \%crispr_format_hash );
            
            push @crisprs_gff, $crispr_pair_parent_datum, $crispr_left_datum, $crispr_right_datum ;
        }


    return \@crisprs_gff;
}

=head prep_gff_datum
given: hash ref of key value pairs
returns: ref to array of tab separated values

The gff format requires hard tab separated list of values in specified fields.
=cut

sub prep_gff_datum {
    my $datum_hr = shift;

    my @data;

    push @data, @$datum_hr{qw/
        seqid
        source
        type
        start
        end
        score
        strand
        phase
        attributes
        /};
    my $datum = join "\t", @data;
    return $datum;
}

=head
Similar methods for design retrieval and browsing
=cut

sub gibson_designs_for_region {
    my $schema = shift;
    my $params = shift;

    my $chromosome_id = get_chromosome_id($schema, $params);

    my $oligo_rs = $schema->resultset('GibsonDesignBrowser')->search( {},
        {
            bind => [
                $params->{start_coord},
                $params->{end_coord},
                $chromosome_id,
                $params->{assembly_id},
            ],
        }
    );


    return $oligo_rs;
}

sub design_oligos_to_gff {
    my $oligo_rs = shift;
    my $params = shift;

    my @oligo_gff;

    push @oligo_gff, "##gff-version 3";
    push @oligo_gff, '##sequence-region lims2-region '
        . $params->{'start_coord'}
        . ' '
        . $params->{'end_coord'} ;
    push @oligo_gff, '# Gibson designs for region '
        . $params->{'species'}
        . '('
        . $params->{'assembly_id'}
        . ') '
        . $params->{'chromosome_number'}
        . ':'
        . $params->{'start_coord'}
        . '-'
        . $params->{'end_coord'} ;

        my $gibson_designs; # collects the primers and coordinates for each design. It is a hashref of arrayrefs. 
        $gibson_designs = parse_gibson_designs( $oligo_rs );
        my $design_meta_data;
        $design_meta_data = generate_design_meta_data ( $gibson_designs );
        # The gff parent is generated from the meta data for the design
        # must do this for each design (as there may be several)
        foreach my $design_data ( keys %$design_meta_data ) {
            my %oligo_format_hash = (
                'seqid' => $params->{'chromosome_number'},
                'source' => 'LIMS2',
                'type' =>  $design_meta_data->{$design_data}->{'design_type'},
                'start' => $design_meta_data->{$design_data}->{'design_start'},
                'end' => $design_meta_data->{$design_data}->{'design_end'},
                'score' => '.',
                'strand' => ( $design_meta_data->{$design_data}->{'strand'} eq '-1' ) ? '-' : '+',
                'phase' => '.',
                'attributes' => 'ID='
                    . 'D_' . $design_data . ';'
                    . 'Name=' . 'D_' . $design_data
                );
            my $oligo_parent_datum = prep_gff_datum( \%oligo_format_hash );
            push @oligo_gff, $oligo_parent_datum;

            # process the components of the design
            $oligo_format_hash{'type'} = 'CDS';
            foreach my $oligo ( keys %{$gibson_designs->{$design_data}} ) {
                $oligo_format_hash{'start'} = $gibson_designs->{$design_data}->{$oligo}->{'chr_start'};
                $oligo_format_hash{'end'}   = $gibson_designs->{$design_data}->{$oligo}->{'chr_end'};
                $oligo_format_hash{'strand'} = ( $gibson_designs->{$design_data}->{$oligo}->{'chr_strand'} eq '-1' ) ? '-' : '+';
                $oligo_format_hash{'attributes'} =     'ID='
                    . $oligo . ';'
                    . 'Parent=D_' . $design_data . ';'
                    . 'Name=' . $oligo . ';'
                    . 'color=' . $gibson_designs->{$design_data}->{$oligo}->{'colour'};
                my $oligo_child_datum = prep_gff_datum( \%oligo_format_hash );
                push @oligo_gff, $oligo_child_datum ;
            }
        }




    return \@oligo_gff;
}


=head parse_gibson_designs
Given and GibsonDesignBrowser Resultset.
Returns hashref of hashrefs keyd on design_id
=cut

sub parse_gibson_designs {
    my $gibson_rs = shift;

    my %design_structure;

    # Note that the result set is ordered first by design_id and then by chr_start
    # so we can rely on all the data for one design to be grouped together
    # and within the group for the oligos to be properly ordered,
    # whether they are on the Watson or Crick strands.

    # When the gff format is generated, 3s, 5s, and Es will be coloured in pairs
    # 5F with 5R, EF with ER, 3F with 3R

    while ( my $gibson = $gibson_rs->next ) {
        $design_structure{ $gibson->design_id } ->
            {$gibson->oligo_type_id} = {
                'design_oligo_id' => $gibson->oligo_id,
                'chr_start' => $gibson->chr_start,
                'chr_end' => $gibson->chr_end,
                'chr_strand' => $gibson->chr_strand,
                'colour'     => gibson_colour( $gibson->oligo_type_id ),
                'design_type' => $gibson->design_type_id,
            };
    }

    return \%design_structure;
}

=head generate_design_meta_data
Given a design_structure hashref provided by the parse_gibson_design method
Returns a design_meta_data hashref containing the start and end coordinates for the entire design

=cut

sub generate_design_meta_data {
    my $gibson_designs = shift;

    my %design_meta_data;
    my @design_keys;

    @design_keys = sort keys %$gibson_designs;

    foreach my $design_key ( @design_keys ) {
        if ( $gibson_designs->{$design_key}->{'3F'}->{'chr_strand'} == 1 ) {
            # calculate length of design on the plus strand
            $design_meta_data{ $design_key } = {
                'design_start' => $gibson_designs->{$design_key}->{'5F'}->{'chr_start'},
                'design_end'   => $gibson_designs->{$design_key}->{'3R'}->{'chr_end'},
                'strand'       => $gibson_designs->{$design_key}->{'5F'}->{'chr_strand'},
                'design_type'  => $gibson_designs->{$design_key}->{'5F'}->{'design_type'},
            };

        }
        else {
            # calculate length of design on the minus strand
            $design_meta_data{ $design_key } = {
                'design_start' => $gibson_designs->{$design_key}->{'3R'}->{'chr_start'},
                'design_end'   => $gibson_designs->{$design_key}->{'5F'}->{'chr_end'},
                'strand'       => $gibson_designs->{$design_key}->{'3R'}->{'chr_strand'},
                'design_type'  => $gibson_designs->{$design_key}->{'5F'}->{'design_type'},
            };
        }
    }

    return \%design_meta_data;
}

sub gibson_colour {
    my $oligo_type_id = shift;

    my %colours = (
        '5F' => '#68D310',
        '5R' => '#68D310',
        'EF' => '#589BDD',
        'ER' => '#589BDD',
        '3F' => '#BF249B',
        '3R' => '#BF249B',
    );
    return $colours{ $oligo_type_id };
}

sub get_chromosome_id{
    my ($schema, $params) = @_;

    my ($species, $chr_id);

    $species = $params->{species};

    if(not defined $species){
        my $assembly = $params->{assembly_id}
            or die "no species or assembly provided to get_chromosome_id";
        $species = $schema->resultset('Assembly')->find({ id => $assembly })->species_id
            or die "Could not find assembly $assembly";
        # Add species to params hash for future use
        $params->{species} = $species;
    }
    
    my $chromosome = $schema->resultset('Chromosome')->find({ name => $params->{chromosome_number}, species_id => $species });
    return $chromosome->id;
}
1;