function [command,registerValue]=legacyValveCommand(requested)
% Historical numeric u, simulation only. Neither percent nor degrees verified.
% Keep requested separately in caller logs; this is the limited command.
validateattributes(requested,{'numeric'},{'finite','real'});
command=max(0,min(60,requested));
registerValue=round(command*100); % historical encoding, not a commissioned map
end
