#!/usr/bin/env python3
"""Re-execute all additional URL positives on the exact immutable TS checkout.
Usage: python3 verification/gs1/check_extra_oracle.py /path/to/SpecQR
Read-only toward both repositories; the JSON input exists only in a temp dir.
"""
import hashlib,json,pathlib,subprocess,sys,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'script'))
from gs1_contract import load_extra,request_sha
from native_support import require,strict_json
TS_COMMIT='16efc6c0a8e397c9df3d051d20fce6c1eebdfad7'
def run(argv):
 result=subprocess.run(list(map(str,argv)),capture_output=True,timeout=120)
 require(result.returncode==0 and not result.stderr,'Oracle command failed or wrote stderr')
 return result.stdout
def verify_source(source):
 require(run(['git','-C',source,'rev-parse','HEAD']).decode().strip()==TS_COMMIT,'Wrong TS commit')
 require(run(['git','-C',source,'status','--porcelain'])==b'','TypeScript checkout is not clean')
 tree=run(['git','-C',source,'ls-tree','-rz','HEAD']);bindings={}
 for line in tree.split(b'\0'):
  if not line:continue
  metadata,name=line.split(b'\t',1);mode,kind,sha=metadata.split();require(kind==b'blob' and mode in [b'100644',b'100755'],'Unsupported TS source entry')
  path=source/name.decode();require(path.is_file() and not path.is_symlink(),'Missing source file')
  data=path.read_bytes();require(hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()==sha.decode(),'Source bytes differ from committed TS tree')
  bindings[name.decode()]=hashlib.sha256(data).hexdigest()
 return bindings
source=pathlib.Path(sys.argv[1]).resolve();before=verify_source(source);data=load_extra();requests=[row['request'] for row in data['cases']]
for name,sha in data['source']['sourceHashes'].items():require(before[name]==sha,'Pinned TS module mismatch')
with tempfile.TemporaryDirectory() as temporary:
 path=pathlib.Path(temporary)/'requests.json';path.write_text(json.dumps({'cases':requests}),encoding='utf-8')
 raw=run(['node',ROOT/'verification/gs1/current_ts_oracle.mjs',source,path]);actual=strict_json(raw)
require(len(actual)==len(requests)==139,'Incorrect TypeScript cardinality')
require(actual==[row['expected'] for row in data['cases']],'Expected result differs from independent current TS execution')
require(hashlib.sha256(raw).hexdigest()==data['source']['rawOracleOutputSha256'],'Raw oracle binding mismatch')
require(verify_source(source)==before,'TypeScript source changed during execution')
print(json.dumps({'status':'passed','cases':len(actual),'sourceFiles':len(before),'commit':TS_COMMIT,'sourceStable':True,'oracleOutputSha256':hashlib.sha256(raw).hexdigest()}))
