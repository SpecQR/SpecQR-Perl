#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use JSON::PP ();
use Config;
require "$FindBin::Bin/protocol.pl";
binmode STDIN, ':raw';binmode STDOUT, ':raw';binmode STDERR, ':raw';$|=1;
my $json=JSON::PP->new->utf8->canonical->max_depth(64)->max_size(16*1024*1024);
if(@ARGV==1&&$ARGV[0] eq '--runtime'){print $json->encode({perl=>sprintf('%vd',$^V),os=>$^O,arch=>$Config{archname},wordSize=>8*$Config{ivsize}}),"\n";exit 0}
my $limit=16*1024*1024;
my $buffer='';my $discard=0;
sub respond {
 my ($line,$oversize)=@_;my $result;
 if($oversize){$result={error=>'SpecQRError',isSpecQRError=>JSON::PP::true,code=>'INVALID_INPUT',message=>'JSON input resource limit'}}
 else {my $r=eval {$json->decode($line)};if($@){$result={error=>'SpecQRError',isSpecQRError=>JSON::PP::true,code=>'INVALID_INPUT',message=>'Malformed JSON'}}else{$result=SpecQR::Protocol::run_request($r)}}
 print $json->encode($result),"\n";
}
while(1){my $n=sysread(STDIN,my $chunk,65536);die "Input read failed: $!" unless defined $n;last unless $n;
 while(length($chunk)){my $i=index($chunk,"\n");my $part=$i<0?$chunk:substr($chunk,0,$i);$chunk=$i<0?'':substr($chunk,$i+1);if(!$discard){if(length($buffer)+length($part)>$limit){$buffer='';$discard=1}else{$buffer.=$part}}if($i>=0){respond($buffer,$discard);$buffer='';$discard=0}}
}
respond($buffer,$discard) if length($buffer)||$discard;
