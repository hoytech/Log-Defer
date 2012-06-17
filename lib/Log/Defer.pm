package Log::Defer;

use strict;

our $VERSION = '0.1';

use Time::HiRes;
use Carp qw/croak/;

use Guard;


sub new {
  my ($class, $cb) = @_;
  my $self = {};
  bless $self, $class;

  croak "must provide callback to Log::Defer" unless $cb && ref $cb eq 'CODE';

  my $msg = {
    logs => '',
    start => Time::HiRes::time,
  };

  $self->{msg} = $msg;

  $self->{guard} = guard {
    my $end_time = Time::HiRes::time();
    $msg->{end} = $end_time;
    my $duration = $end_time - $msg->{start};

    foreach my $name (keys %{$msg->{timers}}) {
      push @{$msg->{timers}->{$name}}, $duration
        if @{$msg->{timers}->{$name}} == 1;
    }

    $cb->($msg);
  };

  return $self;
}


sub error {
  $_[0]->_add_log('ERROR', $_[1]);
}

sub info {
  $_[0]->_add_log('INFO', $_[1]);
}

sub debug {
  $_[0]->_add_log('DEBUG', $_[1]);
}


sub timer {
  my ($self, $name) = @_;

  croak "timer $name already registered" if defined $self->{msg}->{timers}->{$name};

  my $timer_start = Time::HiRes::time() - $self->{msg}->{start};
  $timer_start = 0 if $timer_start < 0.0001;

  $self->{msg}->{timers}->{$name} = [ $timer_start, ];

  my $msg = $self->{msg};

  return guard {
    my $timer_end = Time::HiRes::time() - $msg->{start};
    $timer_end = 0 if $timer_end < 0.0001;

    push @{$msg->{timers}->{$name}}, $timer_end;
  }
}

sub event {
  my ($self, $name) = @_;

  croak "event $name already occured" if defined $self->{msg}->{events}->{$name};

  my $event_time = Time::HiRes::time() - $self->{msg}->{start};
  $event_time = 0 if $event_time < 0.0001;

  $self->{msg}->{events}->{$name} = $event_time;
}

sub data {
  my ($self) = @_;

  $self->{msg}->{data} ||= {};

  return $self->{msg}->{data};
}



#### INTERNAL ####

sub _add_log {
  my ($self, $tag, $log) = @_;

  chomp $log;

  my $time = Time::HiRes::time() - $self->{msg}->{start};

  $self->{msg}->{logs} .= "[$tag] $time: $log\n";
}



1;




__END__


=head1 NAME

Log::Defer -


=head1 SYNOPSIS

    use Log::Defer;

    my $logger = Log::Defer->new(\&my_logger_function);
    $logger->info("some info message");
    undef $logger; # write out log message

    sub my_logger_function {
      my $msg = shift;
      print STDERR $msg->{logs};
    }



=head1 DESCRIPTION

B<This module doesn't actually log anything!> To use this module you also need a logging library (some of them are mentioned in L<SEE ALSO>).

B<WARNING:> This module is still under development and the API and resulting messages aren't yet considered stable.

If you're not scared off yet, please read on.

What this module does is allow you to defer recording log messages until after some kind of "transaction" has completed. Typically this transaction is something like an HTTP request or a cron job. Generally log messages are easier to read if they are recorded "atomically" and not intermingled with log messages created by other requests.

The simplest use case is outlined in the L<SYNOPSIS>. You create a new Log::Defer object and pass in a coderef. This coderef will be called with a message hash reference (C<$msg>) once the Log::Defer object is destroyed, ie once all references to the object are overwritten or go out of scope.

Why not just append messages to a string and then call your logger function once the transaction is complete?

First, if a transaction has several possible paths it can take, there is no need to manually ensure that every possible path ends up calling your logging routine at the end.

Second, Log::Defer makes it easy to gather timing information about the various stages of your request. This is explained further below.




=head1 LOG MESSAGES






=head1 TIMERS AND EVENTS


    sub handle_request {
      my $request = shift;
      my $logger = Log::Defer->new(\&my_logging_function);

      my $headers = do {
        my $parse_timer = $logger->('parsing request');
        parse_request($request);
      };

      my $fetch_timer = $logger->('fetching results');
      async_fetch_results($headers, sub {

        $fetch_timer = $logger->('fetching results stage 2');
        async_fetch_results($headers, sub {

          undef $fetch_timer;
          send_response();
          undef $logger; ## write out log

        });

      });
    }





=head1 DATA






=head1 SEE ALSO

As mentioned above, this module doesn't actually log messages so you still must use some other module to write your log messages. There are many libraries on CPAN that can do this and there should be at least one that fits your requirements. Some examples are: L<Sys::Syslog>, L<Log::Dispatch>, L<Log::Handler>, L<Log::Log4perl>, L<Log::Fast>, L<AnyEvent::Log>.

There are also many other libraries that can help timing/metering your requests: L<Devel::Timer>, L<Timer::Simple>, L<Benchmark::Timer>, L<Time::Stopwatch>, L<Time::SoFar>.



=head1 AUTHOR

Doug Hoyte, C<< <doug@hcsw.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2012 Doug Hoyte.

This module is licensed under the same terms as perl itself.

=cut
