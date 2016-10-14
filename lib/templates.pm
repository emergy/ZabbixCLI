package templates;

use strict;
use warnings;
use Net::Zabbix;
use Data::Dumper;

=head1 NAME

templates

=head1 SYNOPSIS

use templates;

my $t = templates->new();

=over

=cut


sub new {
    my ($class, $config) = @_;
    my $self;

    my $zabbix = Net::Zabbix->new(
        $config->{'zabbix-url'},
        $config->{'zabbix-username'},
        $config->{'zabbix-password'},
        $config->{debug},
    );

    $self->{'config'} = $config;
    $self->{'zabbix'} = $zabbix;

    bless $self, $class;
    return $self;
}

=item clear_templates($search, [$template_name])

Clear template(s) for hosts

=cut

sub clear_templates {
    my ($self, $search, $template_name, $clear_templates, $clear_items) = @_;
    my (@clear_list);
    my ($clear_dict);

    my $z = $self->{'zabbix'};

    foreach my $host (@$search) {
        if ($clear_templates) {
            my $templates = $z->get("template", {
                extendoutput => 1,
                hostids => [ $host->{hostid} ],
            });

            foreach my $template (@{$templates->{result}}) {
                if ($template_name) {
                    next if $template_name ne $template->{name};
                }
                
                $clear_dict->{$host->{hostid}}->{name} = $host->{host};
                push @{$clear_dict->{$host->{hostid}}->{templates}}, {
                    id => $template->{templateid},
                    name => $template->{host},
                };
            }
        }

        if ($clear_items) {
            my $items_obj = $z->get("item", {
                extendoutput => 1,
                hostids => [ $host->{hostid} ],
            });

            foreach my $item (@{$items_obj->{result}}) {
                $clear_dict->{$host->{hostid}}->{name} = $host->{host};
                push @{$clear_dict->{$host->{hostid}}->{items}}, {
                    id => $item->{itemid},
                    name => $item->{name},
                };
            }
        }

    }

    if ($clear_dict) {
        while (my ($host_id, $host) = each %$clear_dict) {
            print $host->{name} . "\n";

            if ($host->{templates}) {
                print "\tTemplates:\n";

                foreach my $template (@{$host->{templates}}) {
                    print "\t\t$template->{name}\n";
                }
            }

            if ($host->{items}) {
                print "\tItems:\n";

                foreach my $item (@{$host->{items}}) {
                    print "\t\t$item->{name}\n";
                }
            }

            print "\n";
        }

        print "Unlink this hosts [y/n]: ";
        chomp(my $qa = readline(*STDIN));

        while (my ($host_id, $host) = each %$clear_dict) {
            my @templates_clear;
            foreach my $template (@{$host->{templates}}) {
                push @templates_clear, {
                    templateid => $template->{id},
                };
            }

            my $host_cear_templates = $z->update("host", {
                hostid => $host_id,
                templates_clear => \@templates_clear,
            });

            if ($host_cear_templates->{error}) {
                print "Error: unlink template from $host->{name}: $host_cear_templates->{error}->{message}\n";
                print "$host_cear_templates->{error}->{data}\n\n";
            }

            my @items_clear;
            foreach my $item (@{$host->{items}}) {
                push @items_clear, $item->{id};
            }

            my $item_delete_obj = $z->delete("item", \@items_clear);
            
            if ($item_delete_obj->{error}) {
                print Dumper($item_delete_obj->{error});
            }
        }
    }
}

=item get_template_ids_by_name($template_name, $search)

Get list template id's by name
    $search - bollean
    1) search
    2) filter

=cut

sub get_template_ids_by_name {
    my ($self, $template_name, $search) = @_;
    my @list;
    
    my $z = $self->{'zabbix'};

    my $opts;

    if ($search) {
        $opts = {
            search => {
                 name => $template_name,
            },
        }
    } else {
        $opts = {
            filter => {
                name => $template_name,
            },
        }
    }

    my $get_template = $z->get("template", $opts);


    foreach (@{$get_template->{result}}) {
        push @list, {
            $_->{templateid} => $_->{name},
        };
    }

    return \@list;
}

