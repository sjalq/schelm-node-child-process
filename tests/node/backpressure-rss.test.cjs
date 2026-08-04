"use strict";
const assert=require("node:assert/strict"),{spawn}=require("node:child_process");
const chunks=10000,size=1024,limit=64*1024;
const child=spawn(process.execPath,["-e",`const b=Buffer.alloc(${size},120);let i=0;function go(){while(i<${chunks}){i++;if(!process.stdout.write(b))return process.stdout.once('drain',go)}process.stdout.end()}go()`],{stdio:["ignore","pipe","ignore"]});
child.stdout.pause();const before=process.memoryUsage().rss;let received=0,maxReadable=0,maxRss=before,reading=false;
function demand(){if(reading)return;reading=true;const chunk=child.stdout.read(limit);reading=false;if(chunk){received+=chunk.length;maxReadable=Math.max(maxReadable,child.stdout.readableLength);maxRss=Math.max(maxRss,process.memoryUsage().rss);setImmediate(demand);}}
child.stdout.on("readable",demand);
setTimeout(()=>{child.stdout.resume();child.stdout.pause();demand();},100);
child.stdout.on("end",()=>{assert.equal(received,chunks*size);assert.ok(maxReadable<2*1024*1024,`Node readable buffer ${maxReadable}`);assert.ok(maxRss-before<128*1024*1024,`RSS delta ${maxRss-before}`);console.log(JSON.stringify({ok:true,chunks,bytes:received,maxReadable,rssDelta:maxRss-before,scope:"Node internal measured; package slice 65536"}));});
child.on("error",e=>{throw e});setTimeout(()=>{if(received<chunks*size){console.error({received});process.exit(1)}},15000);
