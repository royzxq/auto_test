function StartClientRecorder(config_file)
warning('off','all');
clear mex;

if nargin < 1
    config_file = 'config_temp';
end


try
    cmds = textread(config_file, '%s', 'delimiter', '\n');
    for i=1:length(cmds)
        eval(cmds{i});
    end
    clear('cmds');
catch
    % default setting
    IP = '10.42.0.2';
    Port = 12999;
    ref_audio_name = 'speech.wav';
    max_play_count = 6;
    sil_duration_between_playbacks = 2;
    record_device_name = '';
    playback_device_name = '';    
    fprintf('Some problems in loading the config file! Using the default...\n');
end

global glb_t; 
global play_time;

if ispc
    default_device_name = 'VB-Audio';
else
    default_device_name = 'Sound Siphon';
end

if isempty(record_device_name)
    record_device_name = default_device_name;
end

dev_info = audiodevinfo;
dev_info = dev_info.input;
dev_id = -1;

for i = 1 : length(dev_info)
    if ~isempty(strfind(lower(dev_info(i).Name), lower(record_device_name)))
        dev_id = dev_info(i).ID;
        fprintf('\nUsing audio device: %s\n', dev_info(i).Name);
        break;
    end  
end

if dev_id == -1
    dev_id_list = [];
    fprintf('Cannot find the audio device name...\nID\tName\n');
    for i = 1: length(dev_info)
        fprintf('%d\t%s\n', dev_info(i).ID, dev_info(i).Name);
        dev_id_list = [dev_id_list, dev_info(i).ID];
    end
    ans_device = input('Input the ID of an available device above:', 's');
    dev_id = str2double(ans_device);
    if ~ismember(dev_id, dev_id_list)
        error('Invalid device ID! Please change the recording device name...\n');
    end
end  

tnow = datestr(now,'dd-mmm-yyyy-HH-MM-SS');
report_path = ['report-', tnow];
audio_path = ['audio-', tnow];

cli = tcpip(IP, Port, 'NetworkRole', 'client');
cli.TimeOut = 30;
cli.BytesAvailableFcnMode = 'terminator';
cli.OutputBufferSize = 20000000;
cli.UserData = [];

[y_ref, Fs] = audioread(ref_audio_name);
r = audiorecorder(Fs, 16, 1, dev_id);

fprintf('Opening connection to player server IP %s, port %d...\n', IP, Port);
pause(.1);
try
    fopen(cli);
    glb_t = tic;  % start the global timer
    fprintf('Player server is connected...\n');
catch
    error('Cannot open connection because the server is not ready...\n');
end
    
pause(.1);
cli.BytesAvailableFcn = {@handle_cli, glb_t, r};        
send_msg(cli, 'do_init');  % sending msg do initialization    
binblockwrite(cli, y_ref, 'double');
pause(.1);
send_msg(cli, Fs);        
send_msg(cli, max_play_count);
send_msg(cli, sil_duration_between_playbacks);
if isempty(playback_device_name)
    send_msg(cli, char(9));
else
    send_msg(cli, playback_device_name);
end

pause(.3);
ans_device = receive_msg(cli); % receiving the response whether found the device
if ~strcmp(ans_device(1), char(8))
    ans_device = regexprep(ans_device, char(12), '\t');
    ans_device = regexprep(ans_device, char(11), '\n');
    fprintf('\nCannot find the playback device at the server side...\n%s', ans_device);
    ans_device = input('Input the ID of an available device above:', 's');
    send_msg(cli, ans_device);
    pause(.1);
    ans_device = receive_msg(cli);
    if strcmp(ans_device, char(9))
        fclose(cli);
        error('Cannot find the device name! Terminate this session...\n');
    else
        fprintf('Using playback audio device: %s\n', ans_device);
    end
else
    fprintf('Using playback audio device: %s\n', ans_device(2:end));
end

player_delay = str2double(receive_msg(cli)); % receiving the global player delay
fprintf('Received the global player delay = %.4f sec...\n', player_delay);
clear('y_ref');

