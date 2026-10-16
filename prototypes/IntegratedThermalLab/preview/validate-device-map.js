'use strict';
// Offline configuration review only; never opens a port or sends commands.
const fs=require('node:fs');const api=require('./lab-contracts.js');
if(!process.argv[2]){console.error('Usage: node preview/validate-device-map.js config/device_map_template.csv');process.exitCode=2;}
else{try{const rows=api.parseCsv(fs.readFileSync(process.argv[2],'utf8')),errors=api.validateDeviceMap(rows);if(errors.length){console.error(JSON.stringify({ready:false,errors},null,2));process.exitCode=2;}else console.log(JSON.stringify({configurationChecksPassed:true,hardwareDriver:'UNIMPLEMENTED',readyForRealIO:false,signals:rows.length}));}catch(e){console.error(e.message);process.exitCode=2;}}
