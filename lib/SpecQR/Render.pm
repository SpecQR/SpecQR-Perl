package SpecQR::Render;
use 5.026;
use strict;
use warnings;
use Exporter 'import';
use Scalar::Util qw(blessed looks_like_number);
use POSIX qw(isfinite);
use MIME::Base64 qw(encode_base64);
use SpecQR::Error qw(fail is_number is_string require_hash require_array require_bool require_range);
our @EXPORT_OK = qw(color_text parse_color contrast_ratio geometry to_svg to_pixels to_png to_svg_data_url to_png_data_url render_dimensions);
our %EXPORT_TAGS = (all => \@EXPORT_OK);
use constant RASTER_PIXEL_BUDGET => 4*1024*1024;
use constant SVG_CHARACTER_BUDGET => 8*1024*1024;
use constant DATA_URL_CHARACTER_BUDGET => 32*1024*1024;
use constant MAX_GEOMETRY_INTEGER => 1_000_000_000;

sub _reject_tied_args { for my $arg (@_) { fail('INVALID_INPUT','Tied values are not supported') if tied($arg); } }
sub _integer {
    my ($v,$lo,$hi,$label)=@_;
    fail('INVALID_INPUT',"$label must be an integer in $lo..$hi")
        if !is_number($v) || int($v)!=$v || $v<$lo || $v>$hi;
    return 0+$v;
}
sub _options {
    _reject_tied_args(@_);
    my ($raw)=@_; $raw={} unless defined $raw;
    require_hash($raw,'Render options');
    fail('INVALID_INPUT','Render options must be an ordinary hash') if ref($raw) ne 'HASH' || tied(%$raw);
    my %o=(margin=>4,scale=>8,foreground=>'#000000',background=>'#ffffff');
    for my $k (keys %$raw) { fail('INVALID_INPUT',"Unknown render option: $k") unless exists $o{$k}; $o{$k}=$raw->{$k}; }
    $o{margin}=_integer($o{margin},0,MAX_GEOMETRY_INTEGER,'Margin');
    $o{scale}=_integer($o{scale},1,MAX_GEOMETRY_INTEGER,'Scale');
    $o{foreground}=color_text($o{foreground}); $o{background}=color_text($o{background});
    return \%o;
}
sub _matrix {
    _reject_tied_args(@_);
    my ($arg,$raw)=@_;
    if (ref($arg) eq 'HASH') {
        require_hash($arg,'QR result');
        if (!defined $raw && ref($arg->{options}) eq 'HASH') {
            require_hash($arg->{options},'QR options');
            $raw={ map { $_=>$arg->{options}{$_} } qw(margin scale foreground background) };
        }
        $arg=$arg->{matrix};
    }
    require_array($arg,'Matrix');
    fail('INVALID_INPUT','Matrix must be a square array of 21..177 modules') if ref($arg) ne 'ARRAY' || tied(@$arg) || @$arg<21 || @$arg>177 || (@$arg-17)%4;
    my $n=@$arg;
    for my $row (@$arg) {
        require_array($row,'Matrix row');
        fail('INVALID_INPUT','Matrix rows must have equal lengths') if ref($row) ne 'ARRAY' || tied(@$row) || @$row!=$n;
        for my $b (@$row) {
            require_bool($b,'Matrix module');
        }
    }
    return ($arg,_options($raw));
}
sub color_text {
    _reject_tied_args(@_);
    my ($v)=@_;
    fail('INVALID_COLOR','Color must be a short ASCII string') unless is_string($v) && utf8::valid($v);
    fail('INVALID_COLOR','Color must be a short ASCII string') if length($v)>64 || $v =~ /[^\x00-\x7f]/;
    $v =~ s/\A[\x09-\x0d\x20]+|[\x09-\x0d\x20]+\z//g;
    fail('INVALID_COLOR','Color must be hex or a simple ASCII CSS name') unless $v =~ /\A(?:\#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})|[A-Za-z]+)\z/;
    return $v;
}
sub parse_color {
    _reject_tied_args(@_);
    my ($v,$strict)=@_; $strict=1 unless defined $strict;
    my $s=lc color_text($v);
    return [0,0,0,255] if $s eq 'black';
    return [255,255,255,255] if $s eq 'white';
    return [0,0,0,0] if $s eq 'transparent';
    if ($s =~ s/\A#//) {
        my @c=length($s)<=4 ? map {hex($_)*17} split(//,$s) : map {hex($_)} ($s =~ /(..)/g);
        push @c,255 if @c==3;
        return \@c;
    }
    fail('INVALID_COLOR','Raster colors require hex, black, white, or transparent') if $strict;
    return undef;
}
sub contrast_ratio {
    _reject_tied_args(@_);
    my ($fg,$bg)=@_;
    for my $c ($fg,$bg) {
        require_array($c,'RGBA','INVALID_COLOR');
        fail('INVALID_COLOR','RGBA requires four channels') if ref($c) ne 'ARRAY' || tied(@$c) || @$c!=4;
        for (@$c) { require_range($_,0,255,'Color channel','INVALID_COLOR'); }
    }
    my ($a,$b)=(0,0); my @weights=(0.2126,0.7152,0.0722);
    for my $i (0..2) {
        my $back=$bg->[$i]/255*($bg->[3]/255)+1-$bg->[3]/255;
        my $front=$fg->[$i]/255*($fg->[3]/255)+$back*(1-$fg->[3]/255);
        my $fl=$front<=0.04045 ? $front/12.92 : (($front+0.055)/1.055)**2.4;
        my $bl=$back<=0.04045 ? $back/12.92 : (($back+0.055)/1.055)**2.4;
        $a+=$fl*$weights[$i]; $b+=$bl*$weights[$i];
    }
    return $a>$b ? ($a+0.05)/($b+0.05) : ($b+0.05)/($a+0.05);
}
sub _geometry {
    my ($m,$o,$raster)=@_; my $n=@$m;
    fail('INVALID_INPUT','Render geometry exceeds bound') if $o->{margin}>int((MAX_GEOMETRY_INTEGER-$n)/2);
    my $span=$n+2*$o->{margin};
    fail('INVALID_INPUT','Render geometry exceeds bound') if $o->{scale}>int(MAX_GEOMETRY_INTEGER/$span);
    my $d=$span*$o->{scale};
    fail('INVALID_INPUT','Raster exceeds pixel budget') if $raster && $d>2048;
    return $d;
}
sub geometry { _reject_tied_args(@_); my ($arg,$raw,$raster)=@_; my ($m,$o)=_matrix($arg,$raw); return _geometry($m,$o,$raster); }
sub to_svg {
    _reject_tied_args(@_);
    my ($arg,$raw)=@_; my ($m,$o)=_matrix($arg,$raw); my $d=_geometry($m,$o,0);
    my ($fg,$bg,$s,$margin)=@$o{qw(foreground background scale margin)};
    my $out=qq{<svg xmlns="http://www.w3.org/2000/svg" width="$d" height="$d" viewBox="0 0 $d $d" role="img"><rect width="100%" height="100%" fill="$bg"/><path fill="$fg" d="};
    for my $y (0..$#$m) { for my $x (0..$#$m) { $out.='M'.(($x+$margin)*$s).','.(($y+$margin)*$s)."h${s}v${s}h-${s}z" if $m->[$y][$x]; } }
    $out.='"/></svg>';
    fail('INVALID_INPUT','SVG exceeds character budget') if length($out)>SVG_CHARACTER_BUDGET;
    return $out;
}
sub to_pixels {
    _reject_tied_args(@_);
    my ($arg,$raw)=@_; my ($m,$o)=_matrix($arg,$raw); my $d=_geometry($m,$o,1);
    my $fg=pack('C4',@{parse_color($o->{foreground})}); my $bg=pack('C4',@{parse_color($o->{background})});
    my $s=$o->{scale}; my $margin=$o->{margin}; my $edge=$bg x ($margin*$s);
    my $blank=$bg x $d; my $pixels=$blank x ($margin*$s);
    for my $row (@$m) { my $r=$edge; $r.=($_ ? $fg : $bg) x $s for @$row; $r.=$edge; $pixels.=$r x $s; }
    $pixels.=$blank x ($margin*$s);
    return {width=>$d,height=>$d,pixels=>$pixels};
}
my @CRC;
for my $i (0..255) { my $c=$i; $c=($c>>1)^(($c&1)?0xedb88320:0) for 1..8; push @CRC,$c; }
sub _crc32 {
    my ($data)=@_; my $c=0xffffffff;
    for (my $at=0; $at<length($data); $at+=4096) { for my $v (unpack('C*',substr($data,$at,4096))) { $c=$CRC[($c^$v)&255]^($c>>8); } }
    return ($c^0xffffffff)&0xffffffff;
}
sub _adler32 {
    my ($data)=@_; my ($a,$b)=(1,0);
    for (my $at=0; $at<length($data); $at+=5552) { for my $v (unpack('C*',substr($data,$at,5552))) { $a+=$v; $b+=$a; } $a%=65521; $b%=65521; }
    return ($b<<16)|$a;
}
sub _chunk { my ($kind,$data)=@_; return pack('N',length($data)).$kind.$data.pack('N',_crc32($kind.$data)); }
sub to_png {
    _reject_tied_args(@_);
    my ($arg,$o)=@_; my $image=to_pixels($arg,$o); my $d=$image->{width}; my $stride=4*$d; my $raw='';
    for my $y (0..$d-1) { $raw.="\0".substr($image->{pixels},$y*$stride,$stride); }
    my $z="\x78\x01";
    for (my $at=0; $at<length($raw);) { my $n=length($raw)-$at; $n=65535 if $n>65535; $z.=pack('Cvv',($at+$n==length($raw)?1:0),$n,$n^65535).substr($raw,$at,$n); $at+=$n; }
    $z.=pack('N',_adler32($raw));
    return "\x89PNG\r\n\x1a\n"._chunk('IHDR',pack('NNCCCCC',$d,$d,8,6,0,0,0))._chunk('IDAT',$z)._chunk('IEND','');
}
sub to_svg_data_url {
    _reject_tied_args(@_);
    my $s=to_svg(@_); fail('INVALID_INPUT','SVG URL exceeds budget') if length($s)>int((DATA_URL_CHARACTER_BUDGET-31)/3);
    $s =~ s/([^A-Za-z0-9~!*'()._\-])/sprintf('%%%02X',ord($1))/ge;
    return 'data:image/svg+xml;charset=utf-8,'.$s;
}
sub to_png_data_url {
    _reject_tied_args(@_);
    my $png=to_png(@_); fail('INVALID_INPUT','PNG URL exceeds budget') if int((length($png)+2)/3)*4+22>DATA_URL_CHARACTER_BUDGET;
    return 'data:image/png;base64,'.encode_base64($png,'');
}
sub render_dimensions {
    _reject_tied_args(@_);
    my ($arg,$raw,$dpi)=@_; my ($m,$o)=_matrix($arg,$raw); my $d=_geometry($m,$o,0);
    my $r={width=>$d,height=>$d,modulePixels=>$o->{scale},marginModules=>$o->{margin},dpi=>$dpi,moduleSizeMm=>undef,symbolSizeMm=>undef};
    if (defined $dpi) {
        fail('INVALID_INPUT','DPI must be numeric, finite and positive') if !is_number($dpi) || $dpi<=0;
        my $mm=$o->{scale}/$dpi*25.4; my $symbol=$d/$dpi*25.4;
        fail('INVALID_INPUT','Print geometry must be finite and positive') if !isfinite($mm) || !isfinite($symbol) || $mm<=0 || $symbol<=0;
        $r->{moduleSizeMm}=$mm; $r->{symbolSizeMm}=$symbol;
    }
    return $r;
}
1;