pause(.1);
send_msg(cli, 'start_recording');  
fprintf('Start recording...\n');

play_time = [];
r.StartFcn = {@start_record, glb_t};
r.StopFcn = {@stop_record, glb_t};
record(r);  
pause(.2);
rec_time = get(r, 'UserData');

while 1
    if strcmp(r.Running, 'off') 
        break;
    else
        pause(.5);
    end
end
    
fclose(cli);
fprintf('Obtaining the data...\n');
rec_time = [rec_time; get(r, 'UserData')];
y = getaudiodata(r);    

if ~exist(audio_path, 'file')
    mkdir(audio_path);
    mkdir(report_path);
end

play_time = play_time + player_delay;
[SCORE, offset] = segment_wave(y, Fs, rec_time, play_time, ref_audio_name, audio_path, report_path);      
plot_figure_wave(y, offset, Fs, SCORE);

clear('cli');
clear('r');
end

%%
function handle_cli(obj, event, glb_t, r)

timestamp = toc(glb_t);
global play_time;
msg = fgetl(obj);

switch str2double(msg(1))
    
    case 1 % got acknowledgement
        set(obj, 'UserData', msg);     
    
    case 2  % normal data transfer
        set(obj, 'UserData', msg(2:end));   
        
    case 3  % Internet delay measruement purpose     
        set(obj, 'UserData', timestamp);
        
    case 4  % received a play
        ser_timestamp = str2double(msg(2:end));   
        if ser_timestamp > timestamp
            play_time = [play_time; timestamp - 0.1];
        else
            play_time = [play_time; ser_timestamp];
        end
        fprintf('Received server time: %.4f, at local %.4f sec\n', ser_timestamp, timestamp);

    case 5  % stop recording
        ser_timestamp = str2double(msg(2:end));
        if ser_timestamp > timestamp
            play_time = [play_time; timestamp - 0.1];
        else
            play_time = [play_time; ser_timestamp];
        end
        fprintf('Received server time: %.4f, at local %.4f sec\n', ser_timestamp, timestamp);
        pause(.8);
        stop(r);       
        
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
    error('Time out! Server does not respond...\n');
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
    fclose(obj);
    error('Time out! Server does not respond...\n');
end
end

%%
function start_record(obj, event, glb_t)

timestamp = toc(glb_t);

set(obj, 'UserData', timestamp);
fprintf('Recording started at %.4f....\n', timestamp); 

end

%%
function stop_record(obj, event, glb_t)

timestamp = toc(glb_t);
set(obj, 'UserData', timestamp);
fprintf('Stop Recording at %.4f...\n', timestamp);

end

%%
function [SCORE, offset] = segment_wave(y, Fs, rec_time, play_time, ref_file, audio_path, report_path)
figure('Visible','off');
offset = play_time - rec_time(1);
mos = [];
dly = [];

fid = fopen([report_path, filesep, 'report.txt'], 'w');

for i=1: length(play_time)-1
    fprintf('Processing the %d-th clip file...\n', i);
    end_y = round(offset(i+1)*Fs)-1;
    if end_y > length(y)
        y = [y; zeros(end_y - length(y) +1, 1)];
    end
    tmp_y = y(round(offset(i)*Fs)+1 : end_y);
    outfile = [audio_path, filesep, 'clip-', num2str(i), '.wav'];
    audiowrite(outfile, tmp_y, Fs);    
    
	% fprintf('Acquiring "%s" scores from POLQA...\n', [impair_info, '_clip-', num2str(i), '.wav']);
    [s, ~] = system(['curl -F uploaded=@"', outfile, '" -F reference=@', ref_file, ' http://polqa1.eng.webex.com/polqa/upload_2.php?params=SWB > _tmp.txt']);
    tt = textread('_tmp.txt', '%s');
    delete('_tmp.txt');
    
    if ~isempty(tt)
        score_text = ['clip-', num2str(i), '.wav: MOS=', tt{2}, ', Delay=', tt{5}];
        mos = [mos; str2double(tt{2})]; 
        dly = [dly; str2double(tt{5}(1:end-2))]; 
    else
        score_text = ['clip-', num2str(i), '.wav: Scores are missing...'];        
    end
    
    fprintf(fid, '%s\n', score_text);
    plot_wave_segment(tmp_y, Fs, i, score_text, report_path);
