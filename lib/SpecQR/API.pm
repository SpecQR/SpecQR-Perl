package SpecQR::API;
use 5.026; use strict; use warnings; use Exporter 'import'; use JSON::PP (); use Scalar::Util qw(blessed); use POSIX qw(isfinite);
use SpecQR::Error qw(fail require_range require_hash require_string require_number require_bool is_string is_integer copy_json_checked);
use SpecQR::Tables qw(@ERROR_CORRECTION_LEVELS validate_version level_index qr_size raw_codeword_count data_codeword_count character_count_bits);
use SpecQR::Segments qw(@DATA_MODES strict_text new_segment eci fnc1 fnc1_second structured_append_segment normalize_segments is_control segment_count character_count byte_count logical_bytes bit_length application_indicator_codeword segments_bit_length segments_bits MAX_SINGLE_SYMBOL_CHARACTERS);
use SpecQR::Optimizer qw(create_segments); use SpecQR::Core qw(pad_data_bits interleave_codewords build_matrix validate_matrix);
use SpecQR::Render qw(parse_color contrast_ratio);
our @EXPORT_OK=qw(normalize_options validate_options render_options get_capacity plan plan_segments estimate analyze_segments generate generate_segments diagnostics size module_at);
sub _bool { my $value=$_[0]?1:0;return bless \$value,'JSON::PP::Boolean' }
sub normalize_options { for my $arg (@_) { fail('INVALID_INPUT','Tied values are not supported') if tied($arg) }
 my($raw)=@_;$raw={} unless defined $raw;require_hash($raw,'Options');
 my %o=(errorCorrectionLevel=>'M',version=>0,minVersion=>1,maxVersion=>40,maskPattern=>-1,mode=>'auto',optimizeSegments=>1,allowKanji=>1,boostErrorCorrection=>0,eciAssignment=>-1,gs1=>0,fnc1=>0,fnc1Second=>'',structuredAppend=>undef,margin=>4,scale=>8,foreground=>'#000000',background=>'#ffffff',printDpi=>undef);
 my %extra=map {$_=>1} qw(eci errorCorrection encoding output diagnostics);
 for my $key(keys %$raw){fail('INVALID_INPUT',"Unknown option: $key") unless exists($o{$key})||$extra{$key};$o{$key}=$raw->{$key} unless $extra{$key}}
 if(exists $raw->{errorCorrection}){level_index($raw->{errorCorrection});level_index($raw->{errorCorrectionLevel}) if exists($raw->{errorCorrectionLevel});fail('INVALID_INPUT','Error correction aliases must match') if exists($raw->{errorCorrectionLevel})&&$raw->{errorCorrection} ne $raw->{errorCorrectionLevel};$o{errorCorrectionLevel}=$raw->{errorCorrection}}
 level_index($o{errorCorrectionLevel});validate_version($o{minVersion});validate_version($o{maxVersion});fail('INVALID_VERSION','minVersion must not exceed maxVersion') if $o{minVersion}>$o{maxVersion};
 $o{version}=0 if is_string($o{version})&&$o{version} eq 'auto';require_range($o{version},0,40,'QR version','INVALID_VERSION');
 $o{maskPattern}=-1 if is_string($o{maskPattern})&&$o{maskPattern} eq 'auto';require_range($o{maskPattern},-1,7,'Mask');
 require_string($o{mode},'Mode','INVALID_MODE');fail('INVALID_MODE','Unsupported data mode') unless grep {$o{mode} eq $_} ('auto',@DATA_MODES);
 for my $key(qw(optimizeSegments allowKanji boostErrorCorrection gs1 fnc1)){$o{$key}=require_bool($o{$key},$key,$key eq 'gs1'?'INVALID_GS1':'INVALID_INPUT')}
 require_range($o{eciAssignment},-1,999999,'ECI assignment','INVALID_ECI');
 if(exists $raw->{eci}){my $e=$raw->{eci};my $n;if(blessed($e)&&blessed($e) eq 'JSON::PP::Boolean'){$n=require_bool($e,'ECI boolean','INVALID_ECI')?26:-1}else{require_range($e,0,999999,'ECI assignment','INVALID_ECI');$n=$e}fail('INVALID_ECI','ECI aliases must match') if exists($raw->{eciAssignment})&&$o{eciAssignment}!=$n;$o{eciAssignment}=$n}
 require_range($o{eciAssignment},-1,999999,'ECI assignment','INVALID_ECI');require_string($o{fnc1Second},'FNC1 second indicator','INVALID_MODE');fnc1_second($o{fnc1Second}) if $o{fnc1Second} ne '';
 if(defined $o{structuredAppend}){my $s=$o{structuredAppend};require_hash($s,'Structured append','INVALID_MODE');fail('INVALID_MODE','Structured append requires a header') if exists($s->{mode})&&(!is_string($s->{mode})||$s->{mode} ne 'structured-append');$o{structuredAppend}=structured_append_segment(@$s{qw(index total parity)})}
 my $families=($o{gs1}||$o{fnc1}?1:0)+($o{fnc1Second} ne ''?1:0)+($o{eciAssignment}>=0?1:0)+(defined($o{structuredAppend})?1:0);fail($o{gs1}?'INVALID_GS1':'INVALID_MODE','FNC1, ECI, and SA controls cannot be combined') if $families>1;
 require_range($o{margin},0,1_000_000_000,'Margin');require_range($o{scale},1,1_000_000_000,'Scale');parse_color($o{foreground},0);parse_color($o{background},0);
 if(defined $o{printDpi}){require_number($o{printDpi},'DPI');fail('INVALID_INPUT','DPI must be positive') unless $o{printDpi}>0;my $mm=(177+2*$o{margin})*($o{scale}/$o{printDpi}*25.4);fail('INVALID_INPUT','DPI must produce finite positive print geometry') unless isfinite($mm)&&$mm>0}
 if(exists $raw->{encoding}){require_string($raw->{encoding},'Encoding');fail('INVALID_INPUT','Only UTF-8 encoding is supported') unless $raw->{encoding} =~ /\A[uU][tT][fF]-8\z/}
 if(exists $raw->{output}){require_string($raw->{output},'Output','INVALID_OUTPUT');fail('INVALID_OUTPUT','Unsupported output') unless grep {$raw->{output} eq $_} qw(matrix svg svg-data-url png png-data-url)}
 require_bool($raw->{diagnostics},'diagnostics') if exists $raw->{diagnostics};return \%o;
}
sub validate_options {normalize_options($_[0]);return}
sub render_options {my $o=normalize_options($_[0]);return {map {$_=>$o->{$_}} qw(margin scale foreground background)}}
sub get_capacity { for my $arg (@_) { fail('INVALID_INPUT','Tied values are not supported') if tied($arg) }
 my($v,$level,$mode,$control)=@_;
 if(ref($v) eq 'HASH'){my $o=$v;require_hash($o,'Capacity options');for my $k(keys %$o){fail('INVALID_INPUT',"Unknown capacity option: $k") unless grep {$k eq $_} qw(version errorCorrectionLevel errorCorrection mode controlBits)}level_index($o->{errorCorrection}) if exists($o->{errorCorrection});level_index($o->{errorCorrectionLevel}) if exists($o->{errorCorrectionLevel});$level=exists($o->{errorCorrectionLevel})?$o->{errorCorrectionLevel}:exists($o->{errorCorrection})?$o->{errorCorrection}:'M';fail('INVALID_INPUT','Error correction aliases must match') if exists($o->{errorCorrection})&&exists($o->{errorCorrectionLevel})&&$o->{errorCorrection} ne $o->{errorCorrectionLevel};$mode=exists($o->{mode})?$o->{mode}:'';$control=exists($o->{controlBits})?$o->{controlBits}:0;$v=$o->{version}}
 $level//='M';$mode//='';$control//=0;validate_version($v);level_index($level);require_string($mode,'Mode','INVALID_MODE');require_range($control,0,9_007_199_254_740_991,'Control bits');my $data=data_codeword_count($v,$level);
 my $out={version=>$v,size=>qr_size($v),dataCodewords=>$data,totalCodewords=>raw_codeword_count($v),capacityBits=>$data*8,errorCorrectionLevel=>$level,mode=>$mode,controlBits=>$control,characterCountBits=>-1,modeIndicatorBits=>-1,payloadBits=>-1,maximum=>-1,maxCharacters=>undef,maxBytes=>undef};
 if($mode ne ''){my $w=character_count_bits($v,$mode);my $available=$data*8-$control-4-$w;$available=0 if $available<0;my $max=$mode eq 'numeric'?int($available/10)*3+($available%10>=7?2:$available%10>=4?1:0):$mode eq 'alphanumeric'?int($available/11)*2+($available%11>=6?1:0):$mode eq 'byte'?int($available/8):int($available/13);$max=(1<<$w)-1 if $max>=(1<<$w);@$out{qw(characterCountBits modeIndicatorBits payloadBits maximum)}=($w,4,$available,$max);$out->{$mode eq 'byte'?'maxBytes':'maxCharacters'}=$max}return $out;
}
sub _segment_diagnostic {my($s,$v)=@_;{mode=>$s->{mode},character_count=>character_count($s),byte_count=>byte_count($s),count=>segment_count($s),bit_length=>bit_length($s,$v)}}
sub _diagnostics {
 my($segments,$v,$level,$required,$o,$planning,$ok)=@_;my $capacity=8*data_codeword_count($v,$level);my(@control,@data,@modes);my %modes;my $inputBytes=0;my($ec,$fn,$second,$sa)=(-1,'',undef,undef);
 for my $s(@$segments){my $d=_segment_diagnostic($s,$v);push @data,$d;$inputBytes+=@{logical_bytes($s)};if(is_control($s)){push @control,{%$d}}elsif(!$modes{$s->{mode}}++){push @modes,$s->{mode}}$ec=$s->{assignmentNumber} if $s->{mode} eq 'eci'&&$ec<0;$fn='first-position' if $s->{mode} eq 'fnc1';if($s->{mode} eq 'fnc1-second'){$fn='second-position';$second=$s}$sa=$s if $s->{mode} eq 'structured-append'}
 my $mode=@modes==0?'byte':@modes==1?$modes[0]:'mixed';my @warnings;my $warn=sub {my($code,$severity,$message,$details)=@_;push @warnings,{code=>$code,severity=>$severity,message=>$message,details=>$details//{}}};
 $warn->('QUIET_ZONE_TOO_SMALL','warning','QR readers expect at least four quiet-zone modules.',{margin=>$o->{margin}}) if $o->{margin}<4;
 my $fg=parse_color($o->{foreground},0);my $bg=parse_color($o->{background},0);my $ratio;
 if(defined($fg)&&defined($bg)){$ratio=contrast_ratio($fg,$bg);if($ratio<4.5){$warn->('COLOR_CONTRAST_LOW','warning','Color contrast is below the recommended minimum.',{ratio=>$ratio})}elsif($ratio<7){$warn->('COLOR_CONTRAST_MODERATE','info','Stronger color contrast is recommended.',{ratio=>$ratio})}$warn->('COLOR_ALPHA_USED','warning','Transparent colors can reduce scan reliability.') if $fg->[3]<255||$bg->[3]<255}
 else{$warn->('COLOR_CONTRAST_UNKNOWN','info','These SVG colors cannot be checked for contrast.')}
 $warn->('CAPACITY_NEAR_LIMIT','info','The selected version is close to full capacity.') if $capacity-$required>=0&&$capacity-$required<$capacity*0.05;
 my($mm,$symbolMm);if(defined $o->{printDpi}){$mm=$o->{scale}/$o->{printDpi}*25.4;$symbolMm=(qr_size($v)+2*$o->{margin})*$mm;$warn->('PRINT_MODULE_TOO_SMALL','warning','Print modules are smaller than 0.25 mm.',{module_size_mm=>$mm}) if $mm<0.25}
 my @blocking=map {$_->{code}} grep {$_->{severity} eq 'warning'} @warnings;$warn->('SCAN_RISK','warning','One or more settings may reduce scan reliability.',{blocking_warnings=>\@blocking}) if @blocking;
 my $selection=$o->{version}!=0?'fixed':$ok?'auto-minimum':'auto-range';my $reason=$o->{version}!=0?"Version $v was requested explicitly.":$ok?"Version $v is the smallest version in $o->{minVersion}..$o->{maxVersion} that fits.":"No version in $o->{minVersion}..$o->{maxVersion} fits; capacity is for version $v.";
 my $d={phase=>$planning?'planning':'generation',render_planned=>_bool(0),mask_evaluated=>_bool(!$planning),codewords_built=>_bool(!$planning),ok=>_bool($ok),capacity_version=>$v,error_correction_level=>$level,requested_error_correction_level=>$o->{errorCorrectionLevel},boosted_error_correction=>_bool($level ne $o->{errorCorrectionLevel}),version_selection=>$selection,version_selection_reason=>$reason,mode=>$mode,control_segments=>\@control,segments=>\@data,data_bit_length=>$required,capacity_bits=>$capacity,remaining_bits=>$capacity-$required,overflow_bits=>$required>$capacity?$required-$capacity:0,capacity_utilization=>$required/$capacity,input_bytes=>$inputBytes,gs1=>_bool($fn eq 'first-position'),gs1_validation=>{enabled=>_bool(0),element_count=>0,ais=>[],has_separators=>_bool(0)},warnings=>\@warnings,version=>$ok||$o->{version}!=0?$v:undef,size=>$ok||$o->{version}!=0?qr_size($v):undef,eci_assignment_number=>$ec>=0?$ec:undef,fnc1=>$fn ne ''?$fn:undef,fnc1_second=>{enabled=>_bool(defined $second),application_indicator=>defined($second)?$second->{applicationIndicator}:undef,application_indicator_codeword=>defined($second)?application_indicator_codeword($second):undef},structured_append=>{enabled=>_bool(defined $sa),map {$_=>undef} qw(index total parity sequence_index sequence_total sequence_indicator)}};
 if(defined $sa){$d->{structured_append}={enabled=>_bool(1),index=>$sa->{index},total=>$sa->{total},parity=>$sa->{parity},sequence_index=>$sa->{index}-1,sequence_total=>$sa->{total}-1,sequence_indicator=>(($sa->{index}-1)<<4)|($sa->{total}-1)}}
 $d->{quiet_zone}={modules=>$o->{margin},recommended_modules=>4,is_sufficient=>_bool($o->{margin}>=4)};
 $d->{colors}={ratio=>$ratio,is_inspectable=>_bool(defined $ratio),foreground_alpha=>defined($fg)?$fg->[3]:undef,background_alpha=>defined($bg)?$bg->[3]:undef,is_strong=>_bool(defined($ratio)&&$ratio>=7),is_sufficient=>_bool(defined($ratio)&&$ratio>=4.5&&$fg->[3]==255&&$bg->[3]==255)};
 $d->{print}={dpi=>$o->{printDpi},module_pixels=>$o->{scale},module_size_mm=>$mm,symbol_size_mm=>$symbolMm,recommended_minimum_module_size_mm=>0.25,is_module_size_sufficient=>defined($mm)?_bool($mm>=0.25):undef};return $d;
}
sub _add_controls {
 my($data,$o)=@_;my @out;if($o->{eciAssignment}>=0){push @out,eci($o->{eciAssignment})}elsif($o->{gs1}||$o->{fnc1}){push @out,fnc1()}elsif($o->{fnc1Second} ne ''){push @out,fnc1_second($o->{fnc1Second})}elsif(defined $o->{structuredAppend}){push @out,$o->{structuredAppend}}push @out,@$data;normalize_segments(\@out);
}
sub _select_plan {
 my($factory,$o)=@_;my $lo=$o->{version}==0?$o->{minVersion}:$o->{version};my $hi=$o->{version}==0?$o->{maxVersion}:$o->{version};my(@cache,@required,@fit);my($v,$data,$req,$ok)=($hi,[],0,0);
 for my $candidate($lo..$hi){my $g=$candidate<=9?0:$candidate<=26?1:2;unless(defined $cache[$g]){$cache[$g]=$factory->($candidate);$required[$g]=segments_bit_length($cache[$g],$candidate);$fit[$g]=1;for my $s(@{$cache[$g]}){$fit[$g]=0 if !is_control($s)&&segment_count($s)>=(1<<character_count_bits($candidate,$s->{mode}))}}($v,$data,$req)=($candidate,$cache[$g],$required[$g]);$ok=$fit[$g]&&$req<=8*data_codeword_count($v,$o->{errorCorrectionLevel})?1:0;last if $ok}
 my $level=$o->{errorCorrectionLevel};if($ok&&$o->{boostErrorCorrection}){for my $i(level_index($level)..3){$level=$ERROR_CORRECTION_LEVELS[$i] if $req<=8*data_codeword_count($v,$ERROR_CORRECTION_LEVELS[$i])}}
 my $capacity=8*data_codeword_count($v,$level);return {ok=>_bool($ok),version=>$ok||$o->{version}!=0?$v:0,capacityVersion=>$v,errorCorrectionLevel=>$level,requestedErrorCorrectionLevel=>$o->{errorCorrectionLevel},boostedErrorCorrection=>_bool($level ne $o->{errorCorrectionLevel}),dataBitLength=>$req,capacityBits=>$capacity,remainingBits=>$capacity-$req,segments=>$data,diagnostics=>_diagnostics($data,$v,$level,$req,$o,1,$ok)};
}
sub _input_segments {
 my($value,$v,$o,$opt)=@_;my $data=create_segments($value,$o->{mode},$v,$opt,-1,$o->{allowKanji}&&$o->{eciAssignment}<0?1:0);
 if(($o->{gs1}||$o->{fnc1}||$o->{fnc1Second} ne '')&&grep {$_->{mode} eq 'alphanumeric'&&CORE::index($_->{data},'%')>=0} @$data){my @escaped=map {if($_->{mode} eq 'alphanumeric'){my $s=$_->{data};$s=~s/%/%%/g;new_segment('alphanumeric',$s)}else{$_}} @$data;
  if($o->{mode} eq 'auto'){my $bytes=create_segments($value,'byte',$v,0,-1,0);my $bb=segments_bit_length($bytes,$v);my $eb=segments_bit_length(\@escaped,$v);$data=$bb<$eb||($bb==$eb&&@$bytes<@escaped)?$bytes:\@escaped}else{$data=\@escaped}}
 return _add_controls($data,$o);
}
sub plan { for my $arg (@_) { fail('INVALID_INPUT','Tied values are not supported') if tied($arg) }
 my($value,$raw)=@_;my $o=normalize_options($raw);my $validation;my $opt=$o->{optimizeSegments};
 if(ref($value) eq 'ARRAY'){fail('INVALID_GS1','High-level GS1 requires text') if $o->{gs1}}
 else {my $scalars=strict_text($value);$opt=0 if @$scalars>MAX_SINGLE_SYMBOL_CHARACTERS;if($o->{gs1}){require SpecQR::GS1;my $parsed=SpecQR::GS1::parse_gs1_element_string($value);$validation={enabled=>_bool(1),element_count=>scalar(@{$parsed->{elements}}),ais=>[map {$_->{ai}} @{$parsed->{elements}}],has_separators=>_bool(CORE::index($value,"\x1d")>=0)}}}
 my $p=_select_plan(sub {_input_segments($value,$_[0],$o,$opt)},$o);$p->{diagnostics}{gs1_validation}=$validation if defined $validation;return $p;
}
sub plan_segments { for my $arg (@_) { fail('INVALID_INPUT','Tied values are not supported') if tied($arg) }my($values,$raw)=@_;my $o=normalize_options($raw);fail('INVALID_GS1','Manual GS1 requires an explicit FNC1 segment') if $o->{gs1};my $found=_add_controls(normalize_segments($values),$o);_select_plan(sub {$found},$o)}
sub _build {
 my($p,$o)=@_;fail('DATA_TOO_LONG','Input does not fit the selected QR capacity') unless $p->{ok};my $v=$p->{capacityVersion};my $level=$p->{errorCorrectionLevel};my $data=pad_data_bits(segments_bits($p->{segments},$v),$v,$level);my $inter=interleave_codewords($data,$v,$level);my $built=build_matrix($inter->{codewords},$v,$level,$o->{maskPattern});my $d=_diagnostics($p->{segments},$v,$level,$p->{dataBitLength},$o,0,1);$d->{gs1_validation}=copy_json_checked($p->{diagnostics}{gs1_validation});@$d{qw(mask_pattern mask_penalty)}=@$built{qw(maskPattern penalty)};$d->{mask_penalties}=[map {{mask_pattern=>$_->{maskPattern},penalty=>$_->{penalty}}} @{$built->{maskPenalties}}];$d->{mask_selection_reason}=$o->{maskPattern}<0?'Lowest penalty; first mask wins ties.':'Explicit mask requested.';@$d{qw(data_codewords error_correction_codewords total_codewords)}=(scalar(@$data),scalar(@{$inter->{codewords}})-@$data,scalar(@{$inter->{codewords}}));return {matrix=>$built->{matrix},version=>$v,maskPattern=>$built->{maskPattern},errorCorrectionLevel=>$level,dataCodewords=>$data,codewords=>$inter->{codewords},segments=>$p->{segments},diagnostics=>$d,options=>$o};
}
sub generate { for my $arg (@_) { fail('INVALID_INPUT','Tied values are not supported') if tied($arg) }my($value,$raw)=@_;my $o=normalize_options($raw);_build(plan($value,$o),$o)}
sub generate_segments { for my $arg (@_) { fail('INVALID_INPUT','Tied values are not supported') if tied($arg) }my($values,$raw)=@_;my $o=normalize_options($raw);_build(plan_segments($values,$o),$o)}
sub estimate {plan(@_)} sub analyze_segments {plan_segments(@_)}
sub diagnostics { for my $arg (@_) { fail('INVALID_INPUT','Tied values are not supported') if tied($arg) }my($v)=@_;require_hash($v,'Result');fail('INVALID_INPUT','Uninitialized diagnostics result') unless defined $v->{diagnostics};copy_json_checked($v->{diagnostics})}
sub size { for my $arg (@_) { fail('INVALID_INPUT','Tied values are not supported') if tied($arg) }my($q)=@_;require_hash($q,'QR result');validate_matrix($q->{matrix});scalar(@{$q->{matrix}})}
sub module_at { for my $arg (@_) { fail('INVALID_INPUT','Tied values are not supported') if tied($arg) }my($q,$x,$y)=@_;my $n=size($q);require_range($x,0,$n-1,'Column');require_range($y,0,$n-1,'Row');$q->{matrix}[$y][$x]?1:0}
1;
