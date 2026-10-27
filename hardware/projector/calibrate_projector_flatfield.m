function cal = calibrate_projector_flatfield(varargin)
% CALIBRATE_PROJECTOR_FLATFIELD  Measure the projector's brightness gradient
% with a light meter and save a flat-field correction.
%
%   cal = calibrate_projector_flatfield()
%   cal = calibrate_projector_flatfield('Grid',[5 5],'Margin',0.1)
%
% Run from the MATLAB command window with the arena in place and every
% other light source off (IR and white panels, room lights). The projector
% shows a cross at each measurement point: place the light meter's sensor
% on the cross, press Enter, and type the reading once the screen changes.
% Readings can be in any unit that is linear in light (lux, uW/cm^2,
% photodiode volts); only their ratios are used.
%
% Steps:
%   1. Gamma: readings at the centre at input levels 0, .25, .5, .75 and 1.
%      The level-0 reading (projector black level + ambient light) is
%      subtracted from every other reading.
%   2. Grid: one full-white reading at each grid point.
%   3. Fit a smooth surface to the grid readings and compute the gain that
%      brings every point down to the dimmest part of the measured area.
%      A projector can only be dimmed, so the corrected intensity everywhere
%      equals that of the dimmest area.
%   4. Optional: re-measure the grid with the correction applied.
%
% The result is saved to hardware/projector_fit/projector_flatfield.mat,
% where run_basictrackingstim loads it. projector_flatfield_image turns it
% into the image drawn during stimulus ON.
%
% Options:
%   'Screen'  PTB screen number (default: the projector screen in margo's
%             registration settings if the margo GUI is open, otherwise
%             the highest screen number)
%   'Grid'    [nx ny] number of measurement points (default [5 5])
%   'Margin'  fraction of the window left unmeasured at each edge
%             (default 0.1); set it so the grid covers the arena
%   'Model'   'quadratic' (default) or 'plane' fit a smooth surface;
%             'interp' interpolates the readings directly, for gradients
%             with a hot spot the quadratic can't follow
%   'Gamma'   skip the gamma measurement and use this value

%% Parse inputs

screen_num = [];
grid_n     = [5 5];
margin     = 0.1;
model      = 'quadratic';
gamma      = [];

for i = 1:2:numel(varargin)
    switch lower(varargin{i})
        case 'screen'
            screen_num = varargin{i+1};
        case 'grid'
            grid_n = varargin{i+1};
        case 'margin'
            margin = varargin{i+1};
        case 'model'
            model = lower(varargin{i+1});
        case 'gamma'
            gamma = varargin{i+1};
        otherwise
            error('Unknown option ''%s''.', varargin{i});
    end
end

% check options now rather than after all the readings are taken
if ~any(strcmp(model, {'quadratic', 'plane', 'interp'}))
    error('Unknown model ''%s''.', model);
end
if numel(grid_n) ~= 2 || any(grid_n < 2)
    error('Grid must be [nx ny] with at least 2 points in each direction.');
end
if isempty(which('margo'))
    error('margo is not on the MATLAB path.');
end
save_dir  = fullfile(fileparts(fileparts(which('margo'))), ...
    'hardware', 'projector_fit');
save_path = fullfile(save_dir, 'projector_flatfield.mat');

%% Open the projector window (same settings as initialize_projector)

