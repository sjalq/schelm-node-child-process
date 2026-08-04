"use strict";
const fs=require("node:fs"),vm=require("node:vm"),source=fs.readFileSync(process.argv[2],"utf8"),scope={};
vm.runInNewContext(source.replace(/\}\(this\)\);?\s*$/,"}(scope));"),{scope,console,process,require,setTimeout,clearTimeout,setInterval,clearInterval,DataView,Buffer});
const seen=[],app=scope.Elm.Main.init();app.ports.report.subscribe(value=>{seen.push(value);console.log(JSON.stringify(value));});
setTimeout(()=>{const text=JSON.stringify(seen);if(!text.includes("spawn-failed:ENOENT")||!text.includes("stdout:3")||!text.includes("stderr:3")||!text.includes('"exit":7')||!text.includes('"signal":"SIGTERM"'))process.exitCode=1;process.exit();},500);
