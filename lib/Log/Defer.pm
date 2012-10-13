package Log::Defer;

use strict;

our $VERSION = '0.12';

use Time::HiRes;
use Carp qw/croak/;

use Guard;


sub new {
  my ($class, $cb, $opts) = @_;

  if ($cb) {
    if (ref $cb eq 'CODE') {
      $opts ||= {};
      croak "two callbacks provided" if $opts->{cb};
    } elsif (ref $cb eq 'HASH') {
      $opts = $cb;
      $cb = $opts->{cb};
    } else {
      croak "first arg to new must be a coderef or hashref";
    }
  }

  my $self = $opts;
  bless $self, $class;

  croak "must provide callback to Log::Defer" unless $cb && ref $cb eq 'CODE';

  my $msg = {
    start => format_time(Time::HiRes::time),
  };

  $self->{msg} = $msg;

  $self->{guard} = guard {
    my $end_time = format_time(Time::HiRes::time());
    my $duration = format_time($end_time - $msg->{start});
    $msg->{end} = $duration;

    if (exists $msg->{timers}) {
      foreach my $name (keys %{$msg->{timers}}) {
        push @{$msg->{timers}->{$name}}, $duration
          if @{$msg->{timers}->{$name}} == 1;
      }
    }

    $cb->($msg);
  };

  return $self;
}


sub error {
  my ($self, @logs) = @_;

  $self->add_log(10, @logs);
}

sub warn {
  my ($self, @logs) = @_;

  $self->add_log(20, @logs);
}

sub info {
  my ($self, @logs) = @_;

  $self->add_log(30, @logs);
}

sub debug {
  my ($self, @logs) = @_;

  $self->add_log(40, @logs);
}

