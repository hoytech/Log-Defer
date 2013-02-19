use ExtUtils::MakeMaker;

my $preop =
    'perldoc -uT $(VERSION_FROM) | tee $(DISTVNAME)/README.pod > README.pod;' .
    'pod2text README.pod | tee $(DISTVNAME)/README > README';

my %args = (
  NAME => 'Log::Defer',
  VERSION_FROM => 'lib/Log/Defer.pm',
  LIBS => [''],
  LICENSE => 'perl',
  INC => '-I lib/',
  PREREQ_PM => {
    'Guard' => 0,
  },
  dist => {
    PREOP => $preop,
  },
);


my $eummv = eval ($ExtUtils::MakeMaker::VERSION);
if ($eummv >= 6.45) {
    $args{META_MERGE} = {
        resources => {
            repository => 'git://github.com/hoytech/Log-Defer.git',
            bugtracker => 'https://github.com/hoytech/Log-Defer/issues',
        },
    };
}

WriteMakefile(%args);
