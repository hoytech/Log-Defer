#!/usr/bin/env perl

use strict;

use Test::More tests => 1;

use Log::Defer::Viz;


print "\n\n" . Log::Defer::Viz::viz(timers => {
          "doing main thing" => [
             0.000224,
             0.100655
          ],
          "sent reply" => [
             0.100663,
             0.100740
          ],
          "fetch cache" => [
             0.032724,
             0.080655
          ],
          "DB lookup" => [
             0.000281,
             0.032386
          ],
          "reload blah blah" => [
             0.032380,
             0.119233
          ],
       });

print "\n\n" . Log::Defer::Viz::viz(timers => {
         'blah' => [
            0.123413,
            8.832888,
          ],
         'hello' => [
            0.923413,
            2.293332,
          ],
       });



print "\n\n";


ok(1, 'did a viz');
