function [trackDat, expmt] = update_ymaze_stim(trackDat, expmt)
% Drives a global rectangular stimulus covering all Y-mazes.
% Block structure: 5 min ON / 5 min OFF (repeating).
% Within ON blocks: the light is held steady ON.
% StimStatus: true on frames where the light is physically ON.

    stim  = expmt.meta.stim;
    nROIs = expmt.meta.roi.n;

    % --- determine block state (5 min ON / 5 min OFF) ---
    cycle_T     = stim.on_dur + stim.off_dur;
    t_in_cycle  = mod(trackDat.t, cycle_T);
    in_on_block = t_in_cycle < stim.on_dur;

    stim_on = in_on_block;

    % --- draw stimulus ---
    if stim_on
        Screen('FillRect', expmt.hardware.screen.window, ...
            stim.fg_color, stim.global_rect);
    else
        Screen('FillRect', expmt.hardware.screen.window, ...
            stim.bg_color);
    end

    expmt.hardware.screen.vbl = ...
        Screen('Flip', expmt.hardware.screen.window, ...
            expmt.hardware.screen.vbl + ...
            (expmt.hardware.screen.waitframes - 0.5) * ...
            expmt.hardware.screen.ifi);

    % --- update status ---
    trackDat.StimStatus = repmat(stim_on, nROIs, 1);
    expmt.meta.stim = stim;

end
