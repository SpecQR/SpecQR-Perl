use strict; use warnings; use utf8;
use Test::More;
use lib 'lib';
use SpecQR::StructuredAppend qw(:all);
use SpecQR::Segments qw(numeric alphanumeric new_segment byte_segment fnc1 eci);
use SpecQR::API qw(diagnostics);
use SpecQR::Error ();
sub error_code { my($code,$body,$label)=@_; eval {$body->()}; my $e=$@; ok(ref($e) eq 'SpecQR::Error'&&$e->{code} eq $code,$label) or diag("$e"); }
is(calculate_structured_append_parity('ABC'),64,'text parity'); is(calculate_structured_append_parity([0,255,1]),254,'byte parity');
is(calculate_structured_append_parity('漢字🙂'),do {my $p=0; require Encode;$p^=$_ for unpack('C*',Encode::encode('UTF-8','漢字🙂'));$p},'UTF8 parity');
my $text='ABCDEFGHIJKLMNOPQRSTUVWXYZ'x3;
my $set=generate_structured_append($text,{version=>1,errorCorrectionLevel=>'M'},16,1);
ok($set->{total}>=2&&$set->{total}<=16,'multi symbol'); is($set->{parity},calculate_structured_append_parity($text),'set parity'); is($set->{inputLength},length($text),'input scalar length');
is($set->{diagnostics}{split_strategy},'greedy-largest-fitting','text strategy'); is($set->{diagnostics}{version_selection},'fixed','fixed version');
my @parts;
for my $i (0..$#{$set->{symbols}}) {
 my $q=$set->{symbols}[$i]; my $d=$set->{diagnostics}{symbols}[$i];
 is($q->{segments}[0]{mode},'structured-append','SA header'); is($q->{diagnostics}{structured_append}{index},$i+1,'header index'); is($q->{version},1,'same version');
 push @parts,{index=>$i+1,total=>$set->{total},parity=>$set->{parity},data=>substr($text,$d->{input_start},$d->{input_length})};
}
is(merge_structured_append_parts([reverse @parts])->{data},$text,'merge reverse');
for my $shift (0..$#parts) { my @rot=(@parts[$shift..$#parts],@parts[0..$shift-1]); @rot=@parts if !$shift; is(merge_structured_append_parts(\@rot)->{data},$text,'merge permutation'); }
my $copy=diagnostics($set); $copy->{total}=99; isnt($set->{diagnostics}{total},99,'diagnostics copied');
my @bytes=0..255; my $binary=generate_structured_append(\@bytes,{version=>2,errorCorrectionLevel=>'L'},16); my @bparts;
for my $i (0..$#{$binary->{symbols}}) { my $d=$binary->{diagnostics}{symbols}[$i]; push @bparts,{index=>$i+1,total=>$binary->{total},parity=>$binary->{parity},data=>[@bytes[$d->{input_start}..$d->{input_start}+$d->{input_length}-1]]}; }
is_deeply(merge_structured_append_parts([reverse @bparts])->{data},\@bytes,'binary merge all byte values');
my $unicode='漢字🙂かな'x12; my $u=generate_structured_append($unicode,{version=>2,errorCorrectionLevel=>'M'},16); my @up;
for my $i (0..$#{$u->{symbols}}) { my $d=$u->{diagnostics}{symbols}[$i]; push @up,{index=>$i+1,total=>$u->{total},parity=>$u->{parity},data=>substr($unicode,$d->{input_start},$d->{input_length})}; }
is(merge_structured_append_parts(\@up)->{data},$unicode,'Unicode scalar safe split');
my $segs=[numeric('1234567890'),new_segment('byte','x'x90),alphanumeric('END')];
my $manual=generate_segments_structured_append($segs,{version=>1,errorCorrectionLevel=>'M'},16,1,'full');
is($manual->{inputLength},3,'manual input segment count'); is($manual->{diagnostics}{split_unit_count},92,'byte-only split units'); is(scalar @{$manual->{diagnostics}{split_units}},92,'full detail'); is($manual->{diagnostics}{split_strategy},'segment-boundary-byte-chunk','manual strategy');
is($manual->{parity},calculate_structured_append_segments_parity($segs),'manual parity');
error_code('INVALID_INPUT',sub {generate_structured_append('A')},'single symbol rejects');
error_code('INVALID_INPUT',sub {generate_structured_append('')},'empty rejects');
for my $o ({gs1=>1},{fnc1=>1},{eciAssignment=>26},{fnc1Second=>'A'},{boostErrorCorrection=>1}) { error_code($o->{gs1}?'INVALID_GS1':'INVALID_MODE',sub {generate_structured_append($text,$o)},'incompatible option rejects'); }
error_code('INVALID_MODE',sub {generate_structured_append($text,{},1)},'maxSymbols range');
error_code('INVALID_MODE',sub {generate_segments_structured_append($segs,{mode=>'byte'})},'manual forced mode rejects');
error_code('INVALID_GS1',sub {generate_segments_structured_append([fnc1(),numeric('12')])},'manual FNC1 rejects');
error_code('INVALID_MODE',sub {generate_segments_structured_append([eci(26),numeric('12')])},'manual ECI rejects');
error_code('DATA_TOO_LONG',sub {generate_segments_structured_append([numeric('1'x80)],{version=>1,errorCorrectionLevel=>'H'})},'non-byte manual segment not split');
error_code('INVALID_INPUT',sub {merge_structured_append_parts([])},'empty merge');
error_code('INVALID_INPUT',sub {merge_structured_append_parts([@parts,$parts[0]])},'duplicate merge');
error_code('INVALID_INPUT',sub {merge_structured_append_parts([@parts[0..$#parts-1]])},'missing merge');
my @bad=map {{%$_}} @parts; $bad[0]{parity}^=1; error_code('INVALID_INPUT',sub {merge_structured_append_parts(\@bad)},'parity mismatch');
@bad=map {{%$_}} @parts; $bad[0]{data}.='a'; error_code('INVALID_INPUT',sub {merge_structured_append_parts(\@bad)},'content checksum mismatch');
for my $part ({index=>1,total=>2,parity=>0,data=>[256]},{index=>1,total=>2,parity=>0,data=>[1.5]},{index=>'1',total=>2,parity=>0,data=>'a'},{index=>1,total=>2,parity=>0,data=>{}}) { error_code('INVALID_INPUT',sub {merge_structured_append_parts([$part])},'malformed part'); }

{ package SATieValue; sub TIESCALAR {bless {v=>$_[1]},$_[0]} sub FETCH {$_[0]{v}} }
tie my $tied_input,'SATieValue',$text;
error_code('INVALID_INPUT',sub {generate_structured_append($tied_input,{version=>1})},'tied SA input rejects');
error_code('INVALID_INPUT',sub {calculate_structured_append_parity($tied_input)},'tied parity input rejects');
tie my $tied_parts,'SATieValue',\@parts;
error_code('INVALID_INPUT',sub {merge_structured_append_parts($tied_parts)},'tied merged parts rejects');
tie my $tied_segments,'SATieValue',$segs;
error_code('INVALID_INPUT',sub {generate_segments_structured_append($tied_segments,{version=>1})},'tied manual input rejects');
error_code('INVALID_INPUT',sub {calculate_structured_append_segments_parity($tied_segments)},'tied manual parity input rejects');

my $merged_owned=merge_structured_append_parts(\@parts); ${$merged_owned->{diagnostics}{parity_check}{matches}}=0;
ok(JSON::PP::true(),'merge boolean does not alias process-global true');
ok(merge_structured_append_parts(\@parts)->{diagnostics}{parity_check}{matches},'later merge booleans unaffected');
done_testing;
