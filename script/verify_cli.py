#!/usr/bin/env python3
"""Unicode/binary files, exit status, stderr, and actual CLI output contracts."""
import argparse,hashlib,json,pathlib,subprocess,tempfile,base64,os,sys
from native_support import strict_json,binding,require
from decoder_support import verify_png
from verify_reference import snapshot

def verify(binary,outdir):
 binary=pathlib.Path(binary).resolve();outdir=pathlib.Path(outdir).resolve();outdir.mkdir(parents=True,exist_ok=True)
 before=snapshot();report={'status':'running','binary':binding(binary),'sourceSha256':before,'processes':[]}
 def run(args,ok=True,code=None,input=b''):
  p=subprocess.run([os.environ.get('SPECQR_PERL', 'perl'),str(binary),*args],capture_output=True,timeout=30,cwd=outdir,input=input)
  row={'args':[{'rawArgHex':x.hex()} if isinstance(x,bytes) else x for x in args],'stdinBytes':len(input),'stdinSha256':hashlib.sha256(input).hexdigest(),'exitCode':p.returncode,'stdoutBytes':len(p.stdout),'stdoutSha256':hashlib.sha256(p.stdout).hexdigest(),'stderrBytes':len(p.stderr),'stderrSha256':hashlib.sha256(p.stderr).hexdigest()};report['processes'].append(row)
  if ok:require(p.returncode==0 and not p.stderr,'CLI failed: '+p.stderr.decode(errors='replace'))
  else:
   require(p.returncode==2 and not p.stdout and p.stderr.endswith(b'\n'),'CLI failure protocol mismatch: '+repr((args,p.returncode,p.stdout[:100],p.stderr[:200])))
   if code:require(p.stderr.startswith((code+': ').encode()),'CLI error category mismatch: '+repr(p.stderr))
  return p.stdout
 try:
  text='日本語 é e\u0301 🙂\x00\n';textfile=outdir/'入力 🙂.txt';textfile.write_text(text)
  binarydata=bytes(range(256));bytefile=outdir/'binary.bin';bytefile.write_bytes(binarydata)
  args=['--text-file',str(textfile),'--eci','26','--mode','byte','--format','json']
  q=strict_json(run(args));require(q['diagnostics']['input_bytes']==len(text.encode()),'CLI Unicode length')
  output=outdir/'画像 QR.png';run(args[:-2]+['--format','png','--output',str(output)])
  png,luma,dim=verify_png(output.read_bytes().hex(),q['matrix'],8);require(dim==(len(q['matrix'])+8)*8,'Implicit scale differs')
  require(run(args[:-2]+['--format','png'])==png,'PNG stdout differs from file')
  q2=strict_json(run(['--bytes-file',str(bytefile),'--format','json']))
  require(q2['diagnostics']['input_bytes']==256,'Binary length')
  require(strict_json(run(['--bytes-file','-','--format','json'],input=binarydata))==q2,'Binary stdin differs from file')
  require(strict_json(run(['--text-file','-','--eci','26','--mode','byte','--format','json'],input=text.encode('utf-8')))==q,'Text stdin differs from UTF-8 file')
  require(run(['--text-file','-','--eci','26','--mode','byte','--format','png'],input=text.encode('utf-8'))==png,'Raw PNG stdout differs for stdin input')
  matrix=strict_json(run(['--bytes-file',str(bytefile),'--format','matrix']));require(matrix==q2['matrix'],'Matrix CLI differs')
  dataurl=run(['--text','A','--format','png-data-url']).strip();require(dataurl.startswith(b'data:image/png;base64,'),'PNG URL prefix')
  require(base64.b64decode(dataurl.split(b',')[1],validate=True)==run(['--text','A','--format','png']),'PNG URL roundtrip')
  plan=strict_json(run(['--text','12345','--plan']));require(plan['ok'] and not plan['diagnostics']['codewords_built'],'Planning must be arithmetic')
  sa=strict_json(run(['--bytes-file',str(bytefile),'--structured-append','--version','2','--format','json']));require(2<=sa['total']<=16 and len(sa['symbols'])==sa['total'],'SA CLI')
  require(b'Usage:' in run(['--help']),'Missing help')
  require(b'SpecQR Perl 0.1.0' in run(['--version-info']),'Missing version')
  require(sys.platform=='linux' and pathlib.Path('/dev/full').exists(),'CLI failure profile requires Linux /dev/full')
  for option in ['--help','--version-info']:
   with open('/dev/full','wb') as sink:
    failed=subprocess.run([os.environ.get('SPECQR_PERL','perl'),str(binary),option],stdin=subprocess.DEVNULL,stdout=sink,stderr=subprocess.PIPE,timeout=30,cwd=outdir)
   report['processes'].append({'args':[option],'stdoutDisposition':'Linux /dev/full required failure control','exitCode':failed.returncode,'stderrBytes':len(failed.stderr),'stderrSha256':hashlib.sha256(failed.stderr).hexdigest()})
   require(failed.returncode==2 and failed.stderr.startswith(b'IO_ERROR: ') and failed.stderr.endswith(b'\n') and failed.stderr.count(b'\n')==1,'Early CLI output write failure escaped typed error handling: '+repr((option,failed.returncode,failed.stderr)))
  cases=[([], 'INVALID_INPUT'),(['--text','A','--text','B'],'INVALID_INPUT'),(['--text','A','--unknown'],'INVALID_INPUT'),(['--text','A','--format','gif'],'INVALID_OUTPUT'),(['--text','A','--ecc','oops'],'INVALID_ECC_LEVEL'),(['--text','A','--scale','99999999999999999999999'],'INVALID_INPUT'),(['--text','A','--version','41'],'INVALID_VERSION'),(['--text','A','--print-dpi','nan'],'INVALID_INPUT'),(['--text','A','--foreground','url(x)'],'INVALID_COLOR'),(['--text','A','--mode','numeric'],'INVALID_MODE'),(['--text','a'*3000],'DATA_TOO_LONG'),(['--text-file',str(outdir/'does-not-exist')],'IO_ERROR'),(['--text','A','--output',str(outdir/'absent'/'output.svg')],'IO_ERROR'),(['--text','A','--plan','--structured-append'],'INVALID_MODE'),(['--text','A','--structured-append'],'INVALID_OUTPUT')]
  cases += [(["--text","A","--version","0"],"INVALID_VERSION"),(["--text","A","--mask","-1"],"INVALID_INPUT"),(["--text","A","--eci","-1"],"INVALID_ECI")]
  for args,code in cases:run(args,False,code)
  run(['--text',b'\xff'],False,'INVALID_INPUT')
  run(['--text-file','-'],False,'INVALID_INPUT',input=b'\xe0\x80\x80')
  invalid=outdir/'malformed.txt';invalid.write_bytes(b'\xe0\x80\x80');run(['--text-file',str(invalid)],False,'INVALID_INPUT')
  big=outdir/'oversize.bin';big.write_bytes(b'x'*1000001);run(['--bytes-file',str(big)],False,'DATA_TOO_LONG')
  report['sourceStable']=snapshot()==before;require(report['sourceStable'],'Source changed');report['status']='passed'
 except BaseException as e:report.update(status='failed',error=repr(e));raise
 finally:(outdir/'report.json').write_text(json.dumps(report,indent=2)+'\n')
 return report
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--binary',required=True);p.add_argument('--output',required=True);a=p.parse_args();r=verify(a.binary,a.output);print(json.dumps({'status':r['status'],'processes':len(r['processes'])}))
