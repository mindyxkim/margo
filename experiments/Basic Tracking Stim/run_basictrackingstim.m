function expmt = run_basictrackingstim(expmt,gui_handles,varargin)
%
% Basic tracking with a global light stimulus. Records each fly's
% centroid and speed (mm/s) while a projector drives the whole tray
% with a steady light: 5 min ON / 5 min OFF, repeating, ON first.
% StimStatus records whether the light was ON on each frame.


% Initialization: Get handles and set default preferences
gui_notify(['executing ' mfilename '.m'], gui_handles.disp_note);

% get image handle
imh = findobj(gui_handles.axes_handle, '-depth', 3, 'Type', 'image');

% raw data fields to save each frame (append names of custom fields to
% flag fields for writing to disk)
trackDat.fields = {'centroid'; 'time'; 'speed'; 'StimStatus'};

% initialize labels, files, and cam/video
[trackDat, expmt] = autoInitialize(trackDat, expmt, gui_handles);

% lastFrame = false until last frame of the last video file is reached
trackDat.lastFrame = false;

%% Initialize the psychtoolbox window and projector

bg_color = [0 0 0];    % background black
expmt = initialize_projector(expmt, bg_color);
pause(3);

set(gui_handles.display_menu.Children, 'Checked', 'off')
set(gui_handles.display_menu.Children, 'Enable', 'on')
gui_handles.display_none_menu.Checked = 'on';
gui_handles.display_menu.UserData = 5;

% Get full projector window rect for global stimulus
win = expmt.hardware.screen.window;
full_rect = Screen('Rect', win);   % [x1 y1 x2 y2] in projector coordinates

% Define stim struct
stim.bg_color    = bg_color;
stim.fg_color    = [1 1 1];  % max white

% 5 min ON, 5 min OFF (in seconds), starting with ON
stim.on_dur      = 5 * 60;
stim.off_dur     = 5 * 60;

% One global rectangle covering the entire projector window
stim.global_rect = full_rect;      % drive whole tray

expmt.meta.stim = stim;

% Initialize status (one row per tracked fly)
trackDat.StimStatus = false(size(trackDat.centroid, 1), 1);


% Tracking Loop - Run until duration is exceeded or last frame is reached
while ~trackDat.lastFrame
    
    % update time stamps and frame rate
    [trackDat] = autoTime(trackDat, expmt, gui_handles);

    % query next frame and optionally correct lens distortion
    [trackDat,expmt] = autoFrame(trackDat, expmt,gui_handles);

    % track, sort to ROIs, evaluate noise level, output optional fields
    trackDat = autoTrack(trackDat, expmt, gui_handles);
    
    % update projector stimulus and StimStatus
    [trackDat, expmt] = update_basictrackingstim(trackDat, expmt);

    % output data tracked fields to binary files
    [trackDat,expmt] = autoWriteData(trackDat, expmt, gui_handles);

    % update ref at the reference frequency or reset if noise thresh is exceeded
    [trackDat, expmt] = autoReference(trackDat, expmt, gui_handles);  

    % update current image and display object positions 
    [trackDat, expmt] = autoDisplay(trackDat, expmt, imh, gui_handles);
    
    
end
