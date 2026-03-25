function expmt = analyze_ymaze_stim(expmt, varargin)
%
% Analysis for y-maze with optional light-on information (stimulus).
% Now supports:
%   - StimStatus: pulse-level ON/OFF (per frame)
%   - BlockStatus: 5-min ON/OFF blocks (per frame)
%

%% Parse inputs, read data from hard disk, format in master struct, process centroid data

[expmt, options] = autoDataProcess(expmt, varargin{:});

clearvars -except expmt trackProps options

turns = expmt.data.Turns.raw();

% Optional: stimulus status (pulse-level, may be absent in older experiments)
if isfield(expmt.data, 'StimStatus')
    stimStatus = expmt.data.StimStatus.raw();   % same shape as turns/time
else
    stimStatus = [];
end

% Optional: block-level status (5-min ON/OFF, may be absent in older experiments)
if isfield(expmt.data, 'BlockStatus')
    blockStatus = expmt.data.BlockStatus.raw(); % same shape as turns/time
else
    blockStatus = [];
end

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
         'active'; 'lightOn'; 'blockOn'; ...
         'rBias_ON_block'; 'rBias_OFF_block'; ...
         'n_ON_block'; 'n_OFF_block'};
addprops(expmt.data.Turns, props);

expmt.data.Turns.n = sum(turns ~= 0) - 1;
maxN = max(expmt.data.Turns.n);

expmt.data.Turns.t        = NaN(maxN, expmt.meta.num_traces);
expmt.data.Turns.sequence = NaN(maxN, expmt.meta.num_traces);
expmt.data.Turns.lightOn  = NaN(maxN, expmt.meta.num_traces);   % pulse-level
expmt.data.Turns.blockOn  = NaN(maxN, expmt.meta.num_traces);   % 5-min block-level

% cumulative experiment time
tElapsed = cumsum(expmt.data.time.raw());

for i = 1:expmt.meta.num_traces
    
    % indices of turn frames for this fly
    idx = turns(:, i) ~= 0;
    nTurns_i = sum(idx);
    
    % time stamps of each turn
    expmt.data.Turns.t(1:nTurns_i, i) = tElapsed(idx);
    
    % pulse-level light state at each turn, if available
    if ~isempty(stimStatus)
        expmt.data.Turns.lightOn(1:nTurns_i, i) = stimStatus(idx, i);
    end
    
    % block-level state at each turn, if available
    if ~isempty(blockStatus)
        expmt.data.Turns.blockOn(1:nTurns_i, i) = blockStatus(idx, i);
    end
    
    % calculate turn sequence (right = 1, left = 0)
    tSeq = turns(idx, i);
    tSeq = diff(tSeq);
    if expmt.meta.roi.orientation(i)
        expmt.data.Turns.sequence(1:length(tSeq), i) = (tSeq == 1 | tSeq == -2);
    else
        expmt.data.Turns.sequence(1:length(tSeq), i) = (tSeq == -1 | tSeq == 2);
    end
    
end

% Right turn probability (overall, across all blocks)
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

%% Block-based ON / OFF right-turn bias (5-min ON vs 5-min OFF)

seq   = expmt.data.Turns.sequence;  % per-turn transitions (right=1, left=0)
block = expmt.data.Turns.blockOn;   % per-turn block state (1=ON block, 0=OFF block)
[maxN, nFlies] = size(seq);

% Map blockOn per turn to blockOn per transition (k->k+1) using second turn's block
blockOn_seq = NaN(maxN, nFlies);

for i = 1:nFlies
    
    % Find non-NaN turns for this fly
    idx_turn = ~isnan(block(:, i));
    B = block(idx_turn, i);          % block state at each turn
    nTurns_i = numel(B);
    
    % Sequence entries for this fly
    nSeq_i = sum(~isnan(seq(:, i)));
    
    if nTurns_i >= 2 && nSeq_i > 0
        % sequence(k) corresponds to transition from turn k -> k+1
        % define block state from the *second* turn in each pair: B(2:end)
        nUse = min(nSeq_i, nTurns_i - 1);
        blockOn_seq(1:nUse, i) = B(2:nUse+1);
    end
end

valid      = ~isnan(seq) & ~isnan(blockOn_seq);
isOnBlock  = (blockOn_seq == 1) & valid;
isOffBlock = (blockOn_seq == 0) & valid;

rBias_ON_block  = NaN(1, nFlies);
rBias_OFF_block = NaN(1, nFlies);
n_ON_block      = zeros(1, nFlies);
n_OFF_block     = zeros(1, nFlies);

for i = 1:nFlies
    
    on_i  = isOnBlock(:,  i);
    off_i = isOffBlock(:, i);
    
    n_ON_block(i)  = sum(on_i);
    n_OFF_block(i) = sum(off_i);
    
    if n_ON_block(i) > 0
        rBias_ON_block(i)  = sum(seq(on_i,  i)) / n_ON_block(i);
    end
    if n_OFF_block(i) > 0
        rBias_OFF_block(i) = sum(seq(off_i, i)) / n_OFF_block(i);
    end
end

expmt.data.Turns.rBias_ON_block  = rBias_ON_block';
expmt.data.Turns.rBias_OFF_block = rBias_OFF_block';
expmt.data.Turns.n_ON_block      = n_ON_block';
expmt.data.Turns.n_OFF_block     = n_OFF_block';

%% Generate plots (unchanged overall rBias histogram)

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