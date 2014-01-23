use utf8;
package WGE::Model::Schema::Result::Species;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

WGE::Model::Schema::Result::Species

=cut

use strict;
use warnings;

use Moose;
use MooseX::NonMoose;
use MooseX::MarkAsMethods autoclean => 1;
extends 'DBIx::Class::Core';

=head1 COMPONENTS LOADED

=over 4

=item * L<DBIx::Class::InflateColumn::DateTime>

=back

=cut

__PACKAGE__->load_components("InflateColumn::DateTime");

=head1 TABLE: C<species>

=cut

__PACKAGE__->table("species");

=head1 ACCESSORS

=head2 numerical_id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'species_id_seq'

=head2 id

  data_type: 'text'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "numerical_id",
  {
    data_type         => "integer",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "species_id_seq",
  },
  "id",
  { data_type => "text", is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</numerical_id>

=back

=cut

__PACKAGE__->set_primary_key("numerical_id");

=head1 UNIQUE CONSTRAINTS

=head2 C<unique_species>

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->add_unique_constraint("unique_species", ["id"]);

=head1 RELATIONS

=head2 genes

Type: has_many

Related object: L<WGE::Model::Schema::Result::Gene>

=cut

__PACKAGE__->has_many(
  "genes",
  "WGE::Model::Schema::Result::Gene",
  { "foreign.species_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07022 @ 2014-01-23 10:56:49
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:eghF5HSujUJoyTZ1QuvQPw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
