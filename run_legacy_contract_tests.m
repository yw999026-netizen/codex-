function run_legacy_contract_tests
% Offline MATLAB assertions. No hardware I/O. Execution pending MATLAB runtime.
[clamped,encoded]=labshared.legacyValveCommand([90 20 -1 0 59 60]);
assert(isequal(clamped,[60 20 0 0 59 60]));assert(isequal(encoded,[6000 2000 0 0 5900 6000]));
caught=false;try,labshared.legacyValveCommand(NaN);catch,caught=true;end;assert(caught);
requested=labshared.parseLegacyValveRequest({'120','-2','20','0','59','60'});
assert(isequal(requested,[120;-2;20;0;59;60]));
[modelInput,encoded]=labshared.legacyValveCommand(requested);
assert(isequal(modelInput,[60;0;20;0;59;60]) && encoded(1)==6000);
for text={'NaN','Inf','abc','1+2i'}
    caught=false;try,labshared.parseLegacyValveRequest(text);catch,caught=true;end;assert(caught);
end
assert(labshared.requireSimulation(true));caught=false;
try,labshared.requireSimulation(false);catch err,caught=strcmp(err.identifier,'lab:LegacyHardwareDisabled');end;assert(caught);
fprintf('PASS: legacy simulation gate and request-to-encoding contract\n');
end
