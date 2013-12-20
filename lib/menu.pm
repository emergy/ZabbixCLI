package menu;

use strict;
use warnings;

=encoding utf8

=head1 NAME

menu - simple menu class

=head1 SYNOPSIS

    use menu;

    my $name_field = 'name';

    my $array_hashes = [
        {
            name => 'item1',
            data => $data1,
            options => options1,
        },
        {
            name => 'item2',
            data => $data2,
            options => options2,
        },
    ];

    my $menu->new({         # Make object
        auto_change => 1,   # Auto change menu item if this only one
    });

    $menu->make($name_field, $array_hashes);    # Make menu from array hashes
    $menu->add('item3', $data);                 # Add item to menu


    $menu->show({       # Show menu and return change result
        sort => 1,      # Sort by name
    });

=cut


sub new {
    my ($class, $params) = @_;
    my $self = {
        params => $params,
    };

    bless $self, $class;
    return $self;
}

sub make {
    my ($self, $key, $data_array) = @_;

    foreach my $data (@$data_array) {
        $self->{menu}->{ $data->{$key} } = $data;
        push @{$self->{keys}}, $data->{$key};
    }

    return $self;
}

sub add {
    my ($self, $key, $data) = @_;

    $self->{menu}->{$key} = $data;
    push @{$self->{keys}}, $data->{$key};
    return $self;
}

sub show {
    my ($self, $params) = @_;

    my @keys;
    my $menu = $self->{menu};

    if ($params->{sort}) {
        @keys = sort {$a cmp $b} @{$self->{keys}};
    } else {
        @keys = @{$self->{keys}};
    }

LABEL:

    my $count = 0;
    system("clear");

    for (my $i = 1; $i <= $#keys + 1; $i++) {
        print "$i) $keys[$i - 1]\n";
        $count = $i;
    }

    my $change = 1;
    my $auto_change = 1;
    $auto_change = 0 unless $self->{params}->{auto_change};

    if ($#keys < $auto_change) {
        print "Only one entry. Selected this.";
        print "\n" foreach (1 .. 5);
    } else {
        print "Type you change and enter: ";
        chomp($change = readline(*STDIN));
    }

    unless (ck_valid_change($change, $count)) {
        print "\n" foreach (1 .. 5);
        goto LABEL;
    }

    return $menu->{$keys[$change - 1]};
}

sub ck_valid_change {
    my ($change, $max) = @_;
    my @chars = ( 1 .. $max );

    return $change ~~@chars;
}

1;
