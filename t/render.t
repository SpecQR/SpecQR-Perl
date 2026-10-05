use strict; use warnings; use utf8;
use Test::More;
use lib 'lib';
use SpecQR::API qw(generate);
use SpecQR::Render qw(:all);
use SpecQR::Error ();
sub error_code { my($code,$body,$label)=@_; eval {$body->()}; my $e=$@; ok(ref($e) eq 'SpecQR::Error'&&$e->{code} eq $code,$label) or diag("$e"); }
my $q=generate('HELLO WORLD',{maskPattern=>0});
my $svg=to_svg($q); like($svg,qr/^<svg .*width="232" height="232"/,'default geometry scale8 margin4');
like($svg,qr{<path fill="#000000" d="M},'SVG paths');
is(to_svg_data_url($q),'data:image/svg+xml;charset=utf-8,'.do {my $x=$svg;$x =~ s/([^A-Za-z0-9~!*'()._\-])/sprintf('%%%02X',ord($1))/ge;$x},'exact SVG data URL');
my $pix=to_pixels($q); is($pix->{width},232,'width'); is(length($pix->{pixels}),232*232*4,'RGBA size'); ok(!utf8::is_utf8($pix->{pixels}),'pixels octets');
is(substr($pix->{pixels},0,232*32*4),pack('C4',255,255,255,255)x(232*32),'top quiet zone white');
for my $y (0..20) { for my $x (0..20) { my $want=$q->{matrix}[$y][$x]?pack('C4',0,0,0,255):pack('C4',255,255,255,255); is(substr($pix->{pixels},((($y+4)*8)*232+($x+4)*8)*4,4),$want,"pixel $x,$y"); } }
my $png=to_png($q); is(substr($png,0,8),"\x89PNG\r\n\x1a\n",'PNG signature'); ok(!utf8::is_utf8($png),'PNG octets'); is(substr($png,-12),"\x00\x00\x00\x00IEND\xaeB`\x82",'PNG IEND/CRC');
is(unpack('N',substr($png,16,4)),232,'PNG width'); is(unpack('N',substr($png,20,4)),232,'PNG height');
like(to_png_data_url($q),qr/^data:image\/png;base64,iVBORw0KGgo/,'PNG URL');
is_deeply(parse_color('#abc'),[170,187,204,255],'short RGB'); is_deeply(parse_color('#abcd'),[170,187,204,221],'short RGBA'); is_deeply(parse_color('#01234567'),[1,35,69,103],'long RGBA');
is(parse_color('navy',0),undef,'SVG names supported but not inspected'); is(contrast_ratio([0,0,0,255],[255,255,255,255]),21,'contrast21');
my $d=render_dimensions($q,undef,300); cmp_ok(abs($d->{moduleSizeMm}-8/300*25.4),'<',1e-12,'print geometry');
for my $color ('','red"/>','url(x)','#ab','#ggg','rgb(0,0,0)','a'x65,1,[]) { error_code('INVALID_COLOR',sub {parse_color($color)},'invalid color'); }
error_code('INVALID_COLOR',sub {to_png($q,{foreground=>'navy'})},'unknown PNG color rejects');
for my $o ({scale=>0},{scale=>1_000_000_001},{margin=>-1},{margin=>1_000_000_000},{scale=>'8'},{scale=>[]},{bogus=>1}) { error_code('INVALID_INPUT',sub {to_png($q,$o)},'invalid geometry/options'); }
error_code('INVALID_INPUT',sub {to_png($q,{scale=>71,margin=>4})},'raster budget');
for my $dpi (0,-1,1e-305,'300',[]) { error_code('INVALID_INPUT',sub {render_dimensions($q,undef,$dpi)},'invalid DPI'); }
my $ragged=[[1]]; error_code('INVALID_INPUT',sub {to_svg($ragged)},'ragged matrix rejects');
my $rgba=to_pixels($q,{scale=>1,margin=>0,foreground=>'#1234',background=>'transparent'}); is(length($rgba->{pixels}),21*21*4,'RGBA colored bitmap');

{ package RenderTieValue; sub TIESCALAR {bless {v=>$_[1]},$_[0]} sub FETCH {$_[0]{v}} }
for my $key (qw(scale foreground)) { my %o; tie $o{$key},'RenderTieValue',$key eq 'scale'?1:'#000000'; error_code('INVALID_INPUT',sub {to_svg($q,\%o)},'tied render option rejects'); }
my $tied_matrix=[map {[(0)x21]} 1..21]; tie $tied_matrix->[0][0],'RenderTieValue',1;
error_code('INVALID_INPUT',sub {to_pixels($tied_matrix)},'tied matrix module rejects');
for my $bad_boolean (bless([], 'JSON::PP::Boolean'),do {my $v=2;bless \$v,'JSON::PP::Boolean'}) {
 my $matrix=[map {[(0)x21]} 1..21];$matrix->[0][0]=$bad_boolean;
 error_code('INVALID_INPUT',sub {to_svg($matrix)},'forged boolean module rejects with typed error');
}
tie my $tied_result,'RenderTieValue',$q; error_code('INVALID_INPUT',sub {to_svg($tied_result)},'tied result rejects');
tie my $tied_color,'RenderTieValue','#000'; error_code('INVALID_INPUT',sub {parse_color($tied_color)},'tied color rejects');

done_testing;
