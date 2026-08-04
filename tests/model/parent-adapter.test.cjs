"use strict";const assert=require("node:assert/strict");
const states={Absent:0,Prepared:1,Binding:2,Awaiting:3,Registered:4,Unregistering:5};
function step(s,e){if(s===0&&e==="prepare")return[1,"none"];if(s===1&&e==="bind")return[2,"bind"];if(s===2&&e==="sent")return[3,"none"];if(s===3&&e==="ack")return[4,"start"];if(s===3&&(e==="fail"||e==="timeout"))return[0,"kill-clear"];if(s===4&&e==="cleanup")return[5,"unregister"];if(s===5&&(e==="ack"||e==="timeout"))return[0,"final"];return null;}
assert.deepEqual(["prepare","bind","sent","ack","cleanup","ack"].reduce((a,e)=>step(a[0],e),[0]),[0,"final"]);
assert.deepEqual(["prepare","bind","sent","timeout"].reduce((a,e)=>step(a[0],e),[0]),[0,"kill-clear"]);
for(const bad of ["bind","ack","cleanup"])assert.equal(step(0,bad),null);
console.log(JSON.stringify({ok:true,states:Object.keys(states).length,races:["ack","failure","timeout","unregister-timeout"]}));
