package menu;

use strict;
use warnings;
use Data::Dumper;
use FindBin '$RealBin';


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
        cache_dir => 1,     # Directory for database saved autochange
                            # Default: "$RealBin/../var/menu_cache.db"
    });

    $menu->make($name_field, $array_hashes);    # Make menu from array hashes
    $menu->add('item3', $data);                 # Add item to menu


    my $data = $menu->show({       # Show menu and return change result
        sort => 1,      # Sort by name
    });

=cut



sub new {
    my ($class, $params) = @_;

    unless ($params->{cache_dir}) {
        $params->{cache_dir} = "$RealBin/../var/menu_cache.db";
    }

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

    my $change = 0;
    $change = get_change($self, $menu);# if ($self->{params}->{enable_menu_save});

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
    
    unless ($change) {
        $change = 1;
        my $auto_change = 1;
        $auto_change = 0 unless $self->{params}->{auto_change};
    
        if ($#keys < $auto_change) {
            print "Only one entry. Selected this.";
            print "\n" foreach (1 .. 5);
        } else {
            print "Type you change and enter: ";
            chomp($change = readline(*STDIN));
        }
    
        #if ($self->{params}->{enable_menu_save}) {
            if ($change =~ /s$/) {
                $change =~ s/s$//;
    
                save_change($self, $menu, $change);
            }
        #}
    
        unless (ck_valid_change($change, $count)) {
            print "\n" foreach (1 .. 5);
            $change = 0;
            goto LABEL;
        }
    } else {
        print "Detect saved autochange: $change\n";
    }
    
    return $menu->{$keys[$change - 1]};
}

sub save_change {
    my ($self, $menu, $change) = @_;
    my $cache_dir = $self->{params}->{cache_dir};
    my $create_table = 0;
    unless (-e $cache_dir) {
        $create_table = 1;
        open F, ">", $cache_dir or die "Can't open cache file: $!\n";
        close F;
    }

    require DBI;
    my $db = DBI->connect("dbi:SQLite:$cache_dir","","", {RaiseError => 1, AutoCommit => 1});

    if ($create_table) {
        $db->do("CREATE TABLE menu_cache (id INTEGER PRIMARY KEY, menu TEXT, change INTEGER)");
    }

    my $sth = $db->prepare("INSERT INTO menu_cache VALUES (NULL, ?, ?)");
    $Data::Dumper::Terse = 1;
    $sth->execute(Dumper($menu), $change);

    #$db->commit;
    $db->disconnect;
}

sub get_change {
    my ($self, $menu) = @_;
    my $cache_dir = $self->{params}->{cache_dir};
    my $r;

    return 0 unless (-e $cache_dir);

    require DBI;
    my $db = DBI->connect("dbi:SQLite:$cache_dir","","", {RaiseError => 1, AutoCommit => 1});
    my $sth = $db->prepare("SELECT change FROM menu_cache WHERE menu = ?");
    $Data::Dumper::Terse = 1;
    $sth->execute(Dumper($menu));

    while (my $res = $sth->fetchrow_hashref) {
        $r = $res->{change};
    }

    $db->disconnect;
    return $r;
}

sub ck_valid_change {
    my ($change, $max) = @_;
    my @chars = ( 1 .. $max );

    return $change ~~ @chars;
}

1;