=item link_template($host_id, $template_id)

Link template to host(s)

=cut

sub link_template {
    my ($self, $host_id, $template_id) = @_;
    my $z = $self->{'zabbix'};

    my $link_to_template = $z->raw_request("template", "massadd", {
        'templates' => [{ templateid => $template_id }],
        'hosts' => [$host_id],
    });

    if ($link_to_template->{error}) {
        print $link_to_template->{error}->{message} . "\n";
        print "\t" . $link_to_template->{error}->{data} . "\n";
    } else {
        print "OK\n";
    }
}

=item change_status($search, $status);

Change monitoring status for hosts

=cut

sub change_status {
    my ($self, $search, $status) = @_;
    my $z = $self->{'zabbix'};

    foreach my $host (@$search) {
        my $templates = $z->update("host", {
            hostid => $host->{hostid},
            status => $status,
        });

        if ($templates->{error}) {
            print "Error change status $host->{host}: $templates->{error}->{message}\n";
            print "$templates->{error}->{data}\n";
        }
    }
}


=item change_macros($search, $macros_list);

    Change host macros

    change_macros($search, [
        'PXE.OS=centos',
        'PXE.STATUS=1',
    ]);

    Delete host macros

    change_macros($search, [
        'PXE.OS=',
        'PXE.STATUS',
    ]);

=cut

sub change_macros {
    my ($self, $search, $macros_list) = @_;

    foreach my $host (@$search) {
        my $current_macros_list = $self->{'zabbix'}->get('usermacro', {
            hostids => $host->{hostid},
            output => 'extend',
        });

        if ($current_macros_list->{error}) {
            print $current_macros_list->{error}->{message} . "\n";
            print $current_macros_list->{error}->{data} . "\n";

            exit 1;
        }

        my $macros_is_exist = 0;

        foreach (@$macros_list) {
            my ($macro, $value) = split/=/;

            foreach my $current_macros (@{ $current_macros_list->{result} }) {
                
                if ($macro !~ /^{\$.*}$/) {
                    $macro =~ s/^(.*)$/{\$$1}/;
                }

                if (uc($macro) eq $current_macros->{macro}) {
                    if ($value) {
                        if ($value ne $current_macros->{value}) {
                            my $update_macro_result = $self->{'zabbix'}->update('usermacro', {
                                hostmacroid => $current_macros->{hostmacroid},
                                value => $value,
                            });
                            
                            if ($update_macro_result->{error}) {
                                print $update_macro_result->{error}->{message} . "\n";
                                print $update_macro_result->{error}->{data} . "\n";

                                exit 1;
                            }
                        }
                    } else {
                        my $delete_macro_result = $self->{'zabbix'}->delete('usermacro', [
                            $current_macros->{hostmacroid},
                        ]);

                        if ($delete_macro_result->{error}) {
                            print $delete_macro_result->{error}->{message} . "\n";
                            print $delete_macro_result->{error}->{data} . "\n";

                            exit 1;
                        }
                    }

                    $macros_is_exist = 1;
                } elsif (! $value) {
                    $macros_is_exist = 1;
                }
            }

            unless ($macros_is_exist) {
                my $create_macro_result = $self->{'zabbix'}->create('usermacro', {
                    hostid => $host->{hostid},
                    macro => uc($macro),
                    value => $value,
                });

                if ($create_macro_result->{error}) {
                    print $create_macro_result->{error}->{message} . "\n";
                    print $create_macro_result->{error}->{data} . "\n";

                    exit 1;
                }
            }
        }

        my $result_macros_list = $self->{'zabbix'}->get('usermacro', {
            hostids => $host->{hostid},
            output => 'extend',
        });

        if ($result_macros_list->{error}) {
            print $result_macros_list->{error}->{message} . "\n";
            print $result_macros_list->{error}->{data} . "\n";

            exit 1;
        }

        print $host->{host} . ": \n";

        foreach my $macro (@{ $result_macros_list->{result} }) {
            printf("%30s: %s\n", $macro->{macro}, $macro->{value});
        }

        if ($self->{config}->{get_url_after_update_macros}) {
            require HTTP::Request;
            my $response = HTTP::Request->new(
                GET => $self->{config}->{get_url_after_update_macros}
            );
        }

        print "\n";
    }
}


