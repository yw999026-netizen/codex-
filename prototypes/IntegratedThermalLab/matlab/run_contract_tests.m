function run_contract_tests
% Base MATLAB behavioral checks. No real I/O. Not run in the build environment.
spec=struct('unit','test_u','minimum',0,'maximum',60,'scale',100,'offset',0,'verified',false);
r=itl.valveCommandRecord(90,spec); assert(r.requested==90 && r.clamped==60 && isnan(r.register_value));
assert(strcmp(r.write_status,'NOT_SENT') && isnan(r.actual_feedback));
caught=false;try,itl.valveCommandRecord(90,spec,'real');catch err,caught=strcmp(err.identifier,'itl:Unverified');end;assert(caught);
spec.verified=true;r=itl.valveCommandRecord(90,spec,'real');assert(r.register_value==6000 && strcmp(r.write_status,'NOT_SENT'));
w=struct('window_id','W1','baseline_id','B1','calibration_version','demo-standard-v2','kind','HEAT','valid',true,'xyz_x_um',1,'xyz_y_um',-2,'xyz_z_um',3,'end_elapsed_wall_s',10);
candidate=itl.feedbackFromWindow(w,12,5);assert(isequal(candidate.xyz_um,[1 -2 3]));
caught=false;try,itl.feedbackFromWindow(w,99,5);catch err,caught=strcmp(err.identifier,'itl:StaleFeedback');end;assert(caught);
w.valid=false;caught=false;try,itl.feedbackFromWindow(w,12,5);catch,caught=true;end;assert(caught);
fprintf('PASS: MATLAB command and feedback contracts\n');
end
