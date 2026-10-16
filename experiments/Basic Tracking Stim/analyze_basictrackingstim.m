function expmt = analyze_basictrackingstim(expmt,varargin)
%
% Analysis for basic tracking with a global ON/OFF light stimulus.
% Computes each fly's mean speed (mm/s) during stimulus ON and OFF
% frames, stores it on expmt.data.speed (mean_ON, mean_OFF), and saves a
% paired ON vs OFF figure. The plotSpeed*.m scripts in 'analysis and
% plots' also work directly on this experiment's .mat file.
%
% Run from the margo GUI: autoDataProcess reads options.bouts, which is
% only set when analysis options come from the GUI.

% Parse inputs, read data from hard disk, format in master struct, process centroid data
[expmt,options] = autoDataProcess(expmt,varargin{:});

%% Mean speed during stimulus ON vs OFF

speed      = double(expmt.data.speed.raw());       % [nFrames x nFlies] mm/s
stimStatus = logical(expmt.data.StimStatus.raw()); % [nFrames x nFlies]
speed(~isfinite(speed)) = NaN;

nFlies   = size(speed, 2);
mean_ON  = NaN(nFlies, 1);
mean_OFF = NaN(nFlies, 1);

for i = 1:nFlies
    on_i = stimStatus(:, i);
    mean_ON(i)  = mean(speed(on_i, i),  'omitnan');
    mean_OFF(i) = mean(speed(~on_i, i), 'omitnan');
end

addprops(expmt.data.speed, {'mean_ON'; 'mean_OFF'});
expmt.data.speed.mean_ON  = mean_ON;
expmt.data.speed.mean_OFF = mean_OFF;

clear speed stimStatus

%% Paired ON vs OFF figure

f = figure();
hold on;
plot([1 2], [mean_OFF mean_ON]', '-', 'Color', [0.7 0.7 0.7]);
plot([1 2], [mean(mean_OFF, 'omitnan') mean(mean_ON, 'omitnan')], ...
    'k-o', 'LineWidth', 2, 'MarkerFaceColor', 'k');

set(gca, 'Xtick', [1 2], 'XtickLabel', {'OFF', 'ON'});
xlim([0.5 2.5]);
ylabel('Mean speed (mm/s)');
title(sprintf('Speed during stimulus OFF vs ON (n=%d)', ...
    sum(isfinite(mean_ON) & isfinite(mean_OFF))));

fname = [expmt.meta.path.fig expmt.meta.date '_speed_on_off'];
if ~isempty(expmt.meta.path.fig) && options.save
    savefig(f, fname);
    close(f);
end

% Clean up files and wrap up analysis
autoFinishAnalysis(expmt,options);
