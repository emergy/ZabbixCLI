package ssh;

use strict;
use warnings;
use File::Path qw/ make_path /;
use File::Temp qw/ tempfile tempdir /;
use Data::Dumper;
use config;

=head1 NAME

    SSH - SSH module for ZabbixCLI

=head1 SYNOPSIS

    my $config = {
        mount-dir => $ENV{HOME} . '/.ssh/$hostname',
        ssh-user  => 'root',
        ssh-key   => $ENV{HOME} . '/.ssh/id_rsa',
    };

    my $ssh = ssh->new($config);
    my $return = $ssh->ssh($host, $name, $command);

=cut

sub new {
    my ($class, $config) = @_;
    my $self->{'config'} = $config;

    bless $self, $class;
    return $self;
}

sub ssh {
    my ($self, $host, $name, $command) = @_;
    my $cmd;
    my $config = $self->{'config'};
    $config->{'ssh-command'} = $command if $command;

    if ($config->{'hostopt'}) {
        if ($config->{'hostopt'}->{$name}) {
            foreach (split/\|/, $config->{'hostopt'}->{$name}) {
                $config = config->new($_, $config, 1);
            }
        }
    }

    print "private config: " . Dumper($config) if ($config->{debug});

    my $user = '';
    $user = $config->{'ssh-user'} . '@' if ($config->{'ssh-user'});

    if ($config->{'mount'}) {
        my ($fh, $tempfile);

        $config->{'mount-dir'} =~ s/^~/$ENV{HOME}/;

        if ($config->{'ssh-key'}) { # gen sshfs config
            
            # Create tempory config file for set key
            ($fh, $tempfile) = tempfile("zsXXXXXXXX", DIR => '/tmp');
            print $fh "Host $host\n\tIdentityFile $config->{'ssh-key'}\n";
            close $fh;

            print "Use temp file: $tempfile\n" if $config->{debug};

            $config->{'mount-dir'} =~ s/\$hostname/$name/;
            $cmd = "sshfs -F $tempfile $user$host:/ $config->{'mount-dir'}  $config->{'mount-options'}";
        } else {
            $cmd = "sshfs $user$host:/ $config->{'mount-dir'}  $config->{'mount-options'}";
        }

        make_path($config->{'mount-dir'}) unless -e $config->{'mount-dir'};

    } else {
        my $key = ''; # Use ssh-key if set on config or command line
        $key = "-i $config->{'ssh-key'}" if ($config->{'ssh-key'});
    
        # Use ssh options from config
        my $options = $config->{'ssh-options'} ||= ' ';
        $options .= ' -t ' if ($config->{'ssh-exec'});
        $cmd = "ssh $key $options $user$host";
        $cmd .= " '$config->{'ssh-command'}'" if ($config->{'ssh-command'});
        $cmd .= " '$config->{'ssh-exec'}'" if ($config->{'ssh-exec'});
    }
    
    # Debug
    print 'execute: ' . $cmd . "\n" if ($config->{verbose});

    $ENV{'PROMPT_COMMAND'} = qq(echo -ne "\\033]0;$name\\007");
    print "\033]0;$name\007";

    if ($config->{'ssh-command'}) {
        if ($config->{verbose}) {
            return `$cmd`;
        } else {
            return `$cmd 2>/dev/null`;
        }
    } else {
        print "\c[];$name\a";
        system($cmd);
        print "\c[];Shell\a";
    }
}

1;
