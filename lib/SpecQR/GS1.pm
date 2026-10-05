package SpecQR::GS1;
use 5.026;
use strict;
use warnings;
use Exporter 'import';
use B ();
use bytes ();
use Encode ();
use JSON::PP ();
use Scalar::Util qw(blessed reftype);

our @EXPORT_OK = qw(
  GS1_FNC1_SEPARATOR GS1_MAX_INPUT_CHARACTERS GS1_MAX_ELEMENTS
  get_supported_gs1_ais get_gs1_ai_info calculate_gs1_check_digit validate_gs1_check_digit
  calculate_gtin_check_digit append_gtin_check_digit validate_gtin_check_digit
  calculate_sscc_check_digit append_sscc_check_digit validate_sscc_check_digit
  normalize_gs1_elements parse_gs1_human_readable parse_gs1_element_string
  create_gs1_element_string gs1_to_human_readable gs1_element_string_to_human_readable
  validate_gs1_elements validate_gs1_element_string create_gs1_digital_link
  parse_gs1_digital_link validate_gs1_digital_link normalize_gs1_digital_link
  gs1_normalize gs1_from_human_readable gs1_to_element_string gs1_build gs1_parse
  gs1_digital_link gs1_to_digital_link
);
our %EXPORT_TAGS = (all => \@EXPORT_OK);
use constant GS1_FNC1_SEPARATOR => "\x1d";
use constant GS1_MAX_INPUT_CHARACTERS => 1_000_000;
use constant GS1_MAX_ELEMENTS => 16_384;

