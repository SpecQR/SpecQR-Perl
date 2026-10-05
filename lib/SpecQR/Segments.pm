package SpecQR::Segments;
use 5.026; use strict; use warnings; use utf8;
use Exporter 'import'; use Encode (); use SpecQR::Error qw(fail require_string require_array require_hash require_range require_bool is_string); use SpecQR::Tables qw(validate_version character_count_bits); use SpecQR::KanjiData qw(kanji_codepoint);
use constant {MAX_PAYLOAD_UNITS=>1_000_000,MAX_MANUAL_SEGMENTS=>16_384,MAX_SINGLE_SYMBOL_CHARACTERS=>7089,MAX_SINGLE_SYMBOL_DATA_BITS=>23648};
our @DATA_MODES=qw(numeric alphanumeric kanji byte); our @CONTROL_MODES=qw(eci fnc1 fnc1-second structured-append);
our @EXPORT_OK=qw(MAX_PAYLOAD_UNITS MAX_MANUAL_SEGMENTS MAX_SINGLE_SYMBOL_CHARACTERS MAX_SINGLE_SYMBOL_DATA_BITS @DATA_MODES @CONTROL_MODES strict_text encode_utf8 kanji_code can_encode_kanji kanji_value alpha_value new_segment byte_segment numeric alphanumeric kanji eci fnc1 fnc1_second structured_append_segment mode is_control is_binary text logical_bytes segment_count count character_count byte_count assignment_number application_indicator application_indicator_codeword index total parity payload_bit_length bit_length bits validate_segment normalize_segments segments_bit_length segments_bits);
my $ALPHA='0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:'; my %DATA=map {$_=>1} @DATA_MODES; my %CONTROL=map {$_=>1} @CONTROL_MODES;
sub strict_text { for my $arg (@_) { fail('INVALID_INPUT','Tied values are not supported') if tied($arg) }
 my($s)=@_;require_string($s,'Text');fail('INVALID_INPUT','Text must be a well-formed Perl character string') unless utf8::valid($s);fail('DATA_TOO_LONG','Text resource limit exceeded') if length($s)>MAX_PAYLOAD_UNITS;
 fail('INVALID_INPUT','Non-ASCII text must be a decoded Perl character string') if !utf8::is_utf8($s) && $s=~/[^\x00-\x7f]/;
 fail('INVALID_INPUT','Text must contain Unicode scalars') if !utf8::valid($s) || $s=~/[^\x{0000}-\x{d7ff}\x{e000}-\x{10ffff}]/;
 return [split //,$s];
}
sub encode_utf8 { for my $arg (@_) { fail('INVALID_INPUT','Tied values are not supported') if tied($arg) } my($s)=@_;strict_text($s); Encode::encode('UTF-8',$s,Encode::FB_CROAK|Encode::LEAVE_SRC) }
sub kanji_code { my($c)=@_;return -1 unless is_string($c) && length($c)==1;kanji_codepoint(ord($c)) }
sub can_encode_kanji { kanji_code($_[0])>=0 ? 1:0 }
sub kanji_value { my $c=kanji_code($_[0]);fail('INVALID_MODE','Character is not QR Kanji encodable') if $c<0;my $a=$c-($c<=0x9ffc?0x8140:0xc140);($a>>8)*0xc0+($a&255) }
sub alpha_value { my($c)=@_;return -1 unless is_string($c)&&length($c)==1&&ord($c)<128;CORE::index($ALPHA,$c) }
sub _base { {mode=>$_[0],data=>'',binary=>0,characterCount=>0,assignmentNumber=>-1,applicationIndicator=>'',index=>-1,total=>-1,parity=>-1} }
sub new_segment { for my $arg (@_) { fail('INVALID_INPUT','Tied values are not supported') if tied($arg) }
 my($m,$s)=@_;require_string($m,'Mode','INVALID_MODE');fail('INVALID_MODE','Expected a data mode') unless $DATA{$m};my $chars=strict_text($s);
 for my $c(@$chars) {fail('INVALID_MODE','Numeric data must contain digits') if $m eq 'numeric'&&$c!~/\A[0-9]\z/;fail('INVALID_MODE','Invalid alphanumeric character') if $m eq 'alphanumeric'&&alpha_value($c)<0;fail('INVALID_MODE','Invalid Kanji character') if $m eq 'kanji'&&!can_encode_kanji($c)}
 return {%{_base($m)},data=>$s,characterCount=>scalar(@$chars)};
}
sub byte_segment { for my $arg (@_) { fail('INVALID_INPUT','Tied values are not supported') if tied($arg) }
 my($d)=@_;my $s;
 if(ref($d) eq 'ARRAY') {require_array($d,'Binary bytes');fail('DATA_TOO_LONG','Payload resource limit exceeded') if @$d>MAX_PAYLOAD_UNITS;for my $b(@$d){require_range($b,0,255,'Byte')} $s=pack('C*',@$d)}
 else {require_string($d,'Binary data');fail('INVALID_INPUT','Binary data must be an unflagged octet string or byte array') if utf8::is_utf8($d);fail('DATA_TOO_LONG','Payload resource limit exceeded') if length($d)>MAX_PAYLOAD_UNITS;$s=$d}
 return {%{_base('byte')},data=>$s,binary=>1};
}
sub numeric { new_segment('numeric',$_[0]) } sub alphanumeric { new_segment('alphanumeric',$_[0]) } sub kanji { new_segment('kanji',$_[0]) }
sub eci { for my $arg (@_) { fail('INVALID_INPUT','Tied values are not supported') if tied($arg) } require_range($_[0],0,999999,'ECI assignment','INVALID_ECI');return {%{_base('eci')},assignmentNumber=>$_[0]} }
sub fnc1 { _base('fnc1') }
sub fnc1_second { for my $arg (@_) { fail('INVALID_INPUT','Tied values are not supported') if tied($arg) } my($v)=@_;require_string($v,'FNC1 second indicator','INVALID_MODE');fail('INVALID_MODE','FNC1 second indicator must be two ASCII digits or one Latin letter') unless $v=~/\A(?:[0-9]{2}|[A-Za-z])\z/;return {%{_base('fnc1-second')},applicationIndicator=>$v} }
sub structured_append_segment { for my $arg (@_) { fail('INVALID_INPUT','Tied values are not supported') if tied($arg) } my($i,$t,$p)=@_;require_range($i,1,16,'SA index','INVALID_MODE');require_range($t,2,16,'SA total','INVALID_MODE');require_range($p,0,255,'SA parity','INVALID_MODE');fail('INVALID_MODE','SA index must not exceed total') if $i>$t;return {%{_base('structured-append')},index=>$i,total=>$t,parity=>$p} }
sub _validated { for my $arg (@_) { fail('INVALID_INPUT','Tied values are not supported') if tied($arg) }
 my($s)=@_;require_hash($s,'Segment','INVALID_MODE');my $m=$s->{mode};require_string($m,'Segment mode','INVALID_MODE');
 if($DATA{$m}) { my $bin=exists($s->{binary})?require_bool($s->{binary},'Segment binary'):0;fail('INVALID_MODE','Binary data requires byte mode') if $bin&&$m ne 'byte';return $bin?byte_segment($s->{data}):new_segment($m,$s->{data}) }
 return eci($s->{assignmentNumber}) if $m eq 'eci';return fnc1() if $m eq 'fnc1';return fnc1_second($s->{applicationIndicator}) if $m eq 'fnc1-second';return structured_append_segment(@$s{qw(index total parity)}) if $m eq 'structured-append';fail('INVALID_MODE','Uninitialized or unsupported segment');
}
sub validate_segment { _validated($_[0]);return }
sub mode { _validated($_[0])->{mode} }
sub is_control { my $s=_validated($_[0]);$CONTROL{$s->{mode}}?1:0 }
sub is_binary { _validated($_[0])->{binary} }
sub text { _validated($_[0])->{data} }
sub logical_bytes { my $s=_validated($_[0]);my $bytes=$s->{binary}?$s->{data}:encode_utf8($s->{data});[unpack('C*',$bytes)] }
sub _count { my($s)=@_;return 0 if $CONTROL{$s->{mode}};return length($s->{binary}?$s->{data}:Encode::encode('UTF-8',$s->{data})) if $s->{mode} eq 'byte';length($s->{data}) }
sub segment_count { _count(_validated($_[0])) } sub count { segment_count(@_) }
sub character_count { _validated($_[0])->{characterCount} }
sub byte_count { my $s=_validated($_[0]);return 2*length($s->{data}) if $s->{mode} eq 'kanji';length($s->{binary}?$s->{data}:Encode::encode('UTF-8',$s->{data})) }
sub assignment_number { _validated($_[0])->{assignmentNumber} } sub application_indicator { _validated($_[0])->{applicationIndicator} }
sub application_indicator_codeword { my $s=_validated($_[0]);return -1 if $s->{mode} ne 'fnc1-second';my $v=$s->{applicationIndicator};length($v)==2?0+$v:ord($v)+100 }
sub index { _validated($_[0])->{index} } sub total { _validated($_[0])->{total} } sub parity { _validated($_[0])->{parity} }
sub payload_bit_length {my($m,$n)=@_;require_string($m,'Mode','INVALID_MODE');require_range($n,0,4*MAX_PAYLOAD_UNITS,'Payload count');return int($n/3)*10+(0,4,7)[$n%3] if $m eq 'numeric';return int($n/2)*11+($n%2)*6 if $m eq 'alphanumeric';return $n*13 if $m eq 'kanji';return $n*8 if $m eq 'byte';fail('INVALID_MODE','Expected data mode')}
sub _bit_length {my($s,$v)=@_;my $m=$s->{mode};return $s->{assignmentNumber}<128?12:$s->{assignmentNumber}<16384?20:28 if $m eq 'eci';return 4 if $m eq 'fnc1';return 12 if $m eq 'fnc1-second';return 20 if $m eq 'structured-append';4+character_count_bits($v,$m)+payload_bit_length($m,_count($s))}
sub bit_length {validate_version($_[1]);_bit_length(_validated($_[0]),$_[1])}
sub _append {my($out,$value,$width)=@_;push @$out,map {($value>>$_)&1} reverse 0..$width-1}
sub bits { for my $arg (@_) { fail('INVALID_INPUT','Tied values are not supported') if tied($arg) }
 my($original,$v)=@_;validate_version($v);my $s=_validated($original);my $m=$s->{mode};my $n=_count($s);my $nb=_bit_length($s,$v);
 fail('DATA_TOO_LONG','Segment count does not fit') if !$CONTROL{$m}&&$n>=(1<<character_count_bits($v,$m));fail('DATA_TOO_LONG','Segment exceeds single-symbol capacity') if $nb>MAX_SINGLE_SYMBOL_DATA_BITS;
 my %indicator=(numeric=>1,alphanumeric=>2,byte=>4,kanji=>8,eci=>7,fnc1=>5,'fnc1-second'=>9,'structured-append'=>3);my @out;_append(\@out,$indicator{$m},4);
 if($m eq 'eci') {my $a=$s->{assignmentNumber};if($a<128){_append(\@out,$a,8)}elsif($a<16384){_append(\@out,2,2);_append(\@out,$a,14)}else{_append(\@out,6,3);_append(\@out,$a,21)}}
 elsif($m eq 'fnc1-second'){_append(\@out,application_indicator_codeword($s),8)}
 elsif($m eq 'structured-append'){_append(\@out,$s->{index}-1,4);_append(\@out,$s->{total}-1,4);_append(\@out,$s->{parity},8)}
 elsif($m ne 'fnc1'){
  _append(\@out,$n,character_count_bits($v,$m));my $d=$s->{data};
  if($m eq 'byte'){my $b=$s->{binary}?$d:Encode::encode('UTF-8',$d);_append(\@out,$_,8) for unpack('C*',$b)}
  elsif($m eq 'numeric'){for(my $i=0;$i<length($d);$i+=3){my $part=substr($d,$i,3);_append(\@out,0+$part,(4,7,10)[length($part)-1])}}
  elsif($m eq 'alphanumeric'){my $i=0;for(;$i+1<length($d);$i+=2){_append(\@out,CORE::index($ALPHA,substr($d,$i,1))*45+CORE::index($ALPHA,substr($d,$i+1,1)),11)}_append(\@out,CORE::index($ALPHA,substr($d,$i,1)),6) if $i<length($d)}
  else {_append(\@out,kanji_value($_),13) for split //,$d}
 }
 fail('INVALID_INPUT','Inconsistent segment bit length') if @out!=$nb;return \@out;
}
sub normalize_segments { for my $arg (@_) { fail('INVALID_INPUT','Tied values are not supported') if tied($arg) }
 my($values)=@_;require_array($values,'Segments');fail('DATA_TOO_LONG','Manual segment resource limit exceeded') if @$values>MAX_MANUAL_SEGMENTS;my(@out,%controls);my $units=0;
 for my $i(0..$#$values){my $s=_validated($values->[$i]);$units+=$s->{binary}?length($s->{data}):$s->{characterCount};fail('DATA_TOO_LONG','Manual payload resource limit exceeded') if $units>MAX_PAYLOAD_UNITS;my $m=$s->{mode};if($CONTROL{$m}){++$controls{$m};fail($m eq 'fnc1'?'INVALID_GS1':'INVALID_MODE','Control must be first and unique') if $m ne 'eci'&&($controls{$m}>1||$i!=0)}push @out,$s}
 fail($controls{fnc1}?'INVALID_GS1':'INVALID_MODE','FNC1, ECI, and SA cannot be combined') if keys(%controls)>1;return \@out;
}
sub segments_bit_length { for my $arg (@_) { fail('INVALID_INPUT','Tied values are not supported') if tied($arg) }my($values,$v)=@_;validate_version($v);my $s=normalize_segments($values);my $n=0;$n+=_bit_length($_,$v) for @$s;return $n}
sub segments_bits { for my $arg (@_) { fail('INVALID_INPUT','Tied values are not supported') if tied($arg) }my($values,$v)=@_;my $s=normalize_segments($values);fail('DATA_TOO_LONG','Segments exceed single-symbol capacity') if segments_bit_length($s,$v)>MAX_SINGLE_SYMBOL_DATA_BITS;my @out;push @out,@{bits($_,$v)} for @$s;\@out}
1;
