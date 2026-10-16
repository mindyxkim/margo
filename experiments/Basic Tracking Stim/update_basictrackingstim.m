function [trackDat, expmt] = update_basictrackingstim(trackDat, expmt)
% Drives a global rectangular stimulus covering the whole tray.
% Block structure: on_dur ON / off_dur OFF (repeating), starting with ON.
% The light is held steady for the whole ON block.
% StimStatus: true on frames where the light is ON.

    stim  = expmt.meta.stim;

    % --- determine block state ---
    cycle_T    = stim.on_dur + stim.off_dur;
    t_in_cycle = mod(trackDat.t, cycle_T);
    stim_on    = t_in_cycle < stim.on_dur;

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

    % --- update status (one row per tracked fly) ---
    trackDat.StimStatus = repmat(stim_on, size(trackDat.centroid, 1), 1);

end
