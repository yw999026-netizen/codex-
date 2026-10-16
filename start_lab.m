function engine=start_lab
% Supported unified 18T/3-probe/six-branch simulation launcher.
repositoryRoot=fileparts(mfilename('fullpath'));
addpath(fullfile(repositoryRoot,'prototypes','IntegratedThermalLab','matlab'));
engine=IntegratedThermalLab;
end
