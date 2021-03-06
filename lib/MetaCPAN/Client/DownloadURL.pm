use strict;
use warnings;
package MetaCPAN::Client::DownloadURL;
# ABSTRACT: A Download URL data object

use Moo;

with 'MetaCPAN::Client::Role::Entity';

my %known_fields = (
    scalar   => [qw< date download_url status version >],
    arrayref => [],
    hashref  => [],
);

my @known_fields =
    map { @{ $known_fields{$_} } } qw< scalar arrayref hashref >;

foreach my $field (@known_fields) {
    has $field => (
        is      => 'ro',
        lazy    => 1,
        default => sub {
            my $self = shift;
            return $self->data->{$field};
        },
    );
}

sub _known_fields { return \%known_fields }

1;

__END__

=head1 SYNOPSIS

my $download_url = $mcpan->download_url('Moose');

=head1 DESCRIPTION

A MetaCPAN download_url entiry object.

Supported for MetaCPAN v1 only.

=head1 ATTRIBUTES

=head2 date

=head2 download_url

=head2 status

=head2 version
