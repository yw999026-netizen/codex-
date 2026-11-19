function value = utcNow
% Actual UTC timestamp, never derived from accelerated thermal time.
t = datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss.SSS''Z''');
value = char(t);
end
