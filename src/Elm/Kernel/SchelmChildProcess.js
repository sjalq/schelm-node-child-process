/*
import Elm.Kernel.List exposing (toArray)
import Elm.Kernel.Scheduler exposing (binding, succeed, fail, rawSpawn)
import Elm.Kernel.Utils exposing (Tuple0)
import Bytes exposing (Bytes)
import Maybe exposing (Maybe)
*/
var _SchelmChildProcess_registry = new Map();
var _SchelmChildProcess_isUnix = process.platform === "linux";
function _SchelmChildProcess_code(e){return String(e&&(e.code||e.message)||e).slice(0,256);}
function _SchelmChildProcess_bytes(b){return new DataView(b.buffer,b.byteOffset,b.byteLength);}
function _SchelmChildProcess_maybeBytes(b){return b===null?$elm$core$Maybe$Nothing:$elm$core$Maybe$Just(_SchelmChildProcess_bytes(b));}
function _SchelmChildProcess_signal(e,s){try{process.kill(-e.pgid,s);return "";}catch(x){return _SchelmChildProcess_code(x);}}
function _SchelmChildProcess_capture(stream,limit,onOverflow){
  var chunks=[],kept=0,overflow=false;
  if(!stream)return {finish:function(){return Buffer.alloc(0);}};
  stream.on("data",function(chunk){if(overflow)return;var room=limit-kept;if(chunk.length<=room){chunks.push(Buffer.from(chunk));kept+=chunk.length;}else{if(room>0){chunks.push(Buffer.from(chunk.subarray(0,room)));kept+=room;}overflow=true;onOverflow();}});
  return {finish:function(){return Buffer.concat(chunks,kept);}};
}
function _SchelmChildProcess_beginCleanup(e){
  if(e.cleaning)return;e.cleaning=true;e.termError=_SchelmChildProcess_signal(e,"SIGTERM");
  e.termTimer=setTimeout(function(){e.killError=_SchelmChildProcess_signal(e,"SIGKILL");var n=0,last="still-present";function probe(){n++;try{process.kill(-e.pgid,0);last="still-present";}catch(x){if(x&&x.code==="ESRCH")return complete("gone");last="probe-"+_SchelmChildProcess_code(x);}if(n>=3)return complete(last);e.probeTimer=setTimeout(probe,25);}probe();},e.grace);
  function complete(detail){if(e.completed)return;e.completed=true;clearTimeout(e.termTimer);clearTimeout(e.probeTimer);clearTimeout(e.deadlineTimer);_SchelmChildProcess_registry.delete(e.id);var out=e.captureOut?e.captureOut.finish():null,err=e.captureErr?e.captureErr.finish():null;_Scheduler_rawSpawn(A6(e.finish,e.code,e.signal,e.reason,detail,_SchelmChildProcess_maybeBytes(out),_SchelmChildProcess_maybeBytes(err)));}
  e.complete=complete;
}
var _SchelmChildProcess_start = F8(function(finish,id,program,argv,cwd,envFacts,stdinFacts,outputFacts){return _Scheduler_binding(function(callback){
  if(!_SchelmChildProcess_isUnix){callback(_Scheduler_succeed($elm$core$Result$Err("UNSUPPORTED_PLATFORM")));return;}
  var child,settled=false;function settle(v){if(!settled){settled=true;callback(_Scheduler_succeed(v));}}
  try{
    var ec=envFacts.a,pairs=_List_toArray(envFacts.b),env=ec===0?process.env:(ec===1?Object.assign(Object.create(null),process.env):Object.create(null));pairs.forEach(function(p){env[p.a]=p.b;});
    var sc=stdinFacts.a,sbytes=stdinFacts.b,of=outputFacts.a,sf=outputFacts.b.a,grace=outputFacts.b.b.a,deadline=outputFacts.b.b.b;
    function mode(x){return typeof x==="number"?x:x.a;} function limit(x){return typeof x==="number"?0:x.b;}
    child=require("node:child_process").spawn(program,_List_toArray(argv),{cwd:cwd.$==='Nothing'?undefined:cwd.a,env:env,detached:true,stdio:[sc===1?"inherit":(sc===0?"ignore":"pipe"),mode(of)===0?"inherit":(mode(of)===1?"ignore":"pipe"),mode(sf)===0?"inherit":(mode(sf)===1?"ignore":"pipe")]});
    var e={id:id,child:child,pgid:child.pid,grace:grace,finish:finish,cleaning:false,completed:false,code:-1,signal:"",stdout:child.stdout,stderr:child.stderr,stdin:child.stdin,endedOut:false,endedErr:false,captureOut:null,captureErr:null,reason:null,armed:false,closed:false,remainderOut:null,remainderErr:null,pendingOut:false,pendingErr:false,writePending:false,deadlineTimer:null};_SchelmChildProcess_registry.set(id,e);
    function overflowOut(){if(e.reason===null)e.reason="overflow-stdout";_SchelmChildProcess_beginCleanup(e);} function overflowErr(){if(e.reason===null)e.reason="overflow-stderr";_SchelmChildProcess_beginCleanup(e);} if(mode(of)===2&&typeof of!=="number")e.captureOut=_SchelmChildProcess_capture(e.stdout,limit(of),overflowOut);else if(e.stdout){e.stdout.pause();e.stdout.once("end",function(){e.endedOut=true;});} if(mode(sf)===2&&typeof sf!=="number")e.captureErr=_SchelmChildProcess_capture(e.stderr,limit(sf),overflowErr);else if(e.stderr){e.stderr.pause();e.stderr.once("end",function(){e.endedErr=true;});}
    child.once("spawn",function(){if(deadline>0)e.deadlineTimer=setTimeout(function(){if(e.reason===null)e.reason="deadline";_SchelmChildProcess_beginCleanup(e);},deadline);settle($elm$core$Result$Ok(child.pid));if(sc===2&&sbytes&&e.stdin){try{e.stdin.end(Buffer.from(sbytes.buffer,sbytes.byteOffset,sbytes.byteLength));}catch(_){_SchelmChildProcess_beginCleanup(e);}}});
    child.once("error",function(x){_SchelmChildProcess_registry.delete(id);settle($elm$core$Result$Err(_SchelmChildProcess_code(x)));});
    child.once("close",function(code,signal){e.code=code==null?-1:code;e.signal=signal||"";e.closed=true;if(e.reason===null)e.reason="leader";if(e.armed)_SchelmChildProcess_beginCleanup(e);});
  }catch(x){if(child)try{child.kill("SIGKILL");}catch(_){}settle($elm$core$Result$Err(_SchelmChildProcess_code(x)));}
  return function(){if(!settled&&child)try{process.kill(-child.pid,"SIGKILL");}catch(_){}};
});});
var _SchelmChildProcess_read=F2(function(id,stdout){return _Scheduler_binding(function(callback){var e=_SchelmChildProcess_registry.get(id),s=e&&(stdout?e.stdout:e.stderr);if(!e||!s){callback(_Scheduler_fail("UNAVAILABLE"));return;}var pk=stdout?"pendingOut":"pendingErr",rk=stdout?"remainderOut":"remainderErr";if(e[pk]){callback(_Scheduler_fail("ALREADY_PENDING"));return;}if(e[rk]){var rem=e[rk],part=rem.subarray(0,65536);e[rk]=rem.length>65536?rem.subarray(65536):null;callback(_Scheduler_succeed($elm$core$Maybe$Just(_SchelmChildProcess_bytes(part))));return;}if(stdout?e.endedOut:e.endedErr){callback(_Scheduler_succeed($elm$core$Maybe$Nothing));return;}e[pk]=true;var done=false;function clean(){e[pk]=false;s.removeListener("data",data);s.removeListener("end",end);s.removeListener("error",error);s.pause();}function data(b){if(done)return;done=true;if(b.length>65536)e[rk]=b.subarray(65536);clean();callback(_Scheduler_succeed($elm$core$Maybe$Just(_SchelmChildProcess_bytes(b.subarray(0,65536)))));}function end(){if(done)return;done=true;clean();callback(_Scheduler_succeed($elm$core$Maybe$Nothing));}function error(x){if(done)return;done=true;clean();callback(_Scheduler_fail(_SchelmChildProcess_code(x)));}s.once("data",data);s.once("end",end);s.once("error",error);s.resume();return function(){if(!done){done=true;clean();}};});});
var _SchelmChildProcess_write=F2(function(id,bytes){return _Scheduler_binding(function(callback){var e=_SchelmChildProcess_registry.get(id);if(!e||!e.stdin){callback(_Scheduler_fail("UNAVAILABLE"));return;}if(e.writePending){callback(_Scheduler_fail("ALREADY_PENDING"));return;}e.writePending=true;try{var b=Buffer.from(bytes.buffer,bytes.byteOffset,bytes.byteLength);if(e.stdin.write(b)){e.writePending=false;callback(_Scheduler_succeed(_Utils_Tuple0));return;}e.stdin.once("drain",function(){e.writePending=false;callback(_Scheduler_succeed(_Utils_Tuple0));});}catch(x){e.writePending=false;callback(_Scheduler_fail(_SchelmChildProcess_code(x)));}});});
var _SchelmChildProcess_close=function(id){return _Scheduler_binding(function(callback){var e=_SchelmChildProcess_registry.get(id);if(!e||!e.stdin){callback(_Scheduler_succeed(_Utils_Tuple0));return;}try{e.stdin.end(function(){callback(_Scheduler_succeed(_Utils_Tuple0));});}catch(x){callback(_Scheduler_fail(_SchelmChildProcess_code(x)));}});};
var _SchelmChildProcess_cancel=function(id){return _Scheduler_binding(function(callback){var e=_SchelmChildProcess_registry.get(id);if(e){if(e.reason===null)e.reason="cancel";_SchelmChildProcess_beginCleanup(e);}callback(_Scheduler_succeed(_Utils_Tuple0));});};
var _SchelmChildProcess_cancelMany=function(ids){return _Scheduler_binding(function(callback){_List_toArray(ids).forEach(function(id){var e=_SchelmChildProcess_registry.get(id);if(e){if(e.reason===null)e.reason="shutdown";_SchelmChildProcess_beginCleanup(e);}});callback(_Scheduler_succeed(_Utils_Tuple0));});};

var _SchelmChildProcess_arm=function(id){return _Scheduler_binding(function(callback){var e=_SchelmChildProcess_registry.get(id);callback(_Scheduler_succeed(_Utils_Tuple0));if(e)setTimeout(function(){e.armed=true;if(e.closed)_SchelmChildProcess_beginCleanup(e);},0);});};
