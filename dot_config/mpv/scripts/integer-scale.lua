local function check_integer_scale()
    local vw = mp.get_property_number("video-params/w")
    local vh = mp.get_property_number("video-params/h")
    local dw = mp.get_property_number("display-width")
    local dh = mp.get_property_number("display-height")

    if not (vw and vh and dw and dh) then return end

    -- Compute the actual rendered video dimensions, respecting aspect ratio
    -- Video fills display width; height is constrained by the video's DAR
    local video_aspect = vw / vh
    local display_aspect = dw / dh

    local rendered_w, rendered_h
    if display_aspect >= video_aspect then
        -- Display is wider than video: video fills height, pillarboxed
        rendered_h = dh
        rendered_w = math.floor(dh * video_aspect + 0.5)
    else
        -- Display is taller/narrower than video: video fills width, letterboxed
        rendered_w = dw
        rendered_h = math.floor(dw / video_aspect + 0.5)
    end

    -- Integer scale iff the rendered dimension is an exact multiple of the source
    local scale_w = rendered_w / vw
    local scale_h = rendered_h / vh

    -- Allow a small tolerance for rounding (sub-pixel display alignment)
    local is_integer = math.abs(scale_w - math.floor(scale_w + 0.5)) < 0.02
                   and math.abs(scale_h - math.floor(scale_h + 0.5)) < 0.02
                   and math.abs(scale_w - scale_h) < 0.02  -- uniform scale

    if is_integer then
        mp.set_property("scale",            "nearest")
        mp.set_property("cscale",           "nearest")
        mp.set_property("dscale",           "nearest")
        mp.set_property("scale-antiring",   "0")
        mp.set_property("sigmoid-upscaling","no")
        mp.msg.info(string.format(
            "Integer scale x%.0f (%dx%d → %dx%d), nearest neighbor enabled",
            math.floor(scale_w + 0.5), vw, vh, rendered_w, rendered_h))
    else
        mp.set_property("scale",            "lanczos")
        mp.set_property("cscale",           "lanczos")
        mp.set_property("sigmoid-upscaling","yes")
        mp.msg.info(string.format(
            "Non-integer scale (%.3fx), lanczos enabled", scale_w))
    end
end

mp.observe_property("video-params/w", "number", check_integer_scale)
mp.observe_property("display-width",  "number", check_integer_scale)
mp.observe_property("display-height", "number", check_integer_scale)
