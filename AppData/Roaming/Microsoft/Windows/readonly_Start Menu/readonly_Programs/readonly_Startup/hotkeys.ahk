#Requires AutoHotkey v2.0
#SingleInstance Force
; https://github.com/regulad/hotkeys

; Get primary monitor information
PrimaryMonitorIndex := MonitorGetPrimary()

; Create an array to store the GUI windows
overlay_windows := []

; Hotkey to toggle overlay (Ctrl+Alt+B for "Blinders")
^!b::ToggleOverlay

ToggleOverlay() {
    global overlay_windows, PrimaryMonitorInfo
    
    if (overlay_windows.Length = 0) {
        ; Create overlays
        loop MonitorGetCount() {
            current_monitor := MonitorGetWorkArea(A_Index, &current_left, &current_top, &current_right, &current_bottom)
            
            ; Check if this monitor is not the primary monitor
            if (current_monitor != PrimaryMonitorIndex) {
                width := current_right - current_left
                height := current_bottom - current_top
                
                new_overlay := Gui()
                new_overlay.Opt("+AlwaysOnTop -Caption +ToolWindow")
                new_overlay.BackColor := "Black"
                new_overlay.Show(Format("x{} y{} w{} h{}", current_left, current_top, width, height))
                
                overlay_windows.Push(new_overlay)
            }
        }
    } else {
        ; Remove overlays
        for window in overlay_windows {
            window.Destroy()
        }
        overlay_windows := []
    }
}

; Hotkey to toggle the touchscreen (Ctrl+Alt+V), e.g. while cleaning the screen
^!v::ToggleTouchscreen

; Disabling a device needs admin, so each toggle is one UAC prompt; reading its
; state through WMI does not. The device is matched by its HID usage (Digitizer
; page 0x0D, Touch Screen usage 0x04), which leaves the pen collection alone.
; A disabled touchscreen stays disabled across reboots until toggled back.
ToggleTouchscreen() {
    static touchscreen_id := "HID_DEVICE_UP:000D_U:0004"

    state := TouchscreenState(touchscreen_id)
    if (state = "missing") {
        TrayTip("No touchscreen found", , "Mute")
        return
    }

    verb := (state = "enabled") ? "disable" : "enable"
    try {
        exit_code := RunWait(Format('*RunAs pnputil.exe /{}-device /deviceid "{}"', verb, touchscreen_id), , "Hide")
    } catch {
        return  ; UAC prompt declined
    }

    new_state := TouchscreenState(touchscreen_id)
    if (new_state = state)
        TrayTip(Format("Touchscreen still {} (pnputil exited {})", state, exit_code), , "Iconx Mute")
    else
        TrayTip("Touchscreen " . new_state, , "Mute")
}

; "enabled" if any matching device is not disabled, "disabled" if all are,
; "missing" if there are none
TouchscreenState(hardware_id) {
    found := false
    for device in ComObjGet("winmgmts:").ExecQuery("SELECT HardwareID, ConfigManagerErrorCode FROM Win32_PnPEntity WHERE PNPClass = 'HIDClass'") {
        device_ids := device.HardwareID
        if !IsObject(device_ids)
            continue
        for device_id in device_ids {
            if (device_id = hardware_id) {
                if (device.ConfigManagerErrorCode != 22)  ; CM_PROB_DISABLED
                    return "enabled"
                found := true
            }
        }
    }
    return found ? "disabled" : "missing"
}

#!T:: Run("wt.exe")  ; Launch Windows Terminal with Win+Alt+T
#`::  ; Quake Mode
{
    userProfile := EnvGet("USERPROFILE")
    if WinExist("quake ahk_exe WindowsTerminal.exe")
        Run("wt.exe -w _quake focus-tab")
    else
        Run("wt.exe -w _quake new-tab --profile `"quake`" --startingDirectory `"" . userProfile . "`"")
}

^!s:: Send("{U+2245}") ; Send Congruent

^!a:: Send("{U+2220}") ; Send Angle

^!r:: Send("{U+221F}") ; Send Right Angle

^!d:: Send("{U+2221}") ; Send Measured Angle

^!<:: Send("{U+2264}") ; Send Less than or equal to

^!>:: Send("{U+2265}") ; Send greater than or equal to

^!0:: Send("{U+00B1}") ; send plus/minus

^!t:: Send("{U+25B3}") ; send triangle

^!Left:: Send("{U+2190}") ; send left arrow

^!Up:: Send("{U+2191}") ; send up arrow

^!Right:: Send("{U+2192}") ; send right arrow

^!Down:: Send("{U+2193}") ; send down arrow

!+e:: Send("{U+00C8}") ; upper grave e

!e:: Send("{U+00E8}") ; grave e

^!+e:: Send("{U+00C9}") ; upper acute e

^!e:: Send("{U+00E9}") ; acute e
