package SpecQR::StructuredAppend;
use 5.026;
use strict;
use warnings;
use Exporter 'import';
use JSON::PP ();
use SpecQR::Error qw(fail require_range require_array require_hash require_bool require_string copy_json_checked);
use SpecQR::Tables qw(data_codeword_count character_count_bits);
use SpecQR::Segments qw(MAX_PAYLOAD_UNITS MAX_MANUAL_SEGMENTS strict_text encode_utf8 normalize_segments new_segment byte_segment structured_append_segment is_control is_binary text character_count byte_count segment_count segments_bit_length);
use SpecQR::Optimizer qw(create_segments new_segment_optimization_tracker append_character);
use SpecQR::API qw(normalize_options generate generate_segments);
our @EXPORT_OK=qw(calculate_structured_append_parity calculate_structured_append_segments_parity generate_structured_append generate_segments_structured_append merge_structured_append_parts);
our %EXPORT_TAGS=(all=>\@EXPORT_OK);
sub _reject_tied_args { for my $arg (@_) { fail('INVALID_INPUT','Tied values are not supported') if tied($arg); } }
sub _bool { my $v=$_[0]?1:0; bless \$v,'JSON::PP::Boolean' }
sub _min { $_[0]<$_[1]?$_[0]:$_[1] }
sub _max { $_[0]>$_[1]?$_[0]:$_[1] }
sub _xor { my $p=0; $p^=$_ for unpack('C*',$_[0]); $p }
sub _octets { my($s)=@_; is_binary($s)?text($s):encode_utf8(text($s)) }
sub calculate_structured_append_parity {
    _reject_tied_args(@_);
    my($input)=@_; return _xor(text(byte_segment($input))) if ref($input) eq 'ARRAY';
    strict_text($input); return _xor(encode_utf8($input));
}
sub _manual {
    my($values,$budget)=@_; $budget=MAX_PAYLOAD_UNITS unless defined $budget;
    require_array($values,'Segments'); fail('INVALID_INPUT','Structured Append needs nonempty manual segments') unless @$values;
    fail('DATA_TOO_LONG','Too many manual segments') if @$values>MAX_MANUAL_SEGMENTS;
    my $segments=normalize_segments($values); my $units=0;
    for my $s (@$segments) {
        fail('INVALID_GS1','Structured Append cannot be combined with FNC1') if $s->{mode} eq 'fnc1';
        fail('INVALID_MODE','Structured Append cannot include manual control segments') if is_control($s);
        my $n=is_binary($s)?byte_count($s):character_count($s);
        fail('INVALID_INPUT','Structured Append requires nonempty data segments') if !$n;
        fail('DATA_TOO_LONG','Manual payload exceeds Structured Append capacity') if $n>_min(MAX_PAYLOAD_UNITS,$budget)-$units;
        $units+=$n;
    }
    return $segments;
}
sub calculate_structured_append_segments_parity { _reject_tied_args(@_); my $p=0; $p^=_xor(_octets($_)) for @{_manual($_[0])}; $p }
sub _capacity { 8*data_codeword_count($_[1],$_[0]{errorCorrectionLevel}) }
sub _capacity_version { $_[0]{version} || $_[0]{maxVersion} }
sub _unit_budget { my($o,$max)=@_; $max*int(_max(0,_capacity($o,_capacity_version($o))-20)*3/10) }
sub _check {
    my($o,$max,$manual,$detail,$results)=@_;
    require_range($max,2,16,'maxSymbols','INVALID_MODE');
    require_string($detail,'Split unit detail'); require_string($results,'Symbol result detail');
    fail('INVALID_INPUT','Invalid Structured Append diagnostic detail') unless ($detail eq 'summary'||$detail eq 'full') && ($results eq 'output'||$results eq 'diagnostics');
    fail('INVALID_GS1','Structured Append cannot be combined with gs1') if $o->{gs1};
    fail('INVALID_MODE','Structured Append owns its header and cannot include other controls') if $o->{fnc1} || $o->{eciAssignment}>=0 || length($o->{fnc1Second}) || defined($o->{structuredAppend});
    fail('INVALID_MODE','Structured Append does not support ECC boosting') if $o->{boostErrorCorrection};
    fail('INVALID_MODE','Manual Structured Append preserves caller modes') if $manual && ($o->{mode} ne 'auto'||!$o->{optimizeSegments});
}
sub _numeric_bits { int($_[0]/3)*10+(0,4,7)[$_[0]%3] }
sub _payload_bits {
    my($mode,$n,$nb)=@_; return _numeric_bits($n) if $mode eq 'numeric';
    return int($n/2)*11+($n%2)*6 if $mode eq 'alphanumeric';
    return $n*13 if $mode eq 'kanji'; return $nb*8;
}
sub _segment_bits {
    my($mode,$n,$nb,$v)=@_; my $width=character_count_bits($v,$mode); my $count=$mode eq 'byte'?$nb:$n;
    return 1_000_000_000 if $count>=(1<<$width);
    return 4+$width+_payload_bits($mode,$n,$nb);
}
sub _offsets { my($chars)=@_; my @o=(0); push @o,$o[-1]+length(encode_utf8($_)) for @$chars; \@o }
sub _input_source {
    my($value,$o,$maximum)=@_; my $binary=ref($value) eq 'ARRAY'; my $v=_capacity_version($o);
    if($binary) {
        my $seg=byte_segment($value); my $n=byte_count($seg);
        fail('INVALID_INPUT','Structured Append needs at least two nonempty symbols') if !$n;
        fail('DATA_TOO_LONG','Input exceeds Structured Append capacity') if $n>_unit_budget($o,$maximum);
        fail('INVALID_MODE','Binary input requires byte mode') unless $o->{mode} eq 'auto'||$o->{mode} eq 'byte';
        fail('DATA_TOO_LONG','Input exceeds Structured Append capacity') if $n*8>$maximum*_max(0,_capacity($o,$v)-24-character_count_bits($v,'byte'));
        return {binary=>1,manual=>0,data=>text($seg),length=>$n,inputLength=>$n,byteLength=>$n,parity=>_xor(text($seg))};
    }
    my $chars=strict_text($value); my $n=@$chars;
    fail('INVALID_INPUT','Structured Append needs at least two nonempty symbols') if !$n;
    fail('DATA_TOO_LONG','Input exceeds Structured Append capacity') if $n>_unit_budget($o,$maximum);
    new_segment($o->{mode},$value) if $o->{mode} ne 'auto';
    my $bytes=encode_utf8($value); my $width=1_000_000;
    if($o->{mode} eq 'auto') { $width=_min($width,character_count_bits($v,$_)) for qw(numeric alphanumeric kanji byte); }
    else { $width=character_count_bits($v,$o->{mode}); }
    my $required=$o->{mode} eq 'auto'?_numeric_bits($n):_payload_bits($o->{mode},$n,length($bytes));
    fail('DATA_TOO_LONG','Input exceeds Structured Append capacity') if $required>$maximum*_max(0,_capacity($o,$v)-24-$width);
    return {binary=>0,manual=>0,data=>$value,characters=>$chars,offsets=>_offsets($chars),length=>$n,inputLength=>$n,byteLength=>length($bytes),parity=>_xor($bytes)};
}
sub _segment_source {
    my($values,$o,$maximum)=@_; my $segments=_manual($values,_unit_budget($o,$maximum)); my $v=_capacity_version($o);
    my $s={manual=>1,binary=>0,segments=>$segments,inputLength=>scalar(@$segments),length=>0,byteLength=>0,parity=>0,descriptors=>[]}; my $bits=0;
    for my $i (0..$#$segments) {
        my $seg=$segments->[$i]; my $n=is_binary($seg)?byte_count($seg):character_count($seg); my $bytes=_octets($seg); my $size=length($bytes);
        my $split=$seg->{mode} eq 'byte'?$n:1;
        my $d={segment=>$seg,sourceIndex=>$i,splitStart=>$s->{length},splitCount=>$split,byteStart=>$s->{byteLength},byteLength=>$size};
        $d->{offsets}=_offsets(strict_text(text($seg))) if $seg->{mode} eq 'byte'&&!is_binary($seg);
        push @{$s->{descriptors}},$d; $s->{length}+=$split; $s->{byteLength}+=$size; $s->{parity}^=_xor($bytes);
        $bits+=4+character_count_bits($v,$seg->{mode})+_payload_bits($seg->{mode},$n,$size);
    }
    fail('DATA_TOO_LONG','Segments exceed Structured Append capacity') if $bits>$maximum*_max(0,_capacity($o,$v)-20);
    return $s;
}
sub _input_slice { substr($_[0]{data},$_[1],$_[2]) }
sub _input_byte_length { my($s,$start,$n)=@_; $s->{binary}?$n:$s->{offsets}[$start+$n]-$s->{offsets}[$start] }
sub _ranges {
    my($s,$start,$n)=@_; my $finish=$start+$n; my($low,$high)=(0,scalar @{$s->{descriptors}});
    while($low<$high) { my $mid=$low+int(($high-$low)/2); my $d=$s->{descriptors}[$mid]; if($d->{splitStart}+$d->{splitCount}<=$start) {$low=$mid+1} else {$high=$mid} }
    my @r;
    for(my $i=$low;$i<@{$s->{descriptors}};$i++) {
        my $d=$s->{descriptors}[$i]; last if $d->{splitStart}>=$finish;
        my $overlap=_max($start,$d->{splitStart}); push @r,[$i,$overlap-$d->{splitStart},_min($finish,$d->{splitStart}+$d->{splitCount})-$overlap];
    }
    return \@r;
}
sub _range_bytes {
    my($d,$start,$n)=@_; return [$d->{byteStart},$d->{byteLength}] if $d->{segment}{mode} ne 'byte';
    return [$d->{byteStart}+$d->{offsets}[$start],$d->{offsets}[$start+$n]-$d->{offsets}[$start]] unless is_binary($d->{segment});
    return [$d->{byteStart}+$start,$n];
}
sub _source_bits {
    my($s,$start,$n,$o,$v)=@_; my $cap=_capacity($o,$v);
    if($s->{manual}) {
        my $r=20;
        for my $p (@{_ranges($s,$start,$n)}) { my $d=$s->{descriptors}[$p->[0]]; my $nb=_range_bytes($d,$p->[1],$p->[2])->[1]; my $len=$d->{segment}{mode} eq 'byte'?$p->[2]:character_count($d->{segment}); $r+=_segment_bits($d->{segment}{mode},$len,$nb,$v); last if $r>$cap; }
        return $r;
    }
    return 1_000_000_000 if _numeric_bits($n)>$cap-20;
    return 20+_segment_bits('byte',$n,$n,$v) if $s->{binary};
    return 20+_segment_bits($o->{mode},$n,_input_byte_length($s,$start,$n),$v) if $o->{mode} ne 'auto';
    if($o->{optimizeSegments}) {
        my $tracker=new_segment_optimization_tracker($v,$o->{allowKanji}); my $required=0;
        for my $i ($start..$start+$n-1) { $required=append_character($tracker,$s->{characters}[$i]); last if $required+20>$cap; }
        return $required+20;
    }
    my $data=create_segments(_input_slice($s,$start,$n),'auto',$v,0,-1,$o->{allowKanji});
    for my $seg (@$data) { return 1_000_000_000 if segment_count($seg)>=(1<<character_count_bits($v,$seg->{mode})); }
    return 20+segments_bit_length($data,$v);
}
sub _largest_prefix {
    my($s,$start,$maximum,$o,$v)=@_;
    if(!$s->{manual}&&!$s->{binary}&&$o->{mode} eq 'auto'&&$o->{optimizeSegments}) {
        my $tracker=new_segment_optimization_tracker($v,$o->{allowKanji}); my $cap=_capacity($o,$v)-20;
        for my $i (1..$maximum) { return $i-1 if append_character($tracker,$s->{characters}[$start+$i-1])>$cap; }
        return $maximum;
    }
    my($low,$high,$result)=(1,$maximum,0); my $cap=_capacity($o,$v);
    while($low<=$high) { my $n=$low+int(($high-$low)/2); if(_source_bits($s,$start,$n,$o,$v)<=$cap) {$result=$n;$low=$n+1} else {$high=$n-1} }
    return $result;
}
sub _attempt {
    my($s,$o,$v,$max)=@_; return ['single',[]] if _source_bits($s,0,$s->{length},$o,$v)<=_capacity($o,$v);
    my(@ranges,$start); $start=0;
    while($start<$s->{length}) {
        return ['long',[]] if @ranges==$max;
        my $possible=$s->{length}-$start-(@ranges?0:1); my $n=_largest_prefix($s,$start,$possible,$o,$v);
        return ['long',[]] if $n<=0; push @ranges,[$start,$n]; $start+=$n;
    }
    return [@ranges>=2?'ok':'single',\@ranges];
}
sub _select {
    my($s,$o,$max)=@_; my($lo,$hi)=($o->{version}||$o->{minVersion},$o->{version}||$o->{maxVersion}); my $long=0;
    for my $v ($lo..$hi) { my $a=_attempt($s,$o,$v,$max); return [$v,$a->[1],$o->{version}?'fixed':'auto-minimum'] if $a->[0] eq 'ok'; $long ||= $a->[0] eq 'long'; }
    fail('DATA_TOO_LONG',"Input cannot be split into $max or fewer symbols in the selected version range") if $long;
    fail('INVALID_INPUT','Input fits in one symbol; use generate or a low-level Structured Append header');
}
sub _segment_chunk {
    my($s,$start,$n)=@_; my(@segments,$first,$last,$byte_start,$byte_length); ($first,$last,$byte_start,$byte_length)=(-1,0,0,0);
    for my $p (@{_ranges($s,$start,$n)}) {
        my $d=$s->{descriptors}[$p->[0]]; my $b=_range_bytes($d,$p->[1],$p->[2]);
        if($first<0) {$first=$d->{sourceIndex};$byte_start=$b->[0]} $last=$d->{sourceIndex}+1; $byte_length+=$b->[1];
        if($d->{segment}{mode} eq 'byte') { my $data=substr(text($d->{segment}),$p->[1],$p->[2]); push @segments,is_binary($d->{segment})?byte_segment($data):new_segment('byte',$data); }
        else { push @segments,$d->{segment}; }
    }
    return [\@segments,{source_segment_start=>$first,source_segment_end=>$last,split_unit_start=>$start,split_unit_length=>$n,byte_start=>$byte_start,byte_length=>$byte_length}];
}
sub _full_detail {
    my($s)=@_; my @rows;
    for my $d (@{$s->{descriptors}}) { for my $unit (0..$d->{splitCount}-1) { my $b=_range_bytes($d,$unit,1); push @rows,{source_segment_index=>$d->{sourceIndex},mode=>$d->{segment}{mode},unit_start=>$d->{segment}{mode} eq 'byte'?$unit:0,unit_length=>$d->{segment}{mode} eq 'byte'?1:character_count($d->{segment}),byte_start=>$b->[0],byte_length=>$b->[1]}; } }
    return \@rows;
}
sub _generate_source {
    my($s,$o,$max,$detail,$results)=@_; my($v,$ranges,$selection)=@{_select($s,$o,$max)}; my $total=@$ranges; my(@symbols,@details);
    for my $i (0..$#$ranges) {
        my($start,$n)=@{$ranges->[$i]}; my %chosen=(%$o,version=>$v,minVersion=>$v,maxVersion=>$v,structuredAppend=>structured_append_segment($i+1,$total,$s->{parity})); my($q,$offset);
        if($s->{manual}) { my $chunk=_segment_chunk($s,$start,$n); $q=generate_segments($chunk->[0],\%chosen); $offset=$chunk->[1]; }
        else { my $data=_input_slice($s,$start,$n); $data=[unpack('C*',$data)] if $s->{binary}; $q=generate($data,\%chosen); $offset={input_start=>$start,input_length=>$n,byte_start=>$s->{binary}?$start:$s->{offsets}[$start],byte_length=>_input_byte_length($s,$start,$n)}; }
        push @symbols,$q; my $required=$q->{diagnostics}{data_bit_length};
        push @details,{index=>$i+1,total=>$total,parity=>$s->{parity},sequence_index=>$i,sequence_total=>$total-1,sequence_indicator=>($i<<4)|($total-1),version=>$v,error_correction_level=>$q->{errorCorrectionLevel},data_bit_length=>$required,capacity_bits=>_capacity($o,$v),remaining_bits=>_capacity($o,$v)-$required,mask_pattern=>$q->{maskPattern},%$offset};
    }
    my @warnings;
    push @warnings,{code=>'STRUCTURED_APPEND_MAX_SYMBOLS_NEAR_LIMIT',severity=>'info',message=>'The set uses the configured maximum number of symbols.',details=>{total=>$total,max_symbols=>$max}} if $total==$max;
    push @warnings,{code=>'STRUCTURED_APPEND_DECODER_SUPPORT_VARIES',severity=>'info',message=>'Decoder APIs vary in how they expose Structured Append metadata.',details=>{total=>$total}} if $results eq 'diagnostics';
    my $reason=$selection eq 'fixed'?"Version $v was requested explicitly.":"Version $v is the smallest version in $o->{minVersion}..$o->{maxVersion} that can split the payload into $total symbols.";
    my $d={version=>$v,error_correction_level=>$o->{errorCorrectionLevel},version_selection=>$selection,version_selection_reason=>$reason,total=>$total,parity=>$s->{parity},byte_length=>$s->{byteLength},input_length=>$s->{inputLength},max_symbols=>$max,split_strategy=>$s->{manual}?'segment-boundary-byte-chunk':'greedy-largest-fitting',symbols=>\@details,warnings=>\@warnings};
    if($s->{manual}) { $d->{segment_count}=scalar @{$s->{segments}}; $d->{split_unit_count}=$s->{length}; $d->{split_units_detail}=$detail; $d->{split_units}=_full_detail($s) if $detail eq 'full'; }
    return {symbols=>\@symbols,total=>$total,parity=>$s->{parity},inputLength=>$s->{inputLength},byteLength=>$s->{byteLength},diagnostics=>$d};
}
sub generate_structured_append {
    _reject_tied_args(@_);
    my($input,$raw,$max,$diagnostics)=@_; $max=16 unless defined $max; $diagnostics=0 unless defined $diagnostics; require_bool($diagnostics,'Diagnostics');
    my $o=normalize_options($raw); my $results=$diagnostics?'diagnostics':'output'; _check($o,$max,0,'summary',$results);
    return _generate_source(_input_source($input,$o,$max),$o,$max,'summary',$results);
}
sub generate_segments_structured_append {
    _reject_tied_args(@_);
    my($segments,$raw,$max,$diagnostics,$detail,$results)=@_; $max=16 unless defined $max; $diagnostics=0 unless defined $diagnostics; require_bool($diagnostics,'Diagnostics');
    $detail='summary' unless defined $detail; $results=$diagnostics?'diagnostics':'output' unless defined($results)&&length($results);
    my $o=normalize_options($raw); _check($o,$max,1,$detail,$results); return _generate_source(_segment_source($segments,$o,$max),$o,$max,$detail,$results);
}
sub merge_structured_append_parts {
    _reject_tied_args(@_);
    my($parts)=@_; require_array($parts,'Parts'); fail('INVALID_INPUT','parts must contain 1..16 decoded mappings') if !@$parts||@$parts>16;
    my(@ordered,@summaries,$total,$parity,$kind); my($nb,$actual,$units)=(0,0,0);
    for my $part (@$parts) {
        require_hash($part,'Part'); my $index=require_range($part->{index},1,16,'index'); my $t=require_range($part->{total},2,16,'total'); my $p=require_range($part->{parity},0,255,'parity');
        fail('INVALID_INPUT','Index exceeds total') if $index>$t;
        fail('INVALID_INPUT','Structured Append total mismatch') if defined($total)&&$t!=$total;
        fail('INVALID_INPUT','Structured Append parity mismatch') if defined($parity)&&$p!=$parity;
        fail('INVALID_INPUT',"Duplicate Structured Append index $index") if defined($ordered[$index-1]);
        my $data=$part->{data}; my($typ,$size,$checksum,$n,$owned);
        if(ref($data) eq 'ARRAY') { my $seg=byte_segment($data); ($typ,$n,$size,$checksum,$owned)=('binary',byte_count($seg),byte_count($seg),_xor(text($seg)),[unpack('C*',text($seg))]); }
        else { my $chars=strict_text($data); my $bytes=encode_utf8($data); ($typ,$n,$size,$checksum,$owned)=('string',scalar(@$chars),length($bytes),_xor($bytes),$data); }
        fail('DATA_TOO_LONG','Merged input exceeds the resource limit') if $n>MAX_PAYLOAD_UNITS-$units; $units+=$n;
        fail('INVALID_INPUT','Parts must not mix text and binary data') if defined($kind)&&$kind ne $typ;
        ($total,$parity,$kind)=($t,$p,$typ); $nb+=$size; $actual^=$checksum; $ordered[$index-1]=$owned;
        $summaries[$index-1]={index=>$index,total=>$total,parity=>$parity,data_type=>$kind,byte_length=>$size};
    }
    my @missing=grep {!defined($ordered[$_-1])} 1..$total;
    fail('INVALID_INPUT','Missing Structured Append indexes: '.join(', ',@missing)) if @missing;
    fail('INVALID_INPUT','Part count does not match total') if @$parts!=$total;
    fail('INVALID_INPUT','Structured Append parity check failed') if $actual!=$parity;
    my $data=$kind eq 'string'?join('',@ordered):[map {@$_} @ordered];
    return {data=>$data,total=>$total,parity=>$parity,parts=>\@summaries,diagnostics=>{part_count=>$total,total=>$total,parity=>$parity,data_type=>$kind,byte_length=>$nb,missing=>[],duplicate=>[],parity_check=>{expected=>$parity,actual=>$actual,matches=>_bool(1)}}};
}
1;
