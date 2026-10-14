function files = exportSession(engine,folder)
%EXPORTSESSION Snapshot raw/event/window CSV plus reproducible metadata JSON.
% Empty data keeps the complete schema; absent values remain NaN/empty.
if ~exist(folder,'dir'), mkdir(folder); end
[raw,event,window]=itl.recordTemplates();
writeRecords(engine.Raw,raw,fullfile(folder,'raw.csv'));
writeRecords(engine.Events,event,fullfile(folder,'events.csv'));
writeRecords(engine.Windows,window,fullfile(folder,'windows.csv'));
file=fullfile(folder,'metadata.json'); fid=fopen(file,'w','n','UTF-8');
if fid<0, error('itl:Export','Cannot open metadata output'); end
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(engine.metadata()));
files={fullfile(folder,'raw.csv'),fullfile(folder,'events.csv'),fullfile(folder,'windows.csv'),file};
end
function writeRecords(records,template,file)
if isempty(records)
    t=struct2table(template,'AsArray',true); t(1,:)=[];
else
    t=struct2table(records,'AsArray',true);
end
writetable(t,file,'Encoding','UTF-8');
end
