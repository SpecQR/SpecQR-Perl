#!/usr/bin/env node
// Development-only, current-TypeScript source oracle. Never called by Perl runtime.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import zlib from 'node:zlib';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
const source=path.resolve(process.argv[2]||'');
const output=path.resolve(process.argv[3]||'');
const commit='16efc6c0a8e397c9df3d051d20fce6c1eebdfad7';
const hash=data=>crypto.createHash('sha256').update(data).digest('hex');
if(execFileSync('git',['-C',source,'rev-parse','HEAD'],{encoding:'utf8'}).trim()!==commit)throw Error('Wrong TypeScript source commit');
if(execFileSync('git',['-C',source,'status','--porcelain','--untracked-files=all','--','src'],{encoding:'utf8'}).trim())throw Error('TypeScript source is modified');
const base=path.dirname(fileURLToPath(import.meta.url));
const corpus=fs.readFileSync(path.join(base,'../verification/fixtures/public-reference.jsonl.gz'));
if(hash(corpus)!=='f1649de0f2e62c87fa7b369cdd1f99bd7c092b6a1a2fa52e2e0caf5aea136f82')throw Error('Wrong corpus');
const load=rel=>import(pathToFileURL(path.join(source,rel)));
const {normalizeOptions}=await load('src/options.js');
const {selectPlanForInput}=await load('src/internal/planning.js');
const {buildResultArtifact}=await load('src/internal/build.js');
const {encodeSegments}=await load('src/encoding/modes.js');
const rows=zlib.gunzipSync(corpus).toString('utf8').trim().split('\n').map(JSON.parse),deltas=[];let selected=0;
for(const [index,record] of rows.entries()){
 const r=record.request,o=r.options||{};
 if(!(typeof r.text==='string'&&r.text.includes('%')&&(o.gs1||o.fnc1||o.fnc1Second)))continue;
 selected++;
 if(r.command&&r.command!=='generate')throw Error('Unexpected FNC1 command');
 const options=normalizeOptions(o),plan=selectPlanForInput(r.text,options),artifact=buildResultArtifact(plan,options);
 const expected={version:plan.version,ecc:plan.errorCorrectionLevel,mask:artifact.built.maskPattern,data:Buffer.from(encodeSegments(plan.segments,plan.version,plan.errorCorrectionLevel)).toString('hex'),codewords:Buffer.from(artifact.interleaved.codewords).toString('hex'),matrixHash:hash(artifact.built.matrix.map(row=>row.map(v=>v?'1':'0').join('')).join(''))};
 if(JSON.stringify(expected)!==JSON.stringify(record.expected))deltas.push({index,request:r,historicalExpected:record.expected,expected,reason:'Current TypeScript high-level FNC1 literal-percent escaping and bit comparison replaces historical whole-byte fallback.'});
}
if(selected!==12||deltas.length!==8)throw Error('Unexpected FNC1 delta count: '+selected+'/'+deltas.length);
const sourceSha256={};
function walk(dir){for(const e of fs.readdirSync(dir,{withFileTypes:true})){const p=path.join(dir,e.name);if(e.isDirectory())walk(p);else if(e.isFile())sourceSha256[path.relative(source,p)]=hash(fs.readFileSync(p));else throw Error('Unsupported source entry')}}
walk(path.join(source,'src'));
const result={schema:1,oracleRepository:'https://github.com/SpecQR/SpecQR',oracleCommit:commit,nodeVersion:process.version,fixtureSha256:hash(corpus),fixtureRecords:rows.length,selectedRecords:selected,changedRecords:deltas.length,unchangedRecords:rows.length-deltas.length,sourceSha256,deltas};
fs.writeFileSync(output,JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify({status:'passed',selected,changed:deltas.length,sha256:hash(fs.readFileSync(output))}));
