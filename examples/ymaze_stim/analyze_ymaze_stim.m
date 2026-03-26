function expmt = analyze_ymaze_stim(expmt, varargin)
%
% Analysis for y-maze with light stimulus.
% Derives ON-stim vs OFF-stim periods from turn timestamps and the
% stim timing parameters stored in expmt.meta.stim (on_dur, off_dur).
% StimStatus (pulse-level ON/OFF per frame) is recorded per turn when
% available.
%

%% Parse inputs, read data from hard disk, format in master struct, process centroid data

[expmt, options] = autoDataProcess(expmt, varargin{:});

clearvars -except expmt trackProps options

turns = expmt.data.Turns.raw();

% Pulse-level stimulus status (per frame)
stimStatus = expmt.data.StimStatus.raw();

% Remove first turn for each fly
turn_idx = turns ~= 0;
turn_idx = num2cell(turn_idx, 1);
first_turn_row = cellfun(@(t) find(t, 1, 'first'), ...
    turn_idx, 'UniformOutput', false);
first_turn_col = find(~cellfun(@isempty, first_turn_row))';
first_turn_row = cat(1, first_turn_row{:});
first_turn_idx = sub2ind(size(turns), first_turn_row, first_turn_col);
turns(first_turn_idx) = 0;
turn_idx = cat(2, turn_idx{:});
clear first_turn_col first_turn_idx first_turn_row

%% Calculate turn probability and related metrics

props = {'n'; 't'; 'sequence'; 'switchiness'; 'clumpiness'; 'rBias'; ...
         'active'; 'lightOn'; ...
         'rBias_ON_stim'; 'rBias_OFF_stim'; ...
         'n_ON_stim'; 'n_OFF_stim'};
addprops(expmt.data.Turns, props);

expmt.data.Turns.n = sum(turns ~= 0) - 1;
maxN = max(expmt.data.Turns.n);

expmt.data.Turns.t        = NaN(maxN, expmt.meta.num_traces);
expmt.data.Turns.sequence = NaN(maxN, expmt.meta.num_traces);
expmt.data.Turns.lightOn  = NaN(maxN, expmt.meta.num_traces);   % pulse-level

% cumulative experiment time
tElapsed = cumsum(expmt.data.time.raw());

for i = 1:expmt.meta.num_traces

    % indices of turn frames for this fly
    idx = turns(:, i) ~= 0;
    nTurns_i = sum(idx);

    % time stamps of each turn
    expmt.data.Turns.t(1:nTurns_i, i) = tElapsed(idx);

    % pulse-level light state at each turn
    expmt.data.Turns.lightOn(1:nTurns_i, i) = stimStatus(idx, i);

    % calculate turn sequence (right = 1, left = 0)
    tSeq = turns(idx, i);
    tSeq = diff(tSeq);
    if expmt.meta.roi.orientation(i)
        expmt.data.Turns.sequence(1:length(tSeq), i) = (tSeq == 1 | tSeq == -2);
    else
        expmt.data.Turns.sequence(1:length(tSeq), i) = (tSeq == -1 | tSeq == 2);
    end

end

% Right turn probability (overall)
expmt.data.Turns.n = sum(~isnan(expmt.data.Turns.sequence), 'omitnan');
expmt.data.Turns.rBias = ...
    sum(expmt.data.Turns.sequence, 'omitnan') ./ expmt.data.Turns.n;

% Clumpiness and switchiness
expmt.data.Turns.switchiness = NaN(expmt.meta.num_traces, 1);
expmt.data.Turns.clumpiness  = NaN(expmt.meta.num_traces, 1);

for i = 1:expmt.meta.num_traces

    idx = ~isnan(expmt.data.Turns.sequence(:, i));
    s = expmt.data.Turns.sequence(idx, i);
    r = expmt.data.Turns.rBias(i);
    n = expmt.data.Turns.n(i);
    t = expmt.data.Turns.t(idx, i);
    iti = (t(2:end) - t(1:end-1));

    expmt.data.Turns.switchiness(i) = ...
        sum((s(1:end-1) + s(2:end)) == 1) / (2 * r * (1 - r) * n);
    expmt.data.Turns.clumpiness(i) = ...
        std(iti) / mean(iti);

