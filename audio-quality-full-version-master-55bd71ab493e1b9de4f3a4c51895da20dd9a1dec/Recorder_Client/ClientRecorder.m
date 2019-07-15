function all_complete = ClientRecorder(auto_mode, config_file)

if nargin < 2
    config_file = '_config.txt';
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
    imIP = '10.42.1.1';
    imPort = 11999;
    ref_audio_name = 'speech.wav';
    impair_set_file = 'impairment.txt';
    max_play_count = 6;
    impairment_warmup_time = 10;
    record_device_name = '';
    playback_device_name = '';
    fprintf('Some problems in loading the config file! Using the default...\n');
end

global glb_t; 
global play_time;
global impair_status;

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
    fprintf('Cannot find the audio device name: %s\nID\tName\n', record_device_name);
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

reset_par = 1;
if exist('tmp_variables.mat', 'file')
    if exist('auto_mode', 'var')
        reset_par = 0;
        fprintf('In the auto mode, continuing the last unexpectedly termination...\n');
    else
        startover = input('Detected the last session unexpectedly terminated...\nDo you want to startover (press Enter for yes)?', 's');
        if ~isempty(startover)
            reset_par = 0;       
        end
    end
end

if reset_par
    if ~auto_mode
        proj_name = input('Enter the project name:', 's');
    else
        proj_name = '';
    end
    session = 1;
    score=[];
    figs = [];
    tnow = datestr(now,'dd-mmm-yyyy-HH-MM-SS');
    report_path = ['report-', proj_name, '-', tnow];
    audio_path = ['audio-', proj_name, '-', tnow];
else    
    load('tmp_variables.mat');
end

impair_info = textread(impair_set_file, '%s', 'delimiter', '\n');
max_session_count = length(impair_info);

cl = tcpip(imIP, imPort, 'NetworkRole', 'client');
cl.TimeOut = 30;
cl.BytesAvailableFcnMode = 'terminator';
cl.BytesAvailableFcn = @handle_cl;
cl.UserData = [];

cli = tcpip(IP, Port, 'NetworkRole', 'client');
cli.TimeOut = 30;
cli.BytesAvailableFcnMode = 'terminator';
cli.OutputBufferSize = 20000000;
cli.UserData = [];

DoInitialization = 1;

