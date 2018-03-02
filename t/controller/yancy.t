
=head1 DESCRIPTION

This test ensures that the main "Yancy" controller works correctly as an
API

=head1 SEE ALSO

L<Yancy::Controller::Yancy>

=cut

use Mojo::Base '-strict';
use Test::More;
use Test::Mojo;
use Mojo::JSON qw( true false );
use FindBin qw( $Bin );
use Mojo::File qw( path );
use lib "".path( $Bin, '..', 'lib' );
use Local::Test qw( init_backend );
use Yancy::Controller::Yancy;

my $collections = {
    blog => {
        required => [ qw( title markdown ) ],
        properties => {
            id => { type => 'integer', readOnly => 1 },
            title => { type => 'string' },
            slug => { type => 'string' },
            markdown => { type => 'string', format => 'markdown', 'x-html-field' => 'html' },
            html => { type => 'string', 'x-hidden' => 1 },
        },
    },
};
my ( $backend_url, $backend, %items ) = init_backend(
    $collections,
    blog => [
        {
            title => 'First Post',
            slug => 'first-post',
            markdown => '# First Post',
            html => '<h1>First Post</h1>',
        },
        {
            title => 'Second Post',
            slug => 'second-post',
            markdown => '# Second Post',
            html => '<h1>Second Post</h1>',
        },
    ],
);

local $ENV{MOJO_HOME} = path( $Bin, '..', 'share' );
my $t = Test::Mojo->new( 'Mojolicious' );
my $CONFIG = {
    backend => $backend_url,
    collections => $collections,
};
$t->app->plugin( 'Yancy' => $CONFIG );

my $r = $t->app->routes;
$r->get( '/error/list/nocollection' )->to( 'yancy#list', template => 'blog_list' );
$r->get( '/error/get/nocollection' )->to( 'yancy#get', template => 'blog_view' );
$r->get( '/error/get/noid' )->to( 'yancy#get', collection => 'blog', template => 'blog_view' );
$r->get( '/error/set/nocollection' )->to( 'yancy#set', template => 'blog_edit' );
$r->get( '/error/delete/nocollection' )->to( 'yancy#delete', template => 'blog_delete' );
$r->get( '/error/delete/noid' )->to( 'yancy#delete', collection => 'blog', template => 'blog_delete' );

$r->any( [ 'GET', 'POST' ] => '/edit/:id' )
    ->to( 'yancy#set', collection => 'blog', template => 'blog_edit' )
    ->name( 'blog.edit' );
$r->any( [ 'GET', 'POST' ] => '/delete/:id' )
    ->to( 'yancy#delete', collection => 'blog', template => 'blog_delete' )
    ->name( 'blog.delete' );
$r->any( [ 'GET', 'POST' ] => '/delete-forward/:id' )
    ->to( 'yancy#delete', collection => 'blog', forward_to => 'blog.list' );
$r->any( [ 'GET', 'POST' ] => '/edit' )
    ->to( 'yancy#set', collection => 'blog', template => 'blog_edit', forward_to => 'blog.view' )
    ->name( 'blog.create' );
$r->get( '/:id/:slug' )
    ->to( 'yancy#get' => collection => 'blog', template => 'blog_view' )
    ->name( 'blog.view' );
$r->get( '/' )
    ->to( 'yancy#list' => collection => 'blog', template => 'blog_list' )
    ->name( 'blog.list' );

subtest 'list' => sub {
    $t->get_ok( '/' )
      ->text_is( 'article:nth-child(1) h1 a', 'First Post' )
      ->or( sub { diag shift->tx->res->dom( 'article:nth-child(1)' )->[0] } )
      ->text_is( 'article:nth-child(2) h1 a', 'Second Post' )
      ->or( sub { diag shift->tx->res->dom( 'article:nth-child(2)' )->[0] } )
      ->element_exists( 'article:nth-child(1) h1 a[href=/1/first-post]' )
      ->or( sub { diag shift->tx->res->dom( 'article:nth-child(1)' )->[0] } )
      ->element_exists( 'article:nth-child(2) h1 a[href=/2/second-post]' )
      ->or( sub { diag shift->tx->res->dom( 'article:nth-child(2)' )->[0] } )
      ;

    $t->get_ok( '/', { Accept => 'application/json' } )
      ->json_is( { rows => $items{blog}, total => 2, offset => 0 } )
      ;

    subtest 'errors' => sub {
        $t->get_ok( '/error/list/nocollection' )
          ->status_is( 500 )
          ->content_like( qr{Collection name not defined in stash} );
    };
};

subtest 'get' => sub {
    $t->get_ok( '/1/first-post' )
      ->text_is( 'article:nth-child(1) h1', 'First Post' )
      ->or( sub { diag shift->tx->res->dom( 'article:nth-child(1)' )->[0] } )
      ;

    $t->get_ok( '/1/first-post', { Accept => 'application/json' } )
      ->json_is( $items{blog}[0] )
      ;

    subtest 'errors' => sub {
        $t->get_ok( '/error/get/nocollection' )
          ->status_is( 500 )
          ->content_like( qr{Collection name not defined in stash} );
        $t->get_ok( '/error/get/noid' )
          ->status_is( 500 )
          ->content_like( qr{ID not defined in stash} );
    };
};

