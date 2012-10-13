use strict;

use Test::More tests => 3;

use Log::Defer;

#use Data::Dumper;


my $log = Log::Defer->new({ cb => sub {
  my $msg = shift;

  #print Dumper($msg) . "\n";

  ok(@{ $msg->{logs} } == 2, '2 log messages');
  ok($msg->{logs}->[1]->[2] eq 'B4', 'delayed sub execution worked');
  ok($msg->{logs}->[1]->[3]->{asdf} == 5, 'delayed sub execution can return array');
},

verbosity => 20});


$log->error("A");
$log->warn(sub { return ("B" . (2 + 2), { asdf => 5, }); });
$log->info("C");
$log->debug(sub { die "shouldn't happen" });
