package Log::Defer::Viz;

use strict;

use Carp qw/croak/;




sub viz {
  my %arg = @_;

  my $width = $arg{width} || 80;
  my $timers = $arg{timers} || croak "need timers";

  my @timer_names = sort { $timers->{$a}->[0] <=> $timers->{$b}->[0] } keys %$timers;
  my @timer_names_by_end_time = sort { $timers->{$a}->[1] <=> $timers->{$b}->[1] } keys %$timers;

  my $output = '';


  ## Scan some information

  my $max_time = 0;
  my $max_namelen = 11;

  foreach my $timer_name (@timer_names) {
    my $timer = $timers->{$timer_name};

    $max_time = $timer->[1] if $timer->[1] > $max_time;
    $max_namelen = length($timer_name)+1 if length($timer_name)+1 > $max_namelen;
  }


  ## Bar graph plots

  my $scaling = ($width - $max_namelen - 8) / $max_time;

  foreach my $timer_name (@timer_names) {
    my $timer = $timers->{$timer_name};
    $output .= sprintf("%${max_namelen}s ", $timer_name);

    $output .= ' ' x int($timer->[0] * $scaling);

    my $bar_width = int(($timer->[1] - $timer->[0]) * $scaling) - 1;

    if ($bar_width > 0) {
      $output .= '|';
      $output .= '=' x $bar_width;
      $output .= '|';
    } else {
      $output .= 'X';
    }

    $output .= "\n";
  }


  $output .= '_' x $width . "\n";


  ## Time legend

  my $seen = {};

  $output .= 'times in ms ';
  $output .= ' ' x ($max_namelen - 11);
  $output .= render_time_legend($max_time, $scaling, [ map { $timers->{$_}->[0] } @timer_names ], $seen);

  $output .= ' ' x ($max_namelen + 1);
  $output .= render_time_legend($max_time, $scaling, [ map { $timers->{$_}->[1] } @timer_names_by_end_time ], $seen);

  return $output;
}



sub render_time_legend {
  my ($max_time, $scaling, $vals, $seen) = @_;

  my $output = '';

  my $last_time;
  my $last_time_str_len = 0;

  foreach my $val (@$vals) {
    next if defined $last_time &&
            (abs($last_time - $val) / $max_time) < 0.05;

    my $sep_len = int($scaling * ($val - ($last_time || 0))) - $last_time_str_len;
    $sep_len = 1 if $sep_len < 1 && defined $last_time;
    $output .= ' ' x $sep_len;

    my $time_str = sprintf("%.1f", $val * 1000);

    if ($seen->{$time_str}) {
      $last_time_str_len = 0;
    } else {
      $output .= $time_str;
      $last_time_str_len = length($time_str);
      $seen->{$time_str} = 1;
    }

    $last_time = $val;
  }

  $output .= "\n";

  return $output
}


1;
