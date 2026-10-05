#!/usr/bin/env python3
"""Exact real Perl, full fixture oracle, typed failures, CLI and offline install."""
import argparse,hashlib,json,pathlib,platform,subprocess,os,sys,shutil,time
from prepare_ci import verify
from native_support import require,binding,strict_json
ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--perl',type=pathlib.Path,required=True);p.add_argument('--expect-version',required=True);p.add_argument('--output',type=pathlib.Path,required=True);a=p.parse_args();a.perl=a.perl.resolve();a.output=a.output.resolve()
 require(not a.output.exists(),'Output must be a fresh directory');a.output.mkdir(parents=True)
 initial=verify(ROOT);report={'status':'running','runtime':binding(a.perl),'expectedVersion':a.expect_version,'host':{'os':platform.system(),'arch':platform.machine(),'python':platform.python_version()},'source':initial,'processes':[]};start=time.monotonic()
 env=os.environ.copy();env.update(PYTHONDONTWRITEBYTECODE='1',PYTHONUTF8='1',TZ='UTC',SPECQR_PERL=str(a.perl));env.pop('PERL5LIB',None);env.pop('PERL5OPT',None);env.pop('PERL_LOCAL_LIB_ROOT',None)
 def run(cmd,label,cwd=ROOT,env=env,expect=None,stderr_empty=False,timeout=7200):
  log=a.output/(label+'.log');log.parent.mkdir(parents=True,exist_ok=True);started=time.monotonic();r=subprocess.run([str(x) for x in cmd],cwd=cwd,env=env,capture_output=True,timeout=timeout);log.write_bytes(r.stdout+b'\n--- stderr ---\n'+r.stderr)
  row={'label':label,'argv':[str(x) for x in cmd],'exitCode':r.returncode,'stdoutBytes':len(r.stdout),'stderrBytes':len(r.stderr),'stdoutSha256':hashlib.sha256(r.stdout).hexdigest(),'stderrSha256':hashlib.sha256(r.stderr).hexdigest(),'elapsedSeconds':round(time.monotonic()-started,3),'log':binding(log)};report['processes'].append(row)
  require(r.returncode==0,label+' failed: '+r.stderr.decode(errors='replace')[-2000:])
  if stderr_empty:require(not r.stderr,label+' unexpected stderr')
  if expect is not None:require(r.stdout==expect,label+' unexpected stdout')
  return r.stdout
 try:
  require(platform.system()=='Linux' and platform.machine() in ['x86_64','amd64'],'Reviewed execution profile is Linux x86-64')
  version=run([a.perl,'-e','print sprintf("%vd",$^V),"\\n"'],'perl-version',stderr_empty=True,expect=(a.expect_version+'\n').encode());report['perlVersion']=version.decode().strip()
  run([sys.executable,ROOT/'script/test_harness.py'],'harness-tests')
  tests=sorted((ROOT/'t').glob('*.t'));required_tests={'core.t','gs1.t','render.t','structured_append.t'};require(required_tests<={x.name for x in tests},'Missing required native test group');report['requiredUnitGroups']=sorted(required_tests);report['unitFiles']={str(x.relative_to(ROOT)):binding(x) for x in tests}
  gs1_fixture=ROOT/'verification/fixtures/gs1-upstream.json';gs1_delta=ROOT/'verification/fixtures/gs1-perl-deltas.json';gs1=strict_json(gs1_fixture.read_bytes());require(len(gs1['cases'])==1411,'GS1 fixture count mismatch');report['gs1Fixtures']={'records':1411,'historicalFixture':binding(gs1_fixture),'currentSourceCorrections':binding(gs1_delta)}
  run([a.perl,'-I'+str(ROOT/'lib'),'-MTest::Harness','-e','runtests(@ARGV)',*tests],'native-unit',stderr_empty=True)
  bridge=ROOT/'script/bridge.pl';runtime=strict_json(run([a.perl,bridge,'--runtime'],'bridge-runtime',stderr_empty=True));require(runtime['perl']==a.expect_version and runtime['os']=='linux' and runtime['wordSize']==64,'Unexpected native Perl runtime');report['bridgeRuntime']=runtime
  run([sys.executable,ROOT/'script/verify_gs1.py','--binary',bridge,'--output',a.output/'gs1-current.json'],'gs1-current',stderr_empty=True)
  for suite in ['public','internal']:
   print('Running '+suite+' reference corpus',flush=True);run([sys.executable,ROOT/'script/verify_reference.py','--binary',bridge,'--suite',suite,'--timeout','7200','--output',a.output/(suite+'-reference.json')],suite+'-reference',stderr_empty=True)
  run([sys.executable,ROOT/'script/verify_negative.py','--binary',bridge,'--output',a.output/'negative.json'],'negative',stderr_empty=True)
  run([sys.executable,ROOT/'script/verify_cli.py','--binary',ROOT/'script/specqr','--output',a.output/'cli'],'cli',stderr_empty=True)
  # Install from a separate source copy with an empty home and no module registry.
  package=a.output/'package-copy';shutil.copytree(ROOT,package,ignore=shutil.ignore_patterns('__pycache__','.git'));home=a.output/'consumer-home';home.mkdir();dest=a.output/'installed';consumer_env=env.copy();consumer_env.update(HOME=str(home),PATH=str(a.perl.parent)+os.pathsep+env.get('PATH',''));consumer=a.output/'fresh-consumer';consumer.mkdir()
  run([a.perl,'Makefile.PL','INSTALL_BASE='+str(dest)],'consumer-configure',cwd=package,env=consumer_env,stderr_empty=True)
  run(['make'],'consumer-build',cwd=package,env=consumer_env,stderr_empty=True)
  run(['make','test'],'consumer-test',cwd=package,env=consumer_env,stderr_empty=True)
  run(['make','install'],'consumer-install',cwd=package,env=consumer_env,stderr_empty=True)
  installed=dest/'lib/perl5'
  for src in (ROOT/'lib').rglob('*.pm'):
   target=installed/src.relative_to(ROOT/'lib');require(target.is_file() and target.read_bytes()==src.read_bytes(),'Installed source differs: '+str(src))
  shutil.copy(ROOT/'examples/consumer.pl',consumer/'consumer.pl');run([a.perl,'-I'+str(installed),consumer/'consumer.pl'],'consumer-run',cwd=consumer,env=consumer_env,expect=b'consumer passed\n',stderr_empty=True)
  installed_cli=dest/'bin/specqr';require(installed_cli.is_file(),'Installed CLI absent');consumer_env['PERL5LIB']=str(installed);text=run([a.perl,installed_cli,'--version-info'],'installed-cli',cwd=consumer,env=consumer_env,stderr_empty=True);require(b'SpecQR Perl 0.1.0' in text,'Installed CLI identity mismatch')
  report['offlineConsumer']={'status':'passed','emptyHome':True,'noModuleRegistry':True,'installedSourceExact':True,'registeredPublished':False}
  report['sourceStable']=verify(ROOT)==initial;require(report['sourceStable'],'Source changed');report['status']='passed'
 except BaseException as e:report.update(status='failed',error=repr(e));raise
 finally:report['elapsedSeconds']=round(time.monotonic()-start,3);(a.output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps({'status':report['status'],'perl':a.expect_version,'elapsedSeconds':report['elapsedSeconds']}))
if __name__=='__main__':main()