while 1
    
    fprintf('Opening connection to impair server IP %s, port %d...\n', imIP, imPort);
    impair_status = 1;
    fopen(cl);
    pause(.1);
    fprintf('Impair server is connected...\n');

    send_msg(cl, Port);
    send_msg(cl, impair_info{session});
    warmup_time_extension = str2double(receive_msg(cl));
    warm_up = impairment_warmup_time + warmup_time_extension;
    fprintf('Impairment started with the %d-th parameter set: %s \nImpariment warming up for %d second...\n', session, impair_info{session}, warm_up);
    pause(warm_up);


    fprintf('Opening connection to player server IP %s, port %d...\n', IP, Port);
    pause(.1);
    fopen(cli);
    glb_t = tic;  % start the global timer
    fprintf('Player server is connected...\n');
    pause(.1);

    if DoInitialization
        r = [];
        cli.BytesAvailableFcn = {@handle_cli, glb_t, r};         
        send_msg(cli, 'do_init');  % sending msg do initialization
        [y_ref, Fs] = audioread(ref_audio_name);
        binblockwrite(cli, y_ref, 'double');
        pause(.1);
        send_msg(cli, Fs);        
		player_max_play_count = max_play_count + 3;
        send_msg(cli, player_max_play_count);       
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
            fprintf('\nCannot find the playback device: %s\n%s', playback_device_name, ans_device);
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
        DoInitialization = 0;
    else
        send_msg(cli, 'no');  % sending msg ignore initialization 
    end

    r = audiorecorder(Fs, 16, 1, dev_id);
    cli.BytesAvailableFcn = {@handle_cli, glb_t, r}; 
    impair_par = regexp(impair_info{session}, ' ', 'split');
    if strcmp(impair_par{4}, 'inbound') && strcmp(impair_par{5}, 'TCP') && strcmp(impair_par{1}, 'loss')
		send_msg(cli, 10);
	elseif strcmp(impair_par{5}, 'TCP') && strcmp(impair_par{1}, 'loss') 
        send_msg(cli, 7);
    elseif strcmp(impair_par{1}, 'jitter')
        send_msg(cli, 4);
    else
        send_msg(cli, 2);
    end

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
    
    impair_status = 0;
    while 1
        if strcmp(cl.UserData, 'disconnected')
            break;
        end
        pause(.2);
    end
    set(cl, 'UserData', []);
    fprintf('Impairment with the %d-th parameter set stoped...\n', session);
    fclose(cli);
    pause(.2);
    fclose(cl);       

    fprintf('Obtaining the data...\n');
    rec_time = [rec_time; get(r, 'UserData')];
    y = getaudiodata(r);
    % audiowrite([audio_path, filesep, 's', num2str(session),'_all.wav'], y, Fs);  

    if ~exist(audio_path, 'file')
        mkdir(audio_path);
        mkdir(report_path);
    end

    try
        play_time = play_time(4:end) + player_delay;		
        [SCORE, offset] = segment_wave(y, Fs, rec_time, play_time, ref_audio_name, audio_path, report_path, impair_info{session});
        if SCORE(2,1) > 30
			score = [score; SCORE(:,1)'];   
            fid = fopen([report_path, filesep, 'report_cumulated.txt'], 'w');
            fprintf(fid, '|| Impairment parameter || MOS || Delay ||\n');
			for h = 1: size(score,1)
				fprintf('| %s | %.2f | %d |\n', impair_info{h}, score(h,1), score(h,2));
                fprintf(fid, '| %s | %.2f | %d |\n', impair_info{h}, score(h,1), score(h,2));
			end
			figs = plot_figure_wave(figs, session, max_session_count, y, offset, Fs, SCORE, impair_par, report_path);
            fclose(fid);
		else
			fprintf('This session is problematic...Redoing this session...\n');
			session = session - 1;
		end
    catch exc
        score = [score; [-1, -1]];
        fprintf('%s\n', exc.identifier);
        error('Error in audio segmentation and getting scores...\n');
    end

    if session >= max_session_count
        fprintf('Have completed all the impairment settings! End!\n');
        break;
    end

    session = session + 1; 
    save('tmp_variables', 'proj_name', 'session', 'score', 'figs', 'tnow', 'report_path', 'audio_path');
    fprintf('Starting the next session...\n');
    
end

if exist('tmp_variables.mat', 'file')
    delete('tmp_variables.mat');
end
if exist('figs', 'var')
    if ~isempty(figs)
        ftabs = figs2tabs(figs);
    end
end
all_complete = 1;
end

%%
function handle_cl(obj, event)

global impair_status;
msg = fgetl(obj);
% msg = char(msg(1:end-1)');

switch str2double(msg(1))
    
    case 1 % got acknowledgement
        set(obj, 'UserData', msg);     
    
    case 2  % normal data transfer
        set(obj, 'UserData', msg(2:end));   

    case 3  % respond to check connection
        if impair_status         
            fprintf(obj, '%s', ['32', char(10)]);
        else
            fprintf(obj, '%s', ['31', char(10)]);
            set(obj, 'UserData', 'disconnected');
        end
        
    otherwise
        fprintf('Client sent a message not recognized: %.4f\n', msg);
end 
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
function [SCORE, offset] = segment_wave(y, Fs, rec_time, play_time, ref_file, audio_path, report_path, impair_info)

impair_info = strrep(impair_info, ' ', '-');
offset = play_time - rec_time(1);
  
fid = fopen([report_path, filesep, 'report_', impair_info, '.txt'], 'w');
mos = [];
dly = [];

for i=1: length(play_time)-1
    fprintf('Processing the %d-th clip file...\n', i);
    end_y = round(offset(i+1)*Fs)-1;
    if end_y > length(y)
        y = [y; zeros(end_y - length(y) +1, 1)];
    end
    tmp_y = y(round(offset(i)*Fs)+1 : end_y);
    outfile = [audio_path, filesep, impair_info, '_clip-', num2str(i), '.wav'];
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
end

%%
function figs = plot_figure_wave(figs, session, max_session_count, y, offset, Fs, SCORE, impair_par, report_path)

try
    if mod(session, 5) == 1 || ~ishandle(figs(end))
        figs = [figs, figure];
        set(figs(end), 'Position', [0, 100, 1400, 700]);   
    end
    plot_num = mod(session, 5);
    if plot_num ==0
        plot_num =5;
    end
    subplot(5, 1, plot_num, 'Parent', figs(end));      	
	time_shift = offset(1) - 1;
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
    set(gca,'XTickLabel','');
    ylabel(impair_par, 'FontSize', 10);

    if ~sum(isnan(SCORE))
        title(['MOS: median = ', num2str(SCORE(1,1)), ', avg = ', num2str(SCORE(1,2)),', std = ', num2str(SCORE(1,3)), ...
            ' ; DELAY: median = ', num2str(round(SCORE(2,1))), ', avg = ', num2str(round(SCORE(2,2))), ', std = ', ...
            num2str(round(SCORE(2,3)))]);
    end

    if mod(session, 5) == 0 || session == max_session_count
        print(figs(end), [report_path, filesep, 'waveform_s', num2str(session)], '-dpng', '-r300');
    end
    
catch
    error('Error in printing the figures...\n');
end
end














%%
function varargout = figs2tabs(figHandles)

warning('off','MATLAB:uitabgroup:OldVersion')
if nargin < 1
    error('An array of figure handles must be input')
end

% create figure and tab group
[tabbedFig,tabGroupH] = init_figure;

% create tab for each figure
for tabNum=1:length(figHandles)
   figHandle = figHandles(tabNum);
   add_tab(tabbedFig, tabGroupH, figHandle, tabNum);
end

%set the first tab as active and update to ensure the right guidata, windowsize, etc.
initialize_tab_group(tabbedFig, tabGroupH);

%set output
if nargout == 1
    varargout{1} = tabbedFig;
end

end

function [tabbedFig,tabGroupH] = init_figure
%create tabbed figure
tabbedFig = figure('Name','MATLAB Tabbed GUI', ... %title bar text
    'Tag','tabbedWindow',... 
    'NumberTitle','off', ... %hide figure number in title
    'Menubar','none',... %dont have file menu, etc.
    'IntegerHandle','off',... %use number like 360.0027 instead of 1,2, or 3
    'Resize','on'); %allow user to resize, TODO make contents normalized to allow for proportional resizing


%create a tab group
tabGroupH = uitabgroup;
set(tabGroupH,'SelectionChangeCallback',@update_guidata_and_resize) 
drawnow
end

function initialize_tab_group(tabbedFig, tabGroupH)
%set the first tab as active and update position
curTabNum = 1;
set(tabGroupH,'SelectedIndex',curTabNum)
guiAndTabInfo =  getappdata(tabbedFig,'guiAndTabInfo');
newPos = calcNewPos(curTabNum, guiAndTabInfo);
set(tabbedFig,'Position',newPos)
CenterWindow(tabbedFig)
end


function add_tab(tabbedFig, tabGroupH, figHandle, tabNum)
%get all children a standalone figure
allChildren = get(figHandle,'Children');

%isolate type "uimenu"
%determine types of children
types = get(allChildren,'Type');
types = confirm_cell(types);
uiMenuIndxsBool = cregexp(types,'uimenu');

%add all children except those of type "uimenu"
validChildren = allChildren(~uiMenuIndxsBool);
set(figHandle,'Units','Pixels');
set(validChildren,'Units','Pixels');

% get the handles of the standalone figure
handles = guidata(figHandle);
if isempty(handles)
    handles = 'noguidata';
end

% get name of the standalone figure
figName = get(figHandle,'Name');
if isempty(figName) || strcmp(figName,' ')
    figName = ['tab ' num2str(tabNum)];
end

% create a tab
thisTabH = uitab(tabGroupH, ...
    'Title', figName, ...
    'UserData',tabNum, ...
    'Tag',get(figHandle,'Tag'), ... %make the original tabbedFig's tag this tab's tag
    'DeleteFcn',get(figHandle,'DeleteFcn'));%make the original tabbedFig's DeleteFcn this tab's DeleteFcn

% collect handles and tab info to tabbed gui's appdata 
guiAndTabInfo =  getappdata(gcf,'guiAndTabInfo');
guiAndTabInfo(tabNum).handles = handles;
guiAndTabInfo(tabNum).tabHandles = thisTabH;
%remember the size of the original GUI and resize the tabbed GUI to this
%when tab is switched
guiAndTabInfo(tabNum).position =  get(figHandle,'Position');

%store info
setappdata(tabbedFig,'guiAndTabInfo', guiAndTabInfo);

% move objects from standalone figure to tab
set(validChildren,'Parent',thisTabH);

% close standalone figure since it has been "gutted" and placed onto a tab
delete(figHandle);
end

function update_guidata_and_resize(varargin)

if length(varargin) < 2
    return
end

% tabGroupH = varargin{1};
event_data = varargin{2};
if strcmp(event_data.EventName,'SelectionChange')
    curTabNum = get(event_data.NewValue,'UserData');
else
    return
end

guiAndTabInfo = getappdata(gcf,'guiAndTabInfo');
if isempty(guiAndTabInfo)
    return
end

%get handles of the children in the current tab
handles = guiAndTabInfo(curTabNum).handles;

%update gui data with the handles of the children in the current tab
if ~isempty(handles)
    guidata(gcf, handles);
end

newPos = calcNewPos(curTabNum, guiAndTabInfo);
set(gcf,'Position',newPos)

%force redraw
pause(0.01)
drawnow
end

function newPos = calcNewPos(curTabNum, guiAndTabInfo)
%update the size of the window to match the contents of the tab
%get position of gui when it opened as a standalone
figOrigPos = guiAndTabInfo(curTabNum).position;
newWidth = figOrigPos(3);
newHeight = 30 + figOrigPos(4); %assume tab is 30px tall

%ensure common units
set(gcf,'Units','Pixels');

%get current position
curFigPos = get(gcf,'Position');
curBottom = curFigPos(2);
curHeight = curFigPos(4);

% calculate new size
newBottom = curBottom + (curHeight-newHeight); %keep top left in place
newPos = [curFigPos(1), newBottom, newWidth, newHeight ];
end


function outCell = confirm_cell(inArg)
if ~iscell(inArg)
    outCell = {inArg};
else
    outCell = inArg;
end
end

function bool=cregexp(cellStrArray,pat)
%returns boolean array true at indices where pat is found in cellStrArray
cellStrArray = confirm_cell(cellStrArray);
bool = ~cellfun(@isempty,regexp(cellStrArray,pat));

end

function CenterWindow(hForeground, hBackground)
% centers gui with hForeground over gui hBackground
% hBackground is optional. If it's not included, hForeground is
% centered on the screen.
if nargin ==1
    %Center GUI Window
	origUnits = get(hForeground,'Units');
    set(hForeground,'Units','pixels');
    
    %get display size
    screenSize = get(0, 'ScreenSize');
    
    %calculate the center of the display
    newPos = get(hForeground, 'Position');
    newPos(1) = (screenSize(3)-newPos(3))/2;
    newPos(2) = (screenSize(4)-newPos(4))/2;
    
    %set new position of window
    set(hForeground, 'Position', newPos );
    set(hForeground,'Units',origUnits);
elseif nargin == 2
    % center hForeground over hBackground
	origUnitsF = get(hForeground,'Units');
	origUnitsB = get(hBackground,'Units');
    set(hForeground,'Units','pixels');
    set(hBackground,'Units','pixels');
    
    parentPos = get(hBackground, 'Position');
    
    %calculate the center of the parent, then offset by half the size of
    %hObject
    %     [left, bottom, width, height]
    parentCenter = [parentPos(1)+ parentPos(3)/2, parentPos(2)+ parentPos(4)/2];
    curPos = get(hForeground, 'Position');
    newPos(1) = parentCenter(1)- curPos(3)/2;
    newPos(2) = parentCenter(2)- curPos(4)/2;
    newPos(3) = curPos(3);
    newPos(4) = curPos(4);

    %set new position of foreground window
    set(hForeground, 'Position', newPos );
    
    set(hForeground,'Units',origUnitsF);
    set(hBackground,'Units',origUnitsB);
end
end