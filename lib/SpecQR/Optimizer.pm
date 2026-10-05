package SpecQR::Optimizer;
use 5.026; use strict; use warnings; use Exporter 'import';
use SpecQR::Error qw(fail require_hash require_bool require_string require_range require_array); use SpecQR::Tables qw(validate_version character_count_bits); use SpecQR::Segments qw(@DATA_MODES strict_text alpha_value can_encode_kanji new_segment byte_segment eci MAX_PAYLOAD_UNITS MAX_SINGLE_SYMBOL_CHARACTERS);
our @EXPORT_OK=qw(new_segment_optimization_tracker append_character optimal_bits optimize_segments create_segments);
sub new_segment_optimization_tracker { for my $arg (@_) { fail('INVALID_INPUT','Tied values are not supported') if tied($arg) }
 my($v,$allow)=@_;$v//=1;$allow=1 unless defined $allow;validate_version($v);$allow=require_bool($allow,'allowKanji');
 {version=>$v,allowKanji=>$allow,offsets=>[0],costs=>[0],counts=>[0],previous=>[0],chosen=>[0],queues=>[map {[map {{values=>[],head=>0}} 0..2]} 0..3],keys=>[map {[]} 0..3],widths=>[map {character_count_bits($v,$_)} @DATA_MODES]}
}
sub _base {my($t,$m,$at)=@_;return 10*int($at/3) if $m==0;return 11*int($at/2) if $m==1;return 13*$at if $m==2;8*$t->{offsets}[$at]}
sub _eligible {my($c,$m,$allow)=@_;return $c=~/\A[0-9]\z/ if $m==0;return alpha_value($c)>=0 if $m==1;return $allow&&can_encode_kanji($c) if $m==2;1}
sub _payload {my($t,$m,$a,$b)=@_;my $n=$b-$a;return 10*int($n/3)+(0,4,7)[$n%3] if $m==0;return 11*int($n/2)+6*($n%2) if $m==1;return 13*$n if $m==2;8*($t->{offsets}[$b]-$t->{offsets}[$a])}
sub _count {my($t,$m,$a,$b)=@_;$m==3?$t->{offsets}[$b]-$t->{offsets}[$a]:$b-$a}
sub _validate_tracker {
 my($t)=@_;require_hash($t,'Optimizer tracker');validate_version($t->{version});require_bool($t->{allowKanji},'Tracker allowKanji');
 require_array($t->{costs},'Tracker costs');my $n=@{$t->{costs}};fail('INVALID_INPUT','Uninitialized or oversized tracker') if !$n||$n>MAX_PAYLOAD_UNITS+1;
 for my $k(qw(offsets counts previous chosen)){require_array($t->{$k},"Tracker $k");fail('INVALID_INPUT','Inconsistent tracker lengths') unless @{$t->{$k}}==$n}
 require_array($t->{widths},'Tracker widths');require_array($t->{keys},'Tracker keys');require_array($t->{queues},'Tracker queues');
 fail('INVALID_INPUT','Inconsistent tracker mode arrays') unless @{$t->{widths}}==4&&@{$t->{keys}}==4&&@{$t->{queues}}==4;
 for my $m(0..3){require_range($t->{widths}[$m],1,16,'Tracker width');fail('INVALID_INPUT','Inconsistent tracker count width') if $t->{widths}[$m]!=character_count_bits($t->{version},$DATA_MODES[$m]);require_array($t->{keys}[$m],'Tracker mode keys');fail('INVALID_INPUT','Inconsistent tracker key lengths') unless @{$t->{keys}[$m]}==$n-1;require_array($t->{queues}[$m],'Tracker mode queues');fail('INVALID_INPUT','Inconsistent tracker lanes') unless @{$t->{queues}[$m]}==3;
  for my $q(@{$t->{queues}[$m]}){require_hash($q,'Tracker queue');require_array($q->{values},'Tracker queue values');require_range($q->{head},0,scalar(@{$q->{values}}),'Tracker queue head');require_range($q->{values}[$q->{head}],0,$n-2,'Tracker queue index') if $q->{head}<@{$q->{values}};require_range($q->{values}[-1],0,$n-2,'Tracker queue tail') if @{$q->{values}}}
 }
 require_range($t->{costs}[-1],0,100_000_000,'Tracker cost');require_range($t->{counts}[-1],0,MAX_PAYLOAD_UNITS,'Tracker segment count');require_range($t->{offsets}[-1],0,4*MAX_PAYLOAD_UNITS,'Tracker byte offset');return;
}
sub append_character { for my $arg (@_) { fail('INVALID_INPUT','Tied values are not supported') if tied($arg) }
 my($t,$c)=@_;_validate_tracker($t);my $chars=strict_text($c);fail('INVALID_INPUT','Expected one Unicode scalar') unless @$chars==1;
 fail('INVALID_INPUT','Uninitialized tracker') unless ref($t->{costs}) eq 'ARRAY' && @{$t->{costs}};
 my $n=@{$t->{costs}};fail('DATA_TOO_LONG','Optimizer resource limit exceeded') if $n>MAX_PAYLOAD_UNITS;
 my $cp=ord($c);my $w=$cp<128?1:$cp<2048?2:$cp<65536?3:4;push @{$t->{offsets}},$t->{offsets}[-1]+$w;
 my($bestCost,$bestCount,$bestMode,$bestStart)=(9e15,9e15,-1,0);
 for my $m(0..3){my $start=$n-1;my $key=$t->{costs}[$start]-_base($t,$m,$start);push @{$t->{keys}[$m]},$key;
  unless(_eligible($c,$m,$t->{allowKanji})){$t->{queues}[$m]=[map {{values=>[],head=>0}} 0..2];next}
  my $lanes=$m==0?3:$m==1?2:1;my $lane=$start%$lanes;my $q=$t->{queues}[$m][$lane];
  while(@{$q->{values}}>$q->{head}) {my $j=$q->{values}[-1];last unless $t->{keys}[$m][$j]>$key || ($t->{keys}[$m][$j]==$key&&$t->{counts}[$j]>$t->{counts}[$start]);pop @{$q->{values}}}
  push @{$q->{values}},$start;my $limit=(1<<$t->{widths}[$m])-1;
  for my $k(0..$lanes-1){my $queue=$t->{queues}[$m][$k];++$queue->{head} while $queue->{head}<@{$queue->{values}}&&_count($t,$m,$queue->{values}[$queue->{head}],$n)>$limit;next if $queue->{head}>=@{$queue->{values}};
   my $j=$queue->{values}[$queue->{head}];my $cost=$t->{costs}[$j]+4+$t->{widths}[$m]+_payload($t,$m,$j,$n);my $count=$t->{counts}[$j]+1;
   if($cost<$bestCost||($cost==$bestCost&&$count<$bestCount)){($bestCost,$bestCount,$bestMode,$bestStart)=($cost,$count,$m,$j)}
  }
 }
 fail('INVALID_INPUT','No segmentation path') if $bestMode<0;push @{$t->{costs}},$bestCost;push @{$t->{counts}},$bestCount;push @{$t->{chosen}},$bestMode;push @{$t->{previous}},$bestStart;return $bestCost;
}
sub optimal_bits {for my $arg (@_) {fail('INVALID_INPUT','Tied values are not supported') if tied($arg)} my($t)=@_;_validate_tracker($t);$t->{costs}[-1]}
sub optimize_segments { for my $arg (@_) { fail('INVALID_INPUT','Tied values are not supported') if tied($arg) }
 my($text,$v,$allow)=@_;$v//=1;$allow=1 unless defined $allow;my $chars=strict_text($text);fail('DATA_TOO_LONG','Optimized single-symbol input exceeds 7089 scalars') if @$chars>MAX_SINGLE_SYMBOL_CHARACTERS;my $t=new_segment_optimization_tracker($v,$allow);return [new_segment('byte','')] unless @$chars;
 append_character($t,$_) for @$chars;my @out;my $n=@$chars;while($n>0){my $j=$t->{previous}[$n];my $m=$t->{chosen}[$n];push @out,new_segment($DATA_MODES[$m],substr($text,$j,$n-$j));$n=$j}return [reverse @out];
}
sub create_segments { for my $arg (@_) { fail('INVALID_INPUT','Tied values are not supported') if tied($arg) }
 my($input,$mode,$v,$opt,$eci,$allow)=@_;$mode//='auto';$v//=1;$opt=1 unless defined $opt;$eci=-1 unless defined $eci;$allow=1 unless defined $allow;
 validate_version($v);require_string($mode,'Mode','INVALID_MODE');fail('INVALID_MODE','Unsupported data mode') unless grep {$mode eq $_} ('auto',@DATA_MODES);$opt=require_bool($opt,'optimizeSegments');$allow=require_bool($allow,'allowKanji');require_range($eci,-1,999999,'ECI assignment','INVALID_ECI');my @out;push @out,eci($eci) if $eci>=0;
 if(ref($input) eq 'ARRAY'){fail('INVALID_MODE','Binary input requires byte mode') unless $mode eq 'auto'||$mode eq 'byte';push @out,byte_segment($input);return \@out}
 my $chars=strict_text($input);
 if($mode ne 'auto'){push @out,new_segment($mode,$input)}
 elsif($opt){push @out,@{optimize_segments($input,$v,$allow&&$eci<0?1:0)}}
 else {my($num,$alpha,$kanji)=(1,1,$allow&&$eci<0);for my $c(@$chars){$num=0 unless $c=~/\A[0-9]\z/;$alpha=0 if alpha_value($c)<0;$kanji=0 unless can_encode_kanji($c)}my $m=@$chars&&$num?'numeric':@$chars&&$alpha?'alphanumeric':@$chars&&$kanji?'kanji':'byte';push @out,new_segment($m,$input)}
 return \@out;
}
1;
