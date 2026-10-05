#!/usr/bin/env python3
"""Build checksum-pinned official stable Perl releases, never CPAN modules."""
import argparse,hashlib,json,pathlib,subprocess,tarfile,urllib.request,os
PINS={'5.42.3':'c9387e1473a1866935cb047ece7c2e0a80767a3acdecb79d4a375f8a95970ddc','5.44.0':'505cf43912e9480495c344c70260452e32aa2a73c546a026b3f100053b23ce91'}
def install(version,destination,jobs):
 destination=pathlib.Path(destination).resolve();destination.mkdir(parents=True,exist_ok=True)
 url=f'https://www.cpan.org/src/5.0/perl-{version}.tar.xz';archive=destination/f'perl-{version}.tar.xz';expected=PINS[version]
 if not archive.exists():
  with urllib.request.urlopen(url,timeout=120) as response:data=response.read(64*1024*1024+1)
  if len(data)>64*1024*1024:raise RuntimeError('Toolchain archive exceeds budget')
  archive.write_bytes(data)
 actual=hashlib.sha256(archive.read_bytes()).hexdigest()
 if actual!=expected:raise RuntimeError('Official Perl source checksum mismatch')
 source=destination/f'perl-{version}';prefix=destination/f'runtime-{version}';binary=prefix/'bin/perl'
 if not source.exists():
  with tarfile.open(archive) as tar:
   for member in tar.getmembers():
    path=pathlib.PurePosixPath(member.name)
    if path.is_absolute() or '..' in path.parts or not path.parts or path.parts[0]!=source.name:raise RuntimeError('Unsafe archive member')
   tar.extractall(destination,filter='data')
 processes=[]
 if not binary.exists():
  for label,command in [('configure',['sh','Configure','-des','-Dprefix='+str(prefix),'-Dusethreads']),('build',['make','-j'+str(jobs)]),('install',['make','install'])]:
   r=subprocess.run(command,cwd=source,capture_output=True,timeout=1800);log=destination/f'perl-{version}-{label}.log';log.write_bytes(r.stdout+b'\n--- stderr ---\n'+r.stderr)
   processes.append({'label':label,'argv':command,'exitCode':r.returncode,'stdoutSha256':hashlib.sha256(r.stdout).hexdigest(),'stderrSha256':hashlib.sha256(r.stderr).hexdigest(),'logSha256':hashlib.sha256(log.read_bytes()).hexdigest()})
   if r.returncode:raise RuntimeError('Perl '+label+' failed; see '+str(log))
 r=subprocess.run([binary,'-MJSON::PP','-MMIME::Base64','-MDigest::SHA','-MEncode','-MConfig','-e','print sprintf("%vd",$^V),"\\n",$Config{archname},"\\n"'],capture_output=True,timeout=30)
 if r.returncode or r.stderr or not r.stdout.startswith((version+'\n').encode()):raise RuntimeError('Installed runtime check failed')
 report={'status':'passed','version':version,'sourceUrl':url,'publishedSha256Url':url+'.sha256.txt','sourceSha256':actual,'binary':str(binary),'binarySha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'runtime':r.stdout.decode(),'processes':processes}
 (destination/f'perl-{version}-receipt.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--version',choices=PINS,required=True);p.add_argument('--tools',required=True);p.add_argument('--jobs',type=int,default=4);a=p.parse_args();install(a.version,a.tools,a.jobs)