end

expmt.data.Turns.active = expmt.data.Turns.n > 39;

if isfield(options, 'handles')
    gui_notify('processing complete', options.handles.disp_note)
end

clearvars -except expmt options
disp("Try saving as csv")

%% ON-stim vs OFF-stim right-turn bias
%  Derive stim state from turn timestamps using stim timing parameters

seq    = expmt.data.Turns.sequence;
turnT  = expmt.data.Turns.t;
[maxN, nFlies] = size(seq);

% Stim cycle parameters
on_dur  = expmt.meta.stim.on_dur;
off_dur = expmt.meta.stim.off_dur;
cycle_T = on_dur + off_dur;

% For each turn transition (k -> k+1), determine stim state from
% the timestamp of the second turn
stimState_seq = NaN(maxN, nFlies);

for i = 1:nFlies

    idx_valid = ~isnan(turnT(:, i));
    T = turnT(idx_valid, i);
    nTurns_i = numel(T);
    nSeq_i   = sum(~isnan(seq(:, i)));

    if nTurns_i >= 2 && nSeq_i > 0
        % sequence(k) = transition from turn k to turn k+1
        % assign stim state from the second turn's timestamp
        nUse = min(nSeq_i, nTurns_i - 1);
        t_second = T(2:nUse+1);
        stimState_seq(1:nUse, i) = mod(t_second, cycle_T) < on_dur;
    end
end

valid      = ~isnan(seq) & ~isnan(stimState_seq);
isON_stim  = (stimState_seq == 1) & valid;
isOFF_stim = (stimState_seq == 0) & valid;

rBias_ON_stim  = NaN(1, nFlies);
rBias_OFF_stim = NaN(1, nFlies);
n_ON_stim      = zeros(1, nFlies);
n_OFF_stim     = zeros(1, nFlies);

for i = 1:nFlies

    on_i  = isON_stim(:, i);
    off_i = isOFF_stim(:, i);

    n_ON_stim(i)  = sum(on_i);
    n_OFF_stim(i) = sum(off_i);

    if n_ON_stim(i) > 0
        rBias_ON_stim(i)  = sum(seq(on_i, i)) / n_ON_stim(i);
    end
    if n_OFF_stim(i) > 0
        rBias_OFF_stim(i) = sum(seq(off_i, i)) / n_OFF_stim(i);
    end
end

expmt.data.Turns.rBias_ON_stim  = rBias_ON_stim';
expmt.data.Turns.rBias_OFF_stim = rBias_OFF_stim';
expmt.data.Turns.n_ON_stim      = n_ON_stim';
expmt.data.Turns.n_OFF_stim     = n_OFF_stim';

%% Generate plots

inc  = 0.05;
bins = -inc/2:inc:1+inc/2;

mask = expmt.data.Turns.n > 40;
c = histcounts(expmt.data.Turns.rBias(mask), bins);
c = c ./ (sum(c, 'omitnan'));
c(end) = [];

f = figure();
plot(c, 'Linewidth', 2);

set(gca, 'Xtick', (1:2:length(c)), 'XtickLabel', 0:inc*2:1);
axis([1 length(bins)-1 0 max(c)+0.05]);
xlabel('Right Turn Probability');
title('Y-maze Handedness Histogram');

if isfield(expmt, 'Strain')
    strain = expmt.meta.strain;
else
    strain = '';
end
if isfield(expmt, 'Treatment')
    treatment = expmt.meta.treatment;
else
    treatment = '';
end

legendLabel(1) = { [strain ' ' treatment ...
    ' (u=' num2str(mean(expmt.data.Turns.rBias(mask)), 2) ...
    ', n=' num2str(sum(mask)) ')'] };
legend(legendLabel);

fname = [expmt.meta.path.fig expmt.meta.date '_hist_handedness'];
if ~isempty(expmt.meta.path.fig) && options.save
    hgsave(f, fname);
    close(f);
end

ymazetocsv(expmt);
clearvars -except expmt options

%% Clean up files and wrap up analysis

autoFinishAnalysis(expmt, options);

end
