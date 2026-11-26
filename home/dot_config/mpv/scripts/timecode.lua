local function smpte_timecode()
    local time_pos = mp.get_property_number("time-pos")
    local fps = mp.get_property_number("estimated-vf-fps") or mp.get_property_number("fps")
    if not time_pos or not fps or fps <= 0 then
        return "--:--:--:~--"
    end

    local total_seconds = math.floor(time_pos)
    local hh = math.floor(total_seconds / 3600)
    local mm = math.floor((total_seconds % 3600) / 60)
    local ss = total_seconds % 60
    local ff = math.floor((time_pos - total_seconds) * fps + 0.5)
    if ff >= math.floor(fps) then ff = math.floor(fps) - 1 end -- rounding guard

    return string.format("%02d:%02d:%02d:%02d", hh, mm, ss, ff)
end

local function padded_frame_number()
    local frame_num = mp.get_property_number("estimated-frame-number")
    local frame_count = mp.get_property_number("estimated-frame-count")
    if not frame_num or not frame_count then
        return "-/-"
    end

    local width = #tostring(frame_count)
    return string.format("%0" .. width .. "d/%d", frame_num, frame_count)
end

local function update_user_data()
    mp.set_property_native("user-data/frame-padded", padded_frame_number())
    mp.set_property_native("user-data/timecode-approx", smpte_timecode())
end

mp.add_periodic_timer(0.1, update_user_data)
