#!/usr/bin/env perl 

=head1 NAME

ansible_invertory.pl - Ansible invertory script

=head1 SYNOPSIS

ansible_invertory.pl --list

=head1 ansible.cfg

Add script path to hostfile key in defaults section

=cut

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
        $config->{'zabbix-url'},
        $config->{'zabbix-username'},
        $config->{'zabbix-password'},
    );
    
    my $hosts_query = $z->get('host', {
        output => 'extend',
        selectGroups => 'extend',
        selectInterfaces => 'extend',
    })->{result};

    my $heap = {};
    
    foreach my $host (@$hosts_query) {
        foreach my $group (@{$host->{groups}}) {
            push @{$heap->{'group_all'}->{hosts}}, $host->{name};
            push @{$heap->{$group->{name}}->{hosts}}, $host->{name};
            #print Dumper($host);exit;

            if ($host->{interfaces}) {
                foreach (@{$host->{interfaces}}) {
                    if ($_->{type} eq "1" and $_->{main} eq "1") {
                        if ($_->{ip} ne '0.0.0.0') {
                            $heap->{'_meta'}->{hostvars}->{$host->{name}}->{ansible_ssh_host} = $_->{ip};
                        }
                    }
                }
            }

            foreach (keys %$config) {
                next unless /^ansible_/;
                $heap->{'_meta'}->{hostvars}->{$host->{name}}->{$_} = $config->{$_};
            }
        }
    }

    print to_json($heap, {pretty => 1});
    exit;
}

sub usage {
    pod2usage({-verbose => 2});
    exit;
}
