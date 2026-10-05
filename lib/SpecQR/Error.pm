package SpecQR::Error;
use 5.026; use strict; use warnings;
use Exporter 'import'; use Scalar::Util qw(blessed refaddr reftype); use B qw(svref_2object SVp_IOK SVp_NOK SVp_POK); use POSIX qw(isfinite);
use overload '""' => sub { $_[0]{code}.': '.$_[0]{message} }, fallback => 1;
our @EXPORT_OK=qw(fail require_integer require_range require_number require_string require_array require_hash require_bool is_integer is_number is_string is_bool copy_json_checked);
sub new { my($class,$code,$message)=@_; bless {code=>$code,message=>$message},$class }
sub code { $_[0]{code} } sub message { $_[0]{message} }
sub fail { die __PACKAGE__->new($_[0],$_[1]) }
sub _flags { svref_2object(\$_[0])->FLAGS }
sub is_number { !tied($_[0]) && defined($_[0]) && !ref($_[0]) && (_flags($_[0]) & (SVp_IOK|SVp_NOK)) && isfinite($_[0]) }
sub is_integer { is_number($_[0]) && $_[0]==int($_[0]) }
sub is_string { !tied($_[0]) && defined($_[0]) && !ref($_[0]) && (_flags($_[0]) & SVp_POK) }
sub is_bool { !tied($_[0]) && ((blessed($_[0]) && blessed($_[0]) eq 'JSON::PP::Boolean' && reftype($_[0]) eq 'SCALAR' && !tied(${$_[0]}) && is_integer(${$_[0]}) && (${$_[0]}==0 || ${$_[0]}==1)) || (is_integer($_[0]) && ($_[0]==0 || $_[0]==1))) }
sub require_number { fail('INVALID_INPUT','Tied values are not supported') if tied($_[0]); my($v,$label,$code)=@_; $code//='INVALID_INPUT'; fail($code,($label//'Value').' must be a finite number') unless is_number($v); $v }
sub require_integer { fail('INVALID_INPUT','Tied values are not supported') if tied($_[0]); my($v,$label,$code)=@_; $code//='INVALID_INPUT'; fail($code,($label//'Value').' must be an integer') unless is_integer($v); $v }
sub require_range { fail('INVALID_INPUT','Tied values are not supported') if tied($_[0]); my($v,$lo,$hi,$label,$code)=@_; $code//='INVALID_INPUT'; require_integer($v,$label,$code); fail($code,($label//'Value').' is outside its supported range') if $v<$lo || $v>$hi; $v }
sub require_string { fail('INVALID_INPUT','Tied values are not supported') if tied($_[0]); my($v,$label,$code)=@_; $code//='INVALID_INPUT'; fail($code,($label//'Value').' must be a character string') unless is_string($v); fail($code,($label//'Value').' must contain Unicode scalars') if !utf8::valid($v) || (utf8::is_utf8($v) && $v =~ /[^\x{0000}-\x{d7ff}\x{e000}-\x{10ffff}]/); $v }
sub require_array { fail('INVALID_INPUT','Tied values are not supported') if tied($_[0]); my($v,$label,$code)=@_; $code//='INVALID_INPUT'; fail($code,($label//'Value').' must be an unblessed array reference') unless ref($v) eq 'ARRAY' && !tied(@$v); $v }
sub require_hash { fail('INVALID_INPUT','Tied values are not supported') if tied($_[0]); my($v,$label,$code)=@_; $code//='INVALID_INPUT'; fail($code,($label//'Value').' must be an unblessed hash reference') unless ref($v) eq 'HASH' && !tied(%$v); for my $k (keys %$v) { fail($code, 'Tied hash members are not supported') if tied($v->{$k}) } $v }
sub require_bool { fail('INVALID_INPUT','Tied values are not supported') if tied($_[0]); my($v,$label,$code)=@_; $code//='INVALID_INPUT'; fail($code,($label//'Value').' must be a boolean') unless is_bool($v); $v ? 1:0 }
sub copy_json_checked {
 fail('INVALID_INPUT','Tied values are not supported') if tied($_[0]); my($input)=@_; my(%active,$visited); $visited=0; my $copy; $copy=sub {
  fail('INVALID_INPUT','Tied values are not supported') if tied($_[0]); my($v,$depth)=@_; fail('INVALID_INPUT','Diagnostics exceed tree budget') if $depth>64 || ++$visited>1_000_000;
  return undef unless defined $v;
  if (is_bool($v) && blessed($v)) { my $owned=$v?1:0; return bless \$owned,'JSON::PP::Boolean' }
  if(!ref $v) { fail('INVALID_INPUT','Diagnostics must contain Unicode scalar strings') if !utf8::valid($v) || (utf8::is_utf8($v) && $v =~ /[^\x{0000}-\x{d7ff}\x{e000}-\x{10ffff}]/); fail('INVALID_INPUT','Diagnostics scalar exceeds budget') if length($v)>4_000_000; fail('INVALID_INPUT','Diagnostics contain a non-finite number') if (_flags($v)&(SVp_IOK|SVp_NOK)) && !isfinite($v); return $v }
  fail('INVALID_INPUT','Diagnostics must be an unblessed JSON tree') unless (ref($v) eq 'ARRAY' && !tied(@$v)) || (ref($v) eq 'HASH' && !tied(%$v));
  my $id=refaddr($v); fail('INVALID_INPUT','Diagnostics must not contain cycles') if $active{$id}; local $active{$id}=1;
  return ref($v) eq 'ARRAY' ? [map {$copy->($_,$depth+1)} @$v] : {map {$_=>$copy->($v->{$_},$depth+1)} keys %$v};
 }; return $copy->($input,0);
}
1;
