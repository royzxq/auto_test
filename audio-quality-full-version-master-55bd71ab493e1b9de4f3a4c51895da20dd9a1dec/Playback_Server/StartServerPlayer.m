function StartServerPlayer(port)
warning('off', 'all');

if nargin < 1
    port = 12999;
end

while 1
    try 
        ServerPlayer(port);
    catch exc
        fprintf('%s\n', exc.identifier);
        fprintf('Re-launching the Playback Server...\n');
    end
end        

end

%%
function ServerPlayer(port)

% global setting
if ispc
    playback_delay_test_dev_name = 'VB-Audio Virtual Cable';
else
    playback_delay_test_dev_name = 'Sound Siphon';
end

if exist('player_delay.mat', 'file')
    load('player_delay.mat');
else
    fprintf('Measuring the global player delay...\n');
    player_delay = estimate_player_delay(playback_delay_test_dev_name);
end

global glb_t;
global play_cnt;
global max_play_count;

ser = tcpip('0.0.0.0', port, 'NetworkRole', 'server');
ser.TimeOut = 30;
ser.BytesAvailableFcnMode = 'terminator';
ser.InputBufferSize = 10000000;
ser.UserData = [];
fprintf('Server opened at port %d, waiting for the client recorder...\n', port);

while 1

    fprintf('Waiting for the client...\n');
    fopen(ser);
    glb_t = tic;
    ser.BytesAvailableFcn = {@handle_ser, glb_t};
    fprintf('The client connected...\n');    
    pause(.3);  
    
    ToDoInitialization = receive_msg(ser); % receiving command for whether doing the initialization or not
    if strcmp(ToDoInitialization, 'do_init')        
        ser.BytesAvailableFcn = '';      
		fprintf('Receiving the reference audio, may need a few seconds...\n');		
        y_ref = binblockread(ser, 'double'); % receiving the audio of reference file        
        ser.BytesAvailableFcn = {@handle_ser, glb_t};
        pause(.3);
        Fs = str2double(receive_msg(ser)); % receiving the sample rate
        max_play_count = str2double(receive_msg(ser)); % receiving the max_play_count 
        fprintf('Received information:\n -reference audio length = %.2f sec\n -maximum play count = %d\n', length(y_ref)/Fs, max_play_count-3);      
        
        audio_dev_name = receive_msg(ser); % receiving the playback audio device name        
        if strcmp(audio_dev_name, char(9))
            audio_dev_name = playback_delay_test_dev_name;
        end   
        fprintf(' -playback device name: %s\n', audio_dev_name);
        dev_id = dev_selection(audio_dev_name, ser);
        
        p = audioplayer(y_ref, Fs, 16, dev_id);
        send_msg(ser, player_delay);  % sending the global player delay 
        clear('y_ref');
    end
    
    sil_time = str2double(receive_msg(ser)); % receiving msg silence duration after stop a repeat
    fprintf('Received silence time: %d second.\n', sil_time);
    StartedRecord = receive_msg(ser); % receiving msg start recording    
    if strcmp(StartedRecord, 'start_recording')
        fprintf('Recording started at the client...\n');
    else
        fclose(ser);
        error('Time Out! Cannot connect to client...\n');
    end
    
    pause(1);
    fprintf('Start playing...\n');
    play_cnt = 0;
    p.StartFcn = {@start_play, ser, glb_t};
    p.StopFcn = {@stop_play, ser, glb_t, sil_time};
    fprintf('Repeat done: ');
    play(p);    
   
    while 1
        if strcmp(p.Running, 'off')            
            break;
        end
        pause(.2);
    end
    
    pause(.5);
    fclose(ser);
    fprintf('Closed the client connection...\n');    
end

end

%%
function dev_id = dev_selection(audio_dev_name, ser)

    clear mex;
    dev_info = audiodevinfo;
    dev_info = dev_info.output;
    dev_id = -1;

    for i = 1 : length(dev_info)     
        if ~isempty(strfind(lower(dev_info(i).Name), lower(audio_dev_name)))
            dev_id = dev_info(i).ID;
            dev_name = dev_info(i).Name;
            fprintf('Using audio device: %s\n', dev_name);            
            break;
        end  
    end
    
    if dev_id == -1
        fprintf('\nCannot find the received audio device name...\n');
        dev_msg = ['ID', char(12), 'Name', char(11)];
        dev_id_list = zeros(length(dev_info),1);
        dev_name_list = cell(length(dev_info),1);
        for i = 1: length(dev_info)
            dev_msg = [dev_msg, num2str(dev_info(i).ID), char(12), dev_info(i).Name, char(11)];
            dev_id_list(i) = dev_info(i).ID;
            dev_name_list{i} = dev_info(i).Name;
        end
                
        send_msg(ser, dev_msg);
        pause(.3);
        ans_device = str2double(receive_msg(ser)); % receiving the answer for using default playback
        [~, ans_device] = ismember(ans_device, dev_id_list);
        if ans_device > 0
            dev_id = dev_id_list(ans_device);  
            fprintf('Client specified to use audio device:\n%s\n', dev_name_list{ans_device});
            send_msg(ser, dev_name_list{ans_device});
        else
            send_msg(ser, char(9));
            fclose(ser);
            error('Cannot find the audio device! Terminate this session...\n');
        end         
    else
        send_msg(ser, [char(8), dev_name]);
    end
    
