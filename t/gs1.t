use 5.026;
use strict;
use warnings;
use utf8;
use Test::More;
use JSON::PP ();
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use Encode ();
use Digest::SHA qw(sha256_hex);
use FindBin;
use lib "$FindBin::Bin/../lib";
use SpecQR::GS1 qw(:all);
use Scalar::Util qw(blessed);

my $gtin='09506000134352';
my $primary={ai=>'01',value=>$gtin};
my $uri="https://example.com/01/$gtin";
sub fails {
    my ($detail,$call,$label)=@_; my $ok=eval { $call->(); 1 }; my $e=$@;
    ok(!$ok,$label//'throws');
    isa_ok($e,'SpecQR::Error');
    is($e->{code},'INVALID_GS1','public error category');
    is($e->{detailCode},$detail,'precise error category');
}
sub read_json {
    my ($name)=@_; open my $fh,'<:raw',"$FindBin::Bin/../verification/fixtures/$name" or die "$name: $!";
    local $/; return JSON::PP::decode_json(<$fh>);
}
sub read_current_ts {
    my $path="$FindBin::Bin/../verification/fixtures/current-ts-gs1-1411.json.gz";
    open my $fh,'<:raw',$path or die $!;local $/;my $raw=<$fh>;
    is(sha256_hex($raw),'c2e0678be740d935306353ae15c0e5f80a444a641351b070f5126be81057021b','current TS artifact is pinned');
    my $out;gunzip \$raw => \$out or die $GunzipError;return JSON::PP::decode_json($out);
}
# Cross-language comparison checks payload, every catalog field, diagnostic
# categories/reasons and warning counts. Human wording and Nim's always-present
# optional nulls are deliberately not the TypeScript compatibility contract.
sub contract {
    my ($value)=@_;
    if (ref($value) eq 'HASH') {
        if (exists($value->{code}) && exists($value->{message})) {
            return {map {$_=>contract($value->{$_})} grep {exists($value->{$_}) && defined($value->{$_})} qw(code reason count)};
        }
        return {map {$_=>contract($value->{$_})} grep {defined($value->{$_}) && $_ ne 'isVariable' && !($_ eq 'errors' && $value->{ok})} keys %$value};
    }
    return [map {contract($_)} @$value] if ref($value) eq 'ARRAY';
    return $value;
}
my %OPS=(
 dictionary=>'get_supported_gs1_ais',info=>'get_gs1_ai_info',checkDigit=>'calculate_gs1_check_digit',
 validateCheckDigit=>'validate_gs1_check_digit',gtinDigit=>'calculate_gtin_check_digit',gtinAppend=>'append_gtin_check_digit',
 gtinValidate=>'validate_gtin_check_digit',ssccDigit=>'calculate_sscc_check_digit',ssccAppend=>'append_sscc_check_digit',
 ssccValidate=>'validate_sscc_check_digit',human=>'parse_gs1_human_readable',raw=>'parse_gs1_element_string',
 create=>'create_gs1_element_string',validateElements=>'validate_gs1_elements',validateRaw=>'validate_gs1_element_string',
 linkCreate=>'create_gs1_digital_link',linkParse=>'parse_gs1_digital_link',linkValidate=>'validate_gs1_digital_link',linkNormalize=>'normalize_gs1_digital_link',
);
sub evaluate {
    my ($f)=@_; my $actual; my $ok=eval {
        no strict 'refs';
        my $fn=$OPS{$f->{op}} or die "Unknown fixture operation";
        my $arg=exists($f->{elements})?$f->{elements}:$f->{input};
        $actual=&{"SpecQR::GS1::$fn"}($arg,$f->{options}); 1;
    };
    if (!$ok) { my $e=$@; die $e unless blessed($e) && $e->isa('SpecQR::Error'); return {throws=>{code=>$e->{code},message=>$e->{message}}}; }
    return $actual;
}

subtest '50 concrete AIs and defensive metadata copies' => sub {
    is(scalar @{get_supported_gs1_ais()},50);
    is(get_gs1_ai_info('01')->{length}{exact},14);
    ok(get_gs1_ai_info('10')->{length}{isVariable});
    is_deeply(get_gs1_ai_info('10')->{digitalLinkPathForPrimary},['01']);
    is(get_gs1_ai_info('3105')->{valueKind},'numeric');
    for my $ai ('3106','3206','90','9999') { is(get_gs1_ai_info($ai),undef,"unsupported $ai"); }
    my $a=get_supported_gs1_ais(); $a->[0]{length}{exact}=1; $a->[3]{digitalLinkPathForPrimary}[0]='00';
    is(get_gs1_ai_info('00')->{length}{exact},18,'nested copies isolate catalog');
    is_deeply(get_gs1_ai_info('10')->{digitalLinkPathForPrimary},['01']);
    my $info_bool=get_gs1_ai_info('10')->{length}{isVariable}; $$info_bool=0;
    ok(get_gs1_ai_info('10')->{length}{isVariable},'catalog booleans are independent copies');
    my $valid=validate_gtin_check_digit($gtin); $$valid=0;
    ok(validate_gtin_check_digit($gtin),'boolean result cannot corrupt future booleans');
    ok(JSON::PP::true(),'global JSON true untouched');
    for my $info (@{get_supported_gs1_ais()}) {
        my $value=$info->{valueKind} eq 'text'?'X':$info->{length}{isVariable}?'1':'0'x$info->{length}{exact};
        my $e=[{ai=>$info->{ai},value=>$value}];
        is_deeply(parse_gs1_human_readable(gs1_to_human_readable($e)),$e,"human AI $info->{ai}");
        is_deeply(parse_gs1_element_string(create_gs1_element_string($e))->{elements},$e,"raw AI $info->{ai}");
        ok(validate_gs1_elements($e)->{ok},"validate AI $info->{ai}");
    }
};
subtest 'check digits and strict scalar types' => sub {
    is(calculate_gs1_check_digit('0950600013435'),'2');
    is(append_gtin_check_digit('0950600013435'),$gtin);
    ok(validate_gtin_check_digit($gtin)); ok(!validate_gtin_check_digit('09506000134353'));
    is(calculate_gs1_check_digit('0'),'0'); ok(validate_gs1_check_digit('00'));
    for my $body ('1234567','12345678901','123456789012','1234567890123') { ok(validate_gtin_check_digit(append_gtin_check_digit($body))); }
    ok(validate_sscc_check_digit(append_sscc_check_digit('12345678901234567')));
    fails('GS1_INVALID_CHARSET',sub {calculate_gs1_check_digit('')});
    fails('GS1_INVALID_CHARSET',sub {calculate_gs1_check_digit('1x')});
    fails('GS1_INVALID_LENGTH',sub {validate_gs1_check_digit('1')});
    fails('GS1_INVALID_LENGTH',sub {calculate_gtin_check_digit('123')});
    fails('GS1_INVALID_LENGTH',sub {validate_gtin_check_digit('12')});
    fails('GS1_INVALID_LENGTH',sub {calculate_sscc_check_digit('123')});
    fails('GS1_INVALID_LENGTH',sub {validate_sscc_check_digit('123')});
    for my $bad (undef,1,0.5,[],{},sub {},JSON::PP::true()) {
        fails('GS1_INVALID_INPUT',sub {calculate_gs1_check_digit($bad)},'non-string rejected');
    }
    fails('GS1_INVALID_INPUT',sub {calculate_gs1_check_digit('1'x(GS1_MAX_INPUT_CHARACTERS+1))});
};
subtest 'human raw aliases and separator safety' => sub {
    my $values=[$primary,{ai=>'10',value=>'LOT-A'},{ai=>'17',value=>'271231'}];
    my $human="(01)$gtin(10)LOT-A(17)271231";my $raw="01${gtin}10LOT-A\x1d17271231";
    is(create_gs1_element_string($values),$raw); is(gs1_to_human_readable($values),$human);
    is(gs1_element_string_to_human_readable($raw),$human);
    is_deeply(parse_gs1_human_readable($human),$values);
    is_deeply(parse_gs1_element_string($raw)->{elements},$values);
    ok(parse_gs1_element_string($raw)->{hasSeparators}); ok(!parse_gs1_element_string("01$gtin")->{hasSeparators});
    for my $input ($raw,$human,parse_gs1_element_string($raw),$values) { is_deeply(normalize_gs1_elements($input),$values); }
    is(gs1_build($values),$raw);is(gs1_to_element_string($values),$raw);is_deeply(gs1_parse($raw),parse_gs1_element_string($raw));
    is_deeply(gs1_from_human_readable($human),$values);is_deeply(gs1_normalize($human),$values);
    my $percent=[{ai=>'10',value=>'A%'},{ai=>'21',value=>'B%%'}];
    is(create_gs1_element_string($percent),"10A%\x1d21B%%");is_deeply(parse_gs1_element_string(create_gs1_element_string($percent))->{elements},$percent);
    fails('GS1_MISSING_SEPARATOR',sub {parse_gs1_element_string('10LOT17271231')});
    fails('GS1_MISSING_SEPARATOR',sub {parse_gs1_element_string('10ABC17XXXXXX')});
    for my $s ("\x1d10X","10X\x1d","17271231\x1d10X","10X\x1d\x1d21Y") { fails('GS1_UNEXPECTED_SEPARATOR',sub {parse_gs1_element_string($s)}); }
    fails('GS1_INVALID_CHECK_DIGIT',sub {parse_gs1_human_readable('(01)09506000134353')});
    fails('GS1_INVALID_LENGTH',sub {parse_gs1_human_readable('(10)')});
    fails('GS1_INVALID_LENGTH',sub {parse_gs1_human_readable('(17)123')});
    fails('GS1_INVALID_CHARSET',sub {parse_gs1_human_readable('(17)abcdef')});
    fails('GS1_UNSUPPORTED_AI',sub {parse_gs1_human_readable('(9999)x')});
    for my $s ('(1)x','(10x','10X') { fails('GS1_INVALID_INPUT',sub {parse_gs1_human_readable($s)}); }
    fails('GS1_INVALID_INPUT',sub {parse_gs1_element_string('(10)X')});
    fails('GS1_INVALID_CHARSET',sub {parse_gs1_human_readable('(10)日本')});
    for my $bad ("\xc0\xaf","\xed\xa0\x80","\xf4\x90\x80\x80","\x80","\xf0\x80\x80\x80",chr(0xd800),chr(0x110000)) {
        fails('GS1_INVALID_INPUT',sub {parse_gs1_human_readable('(10)'.$bad)});
    }
};
subtest 'validation and bounded inputs' => sub {
    my $bad=[{ai=>'01',value=>'bad'},{ai=>'17',value=>'short'}];
    my $r=validate_gs1_elements($bad);ok(!$r->{ok});is(scalar @{$r->{errors}},2);
    is($r->{errors}[0]{elementIndex},0);is($r->{errors}[1]{elementIndex},1);is($r->{errors}[1]{ai},'17');
    is(scalar @{validate_gs1_elements($bad,{collectAllErrors=>0})->{errors}},1);
    for my $o ({allowUnsupportedAi=>1},{context=>'other'},{collectAllErrors=>'false'},{unknown=>0},{context=>0},{allowUnsupportedAi=>'0'}) {
        ok(!validate_gs1_elements([$primary],$o)->{ok},'invalid option rejected');
    }
    ok(!validate_gs1_elements([{ai=>'10',value=>'x'}],{context=>'digital-link'})->{ok});
    ok(validate_gs1_elements([$primary],{context=>'digital-link'})->{ok});
    ok(!validate_gs1_element_string('10X')->{hasSeparators});
    fails('GS1_INVALID_INPUT',sub {create_gs1_element_string([])});
    fails('GS1_INVALID_INPUT',sub {create_gs1_element_string([map {{ai=>'10',value=>'X'}} 0..GS1_MAX_ELEMENTS])});
    fails('GS1_INVALID_INPUT',sub {normalize_gs1_elements([{ai=>'10',value=>'A' x GS1_MAX_INPUT_CHARACTERS}])});
    for my $bad (undef,1,{},[{ai=>10,value=>'ABC'}],[{ai=>'10',value=>123}],[[10,'ABC']]) {
        ok(!validate_gs1_elements($bad)->{ok},'invalid container or scalar produces structured failure');
    }
    my $cycle=[];push @$cycle,$cycle;ok(!validate_gs1_elements($cycle)->{ok},'cycle rejected without recursion');
};
{
    package GS1TestTie;
    our $FETCHES=0;
    sub TIESCALAR { bless { value=>$_[1] },$_[0] }
    sub FETCH { ++$FETCHES; $_[0]{value} }
}
subtest 'forged booleans and tied values are rejected without executing FETCH' => sub {
    my $two=2;my $half=0.5;my $text='1';my $nil;my $nested=[];
    for my $forged (bless([], 'JSON::PP::Boolean'),bless({}, 'JSON::PP::Boolean'),
        bless(\$two,'JSON::PP::Boolean'),bless(\$half,'JSON::PP::Boolean'),
        bless(\$text,'JSON::PP::Boolean'),bless(\$nil,'JSON::PP::Boolean'),bless(\$nested,'JSON::PP::Boolean')) {
        my $r=validate_gs1_elements([$primary],{collectAllErrors=>$forged});
        ok(!$r->{ok},'forged boolean produces structured invalid-input');
        is($r->{errors}[0]{code},'GS1_INVALID_INPUT');
    }
    tie my $raw,'GS1TestTie',"01$gtin";
    fails('GS1_INVALID_INPUT',sub {parse_gs1_element_string($raw)});
    my $r=validate_gs1_element_string($raw);ok(!$r->{ok});
    my $field={ai=>'01'};tie $field->{value},'GS1TestTie',$gtin;
    fails('GS1_INVALID_INPUT',sub {normalize_gs1_elements([$field])});
    my $array=[];tie $array->[0],'GS1TestTie',$primary;
    fails('GS1_INVALID_INPUT',sub {normalize_gs1_elements($array)});
    my $options={};tie $options->{baseUrl},'GS1TestTie','https://example.com';
    fails('GS1_INVALID_INPUT',sub {create_gs1_digital_link([$primary],$options)});
    my $booleans={};tie $booleans->{collectAllErrors},'GS1TestTie',0;
    ok(!validate_gs1_elements([$primary],$booleans)->{ok});
    tie my $inner,'GS1TestTie',1;my $tied_bool=bless \$inner,'JSON::PP::Boolean';
    ok(!validate_gs1_elements([$primary],{collectAllErrors=>$tied_bool})->{ok});
    is($GS1TestTie::FETCHES,0,'no user-supplied tied scalar was fetched');
};
subtest 'Digital Link creation parsing normalization and dot data' => sub {
    my $v=[{ai=>'17',value=>'271231'},$primary,{ai=>'10',value=>'LOT A'},{ai=>'21',value=>'S/2'},{ai=>'240',value=>'x+y'}];
    my $expected="https://id.gs1.org/01/$gtin/10/LOT%20A/21/S%2F2?17=271231&240=x%2By";
    is(create_gs1_digital_link($v),$expected);is(gs1_digital_link($v),$expected);is(gs1_to_digital_link($v),$expected);
    my $p=parse_gs1_digital_link($expected);is_deeply($p->{primary},$primary);is(scalar @{$p->{pathElements}},3);is(scalar @{$p->{queryElements}},2);
    ok(validate_gs1_digital_link($expected)->{ok});is(normalize_gs1_digital_link($expected),$expected);
    my $values=[$primary,{ai=>'10',value=>'LOT'},{ai=>'21',value=>'SER'}];
    is(create_gs1_digital_link($values,{pathAis=>['21']}),"https://id.gs1.org/01/$gtin/21/SER?10=LOT");
    is(create_gs1_digital_link($values,{pathAis=>[]}),"https://id.gs1.org/01/$gtin?10=LOT&21=SER");
    is(create_gs1_digital_link($values,{explicitPathAis=>1}),"https://id.gs1.org/01/$gtin?10=LOT&21=SER");
    fails('GS1_INVALID_DIGITAL_LINK_PLACEMENT',sub {create_gs1_digital_link($values,{pathAis=>['17']})});
    my $input="https://EXAMPLE.COM:00443/p/01/$gtin?utm=a&utm=b&x=a+b&empty&x=%E6%97%A5%E6%9C%AC&17=271231";
    my $norm="https://example.com/p/01/$gtin?17=271231&utm=a&utm=b&x=a+b&empty=&x=%E6%97%A5%E6%9C%AC";
    is(normalize_gs1_digital_link($input),$norm);is(normalize_gs1_digital_link($norm),$norm);
    is_deeply(parse_gs1_digital_link($input)->{unknownQuery},[{key=>'utm',value=>'a'},{key=>'utm',value=>'b'},{key=>'x',value=>'a b'},{key=>'empty',value=>''},{key=>'x',value=>'日本'}]);
    is(validate_gs1_digital_link($input)->{warnings}[0]{count},5);
    fails('GS1_DIGITAL_LINK_UNKNOWN_QUERY',sub {parse_gs1_digital_link($input,{unknownQuery=>'reject'})});
    my $dots=[$primary,{ai=>'10',value=>'..'},{ai=>'21',value=>'.'}];
    my $doturi="$uri?10=..&21=.";
    is(create_gs1_digital_link($dots,{baseUrl=>'https://example.com'}),$doturi);
    is(normalize_gs1_digital_link($doturi.'&utm=a&utm=b'),$doturi.'&utm=a&utm=b');
    is_deeply(parse_gs1_digital_link($doturi)->{elements},$dots);
    for my $dot ('.','..','%2e','%2E%2e','.%2E','%2e.') {
        my $u="$uri/10/$dot";
        fails('GS1_INVALID_DIGITAL_LINK_PLACEMENT',sub {parse_gs1_digital_link($u)});
        fails('GS1_INVALID_DIGITAL_LINK_PLACEMENT',sub {normalize_gs1_digital_link($u)});
        ok(!validate_gs1_digital_link($u)->{ok});
    }
    is(create_gs1_digital_link([$primary,{ai=>'10',value=>'%2e'}],{baseUrl=>'https://example.com'}),"$uri/10/%252e");
    for my $data ('%2e','%2E%2e','%','100%','%2f','a/b','a?b','a#b','a+b','a&b') {
        my $e=[$primary,{ai=>'10',value=>$data}];is_deeply(parse_gs1_digital_link(create_gs1_digital_link($e))->{elements},$e,"data preserved $data");
    }
    for my $base ('https://example.com/a/../b','https://example.com/a/%2E%2e/b') {
        is(create_gs1_digital_link([$primary],{baseUrl=>$base}),"https://example.com/b/01/$gtin");
    }
    fails('GS1_INVALID_DIGITAL_LINK_PLACEMENT',sub {create_gs1_digital_link([$primary],{baseUrl=>'https://example.com/%30%31'})});
    fails('GS1_INVALID_DIGITAL_LINK_PLACEMENT',sub {parse_gs1_digital_link("https://example.com/01/./../01/$gtin")});
    fails('GS1_DUPLICATE_AI',sub {create_gs1_digital_link([$primary,$primary])});
    fails('GS1_DUPLICATE_AI',sub {parse_gs1_digital_link("$uri?01=$gtin")});
    fails('GS1_DUPLICATE_AI',sub {parse_gs1_digital_link("$uri?10=x&10=y")});
    fails('GS1_INVALID_DIGITAL_LINK_PLACEMENT',sub {parse_gs1_digital_link("$uri/17/271231")});
    fails('GS1_UNSUPPORTED_AI',sub {parse_gs1_digital_link("$uri?9999=x")});
    fails('GS1_INVALID_INPUT',sub {create_gs1_digital_link([$primary],{baseUrl=>'https://example.com?x=y'})});
    ok(!validate_gs1_digital_link($uri,{normalize=>1})->{ok});
    for my $bad ('%','%0','%GG','%C0%AF','%ED%A0%80','%F4%90%80%80','%FF','%00','%E2%82') {
        fails('GS1_INVALID_PERCENT_ENCODING',sub {parse_gs1_digital_link("$uri?x=$bad")});
    }
    is(normalize_gs1_digital_link("$uri?x=😀"),"$uri?x=%F0%9F%98%80");
    fails('GS1_INVALID_INPUT',sub {parse_gs1_digital_link("$uri?".('x=y&' x GS1_MAX_ELEMENTS))});
    fails('GS1_INVALID_INPUT',sub {parse_gs1_digital_link($uri,{unknownQuery=>'ignore'})});
    fails('GS1_INVALID_INPUT',sub {normalize_gs1_digital_link($uri,{mode=>'other'})});
};
subtest 'strict authority profile and pinned cross-port vectors' => sub {
    for my $host ('example.com','EXAMPLE.COM','example.com.','xn--bcher-kva.example','localhost','127.0.0.1','192.168.1.1','8.8.8.8','0.0.0.0','[::1]','[2001:db8::1]','[::ffff:192.0.2.1]','[1:2:3:4:5:6:7:8]') {
        is_deeply(parse_gs1_digital_link("https://$host/01/$gtin")->{primary},$primary,"accept $host");
    }
    is(normalize_gs1_digital_link("HTTP://LOCALHOST:080/01/$gtin"),"http://localhost/01/$gtin");
    is(validate_gs1_digital_link("http://localhost/01/$gtin")->{warnings}[0]{code},'GS1_DIGITAL_LINK_HTTP');
    for my $host ('example.0x','1.2.3.256','example.123','example.0xff','例.jp','','[::1%25eth0]','[1:2:3:4:5:6:7]','[1:2:3:4:5:6:7:8:9]','[:::]','[1::2::3]','[::ffff:192.000.2.1]','[1.2.3.4::]','[::1]oops') {
        my $u="https://$host/01/$gtin";
        fails($host eq ''?'GS1_INVALID_DIGITAL_LINK_PLACEMENT':'GS1_DIGITAL_LINK_UNSUPPORTED_HOST',sub {parse_gs1_digital_link($u)},"reject host ".join('',map { ord($_)>127 ? sprintf("\\u{%x}",ord($_)) : $_ } split //,$host));
        ok(!validate_gs1_digital_link($u)->{ok});
    }
    my $shared=read_json('current-ts-gs1-shared49.json');my $shared_delta=read_json('native-shared-gs1-deltas3.json');
    my %shared_override=map {$_->{id}=>$_->{expected}} @{$shared_delta->{cases}};
    is(scalar @{$shared->{cases}},49,'all original shared GS1 operations retained');
    for my $row (@{$shared->{cases}}) {
        is_deeply(contract(evaluate($row->{request})),contract($shared_override{$row->{id}}//$row->{expected}),$row->{id});
    }
    open my $extra_bytes,'<:raw',"$FindBin::Bin/../verification/fixtures/url-compatibility-extra.json" or die $!;
    {local $/;is(sha256_hex(<$extra_bytes>),'ce84a1261b5d5d25143f240c67d0d2efb4fd32d053360ae3230c604c7d32cd14','independent extra URL targets are pinned');}
    my $extra=read_json('url-compatibility-extra.json');
    for my $row (@{$extra->{cases}}) {is_deeply(contract(evaluate($row->{request})),contract($row->{expected}),$row->{id});}
    for my $port ('-1','+443','65536','123456','a','443:80') { fails('GS1_DIGITAL_LINK_INVALID_URI',sub {parse_gs1_digital_link("https://example.com:$port/01/$gtin")}); }
    is(normalize_gs1_digital_link("https://example.com:00443/01/$gtin"),$uri);
    is(normalize_gs1_digital_link("https://example.com:00000/01/$gtin"),"https://example.com:0/01/$gtin");
    is(normalize_gs1_digital_link("https://example.com:65535/01/$gtin"),"https://example.com:65535/01/$gtin");
    for my $s ("$uri#x") { fails('GS1_DIGITAL_LINK_FRAGMENT_NOT_ALLOWED',sub {parse_gs1_digital_link($s)}); }
    for my $s ("ftp://example.com/01/$gtin","//example.com/01/$gtin","HTTPſ://example.com/01/$gtin") {
        fails('GS1_DIGITAL_LINK_INVALID_URI',sub {parse_gs1_digital_link($s)});
    }
};
subtest 'URL restoration retains strict security and data boundaries' => sub {
    for my $host ('4294967296','0x100000000','040000000000','1.16777216','1.2.65536','1.2.3.256','08','09','0xg.1','1.2.3.4.5','%2F','%3A','%40','%5B','%5C','%25','[:::]','[::ffff:192.000.2.1]',('9'x1000),('0x'.('f'x900))) {
        my $u="https://$host/01/$gtin";
        fails('GS1_DIGITAL_LINK_UNSUPPORTED_HOST',sub {parse_gs1_digital_link($u)});
        fails('GS1_DIGITAL_LINK_UNSUPPORTED_HOST',sub {normalize_gs1_digital_link($u)});
        ok(!validate_gs1_digital_link($u)->{ok});
    }
    for my $port ('65536',('9'x900)) {fails('GS1_DIGITAL_LINK_INVALID_URI',sub {parse_gs1_digital_link("https://example.com:$port/01/$gtin")});}
    for my $bad ('%','%0','%GG','%C0%AF','%ED%A0%80','%F4%90%80%80','%FF','%00','%E2%82') {
        for my $u ("https://$bad/01/$gtin","https://$bad\@example.com/01/$gtin","$uri/10/$bad","$uri?x=$bad") {
            fails('GS1_INVALID_PERCENT_ENCODING',sub {parse_gs1_digital_link($u)});
            ok(!validate_gs1_digital_link($u)->{ok});
        }
    }
    fails('GS1_INVALID_PERCENT_ENCODING',sub {parse_gs1_digital_link("$uri?x=\x00")});
    for my $host ('例.jp','bücher.example','%C3%BC.example') {fails('GS1_DIGITAL_LINK_UNSUPPORTED_HOST',sub {parse_gs1_digital_link("https://$host/01/$gtin")});}
    my $private='do-not-leak-user:do-not-leak-secret';
    my $result=validate_gs1_digital_link("https://$private\@example.com/01/bad");
    ok(!$result->{ok});unlike(JSON::PP->new->encode($result->{errors}),qr/do-not-leak/,'errors never disclose userinfo');
    for my $context ('.','..','%2e','%2e%2e') {
        for my $u ("https://example.com/01/$context/../01/$gtin","$uri/10/$context") {
            fails('GS1_INVALID_DIGITAL_LINK_PLACEMENT',sub {parse_gs1_digital_link($u)});
            fails('GS1_INVALID_DIGITAL_LINK_PLACEMENT',sub {normalize_gs1_digital_link($u)});
        }
    }
};
subtest 'all 1411 historical inputs with independent current compatibility mappings' => sub {
    my $data=read_json('gs1-upstream.json');my $deltas=read_json('gs1-perl-deltas.json');
    is($data->{upstreamCommit},'15ad15e5c770ea0e39072f8f88b2733018f02ffd');is(scalar @{$data->{cases}},1411);
    is($deltas->{oracleCommit},'4f9154664d35a24cecb30b75cfdba0a9f16ced3e');
    is(scalar @{$deltas->{differences}},252,'explicit independently verified profile and diagnostic differences');
    my %overrides=map {$_->{caseId}=>$_->{expected}} @{$deltas->{differences}};
    is(scalar(keys %overrides),252,'unique explicit delta case IDs');
    my $restored=read_json('approved-restorations80.json');my $migrated=read_json('diagnostic-migrations5.json');
    is(scalar @{$restored->{cases}},80,'80 independently pinned TypeScript positives');
    is(scalar @{$migrated->{cases}},5,'five explicitly mapped diagnostic precedences');
    for my $row (@{$restored->{cases}},@{$migrated->{cases}}) {
        my $f=$data->{cases}[$row->{caseId}];my %request=map {$_=>$f->{$_}} grep {$_ ne 'expected'} keys %$f;
        is_deeply($row->{request},\%request,'unchanged migrated historical input');
        $overrides{$row->{caseId}}=$row->{expected};
    }
    my $current_full=read_current_ts();
    for my $row (@{$restored->{cases}}) {is_deeply($row->{expected},$current_full->{cases}[$row->{caseId}]{expected},'positive expectation comes from TS');}

    open my $fixture_bytes,'<:raw',"$FindBin::Bin/../verification/fixtures/gs1-upstream.json" or die $!;
    { local $/; is(sha256_hex(<$fixture_bytes>),$deltas->{baselineSha256},'unchanged historical corpus digest'); }
    my $different=0;
    for my $id (0..$#{$data->{cases}}) {
        my $f=$data->{cases}[$id];my $expected=exists($overrides{$id})?$overrides{$id}:$f->{expected};
        my $actual=evaluate($f);
        is_deeply(contract($actual),contract($expected),"fixture $id $f->{op}");
        ++$different if exists $overrides{$id};
    }
    is($different,252,'no historical fixture skipped');
    my $audit=$deltas->{currentTsAudit};
    is($audit->{commit},'16efc6c0a8e397c9df3d051d20fce6c1eebdfad7');
    is(scalar @{$audit->{changes}},6,'current TS changed exactly six historical dot cases');
    my %current=map {$_->{caseId}=>$_->{expected}} @{$audit->{changes}};
    my $json=JSON::PP->new->canonical;my $delta_count=0;
    for my $id (0..$#{$data->{cases}}) {
        my $f=$data->{cases}[$id];
        my $upstream=exists($current{$id})?$current{$id}:$f->{expected};
        my $oracle=exists($overrides{$id})?$overrides{$id}:$upstream;
        ++$delta_count if $json->encode(contract($upstream)) ne $json->encode(contract($oracle));
        is_deeply(contract(evaluate($f)),contract($oracle),"current TS fixture $id $f->{op} with explicit Nim profile");
    }
    is($delta_count,168,'exact remaining current TS diagnostic/profile difference count');
};
done_testing;
