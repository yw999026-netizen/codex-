function xyz = displacementUm(C,baseline,current)
%DISPLACEMENTUM Standard current-minus-baseline signed-C convention.
% baseline is 3 readings; current is 3xN probe readings, both in micrometres.
% baseline [10 20 30], current [9;18;27] -> C * [-1;-2;-3].
% Demo C is sign-migrated; the existing measured calibration file is unchanged.
validateattributes(C,{'numeric'},{'size',[3 3],'finite'});
validateattributes(baseline,{'numeric'},{'numel',3,'finite'});
validateattributes(current,{'numeric'},{'2d','size',[3 NaN],'finite'});
xyz=C*(current-baseline(:));
end