end

if ~isempty(mos) && ~isempty(dly)

    SCORE(1,1) = median(mos);
    SCORE(1,2) = mean(mos);
    SCORE(1,3) = std(mos);
    SCORE(1,4) = max(mos);
    SCORE(1,5) = min(mos);
    SCORE(2,1) = round(median(dly));
    SCORE(2,2) = round(mean(dly));
    SCORE(2,3) = round(std(dly));
    SCORE(2,4) = round(max(dly));
    SCORE(2,5) = round(min(dly));

    fprintf(fid, 'MOS: med = %.2f, avg = %.2f, std = %.2f, max = %.2f, min = %.2f\n', SCORE(1,1), SCORE(1,2), SCORE(1,3), SCORE(1,4), SCORE(1,5));
    fprintf(fid, 'DELAY: med = %d, avg = %d, std = %d, max = %d, min = %d\n', SCORE(2,1), SCORE(2,2), SCORE(2,3), SCORE(2,4), SCORE(2,5));
else
    fprintf(fid, 'Cannot get the scores!\n');
    SCORE = [NaN; NaN];
end

fclose(fid);
close all;
end

%%
function plot_figure_wave(y, offset, Fs, SCORE)

fig = figure('Visible','on');
set(fig, 'Position', [0, 500, 1400, 200]);   
	
time_shift = offset(1) - 1;
if time_shift < 0
    time_shift = 0;
end
y = y(round(time_shift*Fs)+1:end);
offset = offset - time_shift;

hold on;
t = 1:length(y);
t = t/Fs;
plot(t, y);
offset = [offset, offset];
for i=1:size(offset,1)
    plot(offset(i,:), [.8, -.8], 'LineWidth', 1, 'Color', [1 0 0]);
end

xlim([0, max(t)]);
ylim([-1, 1]);
xlabel('Time in Second', 'FontSize', 10);
ylabel('Amplitude', 'FontSize', 10);

if ~sum(isnan(SCORE))
    mos_text = ['MOS: median = ', num2str(SCORE(1,1)), ', avg = ', num2str(SCORE(1,2)),', std = ', num2str(SCORE(1,3)), '; '];
    dly_text = ['DELAY: median = ', num2str(round(SCORE(2,1))), ', avg = ', num2str(round(SCORE(2,2))), ', std = ', num2str(round(SCORE(2,3)))];
    title([mos_text, dly_text]);
    fprintf('%s\n%s\n', mos_text, dly_text);
end
end

%%
function plot_wave_segment(y, Fs, i, score_text, report_path)

fig = figure;
hold on;

t = 1:length(y);
t = t/Fs;
subplot(2,1,1);
plot(t, y);

xlim([0, max(t)]);
ylim([-.8, .8]);
xlabel('Time in Second', 'FontSize', 10);
ylabel('Amplitude', 'FontSize', 10);
title(score_text);

set(fig,'PaperUnits','inches');
set(fig,'PaperPosition',[1 1 13 5]);
set(fig,'PaperPositionMode','manual');
% print(gcf,'-dpng','-r300',[report_path, filesep, 'Waveform_Clip', num2str(i)]);

subplot(2,1,2);
spectrogram(y, Fs*0.05, 0, [], Fs, 'yaxis');
if strcmp(version, '8.1.0.604 (R2013a)')
    ylim([0 10000]);
else
    ylim([0 10])
    colormap(fig,'jet');
    colorbar('off');
end
print(gcf,'-dpng','-r300',[report_path, filesep, 'Watch_Clip', num2str(i)]);

close gcf;

end