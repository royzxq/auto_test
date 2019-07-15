function StartServerImpair(port)

if nargin < 1
    port =11999;
end
if ischar(port)
    port = str2double(port);
end

while 1
    try
        ServerImpair(port);
    catch exc
        fprintf('%s\n', exc.identifier);
        fprintf('Re-launching the Impairment Server...\n');
    end
end

end
%%

function ServerImpair(port)

[s, ~] = system('./enable_udp.sh');
preProtocol = '';
ser = tcpip('0.0.0.0', port, 'NetworkRole', 'server');
ser.TimeOut = 30;
ser.BytesAvailableFcnMode = 'terminator';
ser.BytesAvailableFcn = @handle_imser;
ser.UserData = [];
fprintf('Server opened at port %d, waiting for the client recorder...\n', port);

while 1
    
    fprintf('Waiting for the client...\n');
    fopen(ser);
    fprintf('The client connected...\n');
    pause(.1);
    
    pbser_port = str2double(receive_msg(ser));
    impair_info = receive_msg(ser); % receiving the reference file name
    fprintf('Received impairment information: %s\n', impair_info);
    impair_par = regexp(impair_info, ' ', 'split');

    % cleaning out the impairment
    [s, ~] = system('sudo sh enable_udp.sh');
    system('sudo pkill -9 netem.py'); 
    
    if strcmp(impair_par{5}, 'TCP')
        fprintf('Blocking the UDP protocol...\n');
        [s, ~] = system('sudo sh block_udp.sh');
    end
    
    %fprintf('%s; %s \n', preProtocol, preType);
    if strcmp(preProtocol, 'UDP') && strcmp(impair_par{5}, 'TCP')
        send_msg(ser, 190);
        fprintf('Sent impairment warm up time extension: 190 sec...\n');                   
    else
        send_msg(ser, 0);        
    end
    preProtocol = impair_par{5};
    
    if strcmp(impair_par{1}, 'jitter')
        type = ' --jitter ';
    elseif strcmp(impair_par{1}, 'loss')
        type = ' --loss_ratio ';
    else
        error('Wrong type for the impairment information...\n');        
    end
    
    if strcmp(impair_par{4}, 'inbound')
        inbound = ' --inbound';
    elseif strcmp(impair_par{4}, 'outbound')
        inbound = '';
    else
        error('Wrong type for the impairment information...\n');         
    end
    
    if ~prod(isstrprop(impair_par{2}, 'digit'))
        error('Wrong type for the impairment information...\n');
    end
    
    impair_cmd = ['python netem.py -n ', impair_par{3}, inbound, ...
        ' --exclude src=172.19.127.248 --exclude dst=172.19.127.248', ...
        ' --exclude sport=', num2str(pbser_port), ' --exclude dport=', num2str(pbser_port), ...
        ' --exclude sport=', num2str(port), ' --exclude dport=', num2str(port), ... 
        ' netem', type, impair_par{2}, ' &'];
    
    system(impair_cmd);
    fprintf('Impairment with the following command has started...\n%s\n', impair_cmd);
    while 1
        v = check_connection(ser);
        if v < 2           
            break;
        end        
        pause(.5);        
    end
    
    if v == 1
        fprintf('Impairment stopped...\n');
    else
        fprintf('Client unexpectedly terminated, so stop impairment...\n');
    end
    release_cmd = ['python netem.py -n ', impair_par{3}, inbound, ...
               ' --exclude src=172.19.127.248 --exclude dst=172.19.127.248', ...
        ' --exclude sport=', num2str(pbser_port), ' --exclude dport=', num2str(pbser_port), ...
        ' --exclude sport=', num2str(port), ' --exclude dport=', num2str(port), ... 
        ' netem', type, ' 0 &']; 
    system(release_cmd);            
    pause(1);
    system('sudo pkill -9 netem.py');
    [s, ~] = system('sudo sh enable_udp.sh');
    fclose(ser);    
    fprintf('Ended a session...\n');
end

end

%%
function handle_imser(obj, event)

msg = fgetl(obj);

switch str2double(msg(1))
    
    case 1 % got acknowledgement
        set(obj, 'UserData', msg); 
    
    case 2  % normal data transfer
        set(obj, 'UserData', msg(2:end));
        
    case 3 % get connection status
        set(obj, 'UserData', msg(2:end));        
        
    otherwise
        fprintf('Client sent a message not recognized: %.4f\n', msg);        
end

end

%%
function v = send_msg(obj, data)

v = 0;
if ~ischar(data)
    data = num2str(data);
end
for count = 1: 3   
    fprintf(obj, '2%s', [data, char(10)]);
    for i=1:100 
        pause(0.1);
        rtn = get(obj, 'UserData');
        if strcmp(rtn, '1')
            v = 1;
            set(obj, 'UserData', []);
            break;
        end    
    end
    if v
        break;
    end
end
pause(.2);
if ~v
    error('Time out! seems disconnected...\n');
end

end
%%
function [msg, v] = receive_msg(obj)

msg = [];
v = 0;
for i=1:300    
    msg = get(obj, 'UserData');
    if ~isempty(msg)
        set(obj, 'UserData', []);
        fprintf(obj, '%s', ['1', char(10)]);
        v = 1;
        break;
    end
    pause(0.1);
end
pause(.2);        
if ~v
    error('Time out! seems disconnected...\n');
end

end
%%

function v = check_connection(obj)

v = 0;
for count = 1 : 2
    fprintf(obj, '%s', ['3', char(10)]);
    for i=1:50 
        pause(0.1);
        rtn = get(obj, 'UserData');
        if ~isempty(rtn)            
            v = str2double(rtn);
            set(obj, 'UserData', []);
            break;
        end            
    end    
    if v
        break;
    end
end
pause(.2);    

end

