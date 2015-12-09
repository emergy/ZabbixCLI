package host;

use strict;
use warnings;
use Net::Zabbix;
use Data::Dumper;

=encoding utf8

=head1 NAME

host

=head1 SYNOPSIS

    use host;

    my $host_obj = host->new($config);

    my $results = $host_obj->search($query, \%params);

    my $interfaces = $host_obj->get_interfaces($host);

    $host_obj->show_results($results, $verbose);

    my $hosts = $host_obj->get_hosts_by_group($group_id);

    my $groups = $host_obj->get_groups();

=head2 params search

=over 4

B<clean-proto> - Remove protocol from query (s;^(?:https?|ftp)://(.*?)(/|:\d+)?$;$1;)

B<fields> - Fields for search (Default: ["ip", "dns", "name", "host"])

B<regexp> - Use regexport query

B<searchByAny> - If set to true return results that match any of the criteria given in the filter or search parameter instead of all of them. (Default: false)

B<sortfield> - Sort the result by the given properties. Refer to a specific API get method description for a list of properties that can be used for sorting. (Default: "host")

=back

=cut

sub new {
    my ($class, $config) = @_;
    my $self;

    my $zabbix = Net::Zabbix->new(
        $config->{'zabbix-url'},
        $config->{'zabbix-username'},
        $config->{'zabbix-password'},
    );

    $self->{'config'} = $config;
    $self->{'zabbix'} = $zabbix;

    bless $self, $class;
    return $self;
}

sub get_groups {
    my ($self) = @_;
    my $config = $self->{'config'};
    my $zabbix = $self->{'zabbix'};

    return $zabbix->get("hostgroup", {
        output => "extend"
    });
}

sub get_hosts_by_group {
    my ($self, $group_id) = @_;
    my $config = $self->{'config'};
    my $zabbix = $self->{'zabbix'};

    return $zabbix->get("host", {
        #"output" => ["host"],
        #"selectGroups" => "extend",
        groupids => $group_id,
    });
}

sub search {
    my ($self, $raw_query, $params) = @_;
    my $config = $self->{'config'};
    my $zabbix = $self->{'zabbix'};
    my @r;

    foreach my $key (keys %$params) {
        $config->{$key} = $params->{$key};
    }
    
    $config->{'fields'} ||= ["ip", "dns", "name", "host"]; # Default fields

    my $search_opts = {};

    my @query_list = grep { !/^!/ } split(/:/, $raw_query);
    my @black_list = grep { /^!/ } split(/:/, $raw_query);


    foreach my $query (@query_list) {
        if ($config->{'replace-space'}) {
            if ($query =~ /\s/) {
                $query =~ s/\s+/.*/g;
                $config->{'regexp'} = 1;
            }
        }
    
        unless ($config->{'regexp'}) {
            # Aliases
            $query = $config->{alias}->{$query} if $config->{alias}->{$query};
    
            $search_opts->{$_} = $query foreach (@{$config->{'fields'}});
        }
    
        $config->{'sortfield'} ||= "host";
        my $select_inventory;
        my $select_macros;

        if (defined $config->{verbose} && $config->{verbose} == 2) {
            $select_inventory = 'extend';
            $select_macros = 'extend';
        }
    
        my $res = $zabbix->get("host", {
            search      => $search_opts,
            searchByAny => $config->{'searchByAny'},
            sortfield   => $config->{'sortfield'},
            selectInventory => $select_inventory,
            selectMacros => $select_macros,
        });
    
    
    
        if (ref $res->{result} eq 'ARRAY') {
            foreach my $host (@{$res->{result}}) {
                if ($config->{'regexp'}) {
                    my $safe = 0;
    
                    foreach my $field (@{$config->{'fields'}}) {
                        if ($host->{$field}) {

                            if ($host->{$field} =~ /$query/) {
                                foreach my $bl_item (@black_list) {
                                    $bl_item =~ s/^!//;

                                    if ($bl_item) {
                                        $safe = 1 if $host->{$field} !~ /$bl_item/;
                                    }
                                }
                                
                                $safe = 1 if $#black_list < 0;
                            }
                        }
                    }
        
                    next unless $safe;
                }
    
                # Enabled only arg
                if ($config->{'enabled-only'}) {
                    next if $host->{'status'} == 1;
                }
         
                # Disabled only arg
                if ($config->{'disabled-only'}) {
                    next if $host->{'status'} == 0;
                }
    
                print Dumper($host) if $config->{debug};
                push @r, $host;
            }
    
        }
    }

    return \@r;
}

sub get_interfaces {
    my ($self, $host) = @_;
    my $h;

    my $config = $self->{'config'};
    my $zabbix = $self->{'zabbix'};

    my $r = $zabbix->get("hostinterface", {
        hostids => $host->{hostid},
    });

    foreach my $i (@{$r->{result}}) {
        if ($i->{type} eq "1") {
            if ($h->{agent}) {
                if (ref $h->{agent} eq 'ARRAY') {
                    push @{$h->{agent}}, $i;
                } else {
                    my $it = $h->{agent};
                    $h->{agent} = [$it, $i];
                }
            } else {
                $h->{agent} = $i;
            }
        }
        $h->{ipmi} = $i if ($i->{type} eq "3");
    }

    return $h;
}

sub show_results {
    my ($self, $search, $params) = @_;
    $params->{interface} ||= 'agent';

    my @show_list;
    my $max_length = 0;

    # Just show find result
    foreach my $host (@$search) {
        my $interfaces = get_interfaces($self, $host);
 
        if ($params->{verbose}) {
            show_verbose($host, $interfaces);
        } else {
            if ($interfaces->{$params->{interface}}) {
                my $iflist;

                if (ref $interfaces->{$params->{interface}} eq 'ARRAY') {
                    $iflist = join(", ", map {$_ = $_->{ip}} @{$interfaces->{$params->{interface}}}),
                } else {
                    $iflist = $iflist = $interfaces->{$params->{interface}}->{ip};
                }

                my $show_hostname;
                if ($host->{status}) {
                    $show_hostname = "\033[91m" . $host->{host} . "\033[0m";
                } else {
                    $show_hostname = $host->{host};
                }

                push @show_list, {
                    iflist => $iflist,
                    hostname => $show_hostname,
                };

                $max_length = length($iflist) if ($max_length < length($iflist));

            } else {
                print STDERR "Host \"$host->{host}\" $params->{interface} interfaces not exists\n";
            }
        }
    }

    printf "%-$max_length" . "s\t%s\n", $_->{iflist}, $_->{hostname} foreach @show_list;
}

sub show_verbose {
    my ($host, $if) = @_;

    my $show_hostname;
    if ($host->{status}) {
        $show_hostname = "\033[91m" . $host->{host} . "\033[0m";
    } else {
        $show_hostname = $host->{host};
    }

    print "Host: " . $show_hostname . "\n";

    if (($host->{name}) and ($host->{name} ne $host->{host})) {
        print "Description: " . $host->{name} . "\n";
    }

    if ($if->{agent}) {
        print "  Interface agent:\n";
        if (ref $if->{agent} eq 'ARRAY') {
            foreach (@{$if->{agent}}) {
                show_verbose_if($_);
            }
        } else {
            show_verbose_if($if->{agent});
        }
    }

    if ($host->{inventory} && ref $host->{inventory} eq 'HASH') {
        print "  Inventory:\n";
        foreach my $key (keys $host->{inventory}) {
            if (defined $host->{inventory}->{$key} && $host->{inventory}->{$key} ne '') {
                print "    $key: $host->{inventory}->{$key}\n";
            }
        }
        print "\n";
    }

    if ($host->{macros} && ref $host->{macros} eq 'ARRAY') {
        print "  Macros:\n";
        foreach my $macros (@{$host->{macros}}) {
            print "    $macros->{macro}: $macros->{value}\n";
        }
        print "\n";
    }

    if (($if->{ipmi}->{ip}) or ($if->{ipmi}->{dns})) {
        print "  Interface IPMI\n";
        show_verbose_if($if->{ipmi}, $host->{ipmi_username}, $host->{ipmi_password});
    }
    print "----------------------------------------------\n\n";
}

sub show_verbose_if {
    my ($if, $login, $password) = @_;

    print "    IP: " . $if->{ip} . "\n" if $if->{ip};
    print "    DNS: " . $if->{dns} . "\n" if $if->{dns};
    print "    PORT: " . $if->{port} . "\n" if $if->{port};
    print "    LOGIN: " . $login . "\n" if $login;
    print "    PASSWORD: " . $password . "\n" if $password;
    print "\n";
}

1;
