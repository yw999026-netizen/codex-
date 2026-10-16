(function(root,factory){if(typeof module==='object'&&module.exports)module.exports=factory();else root.ITLContracts=factory();})(typeof globalThis!=='undefined'?globalThis:this,function(){
'use strict';
function missing(v){return v===null||v===undefined||String(v).trim()===''||String(v)==='未填';}
function validateDeviceMap(rows,options){
 const config=Object.assign({requireSingleBus:true},options||{}),errors=[],addresses=new Map(),buses=new Map(),names=new Set(),physical=new Map();
 const add=(row,code,message)=>errors.push({row,code,message});
 if(!Array.isArray(rows)||!rows.length)return [{row:0,code:'EMPTY',message:'设备表为空'}];
 rows.forEach((r,index)=>{const line=index+2;
  if(missing(r.logical_device))add(line,'MISSING','缺少logical_device');else if(names.has(r.logical_device))add(line,'DUPLICATE_SIGNAL','逻辑信号重复');else names.add(r.logical_device);
  if(r.verification_status!=='verified')add(line,'UNVERIFIED','设备或人工来源未核实');
  if(missing(r.unit))add(line,'MISSING','缺少工程单位');
  if(r.source==='manual'){if(missing(r.manual_reference))add(line,'MISSING','人工来源需要记录方法和时间依据');return;}
  if(r.source!=='modbus'){add(line,'SOURCE','数据来源未配置为modbus或manual');return;}
  const required=['physical_device_id','bus_id','serial_port','slave_id','baud_rate','data_bits','parity','stop_bits','function_code','register_start','address_base','register_count','channel_count','data_type','byte_order','scale','offset'];
  required.forEach(k=>{if(missing(r[k]))add(line,'MISSING','缺少'+k);});
  const integer=(k,min,max)=>{if(!missing(r[k])&&(!Number.isInteger(Number(r[k]))||Number(r[k])<min||Number(r[k])>max))add(line,'RANGE',k+'范围无效');};
  integer('slave_id',1,247);integer('baud_rate',1,10000000);integer('data_bits',7,8);integer('register_start',0,65535);integer('register_count',1,125);integer('channel_count',1,125);
  if(!missing(r.function_code)&&![1,2,3,4,5,6,15,16].includes(Number(r.function_code)))add(line,'FUNCTION_CODE','功能码未支持');
  if(!missing(r.parity)&&!['none','even','odd'].includes(r.parity))add(line,'PARITY','校验格式无效');
  if(!missing(r.stop_bits)&&![1,2].includes(Number(r.stop_bits)))add(line,'STOP_BITS','停止位无效');
  if(!missing(r.address_base)&&!['matlab_address_1','protocol_offset_0'].includes(r.address_base))add(line,'ADDRESS_BASE','须明确寄存器地址基准');
  if(r.address_base==='matlab_address_1'&&Number(r.register_start)<1)add(line,'ADDRESS_BASE','MATLAB地址必须从1起');
  for(const k of ['scale','offset'])if(!missing(r[k])&&!Number.isFinite(Number(r[k])))add(line,'NUMBER',k+'必须有限');
  if(!missing(r.scale)&&Number(r.scale)===0)add(line,'SCALE','比例不能为零');
  if(!missing(r.bus_id)){
   const signature=[r.serial_port,r.baud_rate,r.data_bits,r.parity,r.stop_bits].map(String).join('|');
   if(buses.has(r.bus_id)&&buses.get(r.bus_id)!==signature)add(line,'BUS_SETTINGS','同一总线端口或通信参数不一致');else buses.set(r.bus_id,signature);
   if(!missing(r.physical_device_id)&&!missing(r.slave_id)){
    const key=r.bus_id+'|'+Number(r.slave_id),device=r.bus_id+'|'+r.physical_device_id;
    if(addresses.has(key)&&addresses.get(key)!==r.physical_device_id)add(line,'ADDRESS_COLLISION','不同物理设备共用从站地址');else addresses.set(key,r.physical_device_id);
    if(physical.has(device)&&physical.get(device)!==Number(r.slave_id))add(line,'DEVICE_ADDRESS','同一物理设备的逻辑行站号不同');else physical.set(device,Number(r.slave_id));
   }
  }
 });
 if(config.requireSingleBus&&buses.size>1)add(0,'MULTIPLE_BUSES','本项目要求一条共享总线');
 return errors;
}
function makeValveCommand(requested,spec,mode){
 const s=Object.assign({unit:'percent',min:0,max:100,registerScale:null,registerOffset:0,verified:false},spec||{});mode=mode||'simulation';
 if(!['simulation','real'].includes(mode))throw Error('模式无效');
 if(!Number.isFinite(requested)||!Number.isFinite(s.min)||!Number.isFinite(s.max)||s.min>s.max||missing(s.unit))throw Error('阀门请求或限幅参数无效');
 if(mode==='real'&&(!s.verified||!Number.isFinite(s.registerScale)||s.registerScale===0||!Number.isFinite(s.registerOffset)))throw Error('阀门单位/编码尚未核实 verified');
 const clamped=Math.max(s.min,Math.min(s.max,requested));
 const encoded=s.verified&&Number.isFinite(s.registerScale)&&s.registerScale!==0&&Number.isFinite(s.registerOffset)?Math.round(clamped*s.registerScale+s.registerOffset):null;
 if(encoded!==null&&(!Number.isSafeInteger(encoded)||encoded<0||encoded>65535))throw Error('阀门编码超出uint16');
 return {requested,clamped,engineeringUnit:s.unit,registerValue:encoded,writeStatus:'NOT_SENT',actualFeedback:null,feedbackSource:'missing',mode};
}
function feedbackFromWindow(window,nowSec,maxAgeSec){
 if(!window||window.valid!==true||window.kind!=='thermal'||!window.windowId||!window.baselineId||!window.calibrationVersion||!Array.isArray(window.xyz)||window.xyz.length!==3||!window.xyz.every(Number.isFinite))throw Error('反馈必须来自有基准和标定版本的有效XYZ窗口');
 if(!Number.isFinite(nowSec)||!Number.isFinite(maxAgeSec)||maxAgeSec<0||!Number.isFinite(window.endWallSec)||nowSec<window.endWallSec||nowSec-window.endWallSec>maxAgeSec)throw Error('窗口时间或龄期无效');
 return {windowId:window.windowId,baselineId:window.baselineId,calibrationVersion:window.calibrationVersion,sampleWallSec:window.endWallSec,ageSec:nowSec-window.endWallSec,xyz:window.xyz.slice()};
}
function parseCsv(text){
 const records=[],row=[];let field='',quoted=false;const s=String(text).replace(/^\ufeff/,'');
 for(let i=0;i<s.length;i++){const c=s[i];if(quoted){if(c==='"'&&s[i+1]==='"'){field+='"';i++;}else if(c==='"')quoted=false;else field+=c;}else if(c==='"'){if(field)throw Error('CSV引号位置无效');quoted=true;}else if(c===','){row.push(field);field='';}else if(c==='\n'||c==='\r'){if(c==='\r'&&s[i+1]==='\n')i++;row.push(field);if(row.some(v=>v!==''))records.push(row.splice(0));else row.length=0;field='';}else field+=c;}
 if(quoted)throw Error('CSV引号未闭合');if(field!==''||row.length){row.push(field);records.push(row);}
 if(!records.length)return [];const headers=records.shift();if(headers.some(h=>!h)||new Set(headers).size!==headers.length)throw Error('CSV列名重复或空白');
 return records.map(values=>{if(values.length!==headers.length)throw Error('CSV列数不一致');return Object.fromEntries(headers.map((h,i)=>[h,values[i]]));});
}
return {validateDeviceMap,makeValveCommand,feedbackFromWindow,parseCsv};
});
