function img = projector_flatfield_image(cal, rect)
% PROJECTOR_FLATFIELD_IMAGE  Image that evens out the projector's brightness.
%
%   img = projector_flatfield_image(cal, rect) returns a uint8 image the
%   size of rect ([x1 y1 x2 y2], projector pixels) from a calibration made
%   by calibrate_projector_flatfield. Draw it as a texture in place of a
%   full-white fill. Pixel values already include the gamma correction.

W = rect(3) - rect(1);
H = rect(4) - rect(2);
[u, v] = meshgrid(((1:W) - 0.5) / W, ((1:H) - 0.5) / H);

gain = interp2(cal.map_u, cal.map_v, cal.gain, u, v, 'linear');
img  = uint8(round(255 * gain .^ (1 / cal.gamma)));

end
