use 5.006;
use strict;
use warnings FATAL => 'all';
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Net::SMTP::Bulk',
    license             => 'Perl_5',
    dist_author         => q{KnowZero},
    dist_version_from   => 'lib/Net/SMTP/Bulk.pm',
    release_status      => 'stable',
    configure_requires => {
        'Module::Build' => 0,
    },
    build_requires => {
        'Test::More' => 0,
    },
    requires => {
        'AnyEvent'              => 0,
        'Encode'              => 0,
    },
    recommends => {
        'Coro'              => 0,
        'IO::Socket::SSL'              => 0,
        'Authen::SASL'              => 0,
        'MIME::Base64'              => 0,
    },
    add_to_cleanup     => [ 'Net-SMTP-Bulk-*' ],
    create_readme => 1,
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
