#!/usr/bin/env perl 

use strict;
use warnings;
use Data::Dumper;
use FindBin '$RealBin';
use lib "$RealBin/../lib";
use Net::Zabbix;
use config;
use Getopt::Long;
use Pod::Usage;
use JSON;

my $config = config->new("$RealBin/../etc/config");

Getopt::Long::Configure ("bundling");
GetOptions(
    "help|h|?" => sub { usage() },
    "list" => sub { list() },
    "host" => sub { print "{}\n" },
);

usage();

sub list {
    my $z = Net::Zabbix->new(
        $config->{'server'},
        $config->{'username'},
        $config->{'password'},
    );
    
    my $hosts_query = $z->get('host', {
        output => 'extend',
        selectGroups => 'extend',
    })->{result};

    my $heap = {};
    
    foreach my $host (@$hosts_query) {
        foreach my $group (@{$host->{groups}}) {
            push @{$heap->{'group_all'}->{hosts}}, $host->{name};
            push @{$heap->{$group->{name}}->{hosts}}, $host->{name};
            $heap->{'_meta'}->{hostvars}->{ $host->{name} } = {
                ansible_connection => 'ssh',
                ansible_ssh_user => 'root',
                ansible_ssh_private_key_file => '~/.ssh/b',
                ansible_python_interpreter => 'python',
            };
        }
    }

#     push @{$heap->{'_meta'}} = {
#         hostvars => {},
#     };

    print to_json($heap, {pretty => 1});
}

sub usage {
    pod2usage(1);
    exit;
}
