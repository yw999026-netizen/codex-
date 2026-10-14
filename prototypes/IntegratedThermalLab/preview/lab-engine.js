(function(root,factory){if(typeof module==='object'&&module.exports)module.exports=factory();else root.ITL=factory();})(typeof globalThis!=='undefined'?globalThis:this,function(){
'use strict';
const GROUPS=['0','A','B','C','AB','AC','BC','ABC'];
const TEMPS=['床身右侧','立柱左侧','立柱右侧','横梁上端','环境温度','Z轴前端轴承','Z轴后端轴承','X轴前端轴承','Y2轴前端轴承','Y1轴前端轴承','Y1轴后端轴承','Z轴螺母','Y2轴螺母','Y1轴螺母','Y2轴后端轴承','X轴螺母','X轴后端轴承','主轴前端轴承'];
const C=[[.9428090416,-.4714045208,-.4714045208],[0,.8164965809,-.8164965809],[.4714045208,.4714045208,.4714045208]];
const H=[[Math.SQRT1_2,0,Math.SQRT1_2],[-Math.SQRT1_2/2,Math.sqrt(3)*Math.SQRT1_2/2,Math.SQRT1_2],[-Math.SQRT1_2/2,-Math.sqrt(3)*Math.SQRT1_2/2,Math.SQRT1_2]];
function copy(v){if(Array.isArray(v))return v.map(copy);if(v&&typeof v==='object'){const out={};for(const k of Object.keys(v))out[k]=copy(v[k]);return out;}return v;}
function mul(a,v){return a.map(row=>row.reduce((s,x,i)=>s+x*v[i],0));}
function means(rows){return rows[0].map((_,i)=>rows.reduce((s,r)=>s+r[i],0)/rows.length);}
function sd(rows){if(rows.length<2)return [NaN,NaN,NaN];const mean=means(rows);return mean.map((m,i)=>Math.sqrt(rows.reduce((s,r)=>s+(r[i]-m)**2,0)/(rows.length-1)));}
function csvCell(v){if(v===null||v===undefined||(typeof v==='number'&&!Number.isFinite(v)))return '';const s=String(v);return /[",\n\r]/.test(s)?'"'+s.replace(/"/g,'""')+'"':s;}
function csv(headers,rows){return headers.join(',')+'\n'+rows.map(row=>row.map(csvCell).join(',')).join('\n')+(rows.length?'\n':'');}
function createQueue(clock){
 return {jobs:[],busy:false,history:[],completed:0,maxConcurrent:0,
  push(name,fn){if(typeof fn!=='function')throw Error('任务必须是函数');this.jobs.push({name,fn});},
  clear(){this.jobs=[];},
  flush(){if(this.busy)return;this.busy=true;this.maxConcurrent=Math.max(this.maxConcurrent,1);
   try{while(this.jobs.length){const job=this.jobs.shift();const entry={name:job.name,startTimeIso:new Date(clock?clock():Date.now()).toISOString(),success:false};
    try{const value=job.fn();if(value&&typeof value.then==='function')throw Error('模拟同步适配器不接受异步任务');entry.success=true;this.completed++;}
    finally{entry.endTimeIso=new Date(clock?clock():Date.now()).toISOString();this.history.push(entry);if(this.history.length>300)this.history.shift();}
   }}finally{this.busy=false;}
  }
 };
}
class Lab{
 constructor(options){
  this.config=Object.assign({mode:'simulation',sampleIntervalSec:1,settleSec:2,windowSamples:5,thermalAcceleration:120,probeLimitUm:100,group:'ABC',openingPercent:60},options||{});
  if(this.config.mode!=='simulation')throw Error('此原型仅支持模拟模式，真实设备尚未配置');
  for(const k of ['sampleIntervalSec','windowSamples','thermalAcceleration','probeLimitUm'])if(!Number.isFinite(this.config[k])||this.config[k]<=0)throw Error('演示参数必须为正数');
  if(!Number.isInteger(this.config.windowSamples)||!Number.isFinite(this.config.settleSec)||this.config.settleSec<0)throw Error('窗口参数无效');
  if(!Number.isFinite(this.config.openingPercent)||this.config.openingPercent<0||this.config.openingPercent>100)throw Error('模拟开度必须在0—100%');
  this.clock=this.config.clock||(()=>Date.now());this.monotonic=this.config.monotonic||(()=>performance.now()/1000);
  this.originMono=this.monotonic();this.lastTick=0;this.modelLast=0;this.elapsedWallSec=0;this.simulationTimeSec=0;
  this.id='SIM-'+new Date(this.clock()).toISOString().replace(/[-:.TZ]/g,'')+'-'+Math.random().toString(36).slice(2,6);
  this.phase='IDLE';this.group='ABC';this.confirmations={stopped:false,positioned:false,oriented:false};
  this.baselineReady=false;this.baseline=null;this.lastXYZ=null;this.raw=[];this.windows=[];this.events=[];
  this.command=[0,0,0,0,0,0];this.opening=[0,0,0,0,0,0];this.activeWindow=null;this.faultNext=null;this.polling=false;this.pollIndex=0;
  this.bus=createQueue(this.clock);this.latest=null;this.setGroup(this.config.group);
  this.event('EXPERIMENT_CREATED','模拟实验；未连接机床或阀门');
 }
 now(){return Math.max(0,this.monotonic()-this.originMono);}
 iso(){return new Date(this.clock()).toISOString();}
 accrueThermal(){const now=this.now();if(now+1e-9<this.modelLast)throw Error('单调时钟倒退');if(this.phase==='RUNNING')this.simulationTimeSec+=(now-this.modelLast)*this.config.thermalAcceleration;this.modelLast=now;}
 event(action,detail){this.events.push({experimentId:this.id,mode:'simulation',actualTimeIso:this.iso(),elapsedWallSec:this.now(),action,detail:detail||''});}
 requireConfirmations(){if(!Object.values(this.confirmations).every(Boolean))throw Error('请确认主轴停转、同向到位和角向复位');}
 setGroup(group){if(this.phase!=='IDLE'||this.baselineReady)throw Error('实验组别已冻结，请结束后新建实验');if(!GROUPS.includes(group))throw Error('冷却组合无效');this.group=group;this.event('GROUP_SELECTED',group);}
 setConfirmations(flags){this.confirmations={stopped:!!flags.stopped,positioned:!!flags.positioned,oriented:!!flags.oriented};
  this.event('POSE_CONFIRMED',JSON.stringify(this.confirmations));
  if(this.activeWindow&&!Object.values(this.confirmations).every(Boolean)){this.finishWindow(false,'POSE_CHANGED');this.phase=this.baselineReady?'RETURNING':'IDLE';}
 }
 requestBaseline(){if(this.baselineReady)throw Error('每轮基准只建立一次');if(this.phase!=='IDLE')throw Error('当前状态不能建立基准');this.requireConfirmations();this.beginWindow('baseline');}
 beginWindow(kind){this.activeWindow={kind,requestedWall:this.now(),requestedIso:this.iso(),samples:[]};this.phase='SETTLING';this.event('WINDOW_REQUESTED',kind);}
 startRunning(){if(!this.baselineReady)throw Error('请先建立冷态基准');if(this.phase!=='READY')throw Error('当前状态不能运行');
  this.accrueThermal();
  this.confirmations={stopped:false,positioned:false,oriented:false};
  this.command=['A','A','B','B','C','C'].map(g=>this.group.includes(g)?this.config.openingPercent:0);
  this.command.forEach((v,i)=>this.bus.push('模拟写阀门'+(i+1),()=>{this.event('VALVE_COMMAND','支路'+(i+1)+'='+v+'%；仅模拟指令');}));
  this.bus.flush();this.phase='RUNNING';this.event('RUN_STARTED','固定组合'+this.group+'；不执行XYZ闭环');
 }
 returnToPoint(){if(!this.baselineReady||!['RUNNING','READY'].includes(this.phase))throw Error('当前状态不能返回检测位');this.accrueThermal();this.phase='RETURNING';this.confirmations={stopped:false,positioned:false,oriented:false};this.event('RETURN_REQUESTED','等待停转、同向返回与角向复位确认');}
 requestMeasurement(){if(!this.baselineReady)throw Error('请先建立基准');if(this.phase!=='RETURNING')throw Error('请先返回检测位');this.requireConfirmations();this.beginWindow('thermal');}
 inject(type){if(!['communication','overrange'].includes(type))throw Error('故障类型无效');this.faultNext=type;this.event('SIMULATED_FAULT_ARMED',type);}
 recover(){if(this.phase!=='FAULT')throw Error('当前没有通信故障');this.bus.clear();this.faultNext=null;this.phase=this.baselineReady?'READY':'IDLE';this.confirmations={stopped:false,positioned:false,oriented:false};this.event('RECOVERED','基准保留；操作确认已清除');}
 stop(){this.accrueThermal();if(this.activeWindow)this.finishWindow(false,'CANCELLED');this.phase='FINISHED';this.confirmations={stopped:false,positioned:false,oriented:false};this.event('EXPERIMENT_FINISHED','只结束模拟采集；没有发送硬件动作');}
 trueXYZ(){
  const t=this.simulationTimeSec;
  const a=this.group.includes('A')?1:0,b=this.group.includes('B')?1:0,c=this.group.includes('C')?1:0;
  // Illustrative response only, not a fitted plant or evidence of cooling performance.
  return [160*(1-Math.exp(-t/12000))*(1-.15*a-.12*b-.10*c),
    (25*(1-Math.exp(-t/1000))-80*(1-Math.exp(-t/15000)))*(1-.10*a-.15*b-.08*c),
    45*(1-Math.exp(-t/4000))*(1-.08*a-.10*b-.12*c)];
 }
 simulate(){
  const t=this.simulationTimeSec,xyz=this.trueXYZ(),n=this.pollIndex;
  const temps=TEMPS.map((_,i)=>20.2+(i===4?.18:4+i*.55)*(1-Math.exp(-t/(4800+i*130)))+.025*Math.sin(n*.31+i));
  const inPose=Object.values(this.confirmations).every(Boolean)&&this.phase!=='RUNNING';
  let probes=inPose?mul(H,xyz).map((v,i)=>-v+.04*Math.sin(n*.8+i)): [104,104,104];
  if(this.faultNext==='overrange'){probes=[104,probes[1],probes[2]];this.faultNext=null;}
  const flow=this.opening.map(v=>v/100*2);
  const waterIn=this.opening.map(()=>20);
  const waterOut=flow.map((f,i)=>20+(f>0?(temps[[0,0,1,2,3,3][i]]-20)*.15:0));
  return {temps,probes,flow,waterIn,waterOut};
 }
 tick(){
  const now=this.now();if(now+1e-9<this.lastTick)throw Error('单调时钟倒退，不能伪造时间');
  if(this.phase==='FINISHED')return;
  if(this.polling){this.event('POLL_SKIPPED','前一通信周期未完成');return;}
  const dt=now-this.lastTick;this.elapsedWallSec=now;this.lastTick=now;this.polling=true;this.pollIndex++;
  this.accrueThermal();
  this.opening=this.opening.map((v,i)=>v+(this.command[i]-v)*(1-Math.exp(-dt/1.5)));
  if(this.activeWindow&&now-this.activeWindow.requestedWall>=this.config.settleSec)this.phase='MEASURING';
  let values=null,tempTime=null,probeTime=null,coolTime=null;
  try{
   this.bus.push('读取18路温度（模拟）',()=>{if(this.faultNext==='communication'){this.faultNext=null;throw Error('模拟通信超时');}values=this.simulate();tempTime=this.iso();});
   this.bus.push('读取3路探头（模拟）',()=>{probeTime=this.iso();});
   this.bus.push('读取水冷状态（模拟）',()=>{coolTime=this.iso();});this.bus.flush();
   const finite=[...values.temps,...values.probes,...values.flow,...values.waterIn,...values.waterOut,...this.opening].every(Number.isFinite);
   const inRange=values.probes.every(p=>Number.isFinite(p)&&Math.abs(p)<=this.config.probeLimitUm);
   const quality=!finite?'NONFINITE':inRange?'OK':'OUT_OF_RANGE';
   const row={experimentId:this.id,mode:'simulation',actualTimeIso:this.iso(),temperatureTimeIso:tempTime,probeTimeIso:probeTime,coolingTimeIso:coolTime,elapsedWallSec:now,simulationTimeSec:this.simulationTimeSec,group:this.group,phase:this.phase,...values,command:this.command.slice(),opening:this.opening.slice(),quality};
   this.raw.push(row);this.latest=row;
   if(this.activeWindow){
    if(this.phase==='MEASURING')this.activeWindow.samples.push(row);
    if(quality!=='OK'){this.finishWindow(false,quality);this.phase=this.baselineReady?'RETURNING':'IDLE';this.confirmations={stopped:false,positioned:false,oriented:false};}
    else if(this.phase==='MEASURING'&&this.activeWindow.samples.length>=this.config.windowSamples)this.finishWindow(true,'OK');
   }
  }catch(error){
   this.bus.clear();
   const row={experimentId:this.id,mode:'simulation',actualTimeIso:this.iso(),temperatureTimeIso:null,probeTimeIso:null,coolingTimeIso:null,elapsedWallSec:now,simulationTimeSec:this.simulationTimeSec,group:this.group,phase:this.phase,temps:Array(18).fill(NaN),probes:Array(3).fill(NaN),command:this.command.slice(),opening:Array(6).fill(NaN),flow:Array(6).fill(NaN),waterIn:Array(6).fill(NaN),waterOut:Array(6).fill(NaN),quality:'COMMUNICATION_ERROR'};
   this.raw.push(row);this.latest=row;
   if(this.activeWindow)this.finishWindow(false,'COMMUNICATION_ERROR');
   this.phase='FAULT';this.confirmations={stopped:false,positioned:false,oriented:false};this.event('COMMUNICATION_ERROR',error.message);
  }finally{this.polling=false;}
 }
 finishWindow(valid,reason){
  const active=this.activeWindow;if(!active)return;
  const samples=active.samples,probes=samples.map(r=>r.probes),mean=probes.length?means(probes):[NaN,NaN,NaN];
  const w={experimentId:this.id,mode:'simulation',group:this.group,kind:active.kind,valid,reason,count:samples.length,requestedTimeIso:active.requestedIso,startTimeIso:samples.length?samples[0].actualTimeIso:null,endTimeIso:samples.length?samples.at(-1).actualTimeIso:this.iso(),startWallSec:samples.length?samples[0].elapsedWallSec:null,endWallSec:this.now(),probeMean:mean,xyz:[NaN,NaN,NaN],std:[NaN,NaN,NaN]};
  if(valid&&active.kind==='baseline'){this.baseline=mean.slice();this.baselineReady=true;w.xyz=[0,0,0];w.std=sd(probes.map(v=>mul(C,v.map((x,i)=>this.baseline[i]-x))));this.event('BASELINE_COMPLETE','本轮唯一基准；模拟几何');}
  if(valid&&active.kind==='thermal'){
   const xyzPoints=probes.map(v=>mul(C,v.map((x,i)=>this.baseline[i]-x)));
   w.xyz=means(xyzPoints);w.std=sd(xyzPoints);this.lastXYZ=w.xyz.slice();this.event('THERMAL_WINDOW_COMPLETE','有效点数'+w.count);
  }
  if(!valid)this.event('WINDOW_INVALID',reason);
  this.windows.push(w);this.activeWindow=null;
  if(valid)this.phase='READY';
 }
 snapshot(){
  const valid=this.windows.filter(w=>w.kind==='thermal'&&w.valid);
  return copy({experimentId:this.id,mode:'simulation',phase:this.phase,group:this.group,confirmations:this.confirmations,baselineReady:this.baselineReady,baseline:this.baseline,lastXYZ:this.lastXYZ,elapsedWallSec:this.now(),simulationTimeSec:this.simulationTimeSec,windowKind:this.activeWindow?this.activeWindow.kind:null,windowCount:this.activeWindow?this.activeWindow.samples.length:0,windowTarget:this.config.windowSamples,settleRemaining:this.activeWindow?Math.max(0,this.config.settleSec-(this.now()-this.activeWindow.requestedWall)):0,command:this.command,opening:this.opening,latest:this.latest,raw:this.raw,windows:this.windows,events:this.events.slice(-100),bus:{completed:this.bus.completed,busy:this.bus.busy,queued:this.bus.jobs.length,maxConcurrent:this.bus.maxConcurrent,history:this.bus.history.slice(-20)},rmsUm:valid.length?Math.sqrt(valid.reduce((s,w)=>s+w.xyz.reduce((a,x)=>a+x*x,0),0)/valid.length):null,temperatureNames:TEMPS,config:{...this.config,clock:undefined,monotonic:undefined}});
 }
 exportData(){
  const rawHeaders=['experiment_id','mode','actual_time_iso','temperature_time_iso','probe_time_iso','cooling_time_iso','elapsed_wall_s','simulation_time_s','group','phase','quality',...TEMPS.map((_,i)=>'temperature_'+(i+1)+'_C'),...Array.from({length:3},(_,i)=>'probe_'+(i+1)+'_um'),...['valve_command_','valve_feedback_','flow_','water_in_','water_out_'].flatMap(p=>Array.from({length:6},(_,i)=>p+(i+1)+(p.startsWith('valve')?'_percent':p==='flow_'?'_L_min':'_C')))];
  const rawRows=this.raw.map(r=>[r.experimentId,r.mode,r.actualTimeIso,r.temperatureTimeIso,r.probeTimeIso,r.coolingTimeIso,r.elapsedWallSec,r.simulationTimeSec,r.group,r.phase,r.quality,...r.temps,...r.probes,...r.command,...r.opening,...r.flow,...r.waterIn,...r.waterOut]);
  const windowHeaders=['experiment_id','mode','group','kind','valid','reason','count','requested_time_iso','start_time_iso','end_time_iso','start_wall_s','end_wall_s','probe_mean_1_um','probe_mean_2_um','probe_mean_3_um','X_um','Y_um','Z_um','std_X_um','std_Y_um','std_Z_um'];
  const windowRows=this.windows.map(w=>[w.experimentId,w.mode,w.group,w.kind,w.valid,w.reason,w.count,w.requestedTimeIso,w.startTimeIso,w.endTimeIso,w.startWallSec,w.endWallSec,...w.probeMean,...w.xyz,...w.std]);
  const eventHeaders=['experiment_id','mode','actual_time_iso','elapsed_wall_s','action','detail'];
  const eventRows=this.events.map(e=>[e.experimentId,e.mode,e.actualTimeIso,e.elapsedWallSec,e.action,e.detail]);
  const meta={experimentId:this.id,mode:'simulation',version:'1.0',group:this.group,calibrationSource:'模拟演示45度理想几何；不是实机标定',xyzConvention:'XYZ_um = C * (baseline_probe_um - current_probe_um); actual sensor sign requires field calibration.',C,baseline:this.baseline,config:this.snapshot().config,temperatureNames:TEMPS,disclaimer:'全部为模拟数据；未连接机床、未发送真实阀门指令；模拟开度和流量不证明现场冷却条件。',missingValue:'CSV空白代表缺失/不可计算，不是零。',timeMeaning:'actual_time_iso为UTC实际记录时刻；elapsed_wall_s为单调经过时间；simulation_time_s为加速热模型时间。'};
  return {rawCsv:csv(rawHeaders,rawRows),windowsCsv:csv(windowHeaders,windowRows),eventsCsv:csv(eventHeaders,eventRows),metadataJson:JSON.stringify(meta,null,2)};
 }
}
return {createLab:options=>new Lab(options),createQueue,GROUPS,TEMPERATURE_NAMES:TEMPS,DEMO_C:C};
});
