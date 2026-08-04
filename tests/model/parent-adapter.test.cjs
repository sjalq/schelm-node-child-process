"use strict";const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path");
const states={Absent:0,Prepared:1,Binding:2,Awaiting:3,Registered:4,Unregistering:5};
function step(s,e){if(s===0&&e==="prepare")return[1,"none"];if(s===1&&e==="bind")return[2,"bind"];if(s===2&&e==="sent")return[3,"none"];if(s===3&&e==="ack")return[4,"start"];if(s===3&&(e==="fail"||e==="timeout"))return[0,"kill-clear"];if(s===4&&e==="cleanup")return[5,"unregister"];if(s===5&&(e==="ack"||e==="timeout"))return[0,"final"];return null;}
assert.deepEqual(["prepare","bind","sent","ack","cleanup","ack"].reduce((a,e)=>step(a[0],e),[0]),[0,"final"]);
assert.deepEqual(["prepare","bind","sent","timeout"].reduce((a,e)=>step(a[0],e),[0]),[0,"kill-clear"]);
for(const bad of ["bind","ack","cleanup"])assert.equal(step(0,bad),null);
for(const phase of ["Preparing","Binding","Registered","Unregistering"])assert.ok(["Preparing","Binding","Registered","Unregistering"].includes(phase));
const root=path.resolve(__dirname,"../..");
const supervisor=fs.readFileSync(path.join(root,"src/Schelm/Node/ChildProcess/Supervisor.elm"),"utf8");
const kernel=fs.readFileSync(path.join(root,"src/Elm/Kernel/SchelmChildProcess.js"),"utf8");
assert.match(supervisor,/phase = Binding pid[\s\S]*sendToSelf router \(BeginBind oid\)/,"binding committed before request launch");
assert.doesNotMatch(supervisor,/Process\.sleep (25|[1-9][0-9]+)/,"no timing synchronization");
assert.match(supervisor,/Rejecting detail[\s\S]*finishRejected/,"one bind rejection arbiter");
assert.match(kernel,/function _SchelmChildProcess_parentDisconnect\(\)[\s\S]*parentRequests\.clear\(\)[\s\S]*for\(var e of _SchelmChildProcess_registry\.values\(\)\)/,"disconnect fans out requests and registrations");
assert.match(kernel,/cleanup\.phase="absent";_SchelmChildProcess_registry\.delete/,"final boundary is absent");
assert.match(supervisor,/shutdownSupervisor[\s\S]*Preparing[\s\S]*Binding[\s\S]*cancelMany/,"shutdown joins intermediate phases");
console.log(JSON.stringify({ok:true,states:Object.keys(states).length,races:["ack","failure","timeout","disconnect","shutdown","unregister-timeout"]}));
