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
        cache_file => "/var",     # Directory for database saved autochange
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

    unless ($params->{cache_file}) {
        $params->{cache_file} = "$RealBin/../var/menu_cache.db";
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

#     if ($params->{cli}) {
        show_cli($self, $params);
#     } else {
#         show_curses($self, $params);
#     }
}

sub show_curses {
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




#     print Dumper(@keys);exit;
    
    require Curses::UI;

    my $cui = Curses::UI->new(
        -mouse_support => 1,
        -color_support => 0,
        -clear_on_exit => 1,
        #-debug => 1,
    );

    my $win = $cui->add('win', 'Window');
    $cui->set_binding( sub { exit(0); } , "\cC");

    my ($buttons, $ret);

    my $callback = sub {
        my $value = $buttons->get();
        #$cui->leave_curses;
        $ret = $value;
        $cui->mainloopExit;
    };

    map {
        $_ = {
            -label => $_,
            -value => $menu->{$_},
            -onpress => \&$callback,
#             -onpress => sub {
#                 $cui->leave_curses;
#                 my $cb = shift;
#                 $cui->mainloopExit;
# 
#             },
        };
    } @keys;

    $buttons = $win->add('mybuttons', 'Buttonbox',
        -buttons  => \@keys,
        -vertical => 1,
    );

#     $cui->add_callback(1, sub {
#         #$cui->mainloopExit;
#         my $value = $buttons->get();
#         $cui->leave_curses;
#         print Dumper($value);
#         sleep 3;
#         #return $value;
#     });

    $buttons->focus();
    $cui->mainloop;

    clear_screen();
    #endwin();
    #$cui->clear();

    return $ret;

}


sub clear_screen {
#     require Term::Screen::Uni;
#     my $scr = new Term::Screen::Uni;
#     
#     $scr->clrscr();
    print "\033[2J";    #clear the screen
    print "\033[0;0H"; #jump to 0,0
}

sub show_cli {
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
    my $cache_file = $self->{params}->{cache_file};
    my $cache_dir = $cache_file;
    $cache_dir =~ s{/[^/]+$}{};
    my $create_table = 0;

    mkdir $cache_dir if (! -e $cache_dir);

    unless (-e $cache_file) {
        $create_table = 1;
        open F, ">", $cache_file or die "Can't open cache file: $!\n";
        close F;
    }

    require DBI;
    my $db = DBI->connect("dbi:SQLite:$cache_file","","", {RaiseError => 1, AutoCommit => 1});

    if ($create_table) {
        $db->do("CREATE TABLE menu_cache (id INTEGER PRIMARY KEY, menu TEXT, change INTEGER)");
    }

    my $sth = $db->prepare("INSERT INTO menu_cache VALUES (NULL, ?, ?)");
    $Data::Dumper::Terse = 1;
    my @menu_list = sort { $a cmp $b } keys %$menu;
    $sth->execute(Dumper(\@menu_list), $change);

    #$db->commit;
    $db->disconnect;
}

sub get_change {
    my ($self, $menu) = @_;
    my $cache_file = $self->{params}->{cache_file};
    my $r;

    return 0 unless (-e $cache_file);

    require DBI;
    my $db = DBI->connect("dbi:SQLite:$cache_file","","", {RaiseError => 1, AutoCommit => 1});
    my $sth = $db->prepare("SELECT change FROM menu_cache WHERE menu = ?");
    $Data::Dumper::Terse = 1;
    my @menu_list = sort { $a cmp $b } keys %$menu;
    $sth->execute(Dumper(\@menu_list));

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
