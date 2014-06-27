package config;

use strict;
use warnings;

=encoding utf8

=head1 NAME

config - simple config class

=head1 SYNOPSIS

    use config;

    my $config = config->new("$RealBin/../etc/config", {
        # Default values if not set in config file
        
        option1 => "default value",
        option2 => "default value",
    });

    print $config->{opt1};
    print $config->get('opt1');

=head1 CONFIG FORMAT

    opt1 = value
    opt2 = value

    alias opt1 = value
    alias opt1 = value

=cut

sub new {
    my ($class, $config_file, $self, $raw_mode) = @_;

    my $parse_line = sub {
        $_ = shift(@_);

        s/^\s*(.*)\s*$/$1/;
        return if /^\s*#/;

        if (/^([^\s=]+?)\s+([^\s=]+?)\s*=\s*(.+)$/) {
            $self->{$1}->{$2} = $3;
        } elsif (/^(.+?)\s*=\s*(.+)$/) {
            $self->{$1} = $2;
        }
    };

    if ($raw_mode) {
        foreach (split(/\n/, $config_file)) {
            &$parse_line($_);
        }
    } else {
        if (open my $cfg, "<", $config_file) {
            while (<$cfg>) {
                &$parse_line($_);
            }
    
            close $cfg;
        } else {
            $self = _error($self, "Can't open config file", $!);
        }
    }

    bless $self, $class;
    return $self;
}

sub get {
    my ($self, $key) = @_;
    return $self->{$key};
}

sub _error {
    my ($self, $msg, $data);

    $self->{error}->{message} = $msg;
    $self->{error}->{data} = $data;

    return $self;
}

1;
