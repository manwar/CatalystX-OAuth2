use strictures 1;
use Test::More;
use Test::Exception;
use Plack::Test;
use HTTP::Request::Common;
use CatalystX::Test::MockContext;
use URI;
use Moose::Util;

use lib 't/lib';
use AuthServer;

my $ctl  = AuthServer->controller('OAuth2::Provider');
my $mock = mock_context('AuthServer');

{
  my $c = $mock->( GET '/request' );
  ok( !$c->req->can('oauth2'),
    "doesn't install oauth2 accessors before the dispatch" );
  ok( !Moose::Util::does_role( $c->req, 'Catalyst::OAuth2::Request' ) );
  $c->dispatch;
  is(
    $c->res->body,
    'warning: response_type/client_id invalid or missing',
    'displays warning to resource owner'
  );
  is_deeply( $c->error, [], 'dispatches to request action cleanly' );
  ok( !$c->req->can('oauth2'),
    "doesn't install oauth2 accessors if request isn't valid" );
  ok( !Moose::Util::does_role( $c->req, 'Catalyst::OAuth2::Request' ) );
}

{
  my $uri   = URI->new('/request');
  my $query = {
    response_type => 'code',
    client_id     => 1,
    state         => 'bar',
    redirect_uri  => '/foo'
  };

  $uri->query_form($query);
  my $c = $mock->( GET $uri );
  $c->dispatch;
  is_deeply( $c->error, [], 'dispatches to request action cleanly' );
  is( $c->res->body, undef, q{doesn't produce warning} );
  ok( $c->req->can('oauth2'),
    "installs oauth2 accessors if request is valid" );
  ok( Moose::Util::does_role( $c->req, 'Catalyst::OAuth2::Request' ) );
  my $res    = $c->res;
  my $client = $c->controller->store->find_client(1);
  ok( my $redirect = $c->req->oauth2->next_action_uri( $c->controller, $c ) );
  is( $res->location, $redirect, 'redirects to the correct action' );
  is_deeply( { $redirect->query_form }, { %$query, code => 1 } );
  is( $client->codes,                   1 );
  is( $client->codes->first->as_string, 1 );
  is( $res->status,                     302 );
}

{
  my $uri   = URI->new('/secret/request');
  my $query = {
    response_type => 'code',
    client_id     => 1,
    state         => 'bar',
    redirect_uri  => '/foo',
    access_secret => 'foosecret'
  };

  $uri->query_form($query);
  my $c = $mock->( GET $uri );
  $c->dispatch;
  is_deeply( $c->error, [], 'dispatches to request action cleanly' );
  is( $c->res->body, undef, q{doesn't produce warning} );
  ok( $c->req->can('oauth2'),
    "installs oauth2 accessors if request is valid" );
  ok( Moose::Util::does_role( $c->req, 'Catalyst::OAuth2::Request' ) );
  my $res    = $c->res;
  my $client = $c->controller->store->find_client(1);
  ok( my $redirect = $c->req->oauth2->next_action_uri( $c->controller, $c ) );
  is( $res->location, $redirect, 'redirects to the correct action' );
  delete $query->{access_secret};
  is_deeply( { $redirect->query_form }, { %$query, code => 2 } )
    or diag( Data::Dump::dump( $redirect->query_form ) );
  is( $client->codes, 2 );
  is( ( $client->codes->all )[-1]->as_string, 2 );
  is( $res->status, 302 );
}

done_testing();