end

%%
function handle_ser(obj, event, glb_t)

timestamp = toc(glb_t);
msg = fgetl(obj);

switch str2double(msg(1))
    
    case 1 % got acknowledgement
        set(obj, 'UserData', msg); 
    
    case 2  % normal data transfer
        set(obj, 'UserData', msg(2:end));   
        
    case 7          
        fprintf('handling binblockread...\n');          
        
    otherwise
        fprintf('Client sent a message not recognized: %.4f at %.4f\n', msg, timestamp);        
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
    fclose(obj);
    error('Time out! Client does not respond...\n');
end

end

%%
function [msg, v] = receive_msg(obj)

msg = [];
v = 0;
for i=1:600    
    pause(0.1);    
    msg = get(obj, 'UserData');
    if ~isempty(msg)
        set(obj, 'UserData', []);
        fprintf(obj, '%s', ['1', char(10)]);
        v = 1;
        break;
    end
end
pause(.2);        
if ~v
    fclose(obj);
    error('Time out! Client does not respond...\n');
end

end

%%
function start_play(obj, event, server, glb_t)

    global play_cnt;
    play_cnt = play_cnt+1;
    fprintf('%d, ', play_cnt);
    timestamp = toc(glb_t);
    send_timestamp(server, timestamp, 1); % sending timestamp to client

end

%%
function stop_play(obj, event, server, glb_t, sil_time)

    pause(sil_time);
    timestamp = toc(glb_t);
    global play_cnt;
    global max_play_count;
    if play_cnt < max_play_count
        play(obj);
        % repeat playing 
    else 
        fprintf('\nStop playing...\n');
        send_timestamp(server, timestamp, 2); % sending timestamp to client saying stop playing
    end

end

%%
function send_timestamp(obj, data, mode)

    data = num2str(data);
    if mode == 1
        data = ['4', data];
    elseif mode == 2
        data = ['5', data];
    else
        data = ['9', data];
    end
    fprintf(obj, '%s', [data, char(10)]);

end

%%
function player_delay = estimate_player_delay(audio_dev_name)

N = 6;
thld = 0.001;
all_dev = audiodevinfo;
input_id = -1;
output_id = -1;
found_playback_delay_test_dev = 0;

for i = 1 : length(all_dev.input)
    if ~isempty(strfind(lower(all_dev.input(i).Name), lower(audio_dev_name)))
        input_id = all_dev.input(i).ID;
        found_playback_delay_test_dev = 1;
        break;
    end
end
for i = 1 : length(all_dev.output)
    if ~isempty(strfind(lower(all_dev.output(i).Name), lower(audio_dev_name)))
        output_id = all_dev.output(i).ID;
        break;
    end
end

if found_playback_delay_test_dev

    if exist('test.wav', 'file')
        [y, Fs] = audioread('test.wav');
    else
        Fs = 48000;
        t = 0: 1/Fs: 1;
        y = 0.1 * sin(2 * pi * 400 * t);
    end
    a = audioplayer(y, Fs, 16, output_id);
    idx = zeros(6,1);

    for i = 1 : N
        r = audiorecorder(Fs, 16, 1, input_id);
        a.StartFcn = {@start_test_rec, r};
        a.StopFcn = {@stop_test_rec, r};
        play(a);
        pause(1);
        stop(a);
        yy = getaudiodata(r);

        idx(i) = find(abs(yy) > thld,1);
        idx(i) = idx(i)/Fs;
    end

    player_delay = mean(idx(2:end));
    fprintf('The estimated player delay is %.4f second.\n', player_delay);    
        
else
    fprintf('Cannot find the audio device for playback delay measurement...\n');
    fprintf('Using the default playback delay 0.2 sec...\n');
    player_delay = 0.2;
end

save('player_delay.mat', 'player_delay');
fprintf('Saved player_delay.mat...\n');
end

%%
function start_test_rec(obj, event, r)
    record(r);
end

%%
function stop_test_rec(obj, event, r)
    stop(r);
end
