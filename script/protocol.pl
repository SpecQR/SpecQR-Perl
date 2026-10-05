package SpecQR::Protocol;
use strict;
use warnings;
use JSON::PP ();
use MIME::Base64 qw(encode_base64);
use Scalar::Util qw(blessed);
use SpecQR::Error ();
use SpecQR::Segments ();
use SpecQR::Tables ();
use SpecQR::Core ();
use SpecQR::API ();
use SpecQR::GS1 ();
use SpecQR::Render ();
use SpecQR::StructuredAppend ();
sub bad { SpecQR::Error::fail('INVALID_INPUT',$_[0]); }
sub object { bad('Expected object') unless ref($_[0]) eq 'HASH'; $_[0] }
sub field { my ($r,$key,$fallback)=@_;object($r);exists $r->{$key}?$r->{$key}:$fallback }
sub text_value { SpecQR::Error::require_string($_[0],'Value') }
sub wire_segment {
 my ($r)=@_;object($r);my $m=text_value($r->{mode});my $v=field($r,'text',$r->{data});
 return SpecQR::Segments::new_segment($m,text_value($v)) if $m eq 'numeric'||$m eq 'alphanumeric'||$m eq 'kanji';
 if($m eq 'byte') { return SpecQR::Segments::byte_segment($r->{bytes}) if exists $r->{bytes}; return SpecQR::Segments::byte_segment($v) if ref($v) eq 'ARRAY';return SpecQR::Segments::new_segment('byte',text_value($v)); }
 return SpecQR::Segments::eci($r->{assignmentNumber}) if $m eq 'eci';
 return SpecQR::Segments::fnc1() if $m eq 'fnc1';
 return SpecQR::Segments::fnc1_second($r->{applicationIndicator}) if $m eq 'fnc1-second';
 return SpecQR::Segments::structured_append_segment(@{$r}{qw(index total parity)}) if $m eq 'structured-append';
 SpecQR::Error::fail('INVALID_MODE','Unknown segment mode');
}
sub rows { [map { join('',map {$_?'1':'0'} @$_) } @{$_[0]}] }
sub packed { my ($m)=@_;my $bits=join('',@{rows($m)});$bits.='0'x((8-length($bits)%8)%8);encode_base64(pack('B*',$bits),'') }
sub hex_bytes { unpack('H*',pack('C*',@{$_[0]})) }
sub wire_symbol {
 my ($q,$r)=@_;$r||={};my $out={version=>$q->{version},ecc=>$q->{errorCorrectionLevel},mask=>$q->{maskPattern},data=>hex_bytes($q->{dataCodewords}),codewords=>hex_bytes($q->{codewords}),matrix=>rows($q->{matrix}),matrixPacked=>packed($q->{matrix}),segments=>[map { +{mode=>$_->{mode},count=>SpecQR::Segments::segment_count($_)} } @{$q->{segments}}]};
 if(exists $r->{pngScale}) { my %ro=map {$_=>$q->{options}{$_}} qw(margin scale foreground background);$ro{scale}=$r->{pngScale};$out->{png}=unpack('H*',SpecQR::Render::to_png($q,\%ro)); }
 $out->{diagnostics}=$q->{diagnostics} if $r->{diagnostics};
 if($r->{renders}) {$out->{svg}=SpecQR::Render::to_svg($q);$out->{svgDataUrl}=SpecQR::Render::to_svg_data_url($q);$out->{pngDataUrl}=SpecQR::Render::to_png_data_url($q)}
 $out;
}
sub _run {
 my ($r)=@_;object($r);my $command=field($r,'command','generate')//'generate';
 if($command eq 'gf'){my @b;for my $a(0..255){push @b,SpecQR::Core::gf_multiply($a,$_) for 0..255}return {bytes=>hex_bytes(\@b)}}
 if($command eq 'rs'){my $d=$r->{degree};my @b=map {($_*61+$d)&255} 0..299;return {generator=>hex_bytes(SpecQR::Core::reed_solomon_divisor($d)),remainder=>hex_bytes(SpecQR::Core::reed_solomon_remainder(\@b,$d))}}
 if($command eq 'raw'){
  my($v,$e,$seed,$mask)=@{$r}{qw(version ecc seed mask)};my $ordinal=index('LMQH',$e);my $count=SpecQR::Tables::data_codeword_count($v,$e);my @b=map {$seed==0?0:$seed==1?255:(($_*149+$v*43+$ordinal*89+$seed*67)^($_>>($seed+1)))&255} 0..$count-1;
  my $inter=SpecQR::Core::interleave_codewords(\@b,$v,$e);my $q=SpecQR::Core::build_matrix($inter->{codewords},$v,$e,$mask);
  return {data=>hex_bytes(\@b),codewords=>hex_bytes($inter->{codewords}),matrix=>rows($q->{matrix}),matrixPacked=>packed($q->{matrix}),mask=>$q->{maskPattern},penalty=>$q->{penalty},penalties=>[map {$_->{penalty}} @{$q->{maskPenalties}}]};
 }
 if($command eq 'gs1-build'){return {value=>SpecQR::GS1::create_gs1_element_string($r->{elements})}}
 if($command eq 'digital-link-build'){return {value=>SpecQR::GS1::create_gs1_digital_link($r->{elements},$r->{linkOptions}//{})}}
 if($command eq 'digital-link-parse'){return SpecQR::GS1::parse_gs1_digital_link($r->{url})}
 if($command eq 'digital-link-validate'){return SpecQR::GS1::validate_gs1_digital_link($r->{url})}
 if($command eq 'digital-link-normalize'){return {value=>SpecQR::GS1::normalize_gs1_digital_link($r->{url})}}
 my $rawopts=$r->{options}//{};object($rawopts);my $o={%$rawopts};for my $key(qw(optimizeSegments allowKanji boostErrorCorrection gs1 fnc1)){next unless exists $o->{$key};bad('Expected JSON boolean') unless JSON::PP::is_bool($o->{$key})}
 if(exists $o->{version} && defined $o->{version} && !(SpecQR::Error::is_string($o->{version}) && $o->{version} eq 'auto')){SpecQR::Error::require_range($o->{version},1,40,'Version','INVALID_VERSION')}
 if(exists $o->{maskPattern} && defined $o->{maskPattern} && !(SpecQR::Error::is_string($o->{maskPattern}) && $o->{maskPattern} eq 'auto')){SpecQR::Error::require_range($o->{maskPattern},0,7,'Mask')}
 if(exists $o->{eci} && defined $o->{eci} && !JSON::PP::is_bool($o->{eci})){SpecQR::Error::require_range($o->{eci},0,999999,'ECI','INVALID_ECI')}
 if(exists($o->{fnc1Second}) && defined($o->{fnc1Second})){text_value($o->{fnc1Second});SpecQR::Segments::fnc1_second($o->{fnc1Second})}
 for my $key(qw(version maskPattern)){ $o->{$key}='auto' if exists($o->{$key}) && !defined($o->{$key}) }
 for my $key(qw(eci fnc1Second)){ delete $o->{$key} if exists($o->{$key}) && !defined($o->{$key}) }
 if($command eq 'capacity'){my $opts=SpecQR::API::normalize_options($o);my $c=SpecQR::API::get_capacity($opts->{version},$opts->{errorCorrectionLevel},$opts->{mode});return {maximum=>$c->{maximum},dataCodewords=>$c->{dataCodewords},capacityBits=>$c->{capacityBits},countBits=>$c->{characterCountBits}}}
 my $manual=exists $r->{segments};bad('Segments must be an array') if $manual && ref($r->{segments}) ne 'ARRAY';my $input=$manual?[map {wire_segment($_)} @{$r->{segments}}]:exists $r->{bytes}?$r->{bytes}:field($r,'text','');
 if($command eq 'estimate'||$command eq 'plan'){my $p=$manual?SpecQR::API::plan_segments($input,$o):SpecQR::API::plan($input,$o);return {fits=>$p->{ok}?JSON::PP::true:JSON::PP::false,version=>$p->{capacityVersion},requiredBits=>$p->{dataBitLength},capacityBits=>$p->{capacityBits}}}
 if($command eq 'structured-append'){
  my %opts=%$o;my $max=exists $opts{maxSymbols}?delete($opts{maxSymbols}):16;my $sa=$manual?SpecQR::StructuredAppend::generate_segments_structured_append($input,\%opts,$max):SpecQR::StructuredAppend::generate_structured_append($input,\%opts,$max);
  return {total=>$sa->{total},parity=>$sa->{parity},inputLength=>$sa->{inputLength},byteLength=>$sa->{byteLength},symbols=>[map {wire_symbol($_,$r)} @{$sa->{symbols}}],versions=>[map {$_->{version}} @{$sa->{symbols}}],masks=>[map {$_->{maskPattern}} @{$sa->{symbols}}]};
 }
 if($command eq 'generate'){return wire_symbol($manual?SpecQR::API::generate_segments($input,$o):SpecQR::API::generate($input,$o),$r)}
 bad('Unknown command');
}
sub run_request {
 my ($r)=@_;my $out=eval {_run($r)};my $e=$@;return $out unless $e;
 return {error=>'SpecQRError',isSpecQRError=>JSON::PP::true,code=>$e->{code},message=>$e->{message}} if blessed($e)&&$e->isa('SpecQR::Error');
 return {error=>'UnexpectedError',isSpecQRError=>JSON::PP::false,code=>'INTERNAL_ERROR',message=>"$e"};
}
1;
