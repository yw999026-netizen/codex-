function [raw,event,window] = recordTemplates
% Stable scalar schemas ensure empty exports have the same column headers.
common=struct('experiment_id','','mode','simulation','actual_time_iso','', ...
    'baseline_id','','calibration_version','demo-standard-v2','elapsed_wall_s',NaN,'simulation_time_s',NaN,'group','','phase','');
raw=common;
for k=1:18, raw.(sprintf('temperature_%02d_c',k))=NaN; end
for k=1:3, raw.(sprintf('probe_um_%d',k))=NaN; end
for k=1:6
    raw.(sprintf('valve_requested_%d_percent',k))=NaN;
    raw.(sprintf('valve_register_%d',k))=NaN;
    raw.(sprintf('valve_write_status_%d',k))='NOT_SENT';
    raw.(sprintf('feedback_source_%d',k))='simulated';
    raw.(sprintf('valve_command_%d_percent',k))=NaN;
    raw.(sprintf('valve_sim_feedback_%d_percent',k))=NaN;
end
for k=1:6
    raw.(sprintf('flow_sim_%d_l_min',k))=NaN;
    raw.(sprintf('water_in_sim_%d_c',k))=NaN;
    raw.(sprintf('water_out_sim_%d_c',k))=NaN;
end
raw.communication_ok=false; raw.probe_in_range=false; raw.error='';
event=common; event.event=''; event.detail='';
window=common; window.window_id=''; window.kind=''; window.valid=false; window.reason='';
window.count=0; window.request_time_iso=''; window.actual_start_iso=''; window.actual_end_iso='';
window.start_elapsed_wall_s=NaN; window.end_elapsed_wall_s=NaN;
for k=1:3
    window.(sprintf('probe_mean_%d_um',k))=NaN;
    window.(sprintf('probe_std_%d_um',k))=NaN;
end
for axis='xyz'
    window.(sprintf('xyz_%s_um',axis))=NaN;
    window.(sprintf('xyz_std_%s_um',axis))=NaN;
end
end
