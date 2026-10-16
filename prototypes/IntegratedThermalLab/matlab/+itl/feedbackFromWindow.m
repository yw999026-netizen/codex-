function result=feedbackFromWindow(window,nowS,maxAgeS)
% Qualified XYZ candidate only. No control calculation or valve write.
required={'window_id','baseline_id','calibration_version','kind','valid','xyz_x_um','xyz_y_um','xyz_z_um','end_elapsed_wall_s'};
if isempty(window) || ~all(isfield(window,required)), error('itl:Feedback','A complete window is required'); end
xyz=[window.xyz_x_um window.xyz_y_um window.xyz_z_um];
if ~window.valid || ~strcmp(window.kind,'HEAT') || isempty(window.window_id) || isempty(window.baseline_id) || isempty(window.calibration_version) || any(~isfinite(xyz))
    error('itl:Feedback','Feedback requires a valid calibrated heat window and baseline');
end
validateattributes(nowS,{'numeric'},{'scalar','finite'});
validateattributes(maxAgeS,{'numeric'},{'scalar','finite','nonnegative'});
age=nowS-window.end_elapsed_wall_s;
if ~isfinite(age) || age<0 || age>maxAgeS, error('itl:StaleFeedback','Window age is invalid or stale'); end
result=struct('window_id',window.window_id,'baseline_id',window.baseline_id, ...
    'calibration_version',window.calibration_version,'sample_elapsed_s',window.end_elapsed_wall_s,'age_s',age,'xyz_um',xyz);
end
