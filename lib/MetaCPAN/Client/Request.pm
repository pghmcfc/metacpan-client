use strict;
use warnings;
package MetaCPAN::Client::Request;
# ABSTRACT: Object used for making requests to MetaCPAN

use Moo;
use Carp;
use JSON;
use Search::Elasticsearch;
use Search::Elasticsearch::Scroll;
use Try::Tiny;
use HTTP::Tiny;

has domain => (
    is      => 'ro',
    default => sub {'api.metacpan.org'},
);

has version => (
    is      => 'ro',
    default => sub { 'v0' },
);

has base_url => (
    is      => 'ro',
    lazy    => 1,
    default => sub {
        my $self = shift;
        return sprintf('http://%s/%s', $self->domain, $self->version);
    },
);

has ua => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build_ua',
);

has ua_args => (
    is      => 'ro',
    default => sub {
        [ agent => 'MetaCPAN::Client/'.($MetaCPAN::Client::VERSION||'xx') ]
    },
);

sub _build_ua {
    my $self = shift;
    return HTTP::Tiny->new( @{ $self->ua_args } );
}

sub fetch {
    my $self    = shift;
    my $url     = shift or croak 'fetch must be called with a URL parameter';
    my $params  = shift || {};
    my $req_url = sprintf '%s/%s', $self->base_url, $url;
    my $ua      = $self->ua;

    my $result  = keys %{$params}
        ? $ua->post( $req_url, { content => to_json $params } )
        : $ua->get($req_url);

    return $self->_decode_result( $result, $req_url );
}

sub ssearch {
    my $self   = shift;
    my $type   = shift;
    my $args   = shift;
    my $params = shift;

    my $es = Search::Elasticsearch->new(
        nodes            => $self->domain,
        cxn_pool         => 'Static::NoPing',
        send_get_body_as => 'POST',
    );

    my $scroller = Search::Elasticsearch::Scroll->new(
        es          => $es,
        search_type => 'scan',
        scroll      => '5m',
        index       => $self->version,
        type        => $type,
        size        => 1000,
        body        => $self->_build_body($args),
        %{ $params },
    );

    return $scroller;
}

sub _decode_result {
    my $self   = shift;
    my $result = shift;
    my $url    = shift or croak 'Second argument of a URL must be provided';

    ref $result eq 'HASH'
        or croak 'First argument must be hashref';

    my $success = $result->{'success'};

    defined $success
        or croak 'Missing success in return value';

    $success
        or croak "Failed to fetch '$url': " . $result->{'reason'};

    my $content = $result->{'content'}
        or croak 'Missing content in return value';

    my $decoded_result;
    try   { $decoded_result = decode_json $content }
    catch { croak "Couldn't decode '$content': $_" };

    return $decoded_result;
}

sub _build_body {
    my $self  = shift;
    my $args  = shift;

    my $query = _build_body_rec($args);

    return +{ query => $query };
}

sub _build_body_rec {
    my $args  = shift;

    my %query = ();

    my $key = _read_query_key($args);

    if ( $key eq 'all' or $key eq 'either' ) {
        my @elements = map +( _build_body_rec($_) ), @{ $args->{$key} };

        $query{'bool'} = $key eq 'all'
            ? { must   => \@elements }
            : { should => \@elements, "minimum_should_match" => 1 };
    } else {
        %query = %{ _build_query_element($args) };
    }

    return \%query;
}

sub _build_query_element {
    my $args = shift;

    scalar keys %{$args} == 1
        or croak 'Wrong number of keys in query element';

    my ($key) = keys %{$args};

    ! ref( $args->{$key} ) and $args->{$key} =~ /\w/
        or croak 'Wrong type of query arguments';

    my $wildcard = $args->{$key} =~ /[*?]/;
    my $qtype    = $wildcard ? 'wildcard' : 'term';

    return +{ $qtype => $args };
}

sub _read_query_key {
    my $args = shift;

    # search queries take a 1 key/value element hash
    scalar keys %{$args} == 1
        or croak 'Wrong number of query arguments';

    my ($key) = keys %{$args};

    # all/either queries take an array as params
    if ( $key eq 'all' or $key eq 'either' ) {
        ref( $args->{$key} ) eq 'ARRAY'
            or croak 'Wrong type of query arguments for all/either';
    }

    return $key;
}


1;

__END__

=head1 ATTRIBUTES

=head2 domain

    $mcpan = MetaCPAN::Client->new( domain => 'localhost' );

What domain to use for all requests.

Default: B<api.metacpan.org>.

=head2 version

    $mcpan = MetaCPAN::Client->new( version => 'v0' );

What version of MetaCPAN should be used?

Default: B<v0>.

=head2 base_url

    my $mcpan = MetaCPAN::Client->new(
        base_url => 'http://localhost:9999/v2',
    );

Instead of overriding the C<base_url>, you should override the C<domain> and
C<version>. The C<base_url> will be set appropriately automatically.

Default: I<http://$domain/$version>.

=head2 ua

    my $mcpan = MetaCPAN::Client->new( ua => HTTP::Tiny->new(...) );

The user agent object for running requests.

It must provide an interface that matches L<HTTP::Tiny>. Explicitly:

=over 4

=item * Implement post()

Method C<post> must be available that accepts a request URL and a hashref of
options.

=item * Implement get()

Method C<get> must be available that accepts a request URL.

=item * Return result hashref

Must return a result hashref which has key C<success> and key C<content>.

=back

Default: L<HTTP::Tiny>,

=head2 ua_args

    my $mcpan = MetaCPAN::Client->new(
        ua_args => [ agent => 'MyAgent' ],
    );

Arguments sent to the user agent.

Default: user agent string: B<MetaCPAN::Client/$version>.

=head1 METHODS

=head2 fetch

    my $result = $mcpan->fetch('/release/Moose');

    # with parameters
    my $more = $mcpan->fetch(
        '/release/Moose',
        { param => 'value' },
    );

Fetches a path from MetaCPAN (post or get), and returns the decoded result.

=head2 ssearch

Calls an Elastic Search query (using L<Search::Elasticsearch> and returns an
L<Search::Elasticsearch::Scroll> scroller object.

