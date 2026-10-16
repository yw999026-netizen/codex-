function record=valveCommandRecord(requested,spec,mode)
% Pure command preparation, never I/O. Unverified encoding stays NaN.
if nargin<2, spec=struct('unit','percent','minimum',0,'maximum',100,'scale',NaN,'offset',0,'verified',false); end
if nargin<3, mode='simulation'; end
validateattributes(requested,{'numeric'},{'scalar','finite'});
validateattributes(spec.minimum,{'numeric'},{'scalar','finite'});
validateattributes(spec.maximum,{'numeric'},{'scalar','finite','>=',spec.minimum});
if ~ismember(mode,{'simulation','real'}), error('itl:Mode','Unknown mode'); end
if isempty(spec.unit), error('itl:Unit','Unit is required'); end
if strcmp(mode,'real') && (~spec.verified || ~isfinite(spec.scale) || spec.scale==0 || ~isfinite(spec.offset))
    error('itl:Unverified','Valve units and register encoding are unverified.');
end
record=struct('requested',requested,'clamped',max(spec.minimum,min(spec.maximum,requested)), ...
    'unit',spec.unit,'register_value',NaN,'write_status','NOT_SENT', ...
    'actual_feedback',NaN,'feedback_source','missing','mode',mode);
if spec.verified && isfinite(spec.scale) && spec.scale~=0 && isfinite(spec.offset)
    encoded=round(record.clamped*spec.scale+spec.offset);
    validateattributes(encoded,{'numeric'},{'scalar','integer','>=',0,'<=',65535});
    record.register_value=encoded;
end
end
