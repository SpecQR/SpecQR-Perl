package SpecQR::Core;
use 5.026; use strict; use warnings; use Exporter 'import';
use SpecQR::Error qw(fail require_range require_array require_bool); use SpecQR::Tables qw(data_codeword_count block_info format_bits qr_size alignment_positions level_index raw_codeword_count);
our @EXPORT_OK=qw(copy_matrix validate_matrix pad_data_bits gf_multiply reed_solomon_divisor reed_solomon_remainder interleave_codewords mask_condition penalty_score build_matrix);
sub copy_matrix { validate_matrix($_[0]);[map {[map {$_?1:0} @$_]} @{$_[0]}] }
sub _blank {my($n)=@_;[map {[(0)x$n]} 1..$n]}
sub validate_matrix {my($m)=@_;require_array($m,'Matrix');fail('INVALID_INPUT','Matrix must be square, 1..177 modules') if @$m<1||@$m>177;for my $r(@$m){require_array($r,'Matrix row');fail('INVALID_INPUT','Matrix must be square') unless @$r==@$m;require_bool($_,'Matrix module') for @$r}return}
sub _checked_bytes {my($d)=@_;require_array($d,'Codewords');fail('INVALID_INPUT','QR codeword count exceeds 3706') if @$d>3706;require_range($_,0,255,'Codeword') for @$d;return}
sub pad_data_bits {
 my($bits,$v,$level)=@_;my $cap=data_codeword_count($v,$level);require_array($bits,'Bits');fail('DATA_TOO_LONG','Bits exceed data capacity') if @$bits>$cap*8;my @out=(0)x$cap;
 for my $i(0..$#$bits){my $b=require_range($bits->[$i],0,1,'Bit');$out[int($i/8)]|=$b<<(7-$i%8)}
 my $remaining=$cap*8-@$bits;my $terminated=@$bits+($remaining<4?$remaining:4);my $bytes=int(($terminated+7)/8);for my $i($bytes..$cap-1){$out[$i]=($i-$bytes)%2==0?0xec:0x11}return \@out;
}
sub _gf {my($a,$b)=@_;my $r=0;while($b){$r^=$a if $b&1;$b>>=1;$a<<=1;$a^=0x11d if $a&0x100}return $r}
sub gf_multiply {require_range($_[0],0,255,'GF left operand');require_range($_[1],0,255,'GF right operand');_gf(@_)}
my %DIVISORS;
sub reed_solomon_divisor {
 my($degree)=@_;require_range($degree,1,255,'RS degree');return [@{$DIVISORS{$degree}}] if $DIVISORS{$degree};my @out=(1,(0)x$degree);my $root=1;
 for my $factor(0..$degree-1){for(my $i=$factor+1;$i>=1;--$i){$out[$i]^=_gf($out[$i-1],$root)}$root=_gf($root,2)}$DIVISORS{$degree}=[@out];return \@out;
}
sub _remainder {my($data,$div)=@_;my $degree=@$div-1;my @out=(0)x$degree;for my $b(@$data){my $factor=$b^$out[0];for my $i(0..$degree-2){$out[$i]=$out[$i+1]^_gf($div->[$i+1],$factor)}$out[-1]=_gf($div->[-1],$factor)}return \@out}
sub reed_solomon_remainder {_checked_bytes($_[0]);_remainder($_[0],reed_solomon_divisor($_[1]))}
sub interleave_codewords {
 my($data,$v,$level)=@_;my $info=block_info($v,$level);_checked_bytes($data);fail('INVALID_INPUT','Wrong data codeword count') unless @$data==$info->{dataCodewords};my $shortCount=$info->{blocks}-$info->{rawCodewords}%$info->{blocks};my $shortLength=int($info->{rawCodewords}/$info->{blocks})-$info->{eccPerBlock};my $div=reed_solomon_divisor($info->{eccPerBlock});my(@blocks,@codewords);my $offset=0;
 for my $i(0..$info->{blocks}-1){my $n=$shortLength+($i>=$shortCount?1:0);my $d=[@$data[$offset..$offset+$n-1]];push @blocks,{data=>$d,ecc=>_remainder($d,$div)};$offset+=$n}
 for my $col(0..$shortLength){for my $b(@blocks){push @codewords,$b->{data}[$col] if $col<@{$b->{data}}}}
 for my $col(0..$info->{eccPerBlock}-1){push @codewords,$_->{ecc}[$col] for @blocks}
 fail('INVALID_INPUT','Inconsistent interleaving') unless $offset==@$data&&@codewords==$info->{rawCodewords};return {codewords=>\@codewords,blocks=>\@blocks,dataCodewords=>$info->{dataCodewords},totalCodewords=>$info->{rawCodewords},errorCorrectionCodewords=>$info->{rawCodewords}-$info->{dataCodewords}};
}
sub _mask {
 my($m,$x,$y)=@_;return ($x+$y)%2==0 if $m==0;return $y%2==0 if $m==1;return $x%3==0 if $m==2;return ($x+$y)%3==0 if $m==3;return (int($y/2)+int($x/3))%2==0 if $m==4;return ($x*$y)%2+($x*$y)%3==0 if $m==5;return (($x*$y)%2+($x*$y)%3)%2==0 if $m==6;return (($x+$y)%2+($x*$y)%3)%2==0;
}
sub mask_condition {require_range($_[0],0,7,'Mask');require_range($_[1],0,176,'Column');require_range($_[2],0,176,'Row');_mask(@_)?1:0}
sub _line_penalty {my($line)=@_;my($color,$length,$window,$score)=(-1,0,0,0);for my $i(0..$#$line){my $value=$line->[$i]?1:0;if($value==$color){++$length}else{$score+=$length-2 if $length>=5;$color=$value;$length=1}$window=(($window<<1)|$value)&0x7ff;$score+=40 if $i>=10&&($window==0b10111010000||$window==0b00001011101)}$score+=$length-2 if $length>=5;return $score}
sub _penalty {my($m)=@_;my $n=@$m;my($score,$dark)=(0,0);for my $i(0..$n-1){$score+=_line_penalty($m->[$i]);my @col;for my $j(0..$n-1){push @col,$m->[$j][$i];$dark+=$m->[$j][$i]?1:0}$score+=_line_penalty(\@col)}for my $y(0..$n-2){for my $x(0..$n-2){my $a=$m->[$y][$x]?1:0;$score+=3 if $a==($m->[$y][$x+1]?1:0)&&$a==($m->[$y+1][$x]?1:0)&&$a==($m->[$y+1][$x+1]?1:0)}}$score+=int(abs($dark*20-$n*$n*10)/($n*$n))*10;return $score}
sub penalty_score {validate_matrix($_[0]);_penalty($_[0])}
sub _set {my($g,$x,$y,$dark)=@_;if($x>=0&&$x<$g->{side}&&$y>=0&&$y<$g->{side}){$g->{modules}[$y][$x]=$dark?1:0;$g->{functions}[$y][$x]=1}}
sub _finder {my($g,$left,$top)=@_;for my $dy(-1..7){for my $dx(-1..7){my $inside=$dx>=0&&$dx<=6&&$dy>=0&&$dy<=6;_set($g,$left+$dx,$top+$dy,$inside&&($dx==0||$dx==6||$dy==0||$dy==6||($dx>=2&&$dx<=4&&$dy>=2&&$dy<=4)))}}}
sub _format {
 my($g,$level,$mask)=@_;my $data=(format_bits($level)<<3)|$mask;my $rem=$data;for(1..10){$rem=($rem<<1)^((($rem>>9)&1)*0x537)}my $bits=(($data<<10)|$rem)^0x5412;
 _set($g,8,$_,($bits>>$_)&1) for 0..5;_set($g,8,7,($bits>>6)&1);_set($g,8,8,($bits>>7)&1);_set($g,7,8,($bits>>8)&1);_set($g,14-$_,8,($bits>>$_)&1) for 9..14;_set($g,$g->{side}-1-$_,8,($bits>>$_)&1) for 0..7;_set($g,8,$g->{side}-15+$_,($bits>>$_)&1) for 8..14;
}
sub _functions {
 my($g,$v,$level)=@_;_finder($g,0,0);_finder($g,$g->{side}-7,0);_finder($g,0,$g->{side}-7);for my $i(8..$g->{side}-9){_set($g,$i,6,$i%2==0);_set($g,6,$i,$i%2==0)}my $pos=alignment_positions($v);
 for my $yi(0..$#$pos){for my $xi(0..$#$pos){next if ($xi==0&&$yi==0)||($xi==$#$pos&&$yi==0)||($xi==0&&$yi==$#$pos);my($x,$y)=($pos->[$xi],$pos->[$yi]);for my $dy(-2..2){for my $dx(-2..2){my $max=abs($dx)>abs($dy)?abs($dx):abs($dy);_set($g,$x+$dx,$y+$dy,$max!=1)}}}}
 _format($g,$level,0);_set($g,8,$g->{side}-8,1);
 if($v>=7){my $rem=$v;for(1..12){$rem=($rem<<1)^((($rem>>11)&1)*0x1f25)}my $bits=($v<<12)|$rem;for my $i(0..17){my $a=$g->{side}-11+$i%3;my $b=int($i/3);_set($g,$a,$b,($bits>>$i)&1);_set($g,$b,$a,($bits>>$i)&1)}}
}
sub _draw_codewords {
 my($g,$words)=@_;my $at=0;my $right=$g->{side}-1;while($right>=1){$right=5 if $right==6;for my $vertical(0..$g->{side}-1){my $y=(($right+1)&2)==0?$g->{side}-1-$vertical:$vertical;for my $x($right,$right-1){unless($g->{functions}[$y][$x]){$g->{modules}[$y][$x]=($words->[int($at/8)]>>(7-$at%8))&1 if $at<@$words*8;++$at}}}$right-=2}fail('INVALID_INPUT','Inconsistent data-module count') if $at-@$words*8<0||$at-@$words*8>7;
}
sub build_matrix {
 my($words,$v,$level,$mask)=@_;$mask=-1 unless defined $mask;my $n=qr_size($v);level_index($level);require_range($mask,-1,7,'Mask');_checked_bytes($words);fail('INVALID_INPUT','Wrong interleaved codeword count') unless @$words==raw_codeword_count($v);my $base={side=>$n,modules=>_blank($n),functions=>_blank($n)};_functions($base,$v,$level);_draw_codewords($base,$words);my $out={penalty=>9e15,maskPenalties=>[]};
 for my $m($mask<0?(0..7):($mask)){my $g={side=>$n,modules=>[map {[@$_]} @{$base->{modules}}],functions=>$base->{functions}};for my $y(0..$n-1){for my $x(0..$n-1){$g->{modules}[$y][$x]^=1 if !$g->{functions}[$y][$x]&&_mask($m,$x,$y)}}_format($g,$level,$m);my $score=_penalty($g->{modules});push @{$out->{maskPenalties}},{maskPattern=>$m,penalty=>$score};if($score<$out->{penalty}){@$out{qw(matrix maskPattern penalty)}=($g->{modules},$m,$score)}}return $out;
}
1;
