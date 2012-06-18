package Log::Defer;

use strict;

our $VERSION = '0.1';

use Time::HiRes;
use Carp qw/croak/;

use Guard;


my $log_levels = {
  error => 10,
  warn => 20,
  info => 30,
  debug => 40,
};

sub new {
  my ($class, $cb, %args) = @_;
  my $self = {};
  bless $self, $class;

  croak "must provide callback to Log::Defer" unless $cb && ref $cb eq 'CODE';

  my $msg = {
    logs => [],
    start => format_time(Time::HiRes::time),
  };

  $self->{msg} = $msg;

  if (exists $args{level}) {
    if ($args{level} =~ /^\d+$/) {
      $self->{log_level} = $args{level};
    } else {
      $self->{log_level} = $log_levels->{$args{level}};
      croak "bad level value (should be an error level name or a positive integer)"
        if !defined $self->{log_level};
    }
  } else {
    $self->{log_level} = 30;
  }

  $self->{guard} = guard {
    my $end_time = format_time(Time::HiRes::time());
    $msg->{end} = $end_time;
    my $duration = format_time($end_time - $msg->{start});

    foreach my $name (keys %{$msg->{timers}}) {
      push @{$msg->{timers}->{$name}}, $duration
        if @{$msg->{timers}->{$name}} == 1;
    }

    $cb->($msg);
  };

  return $self;
}


sub error {
  my ($self, $msg) = @_;

  $self->_add_log(10, $msg)
    if $self->{log_level} >= 10;
}

sub warn {
  my ($self, $msg) = @_;

  $self->_add_log(20, $msg)
    if $self->{log_level} >= 20;
}

sub info {
  my ($self, $msg) = @_;

  $self->_add_log(30, $msg)
    if $self->{log_level} >= 30;
}

sub debug {
  my ($self, $msg) = @_;

  $self->_add_log(40, $msg)
    if $self->{log_level} >= 40;
}


sub timer {
  my ($self, $name) = @_;

  croak "timer $name already registered" if defined $self->{msg}->{timers}->{$name};

  my $timer_start = format_time(Time::HiRes::time() - $self->{msg}->{start});

  $self->{msg}->{timers}->{$name} = [ $timer_start, ];

  my $msg = $self->{msg};

  return guard {
    my $timer_end = format_time(Time::HiRes::time() - $msg->{start});

    push @{$msg->{timers}->{$name}}, $timer_end;
  }
}

sub data {
  my ($self) = @_;

  $self->{msg}->{data} ||= {};

  return $self->{msg}->{data};
}



#### INTERNAL ####

sub _add_log {
  my ($self, $verbosity, $log) = @_;

  chomp $log;

  my $time = format_time(Time::HiRes::time() - $self->{msg}->{start});

  push @{$self->{msg}->{logs}}, [$verbosity, $time, $log];
}

sub format_time {
  my $time = shift;

  $time = 0 if $time < 0;

  return 0.0 + sprintf("%.6f", $time);
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

First, if a transaction has several possible paths it can take, there is no need to manually ensure that every possible path ends up calling your logging routine at the end. The log writing will be deferred until the logger object is destroyed.

Second, in an asynchronous application where multiple asynchronous tasks are kicked off concurrently, if each task keeps a reference to the logger object, the log writing will be deferred until all tasks are finished.

Finally, Log::Defer makes it easy to gather timing information about the various stages of your request. This is explained further below.




=head1 LOG MESSAGES

Log::Defer objects provide a very basic "log level" system that should be familiar. In order of decreasing verbosity, here are the possible methods:

    $logger->debug("debug message");
    $logger->info("info message");
    $logger->warn("warn message");
    $logger->error("error message");

You can set your log level to muffle messages you aren't interested in. For example, the following logger object will only record C<warn> and C<error> logs:

    my $logger = Log::Defer->new(
                               sub { ... },
                               level => 'warn',
                             );

The default log level is C<info>.

In the deferred logging callback, the log messages are recorded in the C<logs> entry of the C<$msg> hash.




=head1 TIMERS


    sub handle_request {
      my $request = shift;
      my $logger = Log::Defer->new(\&my_logging_function);

      my $headers = do {
        my $parse_timer = $logger->('parsing request');
        parse_request($request);
      };

      my $fetch_timer = $logger->('fetching results');
      async_fetch_results($headers, sub {

        ## stop first timer by overwriting ref, start new timer
        $fetch_timer = $logger->('fetching results stage 2');

        async_fetch_results_stage_2($headers, sub {

          $logger; ## keep reference alive
          undef $fetch_timer;
          send_response();

        });

        my $update_cache_timer = $logger->('update cache');

        async_update_cach(sub {

          $logger; ## keep reference alive
          undef $update_cache_timer;

        });

      });
    }



    total time               |============================================|
    parsing request          |======|
    fetching results                |==========|
    fetching results stage 2                   |==========================|
    update cache                               |==========|
                             0                 0.05073                    0.129351
                                    0.0012                 0.084622




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
