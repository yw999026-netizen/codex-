function xyz = displacementUm(C,baseline,current)
%DISPLACEMENTUM Shared simulator convention, not field polarity calibration.
% baseline is 3 readings; current is 3xN probe readings, both in micrometres.
% A decreasing probe contributes a positive multiple of its column of C:
% baseline [10 20 30], current [9;18;27] -> C * [1;2;3].
validateattributes(C,{'numeric'},{'size',[3 3],'finite'});
validateattributes(baseline,{'numeric'},{'numel',3,'finite'});
validateattributes(current,{'numeric'},{'2d','size',[3 NaN],'finite'});
xyz=C*(baseline(:)-current);
end
