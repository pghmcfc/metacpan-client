

# examples/author.pl

use strict;
use warnings;
use Data::Printer;
use MetaCPAN::Client;

my $author =
    MetaCPAN::Client->new( version => 'v1' )->author('XSAWYERX');

my %output = (
    NAME    => $author->name,
    EMAILS  => $author->email,
    COUNTRY => $author->country,
    CITY    => $author->city,
    PROFILE => $author->profile,
    LINKS   => $author->links,
    RELEASE_COUNTS => $author->release_count,
);

p %output;
