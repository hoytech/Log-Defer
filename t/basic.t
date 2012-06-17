use strict;

use Test::More tests => 19;

use Log::Defer;
use Data::Dumper;


my $triggered;

my $log = Log::Defer->new(sub {
  my $msg = shift;

  print Dumper($msg) . "\n";

  ## start/end time

  ok(exists $msg->{start}, 'start is there');
  ok(exists $msg->{end}, 'end is there');

  ## log messages

  ok($msg->{logs} =~ m{QQQ I.*?QQQ D.*?QQQ E}s);

  ## timers

  ok(exists $msg->{timers}->{junktimer});
  ok(exists $msg->{timers}->{junktimer2});
  ok(exists $msg->{timers}->{junktimer3});

  is(@{$msg->{timers}->{junktimer}}, 2);
  is(@{$msg->{timers}->{junktimer2}}, 2);
  is(@{$msg->{timers}->{junktimer3}}, 2);

  ok($msg->{timers}->{junktimer}->[0] <= $msg->{timers}->{junktimer2}->[0]);
  ok($msg->{timers}->{junktimer2}->[0] <= $msg->{timers}->{junktimer2}->[0]);

  ok($msg->{timers}->{junktimer}->[1] <= $msg->{timers}->{junktimer3}->[0]);
  ok($msg->{timers}->{junktimer3}->[1] <= $msg->{timers}->{junktimer2}->[1]);

  ## events

  ok(exists $msg->{events}->{junkevent});
  ok($msg->{timers}->{junktimer}->[1] <= $msg->{events}->{junkevent});
  ok($msg->{events}->{junkevent} <= $msg->{timers}->{junktimer3}->[0]);

  ## data

  ok($msg->{data}->{junkdata} == 123);

  $triggered = 1;
});


$log->info('QQQ I');

$log->data->{junkdata} = 123;

my $timer = $log->timer('junktimer');
my $timer2 = $log->timer('junktimer2');

select undef,undef,undef,0.1;

undef $timer;

$log->event('junkevent');
$log->debug('QQQ D');

my $timer3 = $log->timer('junktimer3');

select undef,undef,undef,0.1;

undef $timer3;

$log->error('QQQ E');

ok(!$triggered, "logging hasn't happened yet");
undef $log;
ok($triggered, "log happened");
