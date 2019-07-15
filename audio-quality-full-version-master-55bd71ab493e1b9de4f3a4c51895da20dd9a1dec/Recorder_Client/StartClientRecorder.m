function StartClientRecorder(config_file)
warning('off', 'all');
clear mex;

auto_mode = 1;
all_complete = 0;

while ~all_complete
    try
        if nargin < 1
            all_complete = ClientRecorder(auto_mode);
        else
            all_complete = ClientRecorder(auto_mode, config_file);
        end
    catch exc
        fprintf('%s\n', exc.identifier);
        if exist('cl', 'var')
            fclose(cl);
        end
        if exist('cli', 'var')
            fclose(cli);
        end
    end
end