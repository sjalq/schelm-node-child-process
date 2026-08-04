"use strict";const assert=require("node:assert/strict");
function classify(results){for(const x of results){if(x==="ESRCH")return"gone";}const last=results.at(-1);return last==="present"?"still-present":`probe-${last}`;}
assert.equal(classify(["present","ESRCH"]),"gone");assert.equal(classify(["present","present","present"]),"still-present");assert.equal(classify(["EPERM","EPERM","EPERM"]),"probe-EPERM");
let term=0,kill=0;function ladder(){if(term===0)term++;if(kill===0)kill++;return classify(["present","present","present"])}assert.equal(ladder(),"still-present");ladder();assert.equal(term,1);assert.equal(kill,1);
console.log(JSON.stringify({ok:true,probes:3,outcomes:["gone","still-present","probe-EPERM"]}));
