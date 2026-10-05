use strict;
use warnings;
use ExtUtils::MakeMaker;
WriteMakefile(
 NAME => 'SpecQR', VERSION_FROM => 'lib/SpecQR.pm',
 ABSTRACT => 'Dependency-free native Perl QR Model 2 encoder',
 AUTHOR => 'SpecQR contributors', LICENSE => 'mit',
 MIN_PERL_VERSION => '5.042003',
 PREREQ_PM => {}, TEST_REQUIRES => {'Test::More'=>0,'JSON::PP'=>0},
 EXE_FILES => ['script/specqr'],
 test => {TESTS => 't/*.t'},
 META_MERGE => { 'meta-spec'=>{version=>2}, no_index=>{directory=>[qw(t script verification examples)]}, resources=>{repository=>{type=>'git',url=>'https://github.com/SpecQR/SpecQR-Perl.git',web=>'https://github.com/SpecQR/SpecQR-Perl'}} },
);