sub add_log {
  my ($self, $verbosity, @logs) = @_;

  if (!exists $self->{verbosity} || $verbosity <= $self->{verbosity}) {
    my $time = format_time(Time::HiRes::time() - $self->{msg}->{start});

    @logs = $logs[0]->() if $logs[0] && ref $logs[0] eq 'CODE';

    push @{$self->{msg}->{logs}}, [$time, $verbosity, @logs];
  }
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

sub format_time {
  my $time = shift;

  $time = 0 if $time < 0;

  return 0.0 + sprintf("%.6f", $time);
}


1;




__END__


=head1 NAME

Log::Defer - Deferred logs and timers


=head1 SYNOPSIS

    use Log::Defer;
    use JSON::XS; ## or whatever

    my $logger = Log::Defer->new({
                                   cb => \&my_logger_function,
                                   verbosity => 30,
                                 });

    $logger->info("hello world");

    my $timer = $logger->timer('some timer');
    undef $timer; ## stops timer

    undef $logger; ## write out log message

    sub my_logger_function {
      my $msg = shift;
      print JSON::XS->new->pretty(1)->encode($msg);
    }

Prints:

    {
       "start" : 1340421702.16684,
       "end" : 0.000249,
       "logs" : [
          [
             0.000147,
             30,
             "hello world"
          ]
       ]
    }



=head1 DESCRIPTION

B<This module doesn't actually log anything!> To use this module for normal logging purposes you also need a logging library (some of them are mentioned in L<SEE ALSO>).

What this module does is allow you to defer recording log messages until after some kind of "transaction" has completed. Typically this transaction is something like an HTTP request or a cron job. Generally log messages are easier to read if they are recorded "atomically" and are not intermingled with log messages created by other transactions.

This module preserves as much structure as possible which allows you to record machine-parseable log messages if you so choose.



=head1 USAGE

The simplest use case is outlined in the L<SYNOPSIS>. You create a new Log::Defer object and pass in a code ref. This code ref will be called once the Log::Defer object is destroyed or all references to the object go out of scope.

If a transaction has several possible paths it can take, there is no need to manually ensure that every possible path ends up calling your logging routine at the end. The log writing will be deferred until the logger object is destroyed or goes out of scope.

In an asynchronous application where multiple asynchronous tasks are kicked off concurrently, each task can keep a reference to the logger object and the log writing will be deferred until all tasks are finished.

Log::Defer makes it easy to gather timing information about the various stages of your request. This is explained further below.




=head1 STRUCTURED LOGS

So what is the point of this module? Most logging libraries are convenient to use, usually even more-so than Log::Defer. However, this module allows you to record log messages in a format that can be easily analysed if you so choose.

Line-based log protocols are nice because they are compact and since people are used to them they are "easy" to read.

However, doing analysis on line-based or, even worse, ad-hoc unstructured multi-line formats is more difficult than it needs to be. And given the right tools, reading structured log messages can actually be easier than reading line-based logs.



=head1 LOG MESSAGES

Log::Defer objects provide a very basic "log level" system. In order of increasing verbosity, here are the possible logging methods:

    $logger->error("...");  # 10
    $logger->warn("...");   # 20
    $logger->info("...");   # 30
    $logger->debug("...");  # 40

If you pass in a C<verbosity> argument, messages with a higher log level will not be included in the final log message. Otherwise, all log messages are included.

Here is an example of issuing a warning:

    $logger->warn("something weird happened", { username => $username });

In the deferred logging callback, the log messages are recorded in the C<logs> element of the C<$msg> hash. It is an array ref and here would be the element pushed onto C<logs> by the C<warn> method call above:

    [ 0.201223, 20, "something weird happened", { username => "jimmy" } ]

The first element is a timestamp of when the C<warn> method was called in seconds since the C<start> (see L<TIMERS> below).

The second element is the verbosity level. If you wish to implement "log levels" (ie filter out debug messages), you can L<grep> them out when your recording callback is called.




=head1 DELAYED MESSAGE GENERATION

If you would like to record complex messages in debug mode but don't want to burden your production systems with this overhead, you can use delayed message generation:

    $logger->debug(sub { "Connection: " . dump_connection_info($conn) });

The sub won't be evaluated unless the logger object is instantiated with C<verbosity> of 40 or higher (or you omit C<verbosity>).



=head1 DATA

Instead of log messages, you can directly access a C<data> hash reference with the C<data> method:

    $log->data->{junkdata} = 'some data';

This is useful for recording info related to a whole transaction like say a connecting IP address. Anything you put in the C<data> hash reference will be passed along untouched to your defered callback.



=head1 TIMERS

When the logger object is first created, the current time is recorded and is stored in the C<start> element of the log hash. However, you can record timing data of sub-portions of your transaction with timer objects.

Timer objects are created by calling the C<timer> method on the logger object. This method should be passed a description of what you are timing.

The timer starts as soon as the timer object is created and stops once the last reference to the timer is destroyed or goes out of scope, or if the logger object itself is destroyed/goes out of scope.

C<start> is a L<Time::HiRes> absolute timestamp. All other times are relative offsets from this C<start> time. Everything is in seconds.

With the L<Log::Defer::Viz> module you can take your recorded timer data and render log messages that look like this:

     download file |===============================================|
      cache lookup |==============|
      update cache                |=========================================|
         DB lookup                |======================|
        sent reply                                                 X
    ________________________________________________________________________________
    times in ms    0.2            32.4                             100.7
                                                         80.7              119.2

Here is a fairly complicated example of using concurrent timers:

    sub handle_request {
      my $request = shift;
      my $logger = Log::Defer->new(\&my_logging_function);

      my $headers = do {
        my $parse_timer = $logger->timer('parsing request');
        parse_request($request);
      };

      my $fetch_timer = $logger->timer('fetching results');
      async_fetch_results($headers, sub {

        ## stop first timer by undefing ref, then start new timer
        undef $fetch_timer; $fetch_timer = $logger->timer('fetching stage 2');

        async_fetch_stage_2($headers, sub {

          $logger; ## keep reference alive
          undef $fetch_timer;
          send_response();

        });

        my $update_cache_timer = $logger->timer('update cache');

        async_update_cach(sub {

          $logger; ## keep reference alive
          undef $update_cache_timer;

        });

      });
    }




=head1 EXAMPLE LOG MESSAGE

Each structured log message will be passed into the callback provided to C<new>. The message is a perl hash reference that contains various other perl data-structures. What you do at this point is up to you.

What follows is a prettified example of a JSON-encoded log message. Normally all unnecessary white-space would be removed and it would be stored on a single line so that ad-hoc command-line C<grep>ing still works.

    {
       "start" : 1340353046.93565,
       "end" : 0.202386,
       "logs" : [
          [
             0.000158,
             30,
             "This is an info message (verbosity=30)"
          ],
          [
             0.201223,
             20,
             "Warning! \n\n Here is some more data:",
             {
                 "whatever" : 987
             }
          ]
       ],
       "data" : {
          "junkdata" : "some data"
       },
       "timers" : {
          "junktimer" : [
             0.000224,
             0.100655
          ],
          "junktimer2" : [
             0.000281,
             0.202386
          ]
       }
    }








=head1 SEE ALSO

As mentioned above, this module doesn't actually log messages to disk/syslog/anything so you still must use some other module to record your log messages. There are many libraries on CPAN that can do this and there should be at least one that fits your requirements. Some examples are: L<Sys::Syslog>, L<Log::Dispatch>, L<Log::Handler>, L<Log::Log4perl>, L<Log::Fast>, L<AnyEvent::Log>.

Some caveats related to non-monotonous clocks are discussed in L<Time::HiRes>.



=head1 AUTHOR

Doug Hoyte, C<< <doug@hcsw.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2012 Doug Hoyte.

This module is licensed under the same terms as perl itself.

=cut