% close any PTB window left open (margo leaves the projector window open
% after experiments and registration)
sca;
PsychDefaultSetup(2);
Screen('Preference', 'SkipSyncTests', 1);
screen_src = '''Screen'' option';
if isempty(screen_num)
    [screen_num, screen_src] = projectorScreen();
end

try
    [win, rect] = PsychImaging('OpenWindow', screen_num, 0);
    HideCursor(screen_num);
    W = rect(3);
    H = rect(4);
    fprintf('Projector window on screen %d (%d x %d px), from %s\n', ...
        screen_num, W, H, screen_src);
    fprintf('Available screens: %s\n', mat2str(Screen('Screens')));

    %% 1. Gamma and dark level at the centre

    levels   = [0 0.25 0.5 0.75 1];
    lv_read  = [];
    center   = [W H] / 2;

    showMarker(win, center);
    input('Centre: place the sensor on the cross, then press Enter ', 's');

    if isempty(gamma)
        lv_read = zeros(size(levels));
        for k = 1:numel(levels)
            showLevel(win, levels(k));
            lv_read(k) = readNumber( ...
                sprintf('  reading at input level %.2f: ', levels(k)));
        end
        dark = lv_read(1);
        n = (lv_read(2:end-1) - dark) / (lv_read(end) - dark);
        if any(n <= 0) || lv_read(end) <= dark
            error(['Readings do not increase with input level; ' ...
                'check the sensor position and that other lights are off.']);
        end
        % least-squares fit of n = level^gamma
        x = log(levels(2:end-1));
        gamma = sum(x .* log(n)) / sum(x .^ 2);
        fprintf('  gamma = %.2f\n', gamma);
        if gamma < 1 || gamma > 3.5
            warning('Gamma %.2f is unusual; check the readings.', gamma);
        end
    else
        showLevel(win, 0);
        dark = readNumber('  reading with the projector black: ');
    end

    %% 2. Full-white reading at each grid point

    [GU, GV] = meshgrid(linspace(margin, 1 - margin, grid_n(1)), ...
                        linspace(margin, 1 - margin, grid_n(2)));
    u = GU(:);
    v = GV(:);
    npts = numel(u);

    reading = zeros(npts, 1);
    for k = 1:npts
        showMarker(win, [u(k) * W, v(k) * H]);
        input(sprintf(['Point %d/%d: place the sensor on the cross, ' ...
            'then press Enter '], k, npts), 's');
        showLevel(win, 1);
        reading(k) = readNumber('  reading at full white: ');
    end

    P = reading - dark;
    if any(P <= 0)
        error('Some readings are at or below the dark reading.');
    end

    %% 3. Fit a smooth surface and compute the gain map

    % evaluate on a coarse map; clamp to the measured area so the fit is
    % never extrapolated past the grid
    box = [min(u) max(u) min(v) max(v)];
    map_u = linspace(0, 1, 101);
    map_v = linspace(0, 1, 101);
    [MU, MV] = meshgrid(map_u, map_v);
    MU = clamp(MU, box(1), box(2));
    MV = clamp(MV, box(3), box(4));

    if strcmp(model, 'interp')
        % pass through every reading; follows hot spots a surface can't,
        % but also passes meter noise through
        coef = [];
        fitP = P;
        S = interp2(GU(1,:), GV(:,1), reshape(P, size(GU)), MU, MV, 'linear');
    else
        A = designMatrix(u, v, model);
        if size(A, 2) > npts
            error('Grid has too few points for the ''%s'' model.', model);
        end
        coef = A \ P;
        fitP = A * coef;
        S = reshape(designMatrix(MU(:), MV(:), model) * coef, size(MU));
    end

    target = min(S(:));
    if target <= 0
        error(['Fitted intensity reaches zero; check the readings or ' ...
            'use ''Model'',''plane''.']);
    end

    cal.date          = datestr(now);
    cal.screen_num    = screen_num;
    cal.window_rect   = rect;
    cal.model         = model;
    cal.points_uv     = [u v];
    cal.reading       = reading;
    cal.dark          = dark;
    cal.levels        = levels;
    cal.level_reading = lv_read;
    cal.gamma         = gamma;
    cal.coef          = coef;
    cal.fit_rms_pct   = 100 * sqrt(mean((P - fitP) .^ 2)) / mean(P);
    cal.target        = target;
    cal.map_u         = map_u;
    cal.map_v         = map_v;
    cal.gain          = target ./ S;     % light-output gain, 1 = full white

    if ~exist(save_dir, 'dir')
        mkdir(save_dir);
    end
    save(save_path, 'cal');

    fprintf('\nUniformity before (min/max): %.2f\n', min(P) / max(P));
    if ~strcmp(model, 'interp')
        fprintf('Predicted after  (min/max): %.2f\n', ...
            min(P .* target ./ fitP) / max(P .* target ./ fitP));
        fprintf('Surface fit error: %.1f%% RMS\n', cal.fit_rms_pct);
    end
    fprintf(['Corrected ON intensity: %.0f%% of the uncorrected mean ' ...
        '(%.3g after dark subtraction)\n'], 100 * target / mean(P), target);
    fprintf('Saved %s\n', save_path);

    %% 4. Optional check with the correction applied

    answer = input('\nRe-measure the grid with the correction applied? y/n [y]: ', 's');
    if ~strcmpi(strtrim(answer), 'n')
        tex = Screen('MakeTexture', win, projector_flatfield_image(cal, rect));
        verify = zeros(npts, 1);
        for k = 1:npts
            showMarker(win, [u(k) * W, v(k) * H]);
            input(sprintf(['Point %d/%d: place the sensor on the cross, ' ...
                'then press Enter '], k, npts), 's');
            Screen('DrawTexture', win, tex);
            Screen('Flip', win);
            verify(k) = readNumber('  reading with correction: ');
        end
        cal.verify_reading = verify;
        save(save_path, 'cal');
        fprintf('Measured after   (min/max): %.2f\n', ...
            min(verify - dark) / max(verify - dark));
    end

catch err
    sca;
    ShowCursor;
    rethrow(err);
end

sca;
ShowCursor;

%% Summary figure: pixel value drawn during ON

figure();
imagesc(map_u * W, map_v * H, cal.gain .^ (1 / gamma), [0 1]);
axis image;
colormap(gray);
colorbar;
hold on;
plot(u * W, v * H, 'r+', 'MarkerSize', 10, 'LineWidth', 1.5);
xlabel('Projector x (px)');
ylabel('Projector y (px)');
title('Flat-field ON image (1 = full white), + = measured points');

end


function [s, src] = projectorScreen()
% the projector screen set in margo's registration settings when the margo
% GUI is open, otherwise the highest screen number (usually the projector)
s   = max(Screen('Screens'));
src = 'highest screen number (margo GUI not open)';
fig = findall(0, 'Tag', 'gui_fig');
if isempty(fig)
    return
end
try
    expmt = getappdata(fig(1), 'expmt');
    s   = expmt.hardware.projector.reg_params.screen_num;
    src = 'margo projector settings';
catch
    src = 'highest screen number (no projector settings in margo)';
end
end


function showMarker(win, xy)
% black screen with a white cross centred on xy; drawn as two filled
% rectangles because some drivers reject DrawLines wider than 1 px
len = 40;
th  = 3;
bars = [xy(1)-len  xy(1)-th;
        xy(2)-th   xy(2)-len;
        xy(1)+len  xy(1)+th;
        xy(2)+th   xy(2)+len];
Screen('FillRect', win, 0);
Screen('FillRect', win, 1, bars);
Screen('Flip', win);
end


function showLevel(win, level)
% fill the whole window with one input level
Screen('FillRect', win, level);
Screen('Flip', win);
end


function x = readNumber(prompt)
% prompt until a finite number is entered
x = NaN;
while ~isfinite(x)
    x = str2double(input(prompt, 's'));
end
end


function A = designMatrix(u, v, model)
switch model
    case 'plane'
        A = [ones(size(u)) u v];
    case 'quadratic'
        A = [ones(size(u)) u v u.^2 u.*v v.^2];
    otherwise
        error('Unknown model ''%s''.', model);
end
end


function x = clamp(x, lo, hi)
x = min(max(x, lo), hi);
end