sub _bool { my $value=$_[0] ? 1 : 0; return bless \$value, 'JSON::PP::Boolean'; }
sub _fail {
    my ($message, $detail) = @_;
    require SpecQR::Error;
    eval { SpecQR::Error::fail('INVALID_GS1', $message) };
    my $error = $@;
    $error->{detailCode} = $detail // 'GS1_INVALID_INPUT';
    die $error;
}
sub _untied_args {
    for my $i (0..$#_) { _fail('GS1 arguments must not be tied scalars') if tied($_[$i]); }
}
sub _text {
    _untied_args(@_);
    my ($s, $label) = @_;
    $label //= 'GS1 text';
    _fail("$label must be a string to preserve leading zeroes")
      if !defined($s) || ref($s) || !(B::svref_2object(\$s)->FLAGS & B::SVp_POK());
    _fail("$label exceeds the byte work budget") if bytes::length($s) > 4 * GS1_MAX_INPUT_CHARACTERS;
    _fail("$label contains malformed internal Unicode") if !utf8::valid($s);
    _fail("$label exceeds the character work budget") if length($s) > GS1_MAX_INPUT_CHARACTERS;
    _fail("$label must be a Unicode character string, not non-ASCII bytes")
      if !utf8::is_utf8($s) && $s =~ /[^\x00-\x7f]/;
    _fail("$label must contain only Unicode scalar values") if $s =~ /[\x{d800}-\x{dfff}]|[^\x{0}-\x{10ffff}]/;
    _fail("$label exceeds the character work budget") if length($s) > GS1_MAX_INPUT_CHARACTERS;
    my $units = length($s);
    while ($s =~ /[\x{10000}-\x{10ffff}]/g) {
        _fail("$label exceeds the character work budget") if ++$units > GS1_MAX_INPUT_CHARACTERS;
    }
    return $s;
}
sub _array {
    _untied_args(@_);
    my ($x, $label) = @_;
    _fail("$label must be an unblessed, untied array reference")
      if ref($x) ne 'ARRAY' || blessed($x) || tied(@$x);
    _fail('GS1 element count exceeds limit') if @$x > GS1_MAX_ELEMENTS;
    for my $i (0..$#$x) { _fail("$label must not contain tied scalars") if tied($x->[$i]); }
    return $x;
}
sub _hash {
    _untied_args(@_);
    my ($x, $label) = @_;
    _fail("$label must be an unblessed, untied hash reference")
      if ref($x) ne 'HASH' || blessed($x) || tied(%$x);
    _fail("$label exceeds the field count budget") if keys(%$x) > GS1_MAX_ELEMENTS;
    for my $key (keys %$x) { _fail("$label must not contain tied scalar fields") if tied($x->{$key}); }
    return $x;
}
sub _options {
    my ($input, @allowed) = @_;
    return {} if !defined $input;
    _hash($input, 'GS1 options');
    my %allowed = map { $_ => 1 } @allowed;
    for my $key (keys %$input) { _fail("Unknown GS1 option $key") if !$allowed{$key}; }
    return { %$input };
}
sub _boolean {
    _untied_args(@_);
    my ($v, $label) = @_;
    if (ref($v)) {
        _fail("$label must be a genuine JSON::PP boolean")
          if !blessed($v) || blessed($v) ne 'JSON::PP::Boolean' || reftype($v) ne 'SCALAR' || tied($$v);
        $v=$$v;
    }
    _fail("$label must be boolean") if !defined($v) || ref($v) || !(B::svref_2object(\$v)->FLAGS & (B::SVp_IOK()|B::SVp_NOK())) || ($v != 0 && $v != 1);
    return $v ? 1 : 0;
}
sub _digits { defined($_[0]) && $_[0] =~ /\A[0-9]+\z/ }
sub _is_ai { defined($_[0]) && $_[0] =~ /\A[0-9]{2,4}\z/ }
sub _primary { $_[0] eq '00' || $_[0] eq '01' || $_[0] eq '414' }
sub _eligible { $_[1] eq '01' && ($_[0] eq '10' || $_[0] eq '21' || $_[0] eq '22') }
my (@CATALOG, %CATALOG);
sub _add {
    my ($ai, $label, $n, $variable, $kind, $check, $role) = @_;
    $kind //= 'numeric'; $check //= 'none'; $role //= 'data-attribute';
    my $entry = {
      ai => $ai, label => $label,
      length => $variable ? { type => 'variable', min => 1, max => $n, isVariable => _bool(1) }
                          : { type => 'fixed', exact => $n, isVariable => _bool(0) },
      valueKind => $kind, checkDigitRule => $check, digitalLinkRole => $role,
      separator => $variable ? 'required-when-followed' : 'none',
      digitalLinkPathForPrimary => $role eq 'key-qualifier' ? ['01'] : undef,
    };
    push @CATALOG, $entry; $CATALOG{$ai} = $entry;
}
_add('00', 'Serial shipping container code', 18, 0, 'numeric', 'sscc', 'primary-key');
_add('01', 'Global trade item number', 14, 0, 'numeric', 'gtin', 'primary-key');
_add('02', 'Contained trade item GTIN', 14, 0, 'numeric', 'gtin');
_add('10', 'Batch or lot number', 20, 1, 'text', 'none', 'key-qualifier');
for my $p (['11','Production date'], ['12','Due date'], ['13','Packaging date'],
  ['15','Best before date'], ['16','Sell by date'], ['17','Expiration date']) { _add(@$p, 6); }
_add('20', 'Internal product variant', 2);
_add('21', 'Serial number', 20, 1, 'text', 'none', 'key-qualifier');
_add('22', 'Consumer product variant', 20, 1, 'text', 'none', 'key-qualifier');
_add('30', 'Variable count', 8, 1); _add('37', 'Count of contained trade items', 8, 1);
for my $p (['240','Additional product identification'], ['241','Customer part number'],
  ['400','Customer purchase order number']) { _add(@$p, 30, 1, 'text'); }
for my $p (['410','Ship to global location number'], ['411','Bill to global location number'],
  ['412','Purchased from global location number'], ['413','Ship for global location number'],
  ['414','Identification of a physical location'], ['415','Global location number of the invoicing party']) {
    _add(@$p, 13, 0, 'numeric', 'none', $p->[0] eq '414' ? 'primary-key' : 'data-attribute');
}
_add('420','Ship to postal code',20,1,'text');
for my $p (['422','Country of origin'], ['424','Country of processing'],
  ['425','Country of disassembly'], ['426','Country covering full process chain']) { _add(@$p,3); }
for my $p ([3100,'Net weight in kilograms'],[3200,'Net weight in pounds']) {
    for my $ai ($p->[0] .. $p->[0]+5) { _add("$ai",$p->[1],6); }
}
for my $ai (91..99) { _add("$ai",'Company internal information',90,1,'text'); }
sub _copy_info {
    my ($e) = @_; return undef if !defined $e;
    return { %$e, length => {%{$e->{length}}, isVariable => _bool($e->{length}{isVariable})},
      digitalLinkPathForPrimary => defined($e->{digitalLinkPathForPrimary}) ? [@{$e->{digitalLinkPathForPrimary}}] : undef };
}
sub get_supported_gs1_ais { _untied_args(@_);  return [map { _copy_info($_) } @CATALOG]; }
sub get_gs1_ai_info { _untied_args(@_);  my $ai = _text($_[0], 'GS1 AI'); return _copy_info($CATALOG{$ai}); }
sub _numeric {
    my ($value,$label) = @_; my $s = _text($value,$label);
    _fail("$label must contain digits only",'GS1_INVALID_CHARSET') if !_digits($s); return $s;
}
sub calculate_gs1_check_digit { _untied_args(@_); 
    my $s = _numeric($_[0],'GS1 check digit input'); my ($total,$weight) = (0,3);
    for (my $i = length($s)-1; $i >= 0; --$i) {
        $total = ($total + (ord(substr($s,$i,1))-48)*$weight)%10; $weight=4-$weight;
    }
    return ''.((10-$total)%10);
}
sub validate_gs1_check_digit { _untied_args(@_); 
    my $s = _numeric($_[0], 'GS1 check digit value');
    _fail('GS1 check digit value must include body and check digit','GS1_INVALID_LENGTH') if length($s)<2;
    return _bool(calculate_gs1_check_digit(substr($s,0,-1)) eq substr($s,-1));
}
sub calculate_gtin_check_digit { _untied_args(@_); 
    my $s = _numeric($_[0], 'GTIN body');
    _fail('GTIN body must be 7, 11, 12, or 13 digits','GS1_INVALID_LENGTH') if length($s) !~ /\A(?:7|11|12|13)\z/;
    return calculate_gs1_check_digit($s);
}
sub append_gtin_check_digit { _untied_args(@_);  my $digit=calculate_gtin_check_digit($_[0]); return $_[0].$digit; }
sub validate_gtin_check_digit { _untied_args(@_); 
    my $s = _numeric($_[0], 'GTIN');
    _fail('GTIN must be 8, 12, 13, or 14 digits','GS1_INVALID_LENGTH') if length($s) !~ /\A(?:8|12|13|14)\z/;
    return validate_gs1_check_digit($s);
}
sub calculate_sscc_check_digit { _untied_args(@_); 
    my $s = _numeric($_[0], 'SSCC body');
    _fail('SSCC body must be exactly 17 digits','GS1_INVALID_LENGTH') if length($s)!=17;
    return calculate_gs1_check_digit($s);
}
sub append_sscc_check_digit { _untied_args(@_);  my $digit=calculate_sscc_check_digit($_[0]); return $_[0].$digit; }
sub validate_sscc_check_digit { _untied_args(@_); 
    my $s = _numeric($_[0], 'SSCC');
    _fail('SSCC must be exactly 18 digits','GS1_INVALID_LENGTH') if length($s)!=18;
    return validate_gs1_check_digit($s);
}
sub _bounded_elements {
    my ($elements)=@_; _array($elements, 'GS1 elements');
    _fail('GS1 element count exceeds limit') if @$elements > GS1_MAX_ELEMENTS;
    my $work=0;
    for my $e (@$elements) {
        _hash($e,'GS1 element');
        for my $field ('ai','value') {
            my $s=_text($e->{$field},"GS1 element $field");
            $work += length(Encode::encode('UTF-8',$s,Encode::FB_CROAK() | Encode::LEAVE_SRC()));
            _fail('GS1 aggregate text exceeds input budget') if $work > GS1_MAX_INPUT_CHARACTERS;
        }
    }
}
sub _element {
    my ($e,$i)=@_; $i //= 0; _hash($e,"GS1 element $i");
    my $ai=_text($e->{ai},"GS1 element $i AI");
    my $value=_text($e->{value},"GS1 element $i value");
    _fail("GS1 element $i AI must be a 2 to 4 digit string") if !_is_ai($ai);
    my $info=$CATALOG{$ai}; _fail("Unsupported GS1 AI $ai",'GS1_UNSUPPORTED_AI') if !$info;
    my $prefix="GS1 AI $ai value";
    _fail("$prefix must not be empty",'GS1_INVALID_LENGTH') if !length($value);
    _fail("$prefix must not contain the FNC1 separator",'GS1_UNEXPECTED_SEPARATOR') if index($value,"\x1d")>=0;
    _fail("$prefix must be raw data without human-readable parentheses") if $value =~ /[()]/;
    _fail("$prefix must use printable ASCII characters",'GS1_INVALID_CHARSET') if $value =~ /[^\x20-\x7e]/;
    _fail("$prefix must contain digits only",'GS1_INVALID_CHARSET') if $info->{valueKind} eq 'numeric' && !_digits($value);
    if ($info->{length}{isVariable}) {
        _fail("$prefix must be at most $info->{length}{max} characters",'GS1_INVALID_LENGTH') if length($value)>$info->{length}{max};
    } else {
        _fail("$prefix must be exactly $info->{length}{exact} characters",'GS1_INVALID_LENGTH') if length($value)!=$info->{length}{exact};
    }
    _fail("$prefix has an invalid GTIN check digit",'GS1_INVALID_CHECK_DIGIT')
      if $info->{checkDigitRule} eq 'gtin' && !validate_gtin_check_digit($value);
    _fail("$prefix has an invalid SSCC check digit",'GS1_INVALID_CHECK_DIGIT')
      if $info->{checkDigitRule} eq 'sscc' && !validate_sscc_check_digit($value);
    return {ai=>$ai,value=>$value};
}
sub normalize_gs1_elements { _untied_args(@_); 
    my ($input)=@_;
    if (!ref($input)) { my $s=_text($input); return substr($s,0,1) eq '(' ? parse_gs1_human_readable($s) : parse_gs1_element_string($s)->{elements}; }
    if (ref($input) eq 'HASH') { _hash($input,'GS1 parse result'); $input=$input->{elements}; }
    _bounded_elements($input); _fail('GS1 elements must not be empty') if !@$input;
    return [map { _element($input->[$_],$_) } 0..$#$input];
}
sub _ascii_input {
    my ($input,$label)=@_; my $s=_text($input,$label);
    _fail("$label must use ASCII characters",'GS1_INVALID_CHARSET') if $s =~ /[^\x00-\x7f]/;
    _fail("$label must not be empty") if !length($s); return $s;
}
sub _push {
    my ($a,$e)=@_; _fail('GS1 element count exceeds limit') if @$a>=GS1_MAX_ELEMENTS; push @$a,$e;
}
sub parse_gs1_human_readable { _untied_args(@_); 
    my $s=_ascii_input($_[0],'GS1 human-readable input'); my (@out,$p); $p=0;
    while ($p<length($s)) {
        _fail("GS1 AI must be parenthesized at offset $p") if substr($s,$p,1) ne '(';
        my $q=index($s,')',$p+1); _fail("GS1 AI is missing closing parenthesis at offset $p") if $q<0;
        my $stop=index($s,'(',$q+1); $stop=length($s) if $stop<0;
        _push(\@out,_element({ai=>substr($s,$p+1,$q-$p-1),value=>substr($s,$q+1,$stop-$q-1)},scalar @out));
        $p=$stop;
    }
    return \@out;
}
sub _read_ai {
    my ($s,$pos)=@_;
    for my $n (4,3,2) { my $a=substr($s,$pos,$n); return $CATALOG{$a} if length($a)==$n && exists $CATALOG{$a}; }
    return undef;
}
sub parse_gs1_element_string { _untied_args(@_); 
    my $s=_ascii_input($_[0],'GS1 element string'); _fail('GS1 element string must be raw data without parentheses') if $s =~ /[()]/;
    my (@out,$p); $p=0;
    while ($p<length($s)) {
        _fail("Unexpected FNC1 separator at offset $p",'GS1_UNEXPECTED_SEPARATOR') if substr($s,$p,1) eq "\x1d";
        my $info=_read_ai($s,$p); _fail("Unsupported GS1 AI at offset $p",'GS1_UNSUPPORTED_AI') if !$info;
        my $start=$p+length($info->{ai}); my $stop;
        if ($info->{length}{isVariable}) { $stop=index($s,"\x1d",$start); $stop=length($s) if $stop<0; }
        else { $stop=$start+$info->{length}{exact}; $stop=length($s) if $stop>length($s); }
        if ($info->{length}{isVariable} && $stop==length($s)) {
            my $off=$start+1; $off=$stop-22 if $stop-22>$off;
            for (; $off<$stop; ++$off) {
                my $tail=_read_ai($s,$off);
                _fail("GS1 variable field is missing an FNC1 separator before offset $off",'GS1_MISSING_SEPARATOR')
                  if $tail && !$tail->{length}{isVariable} && $off+length($tail->{ai})+$tail->{length}{exact}==$stop;
            }
        }
        _push(\@out,_element({ai=>$info->{ai},value=>substr($s,$start,$stop-$start)},scalar @out));
        $p=$stop;
        if ($info->{length}{isVariable} && $p<length($s)) {
            ++$p; _fail('GS1 element string must not end with an FNC1 separator','GS1_UNEXPECTED_SEPARATOR') if $p>=length($s);
        }
    }
    return {elements=>\@out,hasSeparators=>_bool(index($s,"\x1d")>=0)};
}
sub create_gs1_element_string { _untied_args(@_); 
    my $values=normalize_gs1_elements($_[0]); my $out='';
    for my $i (0..$#$values) {
        my $e=$values->[$i]; $out.=$e->{ai}.$e->{value};
        $out.=GS1_FNC1_SEPARATOR if $i<$#$values && $CATALOG{$e->{ai}}{length}{isVariable};
        _fail('GS1 output exceeds character budget') if length($out)>GS1_MAX_INPUT_CHARACTERS;
    }
    return $out;
}
sub gs1_to_human_readable { _untied_args(@_); 
    my $s=join '',map {'('.$_->{ai}.')'.$_->{value}} @{normalize_gs1_elements($_[0])}; return _text($s,'GS1 output');
}
sub gs1_element_string_to_human_readable { _untied_args(@_);  return gs1_to_human_readable(parse_gs1_element_string($_[0])->{elements}); }

my %REASON = (
  GS1_UNSUPPORTED_AI=>'unsupported-ai',GS1_INVALID_LENGTH=>'invalid-length',GS1_INVALID_CHARSET=>'invalid-charset',
  GS1_MISSING_SEPARATOR=>'missing-separator',GS1_UNEXPECTED_SEPARATOR=>'unexpected-separator',GS1_INVALID_CHECK_DIGIT=>'invalid-check-digit',
  GS1_INVALID_PERCENT_ENCODING=>'invalid-percent-encoding',GS1_INVALID_DIGITAL_LINK_PLACEMENT=>'invalid-digital-link-placement',
  GS1_DUPLICATE_AI=>'duplicate-ai',GS1_DIGITAL_LINK_UNKNOWN_QUERY=>'unknown-query',GS1_DIGITAL_LINK_UNSUPPORTED_HOST=>'unsupported-host',
  GS1_DIGITAL_LINK_INVALID_URI=>'invalid-uri',GS1_DIGITAL_LINK_FRAGMENT_NOT_ALLOWED=>'fragment-not-allowed',
);
sub _is_error { return blessed($_[0]) && $_[0]->isa('SpecQR::Error'); }
sub _issue {
    my ($e,$element,$index)=@_; die $e if !_is_error($e);
    my $code=$e->{detailCode}//'GS1_INVALID_INPUT'; my $message=$e->{message};
    my $issue={code=>$code,message=>$message,reason=>$REASON{$code}//'invalid-input',
      map { $_=>undef } qw(ai value key offset elementIndex expected count)};
    if (ref($element) eq 'HASH' && !blessed($element) && !tied(%$element)) {
        for my $field ('ai','value') {
            my $s=$element->{$field};
            if (defined($s) && !ref($s) && (B::svref_2object(\$s)->FLAGS & B::SVp_POK()) && length($s)<=($field eq 'ai'?4:90)) {
                my $checked=eval { _text($s) }; $issue->{$field}=$checked if !$@;
            }
        }
    }
    $issue->{ai}=$1 if !defined($issue->{ai}) && $message =~ /GS1 AI ([0-9]{2,4})(?![0-9])/;
    $issue->{offset}=0+$1 if $message =~ /offset ([0-9]+)/;
    $issue->{elementIndex}=$index if defined $index;
    $issue->{expected}='ASCII DNS name, canonical dotted IPv4, or RFC IPv6' if $code eq 'GS1_DIGITAL_LINK_UNSUPPORTED_HOST';
    return $issue;
}
sub _failure {
    my ($e,$digital)=@_; my $out={ok=>_bool(0),errors=>[_issue($e)],warnings=>[]};
    if ($digital) { $out->{result}=undef; } else { $out->{elements}=undef; $out->{hasSeparators}=undef; }
    return $out;
}
sub _validation_options {
    my $o=_options($_[0],qw(context collectAllErrors allowUnsupportedAi));
    $o->{context}=exists($o->{context}) ? _text($o->{context},'GS1 context') : 'element-string';
    _fail('GS1 validation context must be element-string or digital-link') if $o->{context} ne 'element-string' && $o->{context} ne 'digital-link';
    $o->{collectAllErrors}=exists($o->{collectAllErrors}) ? _boolean($o->{collectAllErrors},'GS1 collectAllErrors') : 1;
    if (exists($o->{allowUnsupportedAi})) { _fail('GS1 validation allowUnsupportedAi must be false') if _boolean($o->{allowUnsupportedAi},'GS1 allowUnsupportedAi'); }
    return $o;
}
sub validate_gs1_elements { my $guard=eval { _untied_args(@_); 1 }; return _failure($@) if !$guard; 
    my ($input,$options)=@_; my $result; my $success=eval {
        my $o=_validation_options($options); _bounded_elements($input); _fail('GS1 elements must not be empty') if !@$input;
        my (@normal,@errors);
        for my $i (0..$#$input) {
            my $e=eval { _element($input->[$i],$i) };
            if ($@) { push @errors,_issue($@,$input->[$i],$i); last if !$o->{collectAllErrors}; }
            else { push @normal,$e; }
        }
        if (@errors) { $result={ok=>_bool(0),elements=>undef,hasSeparators=>undef,errors=>\@errors,warnings=>[]}; }
        else {
            _fail('GS1 Digital Link requires primary AI 00, 01, or 414','GS1_INVALID_DIGITAL_LINK_PLACEMENT')
              if $o->{context} eq 'digital-link' && !grep {_primary($_->{ai})} @normal;
            $result={ok=>_bool(1),elements=>\@normal,hasSeparators=>undef,errors=>[],warnings=>[]};
        }
        1;
    };
    return $success ? $result : _failure($@);
}
sub validate_gs1_element_string { my $guard=eval { _untied_args(@_); 1 }; return _failure($@) if !$guard; 
    my ($input,$options)=@_; my $result; my $success=eval {
        _validation_options($options); my $p=parse_gs1_element_string($input);
        $result=validate_gs1_elements($p->{elements},$options); $result->{hasSeparators}=$p->{hasSeparators}; 1;
    };
    return $success ? $result : _failure($@);
}

sub _percent_fail { _fail('GS1 URI must use valid percent-encoding and UTF-8 without NUL','GS1_INVALID_PERCENT_ENCODING'); }
sub _decode {
    my ($s,$form)=@_;
    _percent_fail() if $s =~ /%(?![0-9A-Fa-f]{2})/;
    my $bytes=Encode::encode('UTF-8',$s,Encode::FB_CROAK() | Encode::LEAVE_SRC());
    $bytes =~ tr/+/ / if $form;
    $bytes =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;
    my $decoded=eval { Encode::decode('UTF-8',$bytes,Encode::FB_CROAK() | Encode::LEAVE_SRC()) };
    _percent_fail() if $@ || !defined($decoded) || $decoded =~ /\x00|[\x{d800}-\x{dfff}]|[^\x{0}-\x{10ffff}]/;
    return $decoded;
}
sub _encode {
    my ($s,$form)=@_; my $bytes=Encode::encode('UTF-8',$s,Encode::FB_CROAK() | Encode::LEAVE_SRC());
    if ($form) { $bytes =~ s/([^A-Za-z0-9*._ -])/sprintf('%%%02X',ord($1))/ge; $bytes =~ tr/ /+/; }
    else { $bytes =~ s/([^A-Za-z0-9*._~!'()\-])/sprintf('%%%02X',ord($1))/ge; }
    return $bytes;
}
sub _split {
    my ($s,$separator,$limit)=@_; my $n=()=$s =~ /\Q$separator\E/g;
    _fail('GS1 URL component count exceeds limit') if $n >= $limit;
    return [split /\Q$separator\E/,$s,-1];
}
sub _pair {
    my ($s)=@_; my $at=index($s,'=');
    return $at<0 ? {key=>_decode($s,1),value=>''} : {key=>_decode(substr($s,0,$at),1),value=>_decode(substr($s,$at+1),1)};
}
sub _ipv4 {
    my ($s)=@_; my @parts=split /\./,$s,-1; return 0 if @parts!=4;
    for my $part (@parts) { return 0 if $part !~ /\A(?:0|[1-9][0-9]{0,2})\z/ || $part>255; } return 1;
}
sub _ipv6_side {
    my ($s,$allow_ipv4)=@_; return 0 if $s eq ''; my @parts=split /:/,$s,-1; my $n=0;
    for my $i (0..$#parts) {
        my $part=$parts[$i]; return -1 if $part eq '';
        if (index($part,'.')>=0) { return -1 if !$allow_ipv4 || $i!=$#parts || !_ipv4($part); $n+=2; }
        else { return -1 if $part !~ /\A[0-9A-Fa-f]{1,4}\z/; ++$n; }
    }
    return $n;
}
sub _ipv6 {
    my ($s)=@_; my @parts=split /::/,$s,-1;
    return _ipv6_side($parts[0],1)==8 if @parts==1;
    if (@parts==2) { my $a=_ipv6_side($parts[0]);my $b=_ipv6_side($parts[1],1); return $a>=0 && $b>=0 && $a+$b<8; }
    return 0;
}
sub _host_fail { _fail('Unsupported host profile; use an ASCII URL host or RFC IPv6','GS1_DIGITAL_LINK_UNSUPPORTED_HOST'); }
sub _ipv4_number {
    my ($s)=@_; return -1 if $s eq '';
    my $radix=10;
    if ($s =~ s/\A0[xX]//) { $radix=16; }
    elsif (length($s)>=2 && $s =~ s/\A0//) { $radix=8; }
    my $n=0;
    for my $c (split //,$s) {
        my $d=index('0123456789abcdef',lc($c)); return -1 if $d<0 || $d >= $radix;
        # Saturate before arithmetic, then keep validating every remaining digit.
        $n=$n>int((4294967295-$d)/$radix) ? 4294967296 : $n*$radix+$d if $n<4294967296;
    }
    return $n;
}
sub _normalize_ipv4_host {
    my ($host)=@_; my @parts=split /\./,$host,-1; pop @parts if @parts>1 && $parts[-1] eq '';
    my $last=$parts[-1]; return $host if $last !~ /\A[0-9]+\z/ && _ipv4_number($last)<0;
    _host_fail() if @parts>4;
    my @numbers=map {_ipv4_number($_)} @parts;
    _host_fail() if grep {$_<0 || $_>4294967295} @numbers;
    for my $i (0..$#numbers-1) { _host_fail() if $numbers[$i]>255; }
    _host_fail() if $numbers[-1] >= 2**(8*(5-@numbers));
    my $address=$numbers[-1];
    for my $i (0..$#numbers-1) { $address += $numbers[$i] << (8*(3-$i)); }
    return join('.',map {($address >> $_)&255} (24,16,8,0));
}
sub _ipv6_groups {
    my ($s)=@_; return () if $s eq ''; my @groups;
    for my $part (split /:/,$s,-1) {
        if (index($part,'.')>=0) { my @b=split /\./,$part; push @groups,($b[0]<<8)|$b[1],($b[2]<<8)|$b[3]; }
        else { push @groups,hex($part); }
    }
    return @groups;
}
sub _normalize_ipv6 {
    my ($s)=@_; my @sides=split /::/,$s,-1; my @groups=_ipv6_groups($sides[0]);
    if (@sides==2) { my @right=_ipv6_groups($sides[1]); push @groups,(0)x(8-@groups-@right),@right; }
    my ($best,$size,$at)=(-1,1,0);
    while ($at<8) {
        if ($groups[$at]!=0) { ++$at; next; }
        my $start=$at; ++$at while $at<8 && $groups[$at]==0;
        ($best,$size)=($start,$at-$start) if $at-$start>$size;
    }
    my @hex=map {sprintf('%x',$_)} @groups;
    return join(':',@hex) if $best<0;
    return join(':',@hex[0..$best-1]).'::'.join(':',@hex[$best+$size..7]);
}
sub _userinfo_encode {
    my ($s)=@_; my $bytes=Encode::encode('UTF-8',$s,Encode::FB_CROAK() | Encode::LEAVE_SRC());
    $bytes =~ s/([\x00-\x20\x7f-\xff"#\/:;<=>?@\[\\\]^`{|}])/sprintf('%%%02X',ord($1))/ge;
    return $bytes;
}
sub _authority {
    my ($s,$scheme)=@_; _host_fail() if length($s)<1 || length($s)>1024;
    my $userinfo=''; my $at_sign=rindex($s,'@');
    if ($at_sign>=0) {
        my $raw=substr($s,0,$at_sign); _decode($raw); # Validate, never re-decode credential bytes.
        my $colon=index($raw,':');
        my $username=_userinfo_encode($colon<0?$raw:substr($raw,0,$colon));
        my $password=$colon<0?'':_userinfo_encode(substr($raw,$colon+1));
        $userinfo=$username.($password ne ''?':'.$password:'').'@' if $username ne '' || $password ne '';
        $s=substr($s,$at_sign+1);
    }
    my ($host,$port);
    if (substr($s,0,1) eq '[') {
        my $close=index($s,']'); _host_fail() if $close<0;
        my $address=substr($s,1,$close-1); _host_fail() if !_ipv6($address); $host='['._normalize_ipv6($address).']';
        my $tail=substr($s,$close+1);
        if (length($tail)) { _host_fail() if substr($tail,0,1) ne ':'; $port=substr($tail,1); }
    } else {
        my $at=index($s,':'); $host=_decode($at<0?$s:substr($s,0,$at)); $port=substr($s,$at+1) if $at>=0;
        # URL reg-names are not restricted to DNS labels. Full UTS46 is not
        # supplied by Perl core; do not implement an incomplete IDNA substitute.
        _host_fail() if $host eq '' || $host =~ /[\x00-\x20\x7f-\x{10ffff}#%\/:<>?@\[\\\]^|]/;
        $host=_normalize_ipv4_host(lc($host));
    }
    if (defined($port) && $port ne '') {
        _fail('GS1 port must contain decimal digits from 0 to 65535','GS1_DIGITAL_LINK_INVALID_URI') if $port !~ /\A[0-9]+\z/;
        my $n=0;
        for my $digit (split //,$port) {
            $n=$n*10+ord($digit)-48;
            _fail('GS1 port must be from 0 to 65535','GS1_DIGITAL_LINK_INVALID_URI') if $n>65535;
        }
        $host.=':'.$n if !(($scheme eq 'http' && $n==80)||($scheme eq 'https' && $n==443));
    }
    return $userinfo.$host;
}
sub _url {
    my $s=_text($_[0],'GS1 Digital Link URI');
    _percent_fail() if index($s,"\x00")>=0;
    $s =~ s/\A[\x00-\x20]+|[\x00-\x20]+\z//g; $s =~ tr/\t\n\r//d;
    my $fragment=index($s,'#'); my $empty_fragment=$fragment>=0;
    if ($fragment>=0) {
        _fail('GS1 Digital Link URI must not include a fragment','GS1_DIGITAL_LINK_FRAGMENT_NOT_ALLOWED') if $fragment!=length($s)-1;
        $s=substr($s,0,$fragment);
    }
    my $query_at=index($s,'?'); my $head=$query_at<0?$s:substr($s,0,$query_at); my $query=$query_at<0?undef:substr($s,$query_at+1);
    $head =~ tr{\\}{/}; # Query backslashes remain literal payload data.
    _fail('GS1 URI must be an absolute http or https URL','GS1_DIGITAL_LINK_INVALID_URI') if $head !~ /\A([Hh][Tt][Tt][Pp][Ss]?):\/*([^\/]*)(.*)\z/s;
    my ($scheme,$authority,$path)=(lc($1),$2,$3); $authority=_authority($authority,$scheme);
    # WHATWG path serialization, without erasing GS1 dot segments.
    $path=Encode::encode('UTF-8',$path,Encode::FB_CROAK() | Encode::LEAVE_SRC());
    $path =~ s/([\x00-\x20\x7f-\xff"#<>?^`{}])/sprintf('%%%02X',ord($1))/ge;
    _decode($_) for @{_split($path,'/',2*GS1_MAX_ELEMENTS+1)};
    _pair($_) for defined($query) ? @{_split($query,'&',GS1_MAX_ELEMENTS)} : ();
    return {scheme=>$scheme,authority=>$authority,path=>$path,query=>$query,emptyFragment=>$empty_fragment};
}
sub _url_base { $_[0]{scheme}.'://'.$_[0]{authority} }
sub _check_primary {
    my $s=_text($_[0],'GS1 primaryAi'); _fail('GS1 primaryAi must be one of 00, 01, or 414') if !_primary($s); return $s;
}
sub _policy {
    my $s=_text($_[0],'GS1 unknownQuery'); _fail('GS1 unknownQuery must be preserve or reject') if $s ne 'preserve' && $s ne 'reject'; return $s;
}
sub _placement {
    my ($ai,$primary)=@_; _fail("Unsupported GS1 AI $ai",'GS1_UNSUPPORTED_AI') if !$CATALOG{$ai};
    _fail("GS1 AI $ai cannot be placed in the Digital Link path after primary AI $primary",'GS1_INVALID_DIGITAL_LINK_PLACEMENT') if !_eligible($ai,$primary);
}
sub _unique {
    my ($seen,$ai)=@_; _fail("GS1 Digital Link must not contain duplicate AI $ai",'GS1_DUPLICATE_AI') if $seen->{$ai}; $seen->{$ai}=1;
}
sub _prefix {
    my ($parts)=@_; my @stack;
    for my $part (@$parts) { my $decoded=_decode($part); next if $decoded eq '' || $decoded eq '.';
        if ($decoded eq '..') { pop @stack if @stack; } else { push @stack,$part; }
    }
    return @stack ? '/'.join('/',@stack) : '';
}
sub _path_parts {
    my ($path)=@_; $path =~ s{\A/+|/+\z}{}g;
    _fail('GS1 Digital Link path must include primary AI 00, 01, or 414','GS1_INVALID_DIGITAL_LINK_PLACEMENT') if !length($path);
    my $parts=_split($path,'/',2*GS1_MAX_ELEMENTS+1);
    _fail('GS1 Digital Link path must not contain empty segments') if grep {$_ eq ''} @$parts; return $parts;
}
sub _first_ai {
    my ($parts,$primary)=@_;
    for my $i (0..$#$parts) { return $i if $primary eq '' ? _primary($parts->[$i]) : $parts->[$i] eq $primary; }
    _fail('GS1 Digital Link path must include primary AI 00, 01, or 414','GS1_INVALID_DIGITAL_LINK_PLACEMENT');
}
sub create_gs1_digital_link { _untied_args(@_); 
    my ($elements,$options)=@_; my $o=_options($options,qw(baseUrl primaryAi pathAis explicitPathAis));
    my $primary=_check_primary(exists($o->{primaryAi})?$o->{primaryAi}:'01');
    my $base=_url(exists($o->{baseUrl})?$o->{baseUrl}:'https://id.gs1.org');
    _fail('GS1 Digital Link baseUrl must not include query components') if defined($base->{query}) && $base->{query} ne '';
    my $ais=exists($o->{pathAis})?_array($o->{pathAis},'GS1 pathAis'):[];
    _fail('GS1 element count exceeds limit') if @$ais>GS1_MAX_ELEMENTS;
    my $explicit=exists($o->{pathAis}) ? 1 : 0;
    $explicit=_boolean($o->{explicitPathAis},'GS1 explicitPathAis') if exists $o->{explicitPathAis};
    my %paths;
    for my $entry (@$ais) {
        my $ai=_text($entry,'GS1 pathAis entry'); _fail('GS1 pathAis entries must be 2 to 4 digit AI strings') if !_is_ai($ai);
        if ($ai ne $primary) { _placement($ai,$primary); $paths{$ai}=1; }
    }
    my $values=normalize_gs1_elements($elements); my (%seen,$selected);
    for my $i (0..$#$values) { _unique(\%seen,$values->[$i]{ai}); $selected=$i if $values->[$i]{ai} eq $primary; }
    _fail("GS1 input must include primary AI $primary",'GS1_INVALID_DIGITAL_LINK_PLACEMENT') if !defined $selected;
    my @path=($values->[$selected]); my @query;
    for my $i (0..$#$values) {
        next if $i==$selected; my $e=$values->[$i];
        my $in_path=($explicit || @$ais) ? $paths{$e->{ai}} : _eligible($e->{ai},$primary);
        if ($in_path && $e->{value} ne '.' && $e->{value} ne '..') { _placement($e->{ai},$primary); push @path,$e; }
        else { push @query,$e; }
    }
    @query=sort {$a->{ai} cmp $b->{ai} || $a->{value} cmp $b->{value}} @query;
    my $stem=_prefix(_split($base->{path},'/',2*GS1_MAX_ELEMENTS+1));
    for my $part (@{_split($stem,'/',2*GS1_MAX_ELEMENTS+1)}) {
        _fail('GS1 base URL normalized path must not contain a primary AI component (00, 01, or 414), including percent-encoded equivalents','GS1_INVALID_DIGITAL_LINK_PLACEMENT') if _primary(_decode($part));
    }
    my $out=_url_base($base).$stem;
    $out.='/'. _encode($_->{ai}).'/'. _encode($_->{value}) for @path;
    $out.='?'.join('&',map {_encode($_->{ai},1).'='._encode($_->{value},1)} @query) if @query;
    $out.='#' if $base->{emptyFragment};
    return _text($out,'GS1 Digital Link output');
}
sub _parse_link {
    my ($url,$primary,$policy)=@_; _check_primary($primary) if length($primary); _policy($policy);
    my $parts=_path_parts($url->{path}); my $start=_first_ai($parts,$primary);
    for my $i ($start..$#$parts) {
        my $d=_decode($parts->[$i]);
        _fail('GS1 Digital Link path values must not be dot segments; place these values in the query','GS1_INVALID_DIGITAL_LINK_PLACEMENT') if $d eq '.' || $d eq '..';
    }
    _fail('GS1 Digital Link path must contain AI/value pairs') if (@$parts-$start)%2;
    my (%seen,@path,@query,@unknown);
    for (my $i=$start;$i<@$parts;$i+=2) {
        my $ai=$parts->[$i]; _fail('GS1 Digital Link path segment '.($i+1).' must be a GS1 AI') if !_is_ai($ai);
        my $e=_element({ai=>$ai,value=>_decode($parts->[$i+1])},scalar @path);
        _placement($ai,$path[0]{ai}) if @path; _unique(\%seen,$ai); _push(\@path,$e);
    }
    for my $raw (defined($url->{query}) ? @{_split($url->{query},'&',GS1_MAX_ELEMENTS)} : ()) {
        next if $raw eq ''; my $pair=_pair($raw);
        if (_is_ai($pair->{key})) {
            my $e=_element({ai=>$pair->{key},value=>$pair->{value}},scalar(@path)+scalar(@query));
            _unique(\%seen,$e->{ai}); _push(\@query,$e);
        } elsif ($policy eq 'preserve') { push @unknown,$pair; }
        else { _fail('GS1 Digital Link query parameter is not a GS1 AI','GS1_DIGITAL_LINK_UNKNOWN_QUERY'); }
        _fail('GS1 element and query pair count exceeds limit') if @path+@query+@unknown>GS1_MAX_ELEMENTS;
    }
    return {elements=>[@path,@query],primary=>{%{$path[0]}},pathElements=>\@path,queryElements=>\@query,unknownQuery=>\@unknown};
}
sub _link_options {
    my ($options,@extra)=@_; my $o=_options($options,qw(primaryAi unknownQuery),@extra);
    $o->{primaryAi}=exists($o->{primaryAi})?_text($o->{primaryAi},'GS1 primaryAi'):'';
    $o->{unknownQuery}=exists($o->{unknownQuery})?_text($o->{unknownQuery},'GS1 unknownQuery'):'preserve'; return $o;
}
sub parse_gs1_digital_link { _untied_args(@_); 
    my ($input,$options)=@_; my $o=_link_options($options); return _parse_link(_url($input),$o->{primaryAi},$o->{unknownQuery});
}
sub validate_gs1_digital_link { my $guard=eval { _untied_args(@_); 1 }; return _failure($@,1) if !$guard; 
    my ($input,$options)=@_; my $result; my $success=eval {
        my $o=_link_options($options,'normalize');
        _fail('GS1 validation normalize is unsupported; call normalize_gs1_digital_link') if exists($o->{normalize}) && _boolean($o->{normalize},'GS1 normalize');
        my $url=_url($input); my $p=_parse_link($url,$o->{primaryAi},$o->{unknownQuery}); my @warnings;
        push @warnings,{code=>'GS1_DIGITAL_LINK_HTTP',message=>'URI uses HTTP; use HTTPS when transport security is required',reason=>'http-uri'} if $url->{scheme} eq 'http';
        push @warnings,{code=>'GS1_DIGITAL_LINK_UNKNOWN_QUERY_PRESERVED',message=>'Non-GS1 query parameters are preserved',reason=>'unknown-query-preserved',count=>scalar @{$p->{unknownQuery}}} if @{$p->{unknownQuery}};
        $result={ok=>_bool(1),result=>$p,errors=>[],warnings=>\@warnings}; 1;
    };
    return $success ? $result : _failure($@,1);
}
sub normalize_gs1_digital_link { _untied_args(@_); 
    my ($input,$options)=@_; my $o=_link_options($options,'mode');
    my $mode=exists($o->{mode})?_text($o->{mode},'GS1 mode'):'specqr-deterministic'; _fail('GS1 normalization mode must be specqr-deterministic') if $mode ne 'specqr-deterministic';
    my $url=_url($input); my $p=_parse_link($url,$o->{primaryAi},$o->{unknownQuery});
    my $parts=_path_parts($url->{path}); my $start=_first_ai($parts,$o->{primaryAi});
    my $stem=_url_base($url)._prefix([@$parts[0..$start-1]]);
    my $out=create_gs1_digital_link($p->{elements},{baseUrl=>$stem,primaryAi=>$p->{primary}{ai}});
    for my $pair (@{$p->{unknownQuery}}) { $out.=(index($out,'?')>=0?'&':'?')._encode($pair->{key},1).'='._encode($pair->{value},1); }
    return _text($out,'GS1 Digital Link output');
}
sub gs1_normalize { goto &normalize_gs1_elements }
sub gs1_from_human_readable { goto &parse_gs1_human_readable }
sub gs1_to_element_string { goto &create_gs1_element_string }
sub gs1_build { goto &create_gs1_element_string }
sub gs1_parse { goto &parse_gs1_element_string }
sub gs1_digital_link { goto &create_gs1_digital_link }
sub gs1_to_digital_link { goto &create_gs1_digital_link }
1;
