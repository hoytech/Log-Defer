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

    sub my_logger_function {
      my $msg = shift;
      print JSON::XS->new->pretty(1)->encode($msg);
    }

    my $logger = Log::Defer->new({
                                   cb => \&my_logger_function,
                                   verbosity => 30,
                                 });

    $logger->info("hello world");

    my $timer = $logger->timer('some timer');
    undef $timer; ## stops timer

    undef $logger; ## write out log message

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

I believe a lot of log processing is done too early. This module helps you to defer log processing in two ways:

=over 4

=item Defer recording of log messages until a "transaction" has completed

Typically this transaction is something like an HTTP request or a cron job. Generally log messages are easier to read if they are recorded atomically and are not intermingled with log messages created by other transactions.

=item Defer rendering of log messages

Sometimes you don't know how logs should be rendered until long after the message has been written. If you aren't sure what information you'll want to display, or you expect to display logs in multiple different formats, it makes sense to store your logs in a highly structured format so they can be processed as late as possible.

=back


B<This module doesn't actually write out logs!> To use this module for normal logging purposes you also need a logging library (some of them are mentioned in L<SEE ALSO>).





=head1 USAGE

The simplest use case is outlined in the L<SYNOPSIS>. You create a new Log::Defer object and pass in a code ref callback. This callbac will be called once the Log::Defer object is destroyed or once all references to the object go out of scope.

With Log::Defer, if a transaction has several possible code paths it can take, there is no need to manually ensure that every possible path ends up calling your logging routine at the end. The log writing will be deferred until the logger object is destroyed or goes out of scope.

In an asynchronous application where multiple asynchronous tasks are kicked off concurrently, each task can keep a reference to the logger object and the log writing will be deferred until all tasks are finished.

Log::Defer makes it easy to gather timing information about the various stages of your request. This is explained further below.




=head1 STRUCTURED LOGS

Free-form line-based log protocols are probably the most common log formats by far. The formats are usually just happenstance -- whatever happened to be convenient for the programmer.

Unfortunately, doing analysis on ad-hoc unstructured multi-line formats requires a lot of time-consuming parsing work. As well as being a perl module, Log::Defer is also a specification for a structured logging format.

Although this module doesn't impose any external encoding for log messages on you, some tools like the visualisation tool only support JSON at this time.

FIXME: QQQ Normally all unnecessary white-space would be removed and it would be stored on a single line so that ad-hoc command-line C<grep>ing still works.



=head1 LOG MESSAGES

Log::Defer objects provide a very basic "log level" system. In order of increasing verbosity, here are the normal logging methods and their numeric log level:

    $logger->error("...");  # 10
    $logger->warn("...");   # 20
    $logger->info("...");   # 30
    $logger->debug("...");  # 40

You can also use custom log levels:

    $logger->add_log(25, "...");

If you pass in a C<verbosity> argument to the Log::Defer constructor, messages with a higher log level will not be included in the final log message. Otherwise, all log messages are included.

Even if you include noisy debug logs you can filter them out with the visualisation tool at display time. The C<verbosity> argument is only useful for reducing the size of log messages or eliminating unnecessary processing overhead (see the no-overhead debug logs section below).

Note that you can pass in multiple items to a log message and they don't even need to be strings:

    $logger->warn("something weird happened: $@", { username => $username });

In the deferred logging callback, the log messages are recorded in the C<logs> element of the C<$msg> hash. It is an array ref and here would be the element pushed onto C<logs> by the C<warn> method call above:

    [ 0.201223, 20, "something weird happened: peer timeout", { username => "jimmy" } ]

The first element is a timestamp of how long the C<warn> method was called after the C<start> in seconds (see L<TIMERS> below). The second element is the verbosity level of this message.



=head1 NO-OVERHEAD DEBUG LOGS

If you would like to compute complex messages in debug mode but don't want to burden your production systems with this overhead, you can use delayed message generation:

    $logger->debug(sub { "Connection: " . dump_connection_info($conn) });

The sub won't be invoked unless the logger object is instantiated with C<verbosity> of 40 or higher (or you omit C<verbosity> altogether).



=head1 DATA

Instead of log messages, you can directly add items to a C<data> hash reference with the C<data> method:

    $log->data->{ip} = $ENV{REMOTE_ADDR};

This is a useful place to recording info that needs to be extracted since you don't need to crawl through log message entries. Anything you put in the C<data> hash reference will be passed along untouched to your defered callback.



=head1 TIMERS

When the logger object is first created, the current time is recorded as a L<Time::HiRes> absolute timestamp and is stored in the C<start> element of the log hash. All other times are relative offsets from C<start>.

When the logger object is destroyed, the time elapsed since C<start> is stored in C<end>.

In addition to start and duration of the entire transaction, you can also record timing data of sub-portions of your transaction by using timer objects.

Timer objects are created by calling the C<timer> method on the logger object. This method should be passed a description of what you are timing.

The timer starts as soon as the timer object is created and stops once the last reference to the timer is destroyed or goes out of scope. If the logger object itself is destroyed or goes out of scope then all outstanding timers are terminated at that point.

C<start> is a L<Time::HiRes> absolute timestamp. All other times are relative offsets from this C<start> time. Everything is in seconds.

Here is a fairly complicated example showing how to use concurrent timers:

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

Each structured log message will be passed into the callback provided to C<new> as a perl hash reference that contains various other perl data-structures. What you do at this point is up to you.

Here is a prettified example of a JSON-encoded message:

    {
       "start" : 1340353046.93565,
       "end" : 0.202386,
       "logs" : [
          [
             0.000158,
             30,
             "This is an info message (log level=30)"
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



=head1 Visualisation

See the L<Log::Defer::Viz> module for a command line utility that renders Log::Defer logs. Timers are shown something like this:

     download file |===============================================|
      cache lookup |==============|
      update cache                |=========================================|
         DB lookup                |======================|
        sent reply                                                 X
    ________________________________________________________________________________
    times in ms    0.2            32.4                             100.7
                                                         80.7              119.2



=head1 SEE ALSO

As mentioned above, this module doesn't actually log messages to disk/syslog/anything so you still must use some other module to record your log messages. There are many libraries on CPAN that can do this and there should be at least one that fits your requirements. Some examples are: L<Sys::Syslog>, L<Log::Dispatch>, L<Log::Handler>, L<Log::Log4perl>, L<Log::Fast>, L<AnyEvent::Log>.

Additionally, this module doesn't provide any official serialization format. There are many choices for this, including L<JSON::XS>, L<Sereal>, L<Storable>, and L<Data::MessagePack>.

Currently the timestamp generation system is hard-coded to C<Time::HiRes::time>. You should be aware of some caveats related to non-monotonous clocks that are discussed in L<Time::HiRes>.



=head1 AUTHOR

Doug Hoyte, C<< <doug@hcsw.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2012-2013 Doug Hoyte.

This module is licensed under the same terms as perl itself.

=cut
