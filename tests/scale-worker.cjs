"use strict";
const fs=require("node:fs"),vm=require("node:vm"),src=fs.readFileSync(process.argv[2],"utf8"),scope={};
const before=process.memoryUsage().rss;
vm.runInNewContext(src.replace(/\}\(this\)\);?\s*$/,"}(scope));"),{scope,console,process,require,setTimeout,clearTimeout,setInterval,clearInterval,DataView,Buffer,Map});
const app=scope.Elm.ScaleMain.init();let done=false;
app.ports.report.subscribe(x=>{done=true;const rss=process.memoryUsage().rss-before;console.log(JSON.stringify({result:x,rssDelta:rss}));if(x!=="ok"||rss>192*1024*1024)process.exitCode=1;process.exit();});
setTimeout(()=>{if(!done){console.error("scale timeout");process.exit(1);}},180000);
