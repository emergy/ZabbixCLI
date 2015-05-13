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
    my ($self, $search, $template_name) = @_;
    my (@clear_list);

    my $z = $self->{'zabbix'};

    foreach my $host (@$search) {
        my $templates = $z->get("template", {
            extendoutput => 1,
            hostids => [ $host->{hostid} ],
        });

        foreach my $template (@{$templates->{result}}) {
            if ($template_name) {
                next if $template_name ne $template->{name};
            }

            push @clear_list, {
                    id => $host->{hostid},
                    name => $host->{host},

                    templates => [{
                        id => $template->{templateid},
                        name => $template->{host},
                    }],
            };
        }
    }

    if ($#clear_list >= 0) {
        foreach my $host (@clear_list) {
            print $host->{name} . "\n";

            foreach my $template (@{$host->{templates}}) {
                print "\t$template->{name}\n";
            }

            print "\n";
        }

        print "Unlink this hosts [y/n]: ";
        chomp(my $qa = readline(*STDIN));

        foreach my $host (@clear_list) {
            my @templates_clear;
            foreach my $template (@{$host->{templates}}) {
                push @templates_clear, {
                    templateid => $template->{id},
                };
            }

            my $host_cear_templates = $z->update("host", {
                hostid => $host->{id},
                templates_clear => \@templates_clear,
            });

            if ($host_cear_templates->{error}) {
                print "Error: unlink template from $host->{name}: $host_cear_templates->{error}->{message}\n";
                print "$host_cear_templates->{error}->{data}\n\n";
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

    foreach my $host (@{$host_obj->{result}}) {
        print "Host $host->{name}: \n";
        foreach my $template (@{$host->{parentTemplates}}) {
            print "\t$template->{name}\n";
        }
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
#    host.massremove host.massremovehost.massremovehost.massremovehost.massremovehost.massremovehost.massremovehost.massremovehost.massremovehost.massremovehost.massremovehost.massremovehost.massremovehost.massremove
#     my ($self, $search) = @_;
#     my $z = $self->{'zabbix'};
# 
#     foreach my $host (@$search) {
#         my $items = $z->get("item", {
#             hostids => $host->{hostid},
#             extendoutput => 1,
#         });
# 
#         if ($items->{result} and $#{$items->{result}} >= 0) {
#             print "Delete this items from host $host->{name}\n";
#             my @item_list;
# 
#             foreach (@{$items->{result}}) {
#                 print "\t$_->{itemid}\t$_->{name}\n";
#                 push @item_list, $_->{itemid};
#             }
# 
#             print "[y\\n]: ";
#             chomp(my $qa = readline(*STDIN));
# 
#             if ($qa eq 'y') {
#                 foreach (@item_list) {
#                     print Dumper($_);
#                     my $d = $z->delete("item", {
#                         params => [ $_ ]
#                     });
#                     print Dumper($d);
#                     exit;
#                 }
#             }
#         }
#     }
}

=back

=cut

1;
