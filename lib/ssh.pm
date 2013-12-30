package ssh;

use strict;
use warnings;
use File::Path qw/ make_path /;
use File::Temp qw/ tempfile tempdir /;

sub new {
    my ($class, $config) = @_;

    my $self;

    $self->{'config'} = $config;

    bless $self, $class;
    return $self;
}

sub ssh {
    my ($self, $host, $name) = @_;
    my $cmd;
    my $config = $self->{'config'};

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
        $cmd = "ssh $key $options $user$host";
        $cmd .= " '$config->{'ssh-command'}'" if ($config->{'ssh-command'});
    }
    
    # Debug
    print $cmd . "\n" if ($config->{debug});

    system($cmd);
}

1;
