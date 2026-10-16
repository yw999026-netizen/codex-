function requested=parseLegacyValveRequest(text)
% Parse requested numeric u without clipping or substituting zero.
requested=str2double(text);
validateattributes(requested,{'numeric'},{'finite','real','nonempty'});
requested=requested(:);
end