subtest 'set' => sub {

    subtest 'edit existing' => sub {
        $t->get_ok( '/edit/1' )
          ->status_is( 200 )
          ->element_exists( 'form input[name=title]', 'title field exists' )
          ->element_exists( 'form input[name=title][value="First Post"]', 'title field value correct' )
          ->element_exists( 'form input[name=slug]', 'slug field exists' )
          ->element_exists( 'form input[name=slug][value=first-post]', 'slug field value correct' )
          ->element_exists( 'form textarea[name=markdown]', 'markdown field exists' )
          ->text_like( 'form textarea[name=markdown]', qr{\s*\# First Post\s*}, 'markdown field value correct' )
          ->element_exists( 'form textarea[name=html]', 'html field exists' )
          ->text_like( 'form textarea[name=html]', qr{\s*<h1>First Post</h1>\s*}, 'html field value correct' )
          ;

        my %form_data = (
            title => 'Frist Psot',
            slug => 'frist-psot',
            markdown => '# Frist Psot',
            html => '<h1>Frist Psot</h1>',
        );
        $t->post_ok( '/edit/1' => form => \%form_data )
          ->status_is( 200 )
          ->element_exists( 'form input[name=title]', 'title field exists' )
          ->element_exists( 'form input[name=title][value="Frist Psot"]', 'title field value correct' )
          ->element_exists( 'form input[name=slug]', 'slug field exists' )
          ->element_exists( 'form input[name=slug][value=frist-psot]', 'slug field value correct' )
          ->element_exists( 'form textarea[name=markdown]', 'markdown field exists' )
          ->text_like( 'form textarea[name=markdown]', qr{\s*\# Frist Psot\s*}, 'markdown field value correct' )
          ->element_exists( 'form textarea[name=html]', 'html field exists' )
          ->text_like( 'form textarea[name=html]', qr{\s*<h1>Frist Psot</h1>\s*}, 'html field value correct' )
          ;

        my $saved_item = $backend->get( blog => 1 );
        is $saved_item->{title}, 'Frist Psot', 'item title saved correctly';
        is $saved_item->{slug}, 'frist-psot', 'item slug saved correctly';
        is $saved_item->{markdown}, '# Frist Psot', 'item markdown saved correctly';
        is $saved_item->{html}, '<h1>Frist Psot</h1>', 'item html saved correctly';
    };

    subtest 'create new' => sub {
        $t->get_ok( '/edit' )
          ->status_is( 200 )
          ->element_exists( 'form input[name=title]', 'title field exists' )
          ->element_exists( 'form input[name=title][value=]', 'title field value correct' )
          ->element_exists( 'form input[name=slug]', 'slug field exists' )
          ->element_exists( 'form input[name=slug][value=]', 'slug field value correct' )
          ->element_exists( 'form textarea[name=markdown]', 'markdown field exists' )
          ->text_is( 'form textarea[name=markdown]', '', 'markdown field value correct' )
          ->element_exists( 'form textarea[name=html]', 'html field exists' )
          ->text_is( 'form textarea[name=html]', '', 'html field value correct' )
          ;

        my %form_data = (
            title => 'Form Post',
            slug => 'form-post',
            markdown => '# Form Post',
            html => '<h1>Form Post</h1>',
        );
        $t->post_ok( '/edit' => form => \%form_data )
          ->status_is( 302 )
          ->header_like( Location => qr{^/\d+/form-post$}, 'forward_to route correct' )
          ;

        my ( $id ) = $t->tx->res->headers->location =~ m{^/(\d+)};
        my $saved_item = $backend->get( blog => $id );
        is $saved_item->{title}, 'Form Post', 'item title created correctly';
        is $saved_item->{slug}, 'form-post', 'item slug created correctly';
        is $saved_item->{markdown}, '# Form Post', 'item markdown created correctly';
        is $saved_item->{html}, '<h1>Form Post</h1>', 'item html created correctly';
    };

    subtest 'json edit' => sub {
        my %json_data = (
            title => 'First Post',
            slug => 'first-post',
            markdown => '# First Post',
            html => '<h1>First Post</h1>',
        );
        $t->post_ok( '/edit/1' => { Accept => 'application/json' }, form => \%json_data )
          ->status_is( 200 )
          ->json_is( {
            id => 1,
            %json_data,
          } );

        my $saved_item = $backend->get( blog => 1 );
        is $saved_item->{title}, 'First Post', 'item title saved correctly';
        is $saved_item->{slug}, 'first-post', 'item slug saved correctly';
        is $saved_item->{markdown}, '# First Post', 'item markdown saved correctly';
        is $saved_item->{html}, '<h1>First Post</h1>', 'item html saved correctly';
    };

    subtest 'json create' => sub {
        my %json_data = (
            title => 'JSON Post',
            slug => 'json-post',
            markdown => '# JSON Post',
            html => '<h1>JSON Post</h1>',
        );
        $t->post_ok( '/edit' => { Accept => 'application/json' }, form => \%json_data )
          ->status_is( 201 )
          ->json_has( '/id', 'ID is created' )
          ->json_is( '/title' => 'JSON Post', 'returned title is correct' )
          ->json_is( '/slug' => 'json-post', 'returned slug is correct' )
          ->json_is( '/markdown' => '# JSON Post', 'returned markdown is correct' )
          ->json_is( '/html' => '<h1>JSON Post</h1>', 'returned html is correct' )
          ;
        my $id = $t->tx->res->json( '/id' );
        my $saved_item = $backend->get( blog => $id );
        is $saved_item->{title}, 'JSON Post', 'item title saved correctly';
        is $saved_item->{slug}, 'json-post', 'item slug saved correctly';
        is $saved_item->{markdown}, '# JSON Post', 'item markdown saved correctly';
        is $saved_item->{html}, '<h1>JSON Post</h1>', 'item html saved correctly';
    };

    subtest 'errors' => sub {
        $t->get_ok( '/error/set/nocollection' )
          ->status_is( 500 )
          ->content_like( qr{Collection name not defined in stash} );
        $t->get_ok( '/edit/1' => { Accept => 'application/json' } )
          ->status_is( 400 )
          ->json_is( {
            errors => [
                { message => 'GET request for JSON invalid' },
            ],
        } );
        $t->get_ok( '/edit' => { Accept => 'application/json' } )
          ->status_is( 400 )
          ->json_is( {
            errors => [
                { message => 'GET request for JSON invalid' },
            ],
        } );

        $t->post_ok( '/edit/1' => form => {} )
          ->status_is( 400, 'invalid form input gives 400 status' )
          ->text_is( '.errors > li:nth-child(1)', 'Missing property. (/markdown)' )
          ->text_is( '.errors > li:nth-child(2)', 'Missing property. (/title)' )
          ->element_exists( 'form input[name=title]', 'title field exists' )
          ->element_exists( 'form input[name=title][value=]', 'title field value correct' )
          ->element_exists( 'form input[name=slug]', 'slug field exists' )
          ->element_exists( 'form input[name=slug][value=]', 'slug field value correct' )
          ->element_exists( 'form textarea[name=markdown]', 'markdown field exists' )
          ->text_is( 'form textarea[name=markdown]', '', 'markdown field value correct' )
          ->element_exists( 'form textarea[name=html]', 'html field exists' )
          ->text_is( 'form textarea[name=html]', '', 'html field value correct' )
          ;

        $t->post_ok( '/edit' => form => {} )
          ->status_is( 400, 'invalid form input gives 400 status' )
          ->text_is( '.errors > li:nth-child(1)', 'Missing property. (/markdown)' )
          ->text_is( '.errors > li:nth-child(2)', 'Missing property. (/title)' )
          ->element_exists( 'form input[name=title]', 'title field exists' )
          ->element_exists( 'form input[name=title][value=]', 'title field value correct' )
          ->element_exists( 'form input[name=slug]', 'slug field exists' )
          ->element_exists( 'form input[name=slug][value=]', 'slug field value correct' )
          ->element_exists( 'form textarea[name=markdown]', 'markdown field exists' )
          ->text_is( 'form textarea[name=markdown]', '', 'markdown field value correct' )
          ->element_exists( 'form textarea[name=html]', 'html field exists' )
          ->text_is( 'form textarea[name=html]', '', 'html field value correct' )
          ;
    };
};

subtest 'delete' => sub {
    $t->get_ok( '/delete/1' )
      ->status_is( 200 )
      ->text_is( p => 'Are you sure?' )
      ->element_exists( 'input[type=submit]', 'submit button exists' )
      ;

    $t->post_ok( '/delete/1' )
      ->status_is( 200 )
      ->text_is( p => 'Item deleted' )
      ;

    ok !$backend->get( blog => 1 ), 'item is deleted';

    $t->post_ok( '/delete-forward/2' )
      ->status_is( 302, 'forward_to sends redirect' )
      ->header_is( Location => '/', 'forward_to correctly forwards' )
      ;

    ok !$backend->get( blog => 2 ), 'item is deleted with forwarding';

    my $json_item = $backend->list( blog => {}, { limit => 1 } )->{rows}[0];
    $t->post_ok( '/delete/' . $json_item->{id}, { Accept => 'application/json' } )
      ->status_is( 204 )
      ;
    ok !$backend->get( blog => $json_item->{id} ), 'item is deleted via json';

    subtest 'errors' => sub {
        $t->get_ok( '/error/delete/nocollection' )
          ->status_is( 500 )
          ->content_like( qr{Collection name not defined in stash} );
        $t->get_ok( '/error/delete/noid' )
          ->status_is( 500 )
          ->content_like( qr{ID not defined in stash} );
        $t->get_ok( '/delete/1' => { Accept => 'application/json' } )
          ->status_is( 400 )
          ->json_is( {
            errors => [
                { message => 'GET request for JSON invalid' },
            ],
        } );
    };
};

done_testing;