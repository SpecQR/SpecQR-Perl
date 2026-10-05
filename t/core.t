use 5.026; use strict; use warnings; use utf8;
use Test::More; use JSON::PP (); use Digest::SHA qw(sha256_hex);
use lib 'lib';
use SpecQR::Error qw(is_integer is_string copy_json_checked);
use SpecQR::Tables qw(block_info data_codeword_count raw_codeword_count alignment_positions character_count_bits);
use SpecQR::Segments qw(strict_text new_segment byte_segment numeric alphanumeric kanji eci fnc1 fnc1_second structured_append_segment bits bit_length segment_count logical_bytes normalize_segments segments_bit_length kanji_code can_encode_kanji);
use SpecQR::Optimizer qw(optimize_segments new_segment_optimization_tracker append_character optimal_bits);
use SpecQR::Core qw(gf_multiply reed_solomon_divisor reed_solomon_remainder build_matrix interleave_codewords penalty_score);
use SpecQR::API qw(generate generate_segments plan_segments get_capacity normalize_options diagnostics module_at size);
sub throws_code {my($f,$code,$label)=@_;my $e;eval {$f->();1} or $e=$@;ok(ref($e)&&eval {$e->isa('SpecQR::Error')}&&$e->{code} eq $code,$label) or diag(defined($e)?"$e":'no exception')}
sub matrix_hash { sha256_hex(join("\n",map {join '',@$_} @{$_[0]})) }
is(data_codeword_count(1,'L'),19,'version 1 L data capacity');is(raw_codeword_count(40),3706,'version 40 raw capacity');is_deeply(alignment_positions(32),[6,34,60,86,112,138],'version 32 alignment exception');is(character_count_bits(27,'numeric'),14,'group three numeric count bits');
for my $v(1..40){for my $l(qw(L M Q H)){my $b=block_info($v,$l);is($b->{dataCodewords}+$b->{blocks}*$b->{eccPerBlock},$b->{rawCodewords},"block accounting v$v-$l")}}
is(gf_multiply(128,2),29,'GF modulus');is_deeply(reed_solomon_divisor(7),[1,127,122,154,164,11,68,117],'RS degree seven polynomial');is_deeply(reed_solomon_remainder([0,0,0],7),[(0)x7],'zero RS remainder');
is(join('',@{bits(numeric('1234'),1)}),'0001000000010000011110110100','numeric bit stream');is(bit_length(alphanumeric('AB'),1),24,'alphanumeric paired payload');is(segment_count(new_segment('byte','é😀')),6,'UTF8 byte count');is_deeply(logical_bytes(new_segment('byte','é😀')),[195,169,240,159,152,128],'UTF8 octets');is_deeply(logical_bytes(byte_segment([0,255,128])),[0,255,128],'opaque octets');is(segment_count(byte_segment("\xff\0")),2,'unflagged octet constructor');
is(kanji_code('漢'),0x8abf,'pinned Kanji code');ok(can_encode_kanji('字'),'Kanji representable');ok(!can_encode_kanji('😀'),'supplementary scalar not QR Kanji');is(bit_length(kanji('漢字'),1),38,'Kanji bit length');
is(bit_length(eci(127),1),12,'short ECI');is(bit_length(eci(128),1),20,'medium ECI');is(bit_length(eci(16384),1),28,'long ECI');is(bit_length(fnc1_second('A'),1),12,'second FNC1');is(bit_length(structured_append_segment(1,2,255),1),20,'SA header');
throws_code(sub { normalize_segments([numeric('1'),fnc1()]) },'INVALID_GS1','FNC1 must be first');throws_code(sub { normalize_segments([fnc1(),eci(26)]) },'INVALID_GS1','control families exclusive');throws_code(sub {normalize_segments([structured_append_segment(1,2,0),eci(26)])},'INVALID_MODE','SA excludes ECI');
my $s=optimize_segments('HELLO123world',1);is_deeply([map {[$_->{mode},$_->{data}]} @$s],[['alphanumeric','HELLO123'],['byte','world']],'exact optimizer mixed split');
my $t=new_segment_optimization_tracker(1);my $last;for(split //,'1234567890HELLOworld'){$last=append_character($t,$_)}is($last,optimal_bits($t),'incremental optimum');is($last,segments_bit_length(optimize_segments('1234567890HELLOworld',1),1),'tracker and optimizer agree');
my $q=generate('HELLO WORLD');is($q->{version},1,'automatic smallest version');is($q->{maskPattern},0,'minimum penalty mask');is($q->{diagnostics}{mask_penalty},311,'all-mask penalty');is(unpack('H*',pack('C*',@{$q->{dataCodewords}})),'205b0b78d172dc4d4340ec11ec11ec11','known data codewords');is(size($q),21,'QR dimension');ok(module_at($q,0,0),'finder dark');is(get_capacity(1,'L','numeric')->{maximum},41,'numeric capacity');is(get_capacity({version=>1,errorCorrectionLevel=>'L',mode=>'byte'})->{maximum},17,'capacity hash overload');
my $p=SpecQR::API::plan('x'x3000,{maxVersion=>1});ok(!$p->{ok},'overflow planning is nonthrowing');is($p->{version},0,'failed automatic plan has no selected version');is($p->{capacityVersion},1,'overflow capacity version');ok(!$p->{diagnostics}{mask_evaluated},'planning does not evaluate mask');ok(!$p->{diagnostics}{codewords_built},'planning does not build codewords');throws_code(sub {generate('x'x3000,{version=>1})},'DATA_TOO_LONG','generation overflow throws');
my $boost=generate('A',{errorCorrectionLevel=>'L',boostErrorCorrection=>1});is($boost->{errorCorrectionLevel},'H','ECC boost at selected version');
my $literal=generate('A%B',{fnc1=>1,mode=>'alphanumeric',maskPattern=>0});is($literal->{segments}[1]{data},'A%%B','highlevel percent escaping forced alpha');my $manual=generate_segments([fnc1(),alphanumeric('A%%B')],{maskPattern=>0});is_deeply($literal->{codewords},$manual->{codewords},'manual escape and literal highlevel agree');my $percent=SpecQR::API::plan('%'x40,{fnc1=>1});is($percent->{segments}[1]{mode},'byte','percent-heavy auto switches to byte');my $eciPlan=SpecQR::API::plan('漢字',{eciAssignment=>26});is($eciPlan->{segments}[1]{mode},'byte','ECI disables auto Kanji');
my $d=diagnostics($q);$d->{warnings}[0]={code=>'mutated'};is(scalar(@{$q->{diagnostics}{warnings}}),0,'diagnostics owned copy');my $cycle=[];push @$cycle,$cycle;throws_code(sub {copy_json_checked($cycle)},'INVALID_INPUT','diagnostic cycle rejected');
throws_code(sub {generate("\xc3\xa9")},'INVALID_INPUT','unflagged UTF8 octets rejected as text');throws_code(sub {strict_text(chr(0xd800))},'INVALID_INPUT','surrogate rejected');throws_code(sub {numeric(123)},'INVALID_INPUT','numeric scalar rejected as text');throws_code(sub {normalize_options({version=>'1'})},'INVALID_VERSION','string integer rejected');throws_code(sub {normalize_options({scale=>[]})},'INVALID_INPUT','referenced scale rejected');throws_code(sub {normalize_options({optimizeSegments=>'false'})},'INVALID_INPUT','string boolean rejected');throws_code(sub {normalize_options({unknown=>1})},'INVALID_INPUT','unknown option rejected');throws_code(sub {byte_segment([256])},'INVALID_INPUT','byte outside range rejected');throws_code(sub {byte_segment(['1'])},'INVALID_INPUT','numeric-looking string byte rejected');throws_code(sub {gf_multiply('2',1)},'INVALID_INPUT','numeric-looking GF string rejected');throws_code(sub {generate('ok',{gs1=>1,eciAssignment=>26})},'INVALID_GS1','GS1 ECI forbidden');
my $orig=numeric('123');my $np=plan_segments([$orig]);$orig->{data}='999';is($np->{segments}[0]{data},'123','manual inputs defensively copied');
my @eci_context=eci(26);is(scalar(@eci_context),1,'ECI list context returns one item');is(ref($eci_context[0]),'HASH','ECI list context is a hash');my @fnc_context=fnc1_second('09');is(scalar(@fnc_context),1,'FNC1 second list context returns one item');my %sa_context=(header=>structured_append_segment(1,2,0));is(ref($sa_context{header}),'HASH','SA hash-value context returns hash');
throws_code(sub {append_character({costs=>[0]},'a')},'INVALID_VERSION','malformed tracker rejected');
my $huge_scalar=chr(0x80000000);throws_code(sub {strict_text($huge_scalar)},'INVALID_INPUT','extended non-Unicode Perl character rejected');
my $mangled="\xff";Encode::_utf8_on($mangled);throws_code(sub {strict_text($mangled)},'INVALID_INPUT','malformed flagged Perl string rejected');
{package CoreTest::Tie; sub TIEHASH {bless {},shift} sub FIRSTKEY {undef} sub NEXTKEY {undef}}
my %tied;tie %tied,'CoreTest::Tie';throws_code(sub {normalize_options(\%tied)},'INVALID_INPUT','tied options rejected');
my $decoded=JSON::PP->new->decode('{"optimizeSegments":false,"boostErrorCorrection":true}');my $strictOpt=normalize_options($decoded);is($strictOpt->{optimizeSegments},0,'JSON false accepted');is($strictOpt->{boostErrorCorrection},1,'JSON true accepted');
sub rejects_quietly {
 my($name,$code,$action)=@_;my(@warnings,$error);{local $SIG{__WARN__}=sub{push @warnings,@_};eval {$action->();1} or $error=$@}
 ok(ref($error) && eval {$error->isa('SpecQR::Error')} && $error->{code} eq $code,$name.' stable error') or diag(defined($error)?"$error":'no exception');is_deeply(\@warnings,[],$name.' emits no warning');
}
rejects_quietly('Forged Boolean array ECI','INVALID_ECI',sub {SpecQR::API::plan('x',{eci=>bless [],'JSON::PP::Boolean'})});
rejects_quietly('Forged Boolean scalar two ECI','INVALID_ECI',sub {my $two=2;SpecQR::API::plan('x',{eci=>bless \$two,'JSON::PP::Boolean'})});
rejects_quietly('Ill-typed ECI alias','INVALID_ECI',sub {SpecQR::API::plan('x',{eci=>26,eciAssignment=>'bad'})});
rejects_quietly('Undefined capacity ECC alias','INVALID_ECC_LEVEL',sub {get_capacity({version=>1,errorCorrection=>'M',errorCorrectionLevel=>undef})});
rejects_quietly('Undefined option ECC alias','INVALID_ECC_LEVEL',sub {normalize_options({errorCorrection=>'M',errorCorrectionLevel=>undef})});
{package CoreTest::TiedScalar;sub TIESCALAR {bless {value=>$_[1],calls=>0},$_[0]} sub FETCH {++$_[0]{calls};$_[0]{value}}}
for my $method(qw(diagnostics size module_at)){tie my $tiedResult,'CoreTest::TiedScalar',$q;my $tie=tied($tiedResult);my $call=SpecQR::API->can($method);rejects_quietly('Tied top-level '.$method,'INVALID_INPUT',sub {$call->($tiedResult,0,0)});is($tie->{calls},0,$method.' rejects before FETCH')}
rejects_quietly('Bogus optimum getter','INVALID_VERSION',sub {optimal_bits({costs=>['not numeric']})});
my $badTracker=new_segment_optimization_tracker(1);$badTracker->{costs}[0]='not numeric';rejects_quietly('Invalid optimum scalar','INVALID_INPUT',sub {optimal_bits($badTracker)});
for my $badEncoding (chr(0xd800),chr(0x110000)){rejects_quietly('Invalid Unicode encoding option','INVALID_INPUT',sub {normalize_options({encoding=>$badEncoding})})}
my $brokenEncoding="\xc0\xaf";Encode::_utf8_on($brokenEncoding);rejects_quietly('Malformed internal UTF8 encoding option','INVALID_INPUT',sub {normalize_options({encoding=>$brokenEncoding})});
my $ownedResult=generate('BOOLEAN');my $ownedDiagnostic=diagnostics($ownedResult);${$ownedDiagnostic->{ok}}=0;ok($ownedResult->{diagnostics}{ok},'diagnostics clone owns its true Boolean');ok(JSON::PP::true,'diagnostics mutation preserves global true');${$ownedDiagnostic->{render_planned}}=1;ok(!$ownedResult->{diagnostics}{render_planned},'diagnostics clone owns its false Boolean');ok(!JSON::PP::false,'diagnostics mutation preserves global false');
${$ownedResult->{diagnostics}{ok}}=0;my $nextResult=generate('NEXT');ok($nextResult->{diagnostics}{ok},'mutating generated Boolean does not change later results');ok(JSON::PP::true,'generated Boolean mutation preserves global true');
my $sourceTrue=JSON::PP::true;my $copyTrue=copy_json_checked($sourceTrue);${$copyTrue}=0;ok($sourceTrue,'copy_json_checked clones external Boolean source');
my $tiedSlot=[]; tie $tiedSlot->[0],'CoreTest::TiedScalar',numeric('123');
rejects_quietly('Tied manual segment slot','INVALID_INPUT',sub {generate_segments($tiedSlot)});
tie my $tiedSegment,'CoreTest::TiedScalar',numeric('123');
rejects_quietly('Tied individual segment','INVALID_INPUT',sub {SpecQR::Segments::validate_segment($tiedSegment)});
tie my $tiedSegmentArray,'CoreTest::TiedScalar',[numeric('123')];
rejects_quietly('Tied segment array top','INVALID_INPUT',sub {SpecQR::Segments::normalize_segments($tiedSegmentArray)});
done_testing;
