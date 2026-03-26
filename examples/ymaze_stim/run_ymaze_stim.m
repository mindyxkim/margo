function expmt = run_ymaze_stim(expmt, gui_handles, varargin)

%% Parse variable inputs

for i = 1:length(varargin)
    
    arg = varargin{i};
    
    if ischar(arg)
        switch arg
            case 'Trackdat'
                i = i + 1;
                trackDat = varargin{i};     % manually pass in trackDat rather than initializing
        end
    end
end

%% Initialization: Get handles and set default preferences

gui_notify(['executing ' mfilename '.m'], gui_handles.disp_note);

% clear memory
clearvars -except gui_handles expmt trackDat

% get image handle
imh = findobj(gui_handles.axes_handle, '-depth', 3, 'Type', 'image');

%% Experimental Setup

% Initialize tracking variables
trackDat.fields = {'centroid'; 'time'; 'Turns'; 'StimStatus'}; % properties of the tracked objects to be recorded

% initialize labels, files, and cam/video
[trackDat, expmt] = autoInitialize(trackDat, expmt, gui_handles);

% lastFrame = false until last frame of the last video file is reached
trackDat.lastFrame = false;

%% Y-maze specific parameters

% Calculate coordinates of end of each maze arm
trackDat.arm = zeros(expmt.meta.roi.n, 2, 6);
w = expmt.meta.roi.bounds(:, 3);   % width of each ROI
h = expmt.meta.roi.bounds(:, 4);   % height of each ROI

% Offsets to shift arm coords in from edge of ROI bounding box
xShift = w .* 0.15;
yShift = h .* 0.15;

% Coords 1-3 are for upside-down Ys
trackDat.arm(:, :, 1) = ...
    [expmt.meta.roi.corners(:, 1) + xShift, expmt.meta.roi.corners(:, 4) - yShift];
trackDat.arm(:, :, 2) = ...
    [expmt.meta.roi.centers(:, 1),           expmt.meta.roi.corners(:, 2) + yShift];
trackDat.arm(:, :, 3) = ...
    [expmt.meta.roi.corners(:, 3) - xShift, expmt.meta.roi.corners(:, 4) - yShift];

% Coords 4-6 are for right-side up Ys
trackDat.arm(:, :, 4) = ...
    [expmt.meta.roi.corners(:, 1) + xShift, expmt.meta.roi.corners(:, 2) + yShift];
trackDat.arm(:, :, 5) = ...
    [expmt.meta.roi.centers(:, 1),          expmt.meta.roi.corners(:, 4) - yShift];
trackDat.arm(:, :, 6) = ...
    [expmt.meta.roi.corners(:, 3) - xShift, expmt.meta.roi.corners(:, 2) + yShift];

% time stamp of last scored turn for each object
trackDat.turntStamp = zeros(expmt.meta.roi.n, 1);
trackDat.prev_arm    = zeros(expmt.meta.roi.n, 1);

% calculate arm threshold as fraction of width and height
expmt.parameters.arm_thresh = mean([w h], 2) .* 0.2;
nTurns = zeros(size(expmt.meta.roi.centers, 1), 1);

%% Initialize the psychtoolbox window and projector for Y-maze stimulation

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
stim.fg_color    = [255 255 255];    % white in 0–255 PTB range

% 5 min ON, 5 min OFF (in seconds)
stim.on_dur      = 5 * 60;
stim.off_dur     = 5 * 60;

% 30 Hz pulse, 50% duty cycle (1 frame ON / 1 frame OFF at 60 fps)
stim.pulse_period = 1/30;

stim.pulse_ct = 0;                    % frame counter for 30 Hz pulsing
stim.t0 = GetSecs;                   % time-zero for cycle

% One global rectangle covering the entire projector window
stim.global_rect = full_rect;        % drive whole tray

expmt.meta.stim = stim;

% Initialize status
trackDat.StimStatus = false(expmt.meta.roi.n, 1);

%% Main Experimental Loop

while ~trackDat.lastFrame
    
    % update time stamps and frame rate
    [trackDat] = autoTime(trackDat, expmt, gui_handles);

    % query next frame and optionally correct lens distortion
    [trackDat, expmt] = autoFrame(trackDat, expmt, gui_handles);

    % track, sort to ROIs, and output optional fields to sorted fields
    trackDat = autoTrack(trackDat, expmt, gui_handles);

    % update projector stimulus and StimStatus
    [trackDat, expmt] = update_ymaze_stim(trackDat, expmt);

    % Determine if fly has changed to a new arm
    trackDat = detectArmChange(trackDat, expmt);

    % Create placeholder for arm change vector to write to file
    trackDat.Turns = int8(zeros(expmt.meta.roi.n, 1));
    trackDat.Turns(trackDat.changed_arm) = ...
        trackDat.prev_arm(trackDat.changed_arm);
    nTurns(trackDat.changed_arm) = nTurns(trackDat.changed_arm) + 1;

    % output data to binary files
    [trackDat, expmt] = autoWriteData(trackDat, expmt, gui_handles);

    % update ref at the reference frequency or reset if noise thresh is exceeded
    [trackDat, expmt] = autoReference(trackDat, expmt, gui_handles);  
    
    % update the display
    trackDat = autoDisplay(trackDat, expmt, imh, gui_handles);
end

end