=item show_templates($search)

Show all host linked templates

=cut

sub show_templates {
    my ($self, $search) = @_;
    my $z = $self->{'zabbix'};

    my @hostids = map { $_ = $_->{hostid} } @$search;

    my $host_obj = $z->get("host", {
        hostids => \@hostids,
        selectParentTemplates => [
            "name",
        ],
    });

    my @host_list = sort {$a->{name} cmp $b->{name} } @{$host_obj->{result}};

    foreach my $host (@host_list) {
        if ($host->{status} eq '0') {
            print "Host $host->{name}: \n";
        } else {
            print "Host \033[91m$host->{name}\033[0m: \n";
        }
        foreach my $template (@{$host->{parentTemplates}}) {
            print "\t$template->{name}\n";
        }
        print "\n";
    }
}

=item chk_template_is_exist($name)

Check exist template

=cut

sub chk_template_is_exist {
    my ($self, $name) = @_;
    my $z = $self->{'zabbix'};

    # Test for exist Template
    my $template_exist = $z->get("template.exists", {
        name => $name,
    });

    return $template_exist->{result};
}

=item create_template ($template_name, $group_id)

Create template

=cut

sub create_template {
    my ($self, $template_name, $group_id) = @_;
    my $z = $self->{'zabbix'};

    my $create_template = $z->create("template", {
        'host' => $template_name,
        'groups' => {
            groupid => $group_id,
        },
    });

    my $template_id = $create_template->{result}->{templateids}[0]
        if $create_template->{result} and $create_template->{result}->{templateids};

    die "Can't get Template ID\n" unless ($template_id);
    return $template_id;
}

=item create_item ($template_id, $item_name, $key)

Create item

=cut

sub create_item {
    my ($self, $template_id, $item_name, $key) = @_;
    my $z = $self->{'zabbix'};

    my $item_id;
    my $create_item = $z->create("item", {
        'name'      => $item_name,
        'hostid'    => $template_id,
        'key_'      => $key,
        'type'      => 0,
        'data_type' => 0,
        'value_type'=> 0,
        #'units'     => "%",
        'delay'     => 30,
        #'applications' => [ $application_id ],
    });


    if (ref $create_item->{result}->{itemids} eq 'ARRAY') {
        if ($#{$create_item->{result}->{itemids}} == 0) {
            $item_id = $create_item->{result}->{itemids}[0];
        } else {
            die "Error: create_item results > 1\n";
        }
    } else {
        die "Error: create_item result is not array\n";
    }

    return $item_id;
}

=item create_trigger($trigger_name, $template_id, $template_name, $key, $expression)

 priority:
           HIGH=4
           AVERAGE=3
           WARNING=2
           INFORMATION=1

=cut

sub create_trigger {
    my ($self, $trigger_name, $template_id, $template_name, $key, $expression, $priority) = @_;
    my $z = $self->{'zabbix'};

    $z->create("trigger", {
        'description' => $trigger_name,
        'hostid' => $template_id,
        'expression' => $expression,
        'priority' => $priority,
        'status' => 0,
    });
}

=item clear_all_not_in_templates

Clean all items, templates, application, graf if this not linked to any template

=cut

sub clear_all_not_in_templates {
}

=back

=cut

1;
