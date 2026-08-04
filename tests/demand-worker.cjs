"use strict";
const fs=require("node:fs"),vm=require("node:vm"),src=fs.readFileSync(process.argv[2],"utf8"),scope={};
const before=process.memoryUsage().rss;let max=before,done=false;const meter=setInterval(()=>{max=Math.max(max,process.memoryUsage().rss)},5);
vm.runInNewContext(src.replace(/\}\(this\)\);?\s*$/,"}(scope));"),{scope,console,process,require,setTimeout,clearTimeout,setInterval,clearInterval,DataView,Buffer,Map});
const app=scope.Elm.DemandMain.init();app.ports.report.subscribe(x=>{done=true;clearInterval(meter);const rss=max-before;console.log(JSON.stringify({result:x,rssDelta:rss}));if(!x||x.bytes!==10240000||x.chunks<157||rss>128*1024*1024)process.exitCode=1;process.exit();});
setTimeout(()=>{if(!done){console.error("demand timeout");process.exit(1)}},30000);
