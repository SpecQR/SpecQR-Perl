package SpecQR::Tables;
use 5.026; use strict; use warnings; use Exporter "import"; use SpecQR::Error qw(fail require_range require_string);
our @EXPORT_OK=qw(@ERROR_CORRECTION_LEVELS validate_version level_index format_bits qr_size raw_codeword_count block_info data_codeword_count alignment_positions character_count_bits);
our @ERROR_CORRECTION_LEVELS=qw(L M Q H);
my @EccCodewordsPerBlock = (
[7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
  [10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28],
  [13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
  [17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
);
my @NumErrorCorrectionBlocks = (
[1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25],
  [1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49],
  [1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68],
  [1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81],
);
sub validate_version { require_range($_[0],1,40,'QR version','INVALID_VERSION'); return }
sub level_index { require_string($_[0],'ECC','INVALID_ECC_LEVEL'); for my $i(0..3) {return $i if $_[0] eq $ERROR_CORRECTION_LEVELS[$i]} fail('INVALID_ECC_LEVEL','ECC must be L, M, Q, or H') }
sub format_bits { (1,0,3,2)[level_index($_[0])] }
sub qr_size { validate_version($_[0]); 4*$_[0]+17 }
sub raw_codeword_count { my($v)=@_; validate_version($v); my $r=(16*$v+128)*$v+64; if($v>=2) {my $n=int($v/7)+2; $r-=(25*$n-10)*$n-55; $r-=36 if $v>=7} int($r/8) }
sub block_info { my($v,$l)=@_;validate_version($v);my $i=level_index($l);my $b=$NumErrorCorrectionBlocks[$i][$v-1]; my $e=$EccCodewordsPerBlock[$i][$v-1]; my $r=raw_codeword_count($v); {blocks=>$b,eccPerBlock=>$e,rawCodewords=>$r,dataCodewords=>$r-$b*$e} }
sub data_codeword_count { block_info(@_)->{dataCodewords} }
sub alignment_positions { my($v)=@_;validate_version($v);return [] if $v==1; my $n=int($v/7)+2; my $den=$n*2-2; my $step=$v==32?26:int(($v*4+4+$den-1)/$den)*2; return [6,map {qr_size($v)-7-$_*$step} reverse 0..$n-2] }
sub character_count_bits { my($v,$m)=@_;validate_version($v);require_string($m,'Mode','INVALID_MODE');my $g=$v<=9?0:$v<=26?1:2;my %w=(numeric=>[10,12,14],alphanumeric=>[9,11,13],byte=>[8,16,16],kanji=>[8,10,12]);fail('INVALID_MODE','Expected a data mode') unless exists $w{$m};$w{$m}[$g] }
1;
