local ffi = require 'ffi'
local pui = require 'gamesense/pui'
local vector = require 'vector'
local base64 = require 'gamesense/base64'
local msgpack = require 'gamesense/msgpack'
local clipboard = require 'gamesense/clipboard'
local json = require 'gamesense/json'

-- Registration system
local user_registered = false
local user_nickname = ""
local registration_file = "aimplay_user.txt"

-- Load saved nickname
local function load_nickname()
    local success, content = pcall(readfile, registration_file)
    if success and content then
        user_nickname = content
        if user_nickname ~= "" then
            user_registered = true
        end
    end
end

-- Save nickname
local function save_nickname(nickname)
    local success = pcall(writefile, registration_file, nickname)
    if success then
        user_nickname = nickname
        user_registered = true
    end
end

-- Load nickname on script start
load_nickname()

-- Print welcome message if already registered
if user_registered then
    client.delay_call(0.1, function()
        client.color_log(255, 255, 255, "Welcome back ")
        client.color_log(173, 255, 47, user_nickname)
    end)
end

-- References
local reference = {
    double_tap = {ui.reference('RAGE', 'Aimbot', 'Double tap')},
    duck_peek_assist = ui.reference('RAGE', 'Other', 'Duck peek assist'),
    pitch = {ui.reference('AA', 'Anti-aimbot angles', 'Pitch')},
    yaw_base = ui.reference('AA', 'Anti-aimbot angles', 'Yaw base'),
    yaw = {ui.reference('AA', 'Anti-aimbot angles', 'Yaw')},
    yaw_jitter = {ui.reference('AA', 'Anti-aimbot angles', 'Yaw jitter')},
    body_yaw = {ui.reference('AA', 'Anti-aimbot angles', 'Body yaw')},
    freestanding_body_yaw = ui.reference('AA', 'anti-aimbot angles', 'Freestanding body yaw'),
    edge_yaw = ui.reference('AA', 'Anti-aimbot angles', 'Edge yaw'),
    freestanding = {ui.reference('AA', 'Anti-aimbot angles', 'Freestanding')},
    roll = ui.reference('AA', 'Anti-aimbot angles', 'Roll'),
    on_shot_anti_aim = {ui.reference('AA', 'Other', 'On shot anti-aim')},
    slow_motion = {ui.reference('AA', 'Other', 'Slow motion')},
    aa_enabled = ui.reference('AA', 'Anti-aimbot angles', 'Enabled'),
    leg_movement = ui.reference('AA', 'Other', 'Leg movement'),
    damage_override = {ui.reference('RAGE', 'Aimbot', 'Minimum damage override')},
    damage = {ui.reference('RAGE', 'Aimbot', 'Minimum damage')},
    -- AA Other tab elements
    other_on_shot = {ui.reference('AA', 'Other', 'On shot anti-aim')},
    other_slow_motion = {ui.reference('AA', 'Other', 'Slow motion')},
    other_leg_movement = ui.reference('AA', 'Other', 'Leg movement'),
    other_duck_peek = ui.reference('RAGE', 'Other', 'Duck peek assist'),
    other_fake_peek = {ui.reference('AA', 'Other', 'Fake peek')},
    -- Fake lag references
    fake_lag_enabled = ui.reference('AA', 'Fake lag', 'Enabled'),
    fake_lag_amount = ui.reference('AA', 'Fake lag', 'Amount'),
    fake_lag_variance = ui.reference('AA', 'Fake lag', 'Variance'),
    fake_lag_limit = ui.reference('AA', 'Fake lag', 'Limit')
}

-- Helper function to get PUI element values (works like ui.get but for PUI elements)
local function pui_get(element)
    if type(element) == "table" and element.get then
        return element:get()
    else
        return ui.get(element)
    end
end

-- Helper function to set PUI element values
local function pui_set(element, value)
    if type(element) == "table" and element.set then
        element:set(value)
    else
        ui.set(element, value)
    end
end

-- Helper function to set PUI element visibility
local function pui_set_visible(element, visible)
    if type(element) == "table" and element.set_visible then
        element:set_visible(visible)
    else
        ui.set_visible(element, visible)
    end
end

-- Variables
local last_press = 0
local direction = 0
local anti_aim_on_use_direction = 0
local cheked_ticks = 0
local delayed_jitter = false
local is_defensive_active = false
local last_random_yaw = 0
local defensive_start_tick = 0
local last_defensive_state = false
local random_yaw_update_tick = 0
local defensive_pitch_jitter = false
local defensive_yaw_jitter = false
local last_spin_angle = 0
local spin_tick_offset = 0
local last_delay_value = 2
local delay_tick_counter = 0
local delay_last_switch_tick = 0
local current_delay_target = 2

-- Statistics variables
local stats = {
    kills = 0,
    deaths = 0,
    misses = 0,
    start_time = globals.realtime(),
    total_playtime = 0  -- Общее накопленное время
}

local stats_file = "aimplay_stats.txt"

-- Load saved statistics
local function load_stats()
    local success, content = pcall(readfile, stats_file)
    if success and content then
        local data = {}
        for line in content:gmatch("[^\r\n]+") do
            local key, value = line:match("([^:]+):([^:]+)")
            if key and value then
                data[key] = tonumber(value) or 0
            end
        end
        if data.kills then stats.kills = data.kills end
        if data.deaths then stats.deaths = data.deaths end
        if data.misses then stats.misses = data.misses end
        if data.playtime then stats.total_playtime = data.playtime end
    end
    stats.start_time = globals.realtime()
end

-- Save statistics
local function save_stats()
    local current_session = globals.realtime() - stats.start_time
    local total = stats.total_playtime + current_session
    local content = string.format("kills:%d\ndeaths:%d\nmisses:%d\nplaytime:%.2f", 
        stats.kills, stats.deaths, stats.misses, total)
    pcall(writefile, stats_file, content)
end

-- Load stats on script start
load_stats()

-- Variable for periodic save
local last_save_time = globals.realtime()

-- Helper functions
local function contains(tbl, value)
    if type(tbl) ~= "table" then
        return false
    end
    for i = 1, #tbl do
        if tbl[i] == value then
            return true
        end
    end
    return false
end

-- Helpers table for config system
local helpers = {}
helpers['functions'] = {
    contains = function(self, inputString)
        if type(inputString) == "string" then
            if string.find(inputString, "%s") ~= nil and string.find(inputString, "%S") ~= nil then
                local hasSpace = string.find(inputString, "%s") ~= nil
                local hasCharacters = string.find(inputString, "%S") ~= nil
                return hasSpace and hasCharacters
            elseif string.find(inputString, "%s") == nil and string.find(inputString, "%S") ~= nil then
                return true
            else
                return false
            end
        else
            return false
        end
    end
}

local function is_defensive(index)
    cheked_ticks = math.max(entity.get_prop(index, 'm_nTickBase'), cheked_ticks or 0)
    return math.abs(entity.get_prop(index, 'm_nTickBase') - cheked_ticks) > 2 and math.abs(entity.get_prop(index, 'm_nTickBase') - cheked_ticks) < 14
end

-- Settings
local settings = {}
local anti_aim_settings = {}
local anti_aim_states = {'Global', 'Standing', 'Moving', 'Slow motion', 'Crouching', 'Crouching & moving', 'In air', 'In air & crouching', 'No exploits', 'On use'}
local anti_aim_different = {'', ' ', '  ', '   ', '    ', '     ', '      ', '       ', '        ', '         '}

-- Create PUI groups for proper PUI support
local pui_group_aa = pui.group('AA', 'Anti-aimbot angles')
local pui_group_other = pui.group('AA', 'Other')
local pui_group_fakelag = pui.group('AA', 'Fake lag')

-- Tabs
local fake_lag_ref = ui.reference('AA', 'Fake lag', 'Enabled')
local fake_lag_group = pui.group('AA', 'Fake lag')

-- Registration UI
settings.reg_animated = ui.new_label('AA', 'Fake lag', '\aADFF2FFFA I M P L A Y')
settings.reg_welcome = ui.new_label('AA', 'Fake lag', '\aFFFFFFFFWelcome! Please register to continue')
settings.reg_nickname = ui.new_textbox('AA', 'Fake lag', '\aFFFFFFFFYour Nickname')
settings.reg_button = ui.new_button('AA', 'Fake lag', '\aADFF2FFFRegister', function()
    local nickname = ui.get(settings.reg_nickname)
    if nickname ~= "" and #nickname >= 3 then
        save_nickname(nickname)
        -- Print welcome message to console
        client.exec("clear")
        client.color_log(255, 255, 255, "Welcome back ")
        client.color_log(173, 255, 47, nickname)
        client.delay_call(0.1, function()
            client.reload_active_scripts()
        end)
    else
        client.error_log("Nickname must be at least 3 characters long")
    end
end)

settings.animated_label = ui.new_label('AA', 'Fake lag', '\aADFF2FFFA I M P L A Y')
settings.label_color1 = ui.new_color_picker('AA', 'Fake lag', '\aFFFFFFFFLabel color 1', 255, 255, 255, 255)
settings.label_color2 = ui.new_color_picker('AA', 'Fake lag', '\aFFFFFFFFLabel color 2', 173, 255, 47, 255)

settings.tab_selection = ui.new_combobox('AA', 'Fake lag', 'Tabs', ' Information', ' Anti-Aim', ' Ragebot', ' Visual', ' Misc', ' Configuration')
settings.separator_line = ui.new_label('AA', 'Fake lag', '━━━━━━━━━━━━━━━━━━━━━━━━━')
settings.antiaim_subtab = ui.new_combobox('AA', 'Fake lag', '\n', ' Builder', ' Other')
settings.visual_subtab = ui.new_combobox('AA', 'Fake lag', '\n ', ' Main', ' World')
settings.misc_subtab = ui.new_combobox('AA', 'Fake lag', '\n  ', ' Main', ' Exploit')

-- Tab breadcrumb (in Anti-aimbot angles section, always visible first)
settings.breadcrumb = ui.new_label('AA', 'Anti-aimbot angles', '\aFFFFFFFFBreadcrumb')
settings.breadcrumb_line = ui.new_label('AA', 'Anti-aimbot angles', '\aFFFFFFFF━━━━━━━━━━━━━━━━━━━━━━━━━')

-- Information tab
settings.info_welcome = ui.new_label('AA', 'Anti-aimbot angles', '\aFFFFFFFFWelcome back!')
settings.info_kills = ui.new_label('AA', 'Anti-aimbot angles', '\aFFFFFFFFKills: 0')
settings.info_deaths = ui.new_label('AA', 'Anti-aimbot angles', '\aFFFFFFFFDeaths: 0')
settings.info_kd = ui.new_label('AA', 'Anti-aimbot angles', '\aFFFFFFFFK/D Ratio: 0.00')
settings.info_misses = ui.new_label('AA', 'Anti-aimbot angles', '\aFFFFFFFFMisses on you: 0')
settings.info_playtime = ui.new_label('AA', 'Anti-aimbot angles', '\aFFFFFFFFPlaytime: 0m 0s')
settings.info_reset = ui.new_button('AA', 'Anti-aimbot angles', '\aFFFFFFFFReset Statistics', function()
    stats.kills = 0
    stats.deaths = 0
    stats.misses = 0
    stats.total_playtime = 0
    stats.start_time = globals.realtime()
    save_stats()
end)
settings.aa_builder_enable = ui.new_checkbox('AA', 'Anti-aimbot angles', '\aFFFFFFFFEnabled')
settings.anti_aim_state = ui.new_combobox('AA', 'Anti-aimbot angles', '\aFFFFFFFFAnti-aimbot state', anti_aim_states)

-- Create settings for each state using PUI
for i = 1, #anti_aim_states do
    anti_aim_settings[i] = {
        override_state = pui_group_aa:checkbox('\aFFFFFFFFOverride ' .. string.lower(anti_aim_states[i])),
        pitch1 = pui_group_aa:combobox('\aFFFFFFFFPitch' .. anti_aim_different[i], {'Off', 'Default', 'Up', 'Down', 'Minimal', 'Random', 'Custom'}),
        pitch2 = pui_group_aa:slider('\n\aFFFFFFFFPitch' .. anti_aim_different[i], -89, 89, 0, true, '°'),
        yaw_base = pui_group_aa:combobox('\aFFFFFFFFYaw base' .. anti_aim_different[i], {'Local view', 'At targets'}),
        yaw1 = pui_group_aa:combobox('\aFFFFFFFFYaw' .. anti_aim_different[i], {'Off', '180', 'Spin', 'Static', '180 Z', 'Crosshair'}),
        yaw2_left = pui_group_aa:slider('\aFFFFFFFFYaw left' .. anti_aim_different[i], -180, 180, 0, true, '°'),
        yaw2_right = pui_group_aa:slider('\aFFFFFFFFYaw right' .. anti_aim_different[i], -180, 180, 0, true, '°'),
        yaw2_randomize = pui_group_aa:slider('\aFFFFFFFFYaw randomize' .. anti_aim_different[i], 0, 180, 0, true, '°'),
        yaw_jitter1 = pui_group_aa:combobox('\aFFFFFFFFYaw jitter' .. anti_aim_different[i], {'Off', 'Offset', 'Center', 'Random', 'Skitter', 'Delay'}),
        yaw_jitter2_left = pui_group_aa:slider('\aFFFFFFFFYaw jitter left' .. anti_aim_different[i], -180, 180, 0, true, '°'),
        yaw_jitter2_right = pui_group_aa:slider('\aFFFFFFFFYaw jitter right' .. anti_aim_different[i], -180, 180, 0, true, '°'),
        yaw_jitter2_randomize = pui_group_aa:slider('\aFFFFFFFFYaw jitter randomize' .. anti_aim_different[i], 0, 180, 0, true, '°'),
        yaw_jitter2_delay = pui_group_aa:slider('\aFFFFFFFFYaw jitter delay' .. anti_aim_different[i], 2, 10, 2, true, 't'),
        body_yaw1 = pui_group_aa:combobox('\aFFFFFFFFBody yaw' .. anti_aim_different[i], {'Off', 'Opposite', 'Jitter', 'Static'}),
        body_yaw2 = pui_group_aa:slider('\aFFFFFFFFBody Yaw' .. anti_aim_different[i], -180, 180, 0, true, '°'),
        freestanding_body_yaw = pui_group_aa:checkbox('\aFFFFFFFFFreestanding body yaw' .. anti_aim_different[i]),
        roll = pui_group_aa:slider('\aFFFFFFFFRoll' .. anti_aim_different[i], -45, 45, 0, true, '°'),
        force_defensive = pui_group_other:checkbox('\aFFFFFFFFForce defensive' .. anti_aim_different[i]),
        defensive_anti_aimbot = pui_group_other:checkbox('\aADFF2FFF🅾︎\aFFFFFFFF Defensive AA' .. anti_aim_different[i]),
        defensive_pitch = pui_group_other:checkbox('\aFFFFFFFFPitch' .. anti_aim_different[i]),
        defensive_pitch1 = pui_group_other:combobox('\n\aFFFFFFFFPitch 2' .. anti_aim_different[i], {'Off', 'Default', 'Up', 'Down', 'Minimal', 'Random', 'Custom', 'Jitter'}),
        defensive_pitch2 = pui_group_other:slider('\n\aFFFFFFFFPitch 3' .. anti_aim_different[i], -89, 89, 0, true, '°'),
        defensive_pitch3 = pui_group_other:slider('\n\aFFFFFFFFPitch 4' .. anti_aim_different[i], -89, 89, 0, true, '°'),
        defensive_pitch_delay = pui_group_other:slider('\n\aFFFFFFFFPitch delay' .. anti_aim_different[i], 2, 10, 2, true, 't'),
        defensive_yaw = pui_group_other:checkbox('\aFFFFFFFFYaw' .. anti_aim_different[i]),
        defensive_yaw1 = pui_group_other:combobox('\aFFFFFFFFYaw 1' .. anti_aim_different[i], {'180', 'Spin', '180 Z', 'Sideways', 'Random', 'Jitter'}),
        defensive_yaw2 = pui_group_other:slider('\aFFFFFFFFYaw 2' .. anti_aim_different[i], -180, 180, 0, true, '°'),
        defensive_yaw3 = pui_group_other:slider('\aFFFFFFFFYaw 3' .. anti_aim_different[i], -180, 180, 0, true, '°'),
        defensive_yaw_delay = pui_group_other:slider('\aFFFFFFFFYaw delay' .. anti_aim_different[i], 2, 10, 4, true, 't'),
        defensive_spin_speed = pui_group_other:slider('\aFFFFFFFFSpin speed' .. anti_aim_different[i], 1, 50, 15, true, '°/t'),
        defensive_random_speed = pui_group_other:slider('\aFFFFFFFFRandom speed' .. anti_aim_different[i], 1, 20, 5, true, 't'),
        defensive_activation_delay = pui_group_other:slider('\aFFFFFFFFActivation delay' .. anti_aim_different[i], 0, 10, 2, true, 't')
    }
end

settings.separator_line_2 = ui.new_label('AA', 'Anti-aimbot angles', '━━━━━━━━━━━━━━━━━━━━━━━━━')
settings.warmup_disabler = ui.new_checkbox('AA', 'Anti-aimbot angles', '\aFFFFFFFFWarmup disabler')
settings.avoid_backstab = ui.new_checkbox('AA', 'Anti-aimbot angles', '\aFFFFFFFFAvoid backstab')
settings.safe_head_in_air = ui.new_checkbox('AA', 'Anti-aimbot angles', '\aFFFFFFFFSafe head in air')
settings.manual_forward = ui.new_hotkey('AA', 'Anti-aimbot angles', '\aFFFFFFFFManual forward')
settings.manual_right = ui.new_hotkey('AA', 'Anti-aimbot angles', '\aFFFFFFFFManual right')

-- Fake lag controls in Anti-aimbot angles tab (left side)
settings.fakelag_enabled = ui.new_checkbox('AA', 'Anti-aimbot angles', '\aFFFFFFFFEnable fake lag')
settings.fakelag_amount = ui.new_combobox('AA', 'Anti-aimbot angles', '\aFFFFFFFFAmount', 'Dynamic', 'Maximum', 'Fluctuate')
settings.fakelag_variance = ui.new_slider('AA', 'Anti-aimbot angles', '\aFFFFFFFFVariance', 0, 100, 0, true, '%')
settings.fakelag_limit = ui.new_slider('AA', 'Anti-aimbot angles', '\aFFFFFFFFLimit', 1, 14, 14, true, 't')
settings.manual_left = ui.new_hotkey('AA', 'Anti-aimbot angles', '\aFFFFFFFFManual left')
settings.edge_yaw = ui.new_hotkey('AA', 'Anti-aimbot angles', '\aFFFFFFFFEdge yaw')
settings.freestanding = ui.new_hotkey('AA', 'Anti-aimbot angles', '\aFFFFFFFFFreestanding')
settings.freestanding_conditions = ui.new_multiselect('AA', 'Anti-aimbot angles', '\n\aFFFFFFFFFreestanding', 'Standing', 'Moving', 'Slow motion', 'Crouching', 'In air')
settings.tweaks = ui.new_multiselect('AA', 'Anti-aimbot angles', '\n\aFFFFFFFFTweaks', 'Off jitter while freestanding', 'Off jitter on manual')

-- Visual World settings (in AA Anti-aimbot angles to use our tab system)
settings.fog_enable = ui.new_checkbox('AA', 'Anti-aimbot angles', '\aFFFFFFFFEnable Fog')
settings.fog_color = ui.new_color_picker('AA', 'Anti-aimbot angles', '\aFFFFFFFFFog Color', 255, 255, 255, 255)
settings.fog_start = ui.new_slider('AA', 'Anti-aimbot angles', '\aFFFFFFFFFog Start', 0, 16384, 0)
settings.fog_end = ui.new_slider('AA', 'Anti-aimbot angles', '\aFFFFFFFFFog End', 0, 16384, 0)
settings.fog_max_density = ui.new_slider('AA', 'Anti-aimbot angles', '\aFFFFFFFFFog Max Density', 0, 100, 0, true, '%')

settings.bloom_enable = ui.new_checkbox('AA', 'Anti-aimbot angles', '\aFFFFFFFFEnable Bloom')
settings.bloom_scale = ui.new_slider('AA', 'Anti-aimbot angles', '\aFFFFFFFFBloom scale', 0, 500, 100, true, nil, 0.01)
settings.auto_exposure = ui.new_slider('AA', 'Anti-aimbot angles', '\aFFFFFFFFAuto Exposure', -1, 2000, -1, true, nil, 0.001, {[-1]='Off'})
settings.model_ambient_min = ui.new_slider('AA', 'Anti-aimbot angles', '\aFFFFFFFFMinimum model brightness', 0, 1000, 0, true, nil, 0.05)

settings.wall_color_enable = ui.new_checkbox('AA', 'Anti-aimbot angles', '\aFFFFFFFFWall Color (only with bloom)')
settings.wall_color = ui.new_color_picker('AA', 'Anti-aimbot angles', '\aFFFFFFFFWall Color Picker', 255, 0, 0, 128)

settings.color_correction_enable = ui.new_checkbox('AA', 'Anti-aimbot angles', '\aFFFFFFFFColor Correction')
settings.color_correction_color = ui.new_color_picker('AA', 'Anti-aimbot angles', '\aFFFFFFFFColor Correction Picker', 0, 85, 101, 12)

-- Ragebot Advanced Panel settings
settings.advanced_panel_enabled = ui.new_checkbox('AA', 'Anti-aimbot angles', '\aFFFFFFFFAdvanced Panel')
settings.advanced_panel_accent_color = ui.new_color_picker('AA', 'Anti-aimbot angles', '\aFFFFFFFFAccent color', 173, 255, 47, 255)

-- Misc tab settings
settings.fps_boosters = ui.new_multiselect('AA', 'Anti-aimbot angles', '\aFFFFFFFFFPS improvements', 'Post Processing', 'Vignette', 'Bloom', 'Shadows', 'Blood', 'Ragdolls', 'Fog', '3D skybox')
settings.anim_breakers = ui.new_multiselect('AA', 'Anti-aimbot angles', '\aFFFFFFFFAnim breakers', 'Static legs', 'Leg fucker', '0 pitch on landing', 'Earthquake')

-- Visual Main settings
settings.minimum_damage_indicator = ui.new_combobox('AA', 'Anti-aimbot angles', '\aFFFFFFFFMinimum Damage Indicator', 'Off', 'On override', 'Always')
settings.crosshair_indicator = ui.new_checkbox('AA', 'Anti-aimbot angles', '\aFFFFFFFFCrosshair Indicator')

-- Watermark settings
settings.watermark_enable = ui.new_checkbox('AA', 'Anti-aimbot angles', '\aFFFFFFFFWatermark')
settings.watermark_elements = ui.new_multiselect('AA', 'Anti-aimbot angles', '\n\aFFFFFFFFWatermark Elements', 'FPS', 'PING', 'DELAY', 'CPU', 'GPU', 'Time')
settings.watermark_bg_color = ui.new_color_picker('AA', 'Anti-aimbot angles', '\aFFFFFFFFWatermark BG', 11, 11, 11, 107)
settings.watermark_border_color = ui.new_color_picker('AA', 'Anti-aimbot angles', '\aFFFFFFFFWatermark Border', 31, 31, 37, 134)
settings.watermark_x = ui.new_slider('AA', 'Anti-aimbot angles', '\nWatermark X', 0, 2000, 1556, true, 'px', 1)
settings.watermark_y = ui.new_slider('AA', 'Anti-aimbot angles', '\nWatermark Y', 0, 2000, 2, true, 'px', 1)

-- Hit logs settings
settings.hitlogs_enable = ui.new_checkbox('AA', 'Anti-aimbot angles', '\aFFFFFFFFHit Logs')
settings.hitlogs_position = ui.new_combobox('AA', 'Anti-aimbot angles', '\nHit Logs Position', 'Center', 'Top Left')
settings.hitlogs_y_offset = ui.new_slider('AA', 'Anti-aimbot angles', '\nHit Logs Y Offset', -500, 500, 100, true, 'px', 1)

-- Config tab settings
settings.config_label_1 = ui.new_label('AA', 'Anti-aimbot angles', '\aFFFFFFFFConfiguration list')
settings.config_line_1 = ui.new_label('AA', 'Anti-aimbot angles', '\a333333FF⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯')
settings.config_list = ui.new_listbox('AA', 'Anti-aimbot angles', '\n', '')
settings.config_label_2 = ui.new_label('AA', 'Anti-aimbot angles', '\aFFFFFFFFConfiguration management')
settings.config_line_2 = ui.new_label('AA', 'Anti-aimbot angles', '\a333333FF⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯')
settings.config_name = ui.new_textbox('AA', 'Anti-aimbot angles', 'Configuration name')
settings.config_create = ui.new_button('AA', 'Anti-aimbot angles', 'Create', function() end)
settings.config_load = ui.new_button('AA', 'Anti-aimbot angles', 'Load', function() end)
settings.config_save = ui.new_button('AA', 'Anti-aimbot angles', 'Save', function() end)
settings.config_delete = ui.new_button('AA', 'Anti-aimbot angles', 'Delete', function() end)
settings.config_import = ui.new_button('AA', 'Anti-aimbot angles', 'Import from Clipboard', function() end)
settings.config_export = ui.new_button('AA', 'Anti-aimbot angles', 'Export to Clipboard', function() end)


-- Visual World variables
local fog_controller = {
    entity = nil,
    fog_color = 0,
    fog_start = 0,
    fog_end = 0,
    fog_max_density = 0
}

local bloom_default, exposure_min_default, exposure_max_default
local bloom_prev, exposure_prev, model_ambient_min_prev, wallcolor_prev = -1, -1, 0, false

local mat_ambient_light_r = cvar.mat_ambient_light_r
local mat_ambient_light_g = cvar.mat_ambient_light_g
local mat_ambient_light_b = cvar.mat_ambient_light_b
local r_modelAmbientMin = cvar.r_modelAmbientMin

-- FPS improvement cvars
local mat_postprocess_enable = cvar.mat_postprocess_enable
local mat_vignette_enable = cvar.mat_vignette_enable
local mat_bloom_scalefactor_scalar = cvar.mat_bloom_scalefactor_scalar
local cl_csm_shadows = cvar.cl_csm_shadows
local r_dynamic = cvar.r_dynamic
local r_shadows = cvar.r_shadows
local cl_csm_static_prop_shadows = cvar.cl_csm_static_prop_shadows
local cl_csm_world_shadows = cvar.cl_csm_world_shadows
local cl_foot_contact_shadows = cvar.cl_foot_contact_shadows
local cl_csm_viewmodel_shadows = cvar.cl_csm_viewmodel_shadows
local cl_csm_rope_shadows = cvar.cl_csm_rope_shadows
local cl_csm_sprite_shadows = cvar.cl_csm_sprite_shadows
local cl_csm_world_shadows_in_viewmodelcascade = cvar.cl_csm_world_shadows_in_viewmodelcascade
local violence_ablood = cvar.violence_ablood
local violence_hblood = cvar.violence_hblood
local cl_disable_ragdolls = cvar.cl_disable_ragdolls
local fog_enable = cvar.fog_enable
local fog_enable_water_fog = cvar.fog_enable_water_fog
local fog_enableskybox = cvar.fog_enableskybox
local r_3dsky = cvar.r_3dsky

-- Advanced Panel variables
local panel_x, panel_y = 5, 450
local panel_width, panel_height = 280, 120
local panel_dragging = false
local panel_drag_offset_x, panel_drag_offset_y = 0, 0
local panel_header_height = 20
local panel_blur_alpha = 0
local panel_blur_target = 0
local panel_blur_speed = 8
local panel_shots_fired = 0
local panel_shots_hit = 0
local panel_shots_missed = 0

-- Advanced Panel functions
local function get_exploit_charge()
    local local_player = entity.get_local_player()
    if not local_player then return "0.0" end
    
    local charge = entity.get_prop(local_player, "m_flNextAttack")
    if charge then
        local current_time = globals.curtime()
        local charge_percent = math.max(0, math.min(1, (current_time - charge) / 0.5))
        return string.format("%.1f", charge_percent)
    end
    
    return "1.0"
end

local function get_desync_amount()
    local local_player = entity.get_local_player()
    if not local_player then return "0" end
    
    local body_yaw = entity.get_prop(local_player, "m_flPoseParameter", 11)
    if body_yaw then
        local desync = math.abs((body_yaw * 120) - 60)
        return string.format("%.0f", desync)
    end
    
    return "60"
end

local panel_last_condition = "STANDING"
local panel_air_timer = 0

local function get_player_condition()
    local local_player = entity.get_local_player()
    if not local_player or not entity.is_alive(local_player) then
        return "DEAD"
    end
    
    local flags = entity.get_prop(local_player, "m_fFlags")
    local velocity = entity.get_prop(local_player, "m_vecVelocity")
    
    if not flags or not velocity then
        return "UNKNOWN"
    end
    
    local vel_x, vel_y, vel_z
    if type(velocity) == "table" then
        vel_x, vel_y, vel_z = velocity[1] or 0, velocity[2] or 0, velocity[3] or 0
    else
        vel_x = entity.get_prop(local_player, "m_vecVelocity[0]") or 0
        vel_y = entity.get_prop(local_player, "m_vecVelocity[1]") or 0
        vel_z = entity.get_prop(local_player, "m_vecVelocity[2]") or 0
    end
    
    local speed = math.sqrt(vel_x^2 + vel_y^2)
    local is_on_ground = bit.band(flags, 1) ~= 0
    local is_ducking = bit.band(flags, 2) ~= 0
    local current_time = globals.curtime()
    
    local shift_pressed = false
    if client.key_state then
        shift_pressed = client.key_state(0x10)
    end
    
    local fake_duck_active = ui.get(reference.duck_peek_assist)
    
    if fake_duck_active then
        panel_last_condition = "SNEAKING"
        return "SNEAKING"
    end
    
    if not is_on_ground or math.abs(vel_z) > 5 then
        panel_air_timer = current_time
    end
    
    local recently_in_air = (current_time - panel_air_timer) < 0.1
    
    if not is_on_ground or recently_in_air or math.abs(vel_z) > 5 then
        if is_ducking then
            panel_last_condition = "AIR-CROUCH"
            return "AIR-CROUCH"
        else
            panel_last_condition = "AIR"
            return "AIR"
        end
    end
    
    if is_ducking then
        if speed > 5 then
            panel_last_condition = "SNEAKING"
            return "SNEAKING"
        else
            panel_last_condition = "CROUCHING"
            return "CROUCHING"
        end
    end
    
    if shift_pressed and speed > 5 and speed < 100 then
        panel_last_condition = "SLOW-WALK"
        return "SLOW-WALK"
    elseif speed > 100 then
        panel_last_condition = "MOVING"
        return "MOVING"
    elseif speed > 1 then
        panel_last_condition = "STANDING"
        return "STANDING"
    else
        panel_last_condition = "STANDING"
        return "STANDING"
    end
end

local function get_nearest_target()
    local local_player = entity.get_local_player()
    if not local_player or not entity.is_alive(local_player) then
        return nil
    end
    
    local players = entity.get_players(true)
    local nearest_enemy = nil
    local nearest_distance = math.huge
    
    for i = 1, #players do
        local player = players[i]
        if entity.is_alive(player) and entity.is_enemy(player) then
            local local_origin = {entity.get_prop(local_player, "m_vecOrigin")}
            local target_origin = {entity.get_prop(player, "m_vecOrigin")}
            
            if local_origin[1] and target_origin[1] then
                local distance = math.sqrt(
                    (local_origin[1] - target_origin[1])^2 + 
                    (local_origin[2] - target_origin[2])^2 + 
                    (local_origin[3] - target_origin[3])^2
                )
                
                if distance < nearest_distance then
                    nearest_distance = distance
                    nearest_enemy = player
                end
            end
        end
    end
    
    return nearest_enemy
end

local function draw_panel_gradient_line(x, y, width)
    local accent_r, accent_g, accent_b, accent_a = ui.get(settings.advanced_panel_accent_color)
    
    for i = 0, width do
        local progress = i / width
        local alpha_multiplier = math.pow(math.sin(progress * math.pi), 3)
        local alpha = math.floor(accent_a * alpha_multiplier)
        
        if alpha > 5 then
            renderer.line(x + i, y, x + i + 1, y, accent_r, accent_g, accent_b, alpha)
        end
    end
end

-- Damage Indicator variables
local damage_indicator_vars = {
    offset_x = 5,
    offset_y = -20,
    dragging = false,
    drag_offset_x = 0,
    drag_offset_y = 0,
    zone_size = 40,
    mouse_was_pressed_dmg = false,
}

-- Crosshair Indicator variables (from senkotech)
local crosshair_indicator = {
    alpha = 0.0,
    align = 0.0,
    state_alpha = 0.0,
    state_value = 1.0,
    last_state = 'GLOBAL',
    dmg_alpha = 0.0,
    dmg_value = 0.0,
    dt_alpha = 0.0,
    dt_value = 0.0,
    osaa_alpha = 0.0,
    osaa_value = 0.0,
    fs_alpha = 0.0,
    fs_value = 0.0
}

-- Watermark variables
local watermark_vars = {
    dragging = false,
    drag_offset_x = 0,
    drag_offset_y = 0,
    mouse_was_pressed = false,
    fps_data = {last_time = 0, frame_count = 0, current_fps = 0},
    cpu_usage = 39,
    gpu_usage = 50
}

-- Hit logs variables
local hit_logs = {}
local max_logs_center = 5
local max_logs_topleft = 7
local log_lifetime_center = 2
local log_lifetime_topleft = 6
local log_positions = {}

-- Helper function for smooth interpolation
local function lerp(a, b, t)
    return a + (b - a) * t
end

-- Helper function to convert color to hex
local function to_hex(r, g, b, a)
    return string.format("%02x%02x%02x%02x", r, g, b, a)
end

-- Decoration functions (from senkotech)
local function wave_text(s, clock, r1, g1, b1, a1, r2, g2, b2, a2)
    local buffer = {}
    local len = #s
    local div = 1 / math.max(len - 1, 1)
    
    local add_r = r2 - r1
    local add_g = g2 - g1
    local add_b = b2 - b1
    local add_a = a2 - a1
    
    for i = 1, len do
        local char = s:sub(i, i)
        local t = clock % 2
        if t > 1 then
            t = 2 - t
        end
        
        local r = r1 + add_r * t
        local g = g1 + add_g * t
        local b = b1 + add_b * t
        local a = a1 + add_a * t
        
        buffer[#buffer + 1] = "\a"
        buffer[#buffer + 1] = to_hex(r, g, b, a)
        buffer[#buffer + 1] = char
        
        clock = clock + div
    end
    
    return table.concat(buffer)
end

local function fade_text(s, pct, r1, g1, b1, a1, r2, g2, b2, a2)
    if pct == 0 then
        return "\a" .. to_hex(r2, g2, b2, a2) .. s
    end
    
    if pct == 1 then
        return "\a" .. to_hex(r1, g1, b1, a1) .. s
    end
    
    local buffer = {}
    local len = #s
    local div = 1 / math.max(len - 1, 1)
    
    local add_r = r2 - r1
    local add_g = g2 - g1
    local add_b = b2 - b1
    local add_a = a2 - a1
    
    local clock = 0
    local HALF_PI = math.pi / 2
    
    for i = 1, len do
        local char = s:sub(i, i)
        local t = math.sin(HALF_PI * (1 - clock * pct) * (1 - pct * pct))
        
        local r = r1 + add_r * t
        local g = g1 + add_g * t
        local b = b1 + add_b * t
        local a = a1 + add_a * t
        
        buffer[#buffer + 1] = "\a"
        buffer[#buffer + 1] = to_hex(r, g, b, a)
        buffer[#buffer + 1] = char
        
        clock = clock + div
    end
    
    return table.concat(buffer)
end

-- Animation breaker variables
local ground_ticks = 0
local end_time = 0

-- Main setup_command callback
client.set_event_callback('setup_command', function(cmd)
    -- Apply custom fake lag settings
    if ui.get(settings.fakelag_enabled) then
        ui.set(reference.fake_lag_enabled, true)
        
        local amount = ui.get(settings.fakelag_amount)
        if amount == 'Dynamic' then
            ui.set(reference.fake_lag_amount, 'Dynamic')
        elseif amount == 'Maximum' then
            ui.set(reference.fake_lag_amount, 'Maximum')
        else
            ui.set(reference.fake_lag_amount, 'Fluctuate')
        end
        
        ui.set(reference.fake_lag_variance, ui.get(settings.fakelag_variance))
        ui.set(reference.fake_lag_limit, ui.get(settings.fakelag_limit))
    else
        ui.set(reference.fake_lag_enabled, false)
    end
    
    if not ui.get(settings.aa_builder_enable) then
        return
    end
    
    -- Enable AA in cheat
    ui.set(reference.aa_enabled, true)
    
    local self = entity.get_local_player()
    if entity.get_player_weapon(self) == nil then return end

    local using = false
    local anti_aim_on_use = false
    local inverted = entity.get_prop(self, "m_flPoseParameter", 11) * 120 - 60

    local is_planting = entity.get_prop(self, 'm_bInBombZone') == 1 and entity.get_classname(entity.get_player_weapon(self)) == 'CC4' and entity.get_prop(self, 'm_iTeamNum') == 2
    local CPlantedC4 = entity.get_all('CPlantedC4')[1]

    local eye_x, eye_y, eye_z = client.eye_position()
    local pitch, yaw = client.camera_angles()

    local sin_pitch = math.sin(math.rad(pitch))
    local cos_pitch = math.cos(math.rad(pitch))
    local sin_yaw = math.sin(math.rad(yaw))
    local cos_yaw = math.cos(math.rad(yaw))

    local direction_vector = {cos_pitch * cos_yaw, cos_pitch * sin_yaw, -sin_pitch}
    local fraction, entity_index = client.trace_line(self, eye_x, eye_y, eye_z, eye_x + (direction_vector[1] * 8192), eye_y + (direction_vector[2] * 8192), eye_z + (direction_vector[3] * 8192))

    if CPlantedC4 ~= nil then
        dist_to_c4 = vector(entity.get_prop(self, 'm_vecOrigin')):dist(vector(entity.get_prop(CPlantedC4, 'm_vecOrigin')))
        if entity.get_prop(CPlantedC4, 'm_bBombDefused') == 1 then dist_to_c4 = 56 end
        is_defusing = dist_to_c4 < 56 and entity.get_prop(self, 'm_iTeamNum') == 3
    end

    if entity_index ~= -1 then
        if vector(entity.get_prop(self, 'm_vecOrigin')):dist(vector(entity.get_prop(entity_index, 'm_vecOrigin'))) < 146 then
            using = entity.get_classname(entity_index) ~= 'CWorld' and entity.get_classname(entity_index) ~= 'CFuncBrush' and entity.get_classname(entity_index) ~= 'CCSPlayer'
        end
    end

    -- State detection
    if cmd.in_use == 1 and not using and not is_planting and not is_defusing and pui_get(anti_aim_settings[10].override_state) then 
        cmd.buttons = bit.band(cmd.buttons, bit.bnot(bit.lshift(1, 5)))
        anti_aim_on_use = true
        state_id = 10 
    else 
        if (ui.get(reference.double_tap[1]) and ui.get(reference.double_tap[2])) == false and (ui.get(reference.on_shot_anti_aim[1]) and ui.get(reference.on_shot_anti_aim[2])) == false and pui_get(anti_aim_settings[9].override_state) then 
            anti_aim_on_use = false
            state_id = 9 
        else 
            if (cmd.in_jump == 1 or bit.band(entity.get_prop(self, 'm_fFlags'), 1) == 0) and entity.get_prop(self, 'm_flDuckAmount') > 0.8 and pui_get(anti_aim_settings[8].override_state) then 
                anti_aim_on_use = false
                state_id = 8 
            elseif (cmd.in_jump == 1 or bit.band(entity.get_prop(self, 'm_fFlags'), 1) == 0) and entity.get_prop(self, 'm_flDuckAmount') < 0.8 and pui_get(anti_aim_settings[7].override_state) then 
                anti_aim_on_use = false
                state_id = 7 
            elseif bit.band(entity.get_prop(self, 'm_fFlags'), 1) ~= 0 and (entity.get_prop(self, 'm_flDuckAmount') > 0.8 or ui.get(reference.duck_peek_assist)) and vector(entity.get_prop(self, 'm_vecVelocity')):length() > 2 and pui_get(anti_aim_settings[6].override_state) then 
                anti_aim_on_use = false
                state_id = 6 
            elseif bit.band(entity.get_prop(self, 'm_fFlags'), 1) ~= 0 and entity.get_prop(self, 'm_flDuckAmount') > 0.8 and vector(entity.get_prop(self, 'm_vecVelocity')):length() < 2 and pui_get(anti_aim_settings[5].override_state) then 
                anti_aim_on_use = false
                state_id = 5 
            elseif bit.band(entity.get_prop(self, 'm_fFlags'), 1) ~= 0 and vector(entity.get_prop(self, 'm_vecVelocity')):length() > 2 and entity.get_prop(self, 'm_flDuckAmount') < 0.8 and (ui.get(reference.slow_motion[1]) and ui.get(reference.slow_motion[2])) == true and pui_get(anti_aim_settings[4].override_state) then 
                anti_aim_on_use = false
                state_id = 4 
            elseif bit.band(entity.get_prop(self, 'm_fFlags'), 1) ~= 0 and vector(entity.get_prop(self, 'm_vecVelocity')):length() > 2 and entity.get_prop(self, 'm_flDuckAmount') < 0.8 and (ui.get(reference.slow_motion[1]) and ui.get(reference.slow_motion[2])) == false and pui_get(anti_aim_settings[3].override_state) then 
                anti_aim_on_use = false
                state_id = 3 
            elseif bit.band(entity.get_prop(self, 'm_fFlags'), 1) ~= 0 and vector(entity.get_prop(self, 'm_vecVelocity')):length() < 2 and entity.get_prop(self, 'm_flDuckAmount') < 0.8 and pui_get(anti_aim_settings[2].override_state) then 
                anti_aim_on_use = false
                state_id = 2 
            else 
                anti_aim_on_use = false
                state_id = 1 
            end 
        end 
    end
    
    if cmd.in_jump == 1 or bit.band(entity.get_prop(self, 'm_fFlags'), 1) == 0 then 
        freestanding_state_id = 5 
    elseif (entity.get_prop(self, 'm_flDuckAmount') > 0.8 or ui.get(reference.duck_peek_assist)) and bit.band(entity.get_prop(self, 'm_fFlags'), 1) ~= 0 then 
        freestanding_state_id = 4 
    elseif bit.band(entity.get_prop(self, 'm_fFlags'), 1) ~= 0 and vector(entity.get_prop(self, 'm_vecVelocity')):length() > 2 and (ui.get(reference.slow_motion[1]) and ui.get(reference.slow_motion[2])) == true then 
        freestanding_state_id = 3 
    elseif bit.band(entity.get_prop(self, 'm_fFlags'), 1) ~= 0 and vector(entity.get_prop(self, 'm_vecVelocity')):length() > 2 and (ui.get(reference.slow_motion[1]) and ui.get(reference.slow_motion[2])) == false then 
        freestanding_state_id = 2 
    elseif bit.band(entity.get_prop(self, 'm_fFlags'), 1) ~= 0 and vector(entity.get_prop(self, 'm_vecVelocity')):length() < 2 then 
        freestanding_state_id = 1 
    end

    ui.set(settings.manual_forward, 'On hotkey')
    ui.set(settings.manual_right, 'On hotkey')
    ui.set(settings.manual_left, 'On hotkey')

    cmd.force_defensive = pui_get(anti_aim_settings[state_id].force_defensive)

    ui.set(reference.pitch[1], pui_get(anti_aim_settings[state_id].pitch1))
    ui.set(reference.pitch[2], pui_get(anti_aim_settings[state_id].pitch2))
    ui.set(reference.yaw_base, (direction == 180 or direction == 90 or direction == -90) and anti_aim_on_use == false and 'Local view' or pui_get(anti_aim_settings[state_id].yaw_base))
    ui.set(reference.yaw[1], (direction == 180 or direction == 90 or direction == -90) and anti_aim_on_use == false and '180' or pui_get(anti_aim_settings[state_id].yaw1))

    -- Manual yaw handling
    if pui_get(anti_aim_settings[state_id].yaw1) ~= 'Off' and pui_get(anti_aim_settings[state_id].yaw_jitter1) == 'Delay' then
        if inverted > 0 then
            if ui.get(settings.manual_left) and last_press + 0.2 < globals.realtime() then
                direction = direction == -90 and pui_get(anti_aim_settings[state_id].yaw_jitter2_left) or -90
                last_press = globals.realtime()
            elseif ui.get(settings.manual_right) and last_press + 0.2 < globals.realtime() then
                direction = direction == 90 and pui_get(anti_aim_settings[state_id].yaw_jitter2_left) or 90
                last_press = globals.realtime()
            elseif ui.get(settings.manual_forward) and last_press + 0.2 < globals.realtime() then
                direction = direction == 180 and pui_get(anti_aim_settings[state_id].yaw_jitter2_left) or 180
                last_press = globals.realtime()
            end
        else
            if ui.get(settings.manual_left) and last_press + 0.2 < globals.realtime() then
                direction = direction == -90 and pui_get(anti_aim_settings[state_id].yaw_jitter2_right) or -90
                last_press = globals.realtime()
            elseif ui.get(settings.manual_right) and last_press + 0.2 < globals.realtime() then
                direction = direction == 90 and pui_get(anti_aim_settings[state_id].yaw_jitter2_right) or 90
                last_press = globals.realtime()
            elseif ui.get(settings.manual_forward) and last_press + 0.2 < globals.realtime() then
                direction = direction == 180 and pui_get(anti_aim_settings[state_id].yaw_jitter2_right) or 180
                last_press = globals.realtime()
            end
        end
    else
        if inverted > 0 then
            if ui.get(settings.manual_left) and last_press + 0.2 < globals.realtime() then
                direction = direction == -90 and pui_get(anti_aim_settings[state_id].yaw2_left) or -90
                last_press = globals.realtime()
            elseif ui.get(settings.manual_right) and last_press + 0.2 < globals.realtime() then
                direction = direction == 90 and pui_get(anti_aim_settings[state_id].yaw2_left) or 90
                last_press = globals.realtime()
            elseif ui.get(settings.manual_forward) and last_press + 0.2 < globals.realtime() then
                direction = direction == 180 and pui_get(anti_aim_settings[state_id].yaw2_left) or 180
                last_press = globals.realtime()
            end
        else
            if ui.get(settings.manual_left) and last_press + 0.2 < globals.realtime() then
                direction = direction == -90 and pui_get(anti_aim_settings[state_id].yaw2_right) or -90
                last_press = globals.realtime()
            elseif ui.get(settings.manual_right) and last_press + 0.2 < globals.realtime() then
                direction = direction == 90 and pui_get(anti_aim_settings[state_id].yaw2_right) or 90
                last_press = globals.realtime()
            elseif ui.get(settings.manual_forward) and last_press + 0.2 < globals.realtime() then
                direction = direction == 180 and pui_get(anti_aim_settings[state_id].yaw2_right) or 180
                last_press = globals.realtime()
            end
        end
    end

    if pui_get(anti_aim_settings[state_id].yaw1) ~= 'Off' and pui_get(anti_aim_settings[state_id].yaw_jitter1) == 'Delay' then
        if math.random(0, 1) ~= 0 then
            yaw_jitter2_left = pui_get(anti_aim_settings[state_id].yaw_jitter2_left) - math.random(0, pui_get(anti_aim_settings[state_id].yaw_jitter2_randomize))
            yaw_jitter2_right = pui_get(anti_aim_settings[state_id].yaw_jitter2_right) - math.random(0, pui_get(anti_aim_settings[state_id].yaw_jitter2_randomize))
        else
            yaw_jitter2_left = pui_get(anti_aim_settings[state_id].yaw_jitter2_left) + math.random(0, pui_get(anti_aim_settings[state_id].yaw_jitter2_randomize))
            yaw_jitter2_right = pui_get(anti_aim_settings[state_id].yaw_jitter2_right) + math.random(0, pui_get(anti_aim_settings[state_id].yaw_jitter2_randomize))
        end

        if inverted > 0 then
            if yaw_jitter2_left == 180 then yaw_jitter2_left = -180 elseif yaw_jitter2_left == 90 then yaw_jitter2_left = 89 elseif yaw_jitter2_left == -90 then yaw_jitter2_left = -89 end
            if not (direction == 180 or direction == 90 or direction == -90) then direction = yaw_jitter2_left end
        else
            if yaw_jitter2_right == 180 then yaw_jitter2_right = -180 elseif yaw_jitter2_right == 90 then yaw_jitter2_right = 89 elseif yaw_jitter2_right == -90 then yaw_jitter2_right = -89 end
            if not (direction == 180 or direction == 90 or direction == -90) then direction = yaw_jitter2_right end
        end
    else
        if inverted > 0 then
            if math.random(0, 1) ~= 0 then yaw2_left = pui_get(anti_aim_settings[state_id].yaw2_left) - math.random(0, pui_get(anti_aim_settings[state_id].yaw2_randomize)) else yaw2_left = pui_get(anti_aim_settings[state_id].yaw2_left) + math.random(0, pui_get(anti_aim_settings[state_id].yaw2_randomize)) end
            if yaw2_left == 180 then yaw2_left = -180 elseif yaw2_left == 90 then yaw2_left = 89 elseif yaw2_left == -90 then yaw2_left = -89 end
            if not (direction == 90 or direction == -90 or direction == 180) then direction = yaw2_left end
        else
            if math.random(0, 1) ~= 0 then yaw2_right = pui_get(anti_aim_settings[state_id].yaw2_right) - math.random(0, pui_get(anti_aim_settings[state_id].yaw2_randomize)) else yaw2_right = pui_get(anti_aim_settings[state_id].yaw2_right) + math.random(0, pui_get(anti_aim_settings[state_id].yaw2_randomize)) end
            if yaw2_right == 180 then yaw2_right = -180 elseif yaw2_right == 90 then yaw2_right = 89 elseif yaw2_right == -90 then yaw2_right = -89 end
            if not (direction == 90 or direction == -90 or direction == 180) then direction = yaw2_right end
        end
    end

    if direction > 180 or direction < -180 then direction = -180 end
    if anti_aim_on_use_direction > 180 or anti_aim_on_use_direction < -180 then anti_aim_on_use_direction = -180 end

    ui.set(reference.yaw[2], anti_aim_on_use == false and direction or anti_aim_on_use_direction)
    
    local yaw_jitter_type = pui_get(anti_aim_settings[state_id].yaw_jitter1)
    local should_disable_jitter = (direction == 180 or direction == 90 or direction == -90) and contains(ui.get(settings.tweaks), 'Off jitter on manual') and anti_aim_on_use == false
    
    if should_disable_jitter or yaw_jitter_type == 'Delay' or pui_get(anti_aim_settings[state_id].yaw1) == 'Off' then
        ui.set(reference.yaw_jitter[1], 'Off')
    else
        ui.set(reference.yaw_jitter[1], yaw_jitter_type)
    end

    -- Yaw jitter value
    local yaw_jitter_type = pui_get(anti_aim_settings[state_id].yaw_jitter1)
    
    -- Only set yaw jitter value if not using standard types (Center, Offset, Random, Skitter work automatically)
    if yaw_jitter_type ~= 'Off' and yaw_jitter_type ~= 'Center' and yaw_jitter_type ~= 'Offset' and yaw_jitter_type ~= 'Random' and yaw_jitter_type ~= 'Skitter' then
        if inverted > 0 then
            if math.random(0, 1) ~= 0 then yaw_jitter2_left = pui_get(anti_aim_settings[state_id].yaw_jitter2_left) - math.random(0, pui_get(anti_aim_settings[state_id].yaw_jitter2_randomize)) else yaw_jitter2_left = pui_get(anti_aim_settings[state_id].yaw_jitter2_left) + math.random(0, pui_get(anti_aim_settings[state_id].yaw_jitter2_randomize)) end
            if yaw_jitter2_left > 180 or yaw_jitter2_left < -180 then yaw_jitter2_left = -180 end
            ui.set(reference.yaw_jitter[2], pui_get(anti_aim_settings[state_id].yaw1) ~= 'Off' and yaw_jitter2_left or 0)
        else
            if math.random(0, 1) ~= 0 then yaw_jitter2_right = pui_get(anti_aim_settings[state_id].yaw_jitter2_right) - math.random(0, pui_get(anti_aim_settings[state_id].yaw_jitter2_randomize)) else yaw_jitter2_right = pui_get(anti_aim_settings[state_id].yaw_jitter2_right) + math.random(0, pui_get(anti_aim_settings[state_id].yaw_jitter2_randomize)) end
            if yaw_jitter2_right > 180 or yaw_jitter2_right < -180 then yaw_jitter2_right = -180 end
            ui.set(reference.yaw_jitter[2], pui_get(anti_aim_settings[state_id].yaw1) ~= 'Off' and yaw_jitter2_right or 0)
        end
    elseif yaw_jitter_type == 'Center' or yaw_jitter_type == 'Offset' or yaw_jitter_type == 'Random' or yaw_jitter_type == 'Skitter' then
        -- For standard types, set the value from sliders
        if inverted > 0 then
            ui.set(reference.yaw_jitter[2], pui_get(anti_aim_settings[state_id].yaw_jitter2_left))
        else
            ui.set(reference.yaw_jitter[2], pui_get(anti_aim_settings[state_id].yaw_jitter2_right))
        end
    end

    -- Body yaw
    if pui_get(anti_aim_settings[state_id].yaw1) ~= 'Off' and pui_get(anti_aim_settings[state_id].yaw_jitter1) == 'Delay' then
        if (ui.get(reference.double_tap[1]) and ui.get(reference.double_tap[2])) == true or (ui.get(reference.on_shot_anti_aim[1]) and ui.get(reference.on_shot_anti_aim[2])) == true then
            ui.set(reference.body_yaw[1], (direction == 180 or direction == 90 or direction == -90) and contains(ui.get(settings.tweaks), 'Off jitter on manual') and anti_aim_on_use == false and 'Opposite' or 'Static')
        else
            ui.set(reference.body_yaw[1], (direction == 180 or direction == 90 or direction == -90) and contains(ui.get(settings.tweaks), 'Off jitter on manual') and anti_aim_on_use == false and 'Opposite' or 'Jitter')
        end
    else
        ui.set(reference.body_yaw[1], (direction == 180 or direction == 90 or direction == -90) and contains(ui.get(settings.tweaks), 'Off jitter on manual') and anti_aim_on_use == false and 'Opposite' or pui_get(anti_aim_settings[state_id].body_yaw1))
    end

    -- Delay jitter from mytools
    if cmd.command_number % pui_get(anti_aim_settings[state_id].yaw_jitter2_delay) + 1 > pui_get(anti_aim_settings[state_id].yaw_jitter2_delay) - 1 then
        delayed_jitter = not delayed_jitter
    end

    if pui_get(anti_aim_settings[state_id].yaw1) ~= 'Off' and pui_get(anti_aim_settings[state_id].yaw_jitter1) == 'Delay' then
        if (ui.get(reference.double_tap[1]) and ui.get(reference.double_tap[2])) == true or (ui.get(reference.on_shot_anti_aim[1]) and ui.get(reference.on_shot_anti_aim[2])) == true then
            ui.set(reference.body_yaw[2], delayed_jitter and -90 or 90)
        else
            ui.set(reference.body_yaw[2], -40)
        end
    else
        ui.set(reference.body_yaw[2], pui_get(anti_aim_settings[state_id].body_yaw2))
    end

    ui.set(reference.freestanding_body_yaw, pui_get(anti_aim_settings[state_id].yaw1) ~= 'Off' and pui_get(anti_aim_settings[state_id].yaw_jitter1) == 'Delay' and false or pui_get(anti_aim_settings[state_id].freestanding_body_yaw))
    ui.set(reference.roll, pui_get(anti_aim_settings[state_id].roll))

    -- Defensive AA
    if pui_get(anti_aim_settings[state_id].defensive_anti_aimbot) and is_defensive_active and ((ui.get(reference.double_tap[1]) and ui.get(reference.double_tap[2])) or (ui.get(reference.on_shot_anti_aim[1]) and ui.get(reference.on_shot_anti_aim[2]))) and not (direction == 180 or direction == 90 or direction == -90) then
        -- Save the yaw that was set by normal AA (before defensive modifications)
        -- This is the yaw where character is facing after all AA calculations
        local base_yaw = cmd.yaw
        
        -- Check activation delay
        local activation_delay = pui_get(anti_aim_settings[state_id].defensive_activation_delay) or 2
        
        -- Detect defensive state change
        if not last_defensive_state then
            -- Defensive just became active
            defensive_start_tick = cmd.command_number
        end
        
        -- Check if we've passed the activation delay
        local should_apply = false
        if defensive_start_tick > 0 then
            local ticks_since_start = cmd.command_number - defensive_start_tick
            if ticks_since_start >= activation_delay then
                should_apply = true
            end
        end
        
        if should_apply then
            if pui_get(anti_aim_settings[state_id].defensive_pitch) then
                local defensive_pitch_value = 0
                
                if pui_get(anti_aim_settings[state_id].defensive_pitch1) == 'Off' then
                    defensive_pitch_value = 0
                elseif pui_get(anti_aim_settings[state_id].defensive_pitch1) == 'Default' then
                    defensive_pitch_value = 89
                elseif pui_get(anti_aim_settings[state_id].defensive_pitch1) == 'Up' then
                    defensive_pitch_value = -89
                elseif pui_get(anti_aim_settings[state_id].defensive_pitch1) == 'Down' then
                    defensive_pitch_value = 89
                elseif pui_get(anti_aim_settings[state_id].defensive_pitch1) == 'Minimal' then
                    defensive_pitch_value = 89
                elseif pui_get(anti_aim_settings[state_id].defensive_pitch1) == 'Random' then
                    defensive_pitch_value = math.random(pui_get(anti_aim_settings[state_id].defensive_pitch2), pui_get(anti_aim_settings[state_id].defensive_pitch3))
                elseif pui_get(anti_aim_settings[state_id].defensive_pitch1) == 'Custom' then
                    defensive_pitch_value = pui_get(anti_aim_settings[state_id].defensive_pitch2)
                elseif pui_get(anti_aim_settings[state_id].defensive_pitch1) == 'Jitter' then
                    -- Jitter between two pitch values with delay
                    if cmd.command_number % pui_get(anti_aim_settings[state_id].defensive_pitch_delay) + 1 > pui_get(anti_aim_settings[state_id].defensive_pitch_delay) - 1 then
                        defensive_pitch_jitter = not defensive_pitch_jitter
                    end
                    
                    if defensive_pitch_jitter then
                        defensive_pitch_value = pui_get(anti_aim_settings[state_id].defensive_pitch2)
                    else
                        defensive_pitch_value = pui_get(anti_aim_settings[state_id].defensive_pitch3)
                    end
                end
                
                -- Apply defensive pitch directly to cmd
                cmd.pitch = defensive_pitch_value
            end

            if pui_get(anti_aim_settings[state_id].defensive_yaw) then
                -- Don't change yaw jitter and body yaw settings, only apply yaw directly to cmd
                local defensive_yaw_value = 0
                local spin_speed = pui_get(anti_aim_settings[state_id].defensive_spin_speed) or 15
                local random_speed = pui_get(anti_aim_settings[state_id].defensive_random_speed) or 5
                
                if pui_get(anti_aim_settings[state_id].defensive_yaw1) == '180' then
                    defensive_yaw_value = pui_get(anti_aim_settings[state_id].defensive_yaw2)
                elseif pui_get(anti_aim_settings[state_id].defensive_yaw1) == 'Spin' then
                    -- Smooth continuous spin - accumulate angle each tick
                    last_spin_angle = last_spin_angle + spin_speed
                    -- Normalize to -180 to 180 range
                    while last_spin_angle > 180 do
                        last_spin_angle = last_spin_angle - 360
                    end
                    while last_spin_angle < -180 do
                        last_spin_angle = last_spin_angle + 360
                    end
                    defensive_yaw_value = last_spin_angle + pui_get(anti_aim_settings[state_id].defensive_yaw2)
                elseif pui_get(anti_aim_settings[state_id].defensive_yaw1) == '180 Z' then
                    defensive_yaw_value = cmd.command_number % 3 == 0 and pui_get(anti_aim_settings[state_id].defensive_yaw2) or -pui_get(anti_aim_settings[state_id].defensive_yaw2)
                elseif pui_get(anti_aim_settings[state_id].defensive_yaw1) == 'Sideways' then
                    -- Configurable delay for Sideways
                    if cmd.command_number % pui_get(anti_aim_settings[state_id].defensive_yaw_delay) >= pui_get(anti_aim_settings[state_id].defensive_yaw_delay) / 2 then
                        defensive_yaw_value = math.random(85, 100)
                    else
                        defensive_yaw_value = math.random(-100, -85)
                    end
                elseif pui_get(anti_aim_settings[state_id].defensive_yaw1) == 'Random' then
                    -- Random changes every N ticks based on random_speed
                    -- Check if it's time to update the random value
                    if random_yaw_update_tick == 0 or (cmd.command_number - random_yaw_update_tick) >= random_speed then
                        last_random_yaw = math.random(-180, 180)
                        random_yaw_update_tick = cmd.command_number
                    end
                    defensive_yaw_value = last_random_yaw
                elseif pui_get(anti_aim_settings[state_id].defensive_yaw1) == 'Jitter' then
                    -- Jitter between two yaw values with delay
                    if cmd.command_number % pui_get(anti_aim_settings[state_id].defensive_yaw_delay) + 1 > pui_get(anti_aim_settings[state_id].defensive_yaw_delay) - 1 then
                        defensive_yaw_jitter = not defensive_yaw_jitter
                    end
                    
                    if defensive_yaw_jitter then
                        defensive_yaw_value = pui_get(anti_aim_settings[state_id].defensive_yaw2)
                    else
                        defensive_yaw_value = pui_get(anti_aim_settings[state_id].defensive_yaw3)
                    end
                end
                
                -- Set defensive yaw relative to base_yaw (where character is facing after normal AA)
                -- NOT adding to cmd.yaw, but setting it relative to saved base_yaw
                cmd.yaw = base_yaw + defensive_yaw_value
            end
        end
    end
    
    -- Update defensive state tracking
    if not is_defensive_active then
        defensive_start_tick = 0
        random_yaw_update_tick = 0
    end
    last_defensive_state = is_defensive_active

    -- Safe head in air
    if ui.get(settings.safe_head_in_air) and (cmd.in_jump == 1 or bit.band(entity.get_prop(self, 'm_fFlags'), 1) == 0) and entity.get_prop(self, 'm_flDuckAmount') > 0.8 and (entity.get_classname(entity.get_player_weapon(self)) == 'CKnife' or entity.get_classname(entity.get_player_weapon(self)) == 'CWeaponTaser') and anti_aim_on_use == false and not (direction == 180 or direction == 90 or direction == -90) then
        ui.set(reference.pitch[1], 'Down')
        ui.set(reference.yaw[1], '180')
        ui.set(reference.yaw[2], 0)
        ui.set(reference.yaw_jitter[1], 'Off')
        ui.set(reference.body_yaw[1], 'Off')
        ui.set(reference.roll, 0)
    end

    -- Edge yaw
    ui.set(reference.edge_yaw, ui.get(settings.edge_yaw) and anti_aim_on_use == false and true or false)

    -- Freestanding
    local freestanding_conditions = ui.get(settings.freestanding_conditions)
    if ui.get(settings.freestanding) and ((contains(freestanding_conditions, 'Standing') and freestanding_state_id == 1) or (contains(freestanding_conditions, 'Moving') and freestanding_state_id == 2) or (contains(freestanding_conditions, 'Slow motion') and freestanding_state_id == 3) or (contains(freestanding_conditions, 'Crouching') and freestanding_state_id == 4) or (contains(freestanding_conditions, 'In air') and freestanding_state_id == 5)) and anti_aim_on_use == false and not (direction == 180 or direction == 90 or direction == -90) then
        ui.set(reference.freestanding[1], true)
        ui.set(reference.freestanding[2], 'Always on')

        if contains(ui.get(settings.tweaks), 'Off jitter while freestanding') then
            ui.set(reference.yaw[1], '180')
            ui.set(reference.yaw[2], 0)
            ui.set(reference.yaw_jitter[1], 'Off')
            ui.set(reference.body_yaw[1], 'Opposite')
            ui.set(reference.body_yaw[2], 0)
            ui.set(reference.freestanding_body_yaw, true)
        end
    else
        ui.set(reference.freestanding[1], false)
        ui.set(reference.freestanding[2], 'On hotkey')
    end

    -- Avoid backstab
    if ui.get(settings.avoid_backstab) and anti_aim_on_use == false and not (direction == 180 or direction == 90 or direction == -90) then
        local players = entity.get_players(true)
        if players ~= nil then
            for i, enemy in pairs(players) do
                for h = 0, 18 do
                    local head_x, head_y, head_z = entity.hitbox_position(players[i], h)
                    local wx, wy = renderer.world_to_screen(head_x, head_y, head_z)
                    local fractions, entindex_hit = client.trace_line(self, eye_x, eye_y, eye_z, head_x, head_y, head_z)

                    if 250 >= vector(entity.get_prop(enemy, 'm_vecOrigin')):dist(vector(entity.get_prop(self, 'm_vecOrigin'))) and entity.is_alive(enemy) and entity.get_player_weapon(enemy) ~= nil and entity.get_classname(entity.get_player_weapon(enemy)) == 'CKnife' and (entindex_hit == players[i] or fractions == 1) and not entity.is_dormant(players[i]) then
                        ui.set(reference.yaw[1], '180')
                        ui.set(reference.yaw[2], -180)
                    end
                end
            end
        end
    end
    
    -- Animation breakers
    -- Handled in pre_render callback
    
    -- Prevent shooting while dragging damage indicator
    if damage_indicator_vars.dragging then
        cmd.in_attack = 0
    end
end)

-- Animation breakers (from embertrash)
client.set_event_callback("pre_render", function()
    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then return end
    
    local animations = ui.get(settings.anim_breakers)
    if not animations or #animations == 0 then 
        ui.set(reference.leg_movement, "Off")
        return 
    end
    
    local flags = entity.get_prop(me, "m_fFlags")
    local is_on_ground = bit.band(flags, 1) == 1
    
    local first_velocity, second_velocity = entity.get_prop(me, 'm_vecVelocity')
    local speed = math.floor(math.sqrt(first_velocity^2 + second_velocity^2))
    
    -- Update ground ticks
    if is_on_ground then
        ground_ticks = ground_ticks + 1
    else
        ground_ticks = 0
    end
    
    -- Static legs
    if contains(animations, "Static legs") then
        entity.set_prop(me, 'm_flPoseParameter', 1, is_on_ground and speed > 5 and 0 or 6)
        ui.set(reference.leg_movement, "Always slide")
    end
    
    -- Leg fucker (Alternative jitter from embertrash)
    if contains(animations, "Leg fucker") then
        ui.set(reference.leg_movement, globals.tickcount() % 3 == 0 and "Off" or "Always slide")
        entity.set_prop(me, 'm_flPoseParameter', 1, globals.tickcount() % 4 > 1 and 0.5 or 1)
        if is_on_ground and speed < 5 then
            entity.set_prop(me, 'm_flPoseParameter', math.random(40, 80) / 100, 7)
        end
    end
    
    -- 0 pitch on landing
    if contains(animations, "0 pitch on landing") then
        if ground_ticks > 24 and ground_ticks < 150 then
            entity.set_prop(me, 'm_flPoseParameter', 0.5, 12)
        end
    end
    
    -- Earthquake (body lean)
    if contains(animations, "Earthquake") then
        entity.set_prop(me, 'm_flPoseParameter', 0, 2)
    end
end)

-- Paint UI callback
client.set_event_callback('paint_ui', function()
    if entity.get_local_player() == nil then cheked_ticks = 0 end
    
    -- Show registration UI if not registered
    if not user_registered then
        -- Update animated label for registration
        local text = "A I M P L A Y"
        local r1, g1, b1, a1 = ui.get(settings.label_color1)
        local r2, g2, b2, a2 = ui.get(settings.label_color2)
        local highlight_fraction = (globals.realtime() / 2 % 1.2 * 2) - 1.2
        local output = ""
        
        for idx = 1, #text do
            local character = text:sub(idx, idx)
            local character_fraction = idx / #text
            local r, g, b = r1, g1, b1
            local highlight_delta = (character_fraction - highlight_fraction)
            
            if highlight_delta >= 0 and highlight_delta <= 1.4 then
                if highlight_delta > 0.7 then
                    highlight_delta = 1.4 - highlight_delta
                end
                local r_fraction, g_fraction, b_fraction = r2 - r1, g2 - g1, b2 - b1
                r = r1 + r_fraction * highlight_delta / 0.8
                g = g1 + g_fraction * highlight_delta / 0.8
                b = b1 + b_fraction * highlight_delta / 0.8
            end
            
            output = output .. ('\a%02x%02x%02x%02x%s'):format(r, g, b, 255, character)
        end
        
        ui.set(settings.reg_animated, output)
        
        ui.set_visible(settings.reg_animated, true)
        ui.set_visible(settings.reg_welcome, true)
        ui.set_visible(settings.reg_nickname, true)
        ui.set_visible(settings.reg_button, true)
        
        -- Hide ALL main UI elements (with safety checks)
        if settings.animated_label then ui.set_visible(settings.animated_label, false) end
        if settings.label_color1 then ui.set_visible(settings.label_color1, false) end
        if settings.label_color2 then ui.set_visible(settings.label_color2, false) end
        if settings.tab_selection then ui.set_visible(settings.tab_selection, false) end
        if settings.separator_line then ui.set_visible(settings.separator_line, false) end
        if settings.antiaim_subtab then ui.set_visible(settings.antiaim_subtab, false) end
        if settings.visual_subtab then ui.set_visible(settings.visual_subtab, false) end
        if settings.misc_subtab then ui.set_visible(settings.misc_subtab, false) end
        if settings.info_welcome then ui.set_visible(settings.info_welcome, false) end
        if settings.info_kills then ui.set_visible(settings.info_kills, false) end
        if settings.info_deaths then ui.set_visible(settings.info_deaths, false) end
        if settings.info_kd then ui.set_visible(settings.info_kd, false) end
        if settings.info_misses then ui.set_visible(settings.info_misses, false) end
        if settings.info_playtime then ui.set_visible(settings.info_playtime, false) end
        if settings.info_reset then ui.set_visible(settings.info_reset, false) end
        if settings.aa_builder_enable then ui.set_visible(settings.aa_builder_enable, false) end
        if settings.anti_aim_state then ui.set_visible(settings.anti_aim_state, false) end
        if settings.avoid_backstab then ui.set_visible(settings.avoid_backstab, false) end
        if settings.safe_head_in_air then ui.set_visible(settings.safe_head_in_air, false) end
        if settings.manual_forward then ui.set_visible(settings.manual_forward, false) end
        if settings.manual_right then ui.set_visible(settings.manual_right, false) end
        if settings.manual_left then ui.set_visible(settings.manual_left, false) end
        if settings.edge_yaw then ui.set_visible(settings.edge_yaw, false) end
        if settings.freestanding then ui.set_visible(settings.freestanding, false) end
        if settings.freestanding_conditions then ui.set_visible(settings.freestanding_conditions, false) end
        if settings.tweaks then ui.set_visible(settings.tweaks, false) end
        if settings.warmup_disabler then ui.set_visible(settings.warmup_disabler, false) end
        if settings.separator_line_2 then ui.set_visible(settings.separator_line_2, false) end
        
        -- Hide default AA elements
        ui.set_visible(reference.aa_enabled, false)
        ui.set_visible(reference.pitch[1], false)
        ui.set_visible(reference.pitch[2], false)
        ui.set_visible(reference.yaw_base, false)
        ui.set_visible(reference.yaw[1], false)
        ui.set_visible(reference.yaw[2], false)
        ui.set_visible(reference.yaw_jitter[1], false)
        ui.set_visible(reference.yaw_jitter[2], false)
        ui.set_visible(reference.body_yaw[1], false)
        ui.set_visible(reference.body_yaw[2], false)
        ui.set_visible(reference.freestanding_body_yaw, false)
        ui.set_visible(reference.edge_yaw, false)
        ui.set_visible(reference.freestanding[1], false)
        ui.set_visible(reference.freestanding[2], false)
        ui.set_visible(reference.roll, false)
        ui.set_visible(reference.other_on_shot[1], false)
        ui.set_visible(reference.other_on_shot[2], false)
        ui.set_visible(reference.other_slow_motion[1], false)
        ui.set_visible(reference.other_slow_motion[2], false)
        ui.set_visible(reference.other_leg_movement, false)
        -- Don't hide duck peek assist - it should always be visible
        ui.set_visible(reference.other_fake_peek[1], false)
        ui.set_visible(reference.other_fake_peek[2], false)
        
        -- Hide fake lag elements
        ui.set_visible(reference.fake_lag_enabled, false)
        ui.set_visible(reference.fake_lag_amount, false)
        ui.set_visible(reference.fake_lag_variance, false)
        ui.set_visible(reference.fake_lag_limit, false)
        
        -- Hide all state settings (using PUI :set_visible())
        if anti_aim_settings then
            for i = 1, #anti_aim_states do
                if anti_aim_settings[i] then
                    if anti_aim_settings[i].override_state then pui_set_visible(anti_aim_settings[i].override_state, false) end
                    if anti_aim_settings[i].pitch1 then pui_set_visible(anti_aim_settings[i].pitch1, false) end
                    if anti_aim_settings[i].pitch2 then pui_set_visible(anti_aim_settings[i].pitch2, false) end
                    if anti_aim_settings[i].yaw_base then pui_set_visible(anti_aim_settings[i].yaw_base, false) end
                    if anti_aim_settings[i].yaw1 then pui_set_visible(anti_aim_settings[i].yaw1, false) end
                    if anti_aim_settings[i].yaw2_left then pui_set_visible(anti_aim_settings[i].yaw2_left, false) end
                    if anti_aim_settings[i].yaw2_right then pui_set_visible(anti_aim_settings[i].yaw2_right, false) end
                    if anti_aim_settings[i].yaw2_randomize then pui_set_visible(anti_aim_settings[i].yaw2_randomize, false) end
                    if anti_aim_settings[i].yaw_jitter1 then pui_set_visible(anti_aim_settings[i].yaw_jitter1, false) end
                    if anti_aim_settings[i].yaw_jitter2_left then pui_set_visible(anti_aim_settings[i].yaw_jitter2_left, false) end
                    if anti_aim_settings[i].yaw_jitter2_right then pui_set_visible(anti_aim_settings[i].yaw_jitter2_right, false) end
                    if anti_aim_settings[i].yaw_jitter2_randomize then pui_set_visible(anti_aim_settings[i].yaw_jitter2_randomize, false) end
                    if anti_aim_settings[i].yaw_jitter2_delay then pui_set_visible(anti_aim_settings[i].yaw_jitter2_delay, false) end
                    if anti_aim_settings[i].yaw_jitter2_delay_randomize then pui_set_visible(anti_aim_settings[i].yaw_jitter2_delay_randomize, false) end
                    if anti_aim_settings[i].body_yaw1 then pui_set_visible(anti_aim_settings[i].body_yaw1, false) end
                    if anti_aim_settings[i].body_yaw2 then pui_set_visible(anti_aim_settings[i].body_yaw2, false) end
                    if anti_aim_settings[i].freestanding_body_yaw then pui_set_visible(anti_aim_settings[i].freestanding_body_yaw, false) end
                    if anti_aim_settings[i].roll then pui_set_visible(anti_aim_settings[i].roll, false) end
                    if anti_aim_settings[i].force_defensive then pui_set_visible(anti_aim_settings[i].force_defensive, false) end
                    if anti_aim_settings[i].defensive_anti_aimbot then pui_set_visible(anti_aim_settings[i].defensive_anti_aimbot, false) end
                    if anti_aim_settings[i].defensive_pitch then pui_set_visible(anti_aim_settings[i].defensive_pitch, false) end
                    if anti_aim_settings[i].defensive_pitch1 then pui_set_visible(anti_aim_settings[i].defensive_pitch1, false) end
                    if anti_aim_settings[i].defensive_pitch2 then pui_set_visible(anti_aim_settings[i].defensive_pitch2, false) end
                    if anti_aim_settings[i].defensive_pitch3 then pui_set_visible(anti_aim_settings[i].defensive_pitch3, false) end
                    if anti_aim_settings[i].defensive_pitch_delay then pui_set_visible(anti_aim_settings[i].defensive_pitch_delay, false) end
                    if anti_aim_settings[i].defensive_yaw then pui_set_visible(anti_aim_settings[i].defensive_yaw, false) end
                    if anti_aim_settings[i].defensive_yaw1 then pui_set_visible(anti_aim_settings[i].defensive_yaw1, false) end
                    if anti_aim_settings[i].defensive_yaw2 then pui_set_visible(anti_aim_settings[i].defensive_yaw2, false) end
                    if anti_aim_settings[i].defensive_yaw3 then pui_set_visible(anti_aim_settings[i].defensive_yaw3, false) end
                    if anti_aim_settings[i].defensive_yaw_delay then pui_set_visible(anti_aim_settings[i].defensive_yaw_delay, false) end
                end
            end
        end
        
        -- Hide Visual World settings
        if settings.fog_enable then ui.set_visible(settings.fog_enable, false) end
        if settings.fog_color then ui.set_visible(settings.fog_color, false) end
        if settings.fog_start then ui.set_visible(settings.fog_start, false) end
        if settings.fog_end then ui.set_visible(settings.fog_end, false) end
        if settings.fog_max_density then ui.set_visible(settings.fog_max_density, false) end
        if settings.bloom_enable then ui.set_visible(settings.bloom_enable, false) end
        if settings.bloom_scale then ui.set_visible(settings.bloom_scale, false) end
        if settings.auto_exposure then ui.set_visible(settings.auto_exposure, false) end
        if settings.model_ambient_min then ui.set_visible(settings.model_ambient_min, false) end
        if settings.wall_color_enable then ui.set_visible(settings.wall_color_enable, false) end
        if settings.wall_color then ui.set_visible(settings.wall_color, false) end
        if settings.color_correction_enable then ui.set_visible(settings.color_correction_enable, false) end
        if settings.color_correction_color then ui.set_visible(settings.color_correction_color, false) end
        
        -- Hide Ragebot Advanced Panel settings
        if settings.advanced_panel_enabled then ui.set_visible(settings.advanced_panel_enabled, false) end
        if settings.advanced_panel_accent_color then ui.set_visible(settings.advanced_panel_accent_color, false) end
        if settings.minimum_damage_indicator then ui.set_visible(settings.minimum_damage_indicator, false) end
        if settings.crosshair_indicator then ui.set_visible(settings.crosshair_indicator, false) end
        if settings.watermark_enable then ui.set_visible(settings.watermark_enable, false) end
        if settings.watermark_elements then ui.set_visible(settings.watermark_elements, false) end
        if settings.watermark_bg_color then ui.set_visible(settings.watermark_bg_color, false) end
        if settings.watermark_border_color then ui.set_visible(settings.watermark_border_color, false) end
        if settings.watermark_x then ui.set_visible(settings.watermark_x, false) end
        if settings.watermark_y then ui.set_visible(settings.watermark_y, false) end
        if settings.hitlogs_enable then ui.set_visible(settings.hitlogs_enable, false) end
        if settings.hitlogs_position then ui.set_visible(settings.hitlogs_position, false) end
        if settings.hitlogs_y_offset then ui.set_visible(settings.hitlogs_y_offset, false) end
        if settings.fps_boosters then ui.set_visible(settings.fps_boosters, false) end
        if settings.anim_breakers then ui.set_visible(settings.anim_breakers, false) end
        if settings.config_label_1 then ui.set_visible(settings.config_label_1, false) end
        if settings.config_line_1 then ui.set_visible(settings.config_line_1, false) end
        if settings.config_list then ui.set_visible(settings.config_list, false) end
        if settings.config_label_2 then ui.set_visible(settings.config_label_2, false) end
        if settings.config_line_2 then ui.set_visible(settings.config_line_2, false) end
        if settings.config_name then ui.set_visible(settings.config_name, false) end
        if settings.config_create then ui.set_visible(settings.config_create, false) end
        if settings.config_load then ui.set_visible(settings.config_load, false) end
        if settings.config_save then ui.set_visible(settings.config_save, false) end
        if settings.config_delete then ui.set_visible(settings.config_delete, false) end
        if settings.config_import then ui.set_visible(settings.config_import, false) end
        if settings.config_export then ui.set_visible(settings.config_export, false) end
        
        -- Hide breadcrumb
        if settings.breadcrumb then ui.set_visible(settings.breadcrumb, false) end
        if settings.breadcrumb_line then ui.set_visible(settings.breadcrumb_line, false) end
        
        return
    end
    
    -- Hide registration UI
    ui.set_visible(settings.reg_animated, false)
    ui.set_visible(settings.reg_welcome, false)
    ui.set_visible(settings.reg_nickname, false)
    ui.set_visible(settings.reg_button, false)

    -- Update animated label
    local text = "A I M P L A Y"
    local r1, g1, b1, a1 = ui.get(settings.label_color1)
    local r2, g2, b2, a2 = ui.get(settings.label_color2)
    local highlight_fraction = (globals.realtime() / 2 % 1.2 * 2) - 1.2
    local output = ""
    
    for idx = 1, #text do
        local character = text:sub(idx, idx)
        local character_fraction = idx / #text
        local r, g, b = r1, g1, b1
        local highlight_delta = (character_fraction - highlight_fraction)
        
        if highlight_delta >= 0 and highlight_delta <= 1.4 then
            if highlight_delta > 0.7 then
                highlight_delta = 1.4 - highlight_delta
            end
            local r_fraction, g_fraction, b_fraction = r2 - r1, g2 - g1, b2 - b1
            r = r1 + r_fraction * highlight_delta / 0.8
            g = g1 + g_fraction * highlight_delta / 0.8
            b = b1 + b_fraction * highlight_delta / 0.8
        end
        
        output = output .. ('\a%02x%02x%02x%02x%s'):format(r, g, b, 255, character)
    end
    
    ui.set(settings.animated_label, output)
    
    -- Update separator line with color 2
    local r2, g2, b2, a2 = ui.get(settings.label_color2)
    local separator_line = ('\a%02x%02x%02x%02x━━━━━━━━━━━━━━━━━━━━━━━━━'):format(r2, g2, b2, 255)
    ui.set(settings.separator_line, separator_line)
    ui.set(settings.separator_line_2, separator_line)

    local current_tab = ui.get(settings.tab_selection)
    
    -- Update breadcrumb for all tabs
    local r2, g2, b2, a2 = ui.get(settings.label_color2)
    local tab_name = current_tab:gsub("^ ", "")  -- Remove leading space
    local breadcrumb_text = ""
    local line_text = ('\a%02x%02x%02x%02x━━━━━━━━━━━━━━━━━━━━━━━━━'):format(r2, g2, b2, 255)
    
    -- Create breadcrumb based on current tab (tab name always white)
    if current_tab == ' Anti-Aim' then
        local subtab = ui.get(settings.antiaim_subtab):gsub("^ ", "")
        breadcrumb_text = string.format('\aFFFFFFFFAnti-Aim \a%02x%02x%02x%02x/ \aFFFFFFFF%s', r2, g2, b2, 255, subtab)
    elseif current_tab == ' Visual' then
        local subtab = ui.get(settings.visual_subtab):gsub("^ ", "")
        breadcrumb_text = string.format('\aFFFFFFFFVisual \a%02x%02x%02x%02x/ \aFFFFFFFF%s', r2, g2, b2, 255, subtab)
    elseif current_tab == ' Misc' then
        local subtab = ui.get(settings.misc_subtab):gsub("^ ", "")
        breadcrumb_text = string.format('\aFFFFFFFFMisc \a%02x%02x%02x%02x/ \aFFFFFFFF%s', r2, g2, b2, 255, subtab)
    else
        -- For tabs without subtabs, show tab name in white
        breadcrumb_text = ('\aFFFFFFFF%s'):format(tab_name)
    end
    
    ui.set(settings.breadcrumb, breadcrumb_text)
    ui.set(settings.breadcrumb_line, line_text)
    
    -- Update statistics in Information tab
    if current_tab == ' Information' then
        local current_session = globals.realtime() - stats.start_time
        local total_time = stats.total_playtime + current_session
        local minutes = math.floor(total_time / 60)
        local seconds = math.floor(total_time % 60)
        local kd_ratio = stats.deaths > 0 and (stats.kills / stats.deaths) or stats.kills
        
        ui.set(settings.info_kills, string.format('\aFFFFFFFFKills: \a%02x%02x%02xFF%d', r2, g2, b2, stats.kills))
        ui.set(settings.info_deaths, string.format('\aFFFFFFFFDeaths: \a%02x%02x%02xFF%d', r2, g2, b2, stats.deaths))
        ui.set(settings.info_kd, string.format('\aFFFFFFFFK/D Ratio: \a%02x%02x%02xFF%.2f', r2, g2, b2, kd_ratio))
        ui.set(settings.info_misses, string.format('\aFFFFFFFFMisses on you: \a%02x%02x%02xFF%d', r2, g2, b2, stats.misses))
        ui.set(settings.info_playtime, string.format('\aFFFFFFFFPlaytime: \a%02x%02x%02xFF%dm %ds', r2, g2, b2, minutes, seconds))
    end
    
    -- Periodic save every 30 seconds
    if globals.realtime() - last_save_time > 30 then
        save_stats()
        last_save_time = globals.realtime()
    end
    
    local antiaim_subtab = ui.get(settings.antiaim_subtab)
    local builder_enabled = ui.get(settings.aa_builder_enable)
    
    -- Update welcome message with nickname
    ui.set(settings.info_welcome, string.format('\aFFFFFFFFWelcome back, \a%02x%02x%02xFF%s\aFFFFFFFF!', r2, g2, b2, user_nickname))
    
    local visual_subtab = ui.get(settings.visual_subtab)
    
    if ui.is_menu_open() then
        -- Show/hide subtabs
        ui.set_visible(settings.antiaim_subtab, current_tab == ' Anti-Aim')
        ui.set_visible(settings.visual_subtab, current_tab == ' Visual')
        ui.set_visible(settings.misc_subtab, current_tab == ' Misc')
        
        -- Show breadcrumb and line in all tabs
        ui.set_visible(settings.breadcrumb, true)
        ui.set_visible(settings.breadcrumb_line, true)
    end
    
    -- Show/hide Visual World settings
    local show_visual_world = current_tab == ' Visual' and visual_subtab == ' World'
    local bloom_enabled = ui.get(settings.bloom_enable)
    
    ui.set_visible(settings.fog_enable, show_visual_world)
    ui.set_visible(settings.fog_color, show_visual_world and ui.get(settings.fog_enable))
    ui.set_visible(settings.fog_start, show_visual_world and ui.get(settings.fog_enable))
    ui.set_visible(settings.fog_end, show_visual_world and ui.get(settings.fog_enable))
    ui.set_visible(settings.fog_max_density, show_visual_world and ui.get(settings.fog_enable))
    ui.set_visible(settings.bloom_enable, show_visual_world)
    ui.set_visible(settings.bloom_scale, show_visual_world and bloom_enabled)
    ui.set_visible(settings.auto_exposure, show_visual_world and bloom_enabled)
    ui.set_visible(settings.model_ambient_min, show_visual_world and bloom_enabled)
    ui.set_visible(settings.wall_color_enable, show_visual_world)
    ui.set_visible(settings.wall_color, show_visual_world and ui.get(settings.wall_color_enable))
    ui.set_visible(settings.color_correction_enable, show_visual_world)
    ui.set_visible(settings.color_correction_color, show_visual_world and ui.get(settings.color_correction_enable))
    
    -- Show/hide Visual Main Advanced Panel settings
    local show_visual_main = current_tab == ' Visual' and visual_subtab == ' Main'
    ui.set_visible(settings.advanced_panel_enabled, show_visual_main)
    ui.set_visible(settings.advanced_panel_accent_color, show_visual_main and ui.get(settings.advanced_panel_enabled))
    ui.set_visible(settings.minimum_damage_indicator, show_visual_main)
    ui.set_visible(settings.crosshair_indicator, show_visual_main)
    
    -- Show/hide Watermark settings
    ui.set_visible(settings.watermark_enable, show_visual_main)
    local watermark_enabled = show_visual_main and ui.get(settings.watermark_enable)
    ui.set_visible(settings.watermark_elements, watermark_enabled)
    ui.set_visible(settings.watermark_bg_color, watermark_enabled)
    ui.set_visible(settings.watermark_border_color, watermark_enabled)
    ui.set_visible(settings.watermark_x, watermark_enabled)
    ui.set_visible(settings.watermark_y, watermark_enabled)
    
    -- Show/hide Hit Logs settings
    ui.set_visible(settings.hitlogs_enable, show_visual_main)
    local hitlogs_enabled = show_visual_main and ui.get(settings.hitlogs_enable)
    ui.set_visible(settings.hitlogs_position, hitlogs_enabled)
    ui.set_visible(settings.hitlogs_y_offset, hitlogs_enabled and ui.get(settings.hitlogs_position) == "Center")
    
    -- Show/hide Misc settings
    local show_misc = current_tab == ' Misc' and ui.get(settings.misc_subtab) == ' Main'
    ui.set_visible(settings.fps_boosters, show_misc)
    ui.set_visible(settings.anim_breakers, show_misc)
    
    -- Show/hide Config settings
    local show_config = current_tab == ' Configuration'
    ui.set_visible(settings.config_label_1, show_config)
    ui.set_visible(settings.config_line_1, show_config)
    ui.set_visible(settings.config_list, show_config)
    ui.set_visible(settings.config_label_2, show_config)
    ui.set_visible(settings.config_line_2, show_config)
    ui.set_visible(settings.config_name, show_config)
    ui.set_visible(settings.config_create, show_config)
    ui.set_visible(settings.config_load, show_config)
    ui.set_visible(settings.config_save, show_config)
    ui.set_visible(settings.config_delete, show_config)
    ui.set_visible(settings.config_import, show_config)
    ui.set_visible(settings.config_export, show_config)
    
    -- Show/hide Information tab elements (always visible when in Information tab)
    local show_info = current_tab == ' Information'
    ui.set_visible(settings.info_welcome, show_info)
    ui.set_visible(settings.info_kills, show_info)
    ui.set_visible(settings.info_deaths, show_info)
    ui.set_visible(settings.info_kd, show_info)
    ui.set_visible(settings.info_misses, show_info)
    ui.set_visible(settings.info_playtime, show_info)
    ui.set_visible(settings.info_reset, show_info)
    
    if ui.is_menu_open() then
        -- Hide default AA Enabled checkbox
        ui.set_visible(reference.aa_enabled, false)
        
        -- Show/hide AA Other tab elements (only visible in Other subtab)
        local show_other = current_tab == ' Anti-Aim' and antiaim_subtab == ' Other'
        ui.set_visible(reference.other_on_shot[1], show_other)
        ui.set_visible(reference.other_on_shot[2], show_other)
        ui.set_visible(reference.other_slow_motion[1], show_other)
        ui.set_visible(reference.other_slow_motion[2], show_other)
        ui.set_visible(reference.other_leg_movement, show_other)
        -- Duck peek assist is always visible, don't manage it
        ui.set_visible(reference.other_fake_peek[1], show_other)
        ui.set_visible(reference.other_fake_peek[2], show_other)
        
        -- Show/hide AA Builder enable checkbox
        ui.set_visible(settings.aa_builder_enable, current_tab == ' Anti-Aim' and antiaim_subtab == ' Builder')
        
        -- Always hide default AA elements
        ui.set_visible(reference.pitch[1], false)
        ui.set_visible(reference.pitch[2], false)
        ui.set_visible(reference.yaw_base, false)
        ui.set_visible(reference.yaw[1], false)
        ui.set_visible(reference.yaw[2], false)
        ui.set_visible(reference.yaw_jitter[1], false)
        ui.set_visible(reference.yaw_jitter[2], false)
        ui.set_visible(reference.body_yaw[1], false)
        ui.set_visible(reference.body_yaw[2], false)
        ui.set_visible(reference.freestanding_body_yaw, false)
        ui.set_visible(reference.edge_yaw, false)
        ui.set_visible(reference.freestanding[1], false)
        ui.set_visible(reference.freestanding[2], false)
        ui.set_visible(reference.roll, false)
        
        -- Always hide fake lag elements
        ui.set_visible(reference.fake_lag_enabled, false)
        ui.set_visible(reference.fake_lag_amount, false)
        ui.set_visible(reference.fake_lag_variance, false)
        ui.set_visible(reference.fake_lag_limit, false)
        
        -- Anti-Aim Builder tab
        local show_builder = current_tab == ' Anti-Aim' and antiaim_subtab == ' Builder' and builder_enabled
        ui.set_visible(settings.anti_aim_state, show_builder)
        ui.set_visible(settings.avoid_backstab, show_builder)
        ui.set_visible(settings.safe_head_in_air, show_builder)
        ui.set_visible(settings.manual_forward, show_builder)
        ui.set_visible(settings.manual_right, show_builder)
        ui.set_visible(settings.manual_left, show_builder)
        ui.set_visible(settings.edge_yaw, show_builder)
        ui.set_visible(settings.freestanding, show_builder)
        ui.set_visible(settings.separator_line_2, show_builder)
        ui.set_visible(settings.warmup_disabler, show_builder)
        ui.set_visible(settings.freestanding_conditions, show_builder)
        ui.set_visible(settings.tweaks, show_builder)
        
        -- Show/hide custom fake lag elements in Other tab (but in Anti-aimbot angles section)
        local show_fakelag = current_tab == ' Anti-Aim' and antiaim_subtab == ' Other'
        ui.set_visible(settings.fakelag_enabled, show_fakelag)
        ui.set_visible(settings.fakelag_amount, show_fakelag and ui.get(settings.fakelag_enabled))
        ui.set_visible(settings.fakelag_variance, show_fakelag and ui.get(settings.fakelag_enabled))
        ui.set_visible(settings.fakelag_limit, show_fakelag and ui.get(settings.fakelag_enabled))

        for i = 1, #anti_aim_states do
            local show_state = show_builder and ui.get(settings.anti_aim_state) == anti_aim_states[i]
            pui_set_visible(anti_aim_settings[i].override_state, show_state)
            pui_set(anti_aim_settings[1].override_state, true)
            pui_set_visible(anti_aim_settings[1].override_state, false)
            pui_set_visible(anti_aim_settings[i].force_defensive, show_state)
            pui_set_visible(anti_aim_settings[9].force_defensive, false)
            pui_set_visible(anti_aim_settings[i].pitch1, show_state)
            pui_set_visible(anti_aim_settings[i].pitch2, show_state and pui_get(anti_aim_settings[i].pitch1) == 'Custom')
            pui_set_visible(anti_aim_settings[i].yaw_base, show_state)
            pui_set_visible(anti_aim_settings[i].yaw1, show_state)
            pui_set_visible(anti_aim_settings[i].yaw2_left, show_state and pui_get(anti_aim_settings[i].yaw1) ~= 'Off' and pui_get(anti_aim_settings[i].yaw_jitter1) ~= 'Delay')
            pui_set_visible(anti_aim_settings[i].yaw2_right, show_state and pui_get(anti_aim_settings[i].yaw1) ~= 'Off' and pui_get(anti_aim_settings[i].yaw_jitter1) ~= 'Delay')
            pui_set_visible(anti_aim_settings[i].yaw2_randomize, show_state and pui_get(anti_aim_settings[i].yaw1) ~= 'Off' and pui_get(anti_aim_settings[i].yaw_jitter1) ~= 'Delay')
            pui_set_visible(anti_aim_settings[i].yaw_jitter1, show_state and pui_get(anti_aim_settings[i].yaw1) ~= 'Off')
            pui_set_visible(anti_aim_settings[i].yaw_jitter2_left, show_state and pui_get(anti_aim_settings[i].yaw1) ~= 'Off' and pui_get(anti_aim_settings[i].yaw_jitter1) ~= 'Off')
            pui_set_visible(anti_aim_settings[i].yaw_jitter2_left, show_state and pui_get(anti_aim_settings[i].yaw1) ~= 'Off' and pui_get(anti_aim_settings[i].yaw_jitter1) ~= 'Off')
            pui_set_visible(anti_aim_settings[i].yaw_jitter2_right, show_state and pui_get(anti_aim_settings[i].yaw1) ~= 'Off' and pui_get(anti_aim_settings[i].yaw_jitter1) ~= 'Off')
            pui_set_visible(anti_aim_settings[i].yaw_jitter2_randomize, show_state and pui_get(anti_aim_settings[i].yaw1) ~= 'Off' and pui_get(anti_aim_settings[i].yaw_jitter1) ~= 'Off')
            pui_set_visible(anti_aim_settings[i].yaw_jitter2_delay, show_state and pui_get(anti_aim_settings[i].yaw1) ~= 'Off' and pui_get(anti_aim_settings[i].yaw_jitter1) == 'Delay')
            pui_set_visible(anti_aim_settings[i].body_yaw1, show_state and pui_get(anti_aim_settings[i].yaw_jitter1) ~= 'Delay')
            pui_set_visible(anti_aim_settings[i].body_yaw2, show_state and (pui_get(anti_aim_settings[i].body_yaw1) ~= 'Off' and pui_get(anti_aim_settings[i].body_yaw1) ~= 'Opposite') and pui_get(anti_aim_settings[i].yaw_jitter1) ~= 'Delay')
            pui_set_visible(anti_aim_settings[i].freestanding_body_yaw, show_state and pui_get(anti_aim_settings[i].body_yaw1) ~= 'Off' and pui_get(anti_aim_settings[i].yaw_jitter1) ~= 'Delay')
            pui_set_visible(anti_aim_settings[i].roll, show_state)
            pui_set_visible(anti_aim_settings[i].defensive_anti_aimbot, show_state)
            pui_set_visible(anti_aim_settings[9].defensive_anti_aimbot, false)
            pui_set_visible(anti_aim_settings[i].defensive_pitch, show_state and pui_get(anti_aim_settings[i].defensive_anti_aimbot))
            pui_set_visible(anti_aim_settings[9].defensive_pitch, false)
            pui_set_visible(anti_aim_settings[i].defensive_pitch1, show_state and pui_get(anti_aim_settings[i].defensive_anti_aimbot) and pui_get(anti_aim_settings[i].defensive_pitch))
            pui_set_visible(anti_aim_settings[9].defensive_pitch1, false)
            pui_set_visible(anti_aim_settings[i].defensive_pitch2, show_state and pui_get(anti_aim_settings[i].defensive_anti_aimbot) and pui_get(anti_aim_settings[i].defensive_pitch) and (pui_get(anti_aim_settings[i].defensive_pitch1) == 'Random' or pui_get(anti_aim_settings[i].defensive_pitch1) == 'Custom' or pui_get(anti_aim_settings[i].defensive_pitch1) == 'Jitter'))
            pui_set_visible(anti_aim_settings[9].defensive_pitch2, false)
            pui_set_visible(anti_aim_settings[i].defensive_pitch3, show_state and pui_get(anti_aim_settings[i].defensive_anti_aimbot) and pui_get(anti_aim_settings[i].defensive_pitch) and (pui_get(anti_aim_settings[i].defensive_pitch1) == 'Random' or pui_get(anti_aim_settings[i].defensive_pitch1) == 'Jitter'))
            pui_set_visible(anti_aim_settings[9].defensive_pitch3, false)
            pui_set_visible(anti_aim_settings[i].defensive_pitch_delay, show_state and pui_get(anti_aim_settings[i].defensive_anti_aimbot) and pui_get(anti_aim_settings[i].defensive_pitch) and pui_get(anti_aim_settings[i].defensive_pitch1) == 'Jitter')
            pui_set_visible(anti_aim_settings[9].defensive_pitch_delay, false)
            pui_set_visible(anti_aim_settings[i].defensive_yaw, show_state and pui_get(anti_aim_settings[i].defensive_anti_aimbot))
            pui_set_visible(anti_aim_settings[9].defensive_yaw, false)
            pui_set_visible(anti_aim_settings[i].defensive_yaw1, show_state and pui_get(anti_aim_settings[i].defensive_anti_aimbot) and pui_get(anti_aim_settings[i].defensive_yaw))
            pui_set_visible(anti_aim_settings[9].defensive_yaw1, false)
            pui_set_visible(anti_aim_settings[i].defensive_yaw2, show_state and pui_get(anti_aim_settings[i].defensive_anti_aimbot) and pui_get(anti_aim_settings[i].defensive_yaw) and (pui_get(anti_aim_settings[i].defensive_yaw1) == '180' or pui_get(anti_aim_settings[i].defensive_yaw1) == 'Spin' or pui_get(anti_aim_settings[i].defensive_yaw1) == '180 Z' or pui_get(anti_aim_settings[i].defensive_yaw1) == 'Jitter'))
            pui_set_visible(anti_aim_settings[9].defensive_yaw2, false)
            pui_set_visible(anti_aim_settings[i].defensive_yaw3, show_state and pui_get(anti_aim_settings[i].defensive_anti_aimbot) and pui_get(anti_aim_settings[i].defensive_yaw) and pui_get(anti_aim_settings[i].defensive_yaw1) == 'Jitter')
            pui_set_visible(anti_aim_settings[9].defensive_yaw3, false)
            pui_set_visible(anti_aim_settings[i].defensive_yaw_delay, show_state and pui_get(anti_aim_settings[i].defensive_anti_aimbot) and pui_get(anti_aim_settings[i].defensive_yaw) and (pui_get(anti_aim_settings[i].defensive_yaw1) == 'Sideways' or pui_get(anti_aim_settings[i].defensive_yaw1) == 'Jitter'))
            pui_set_visible(anti_aim_settings[9].defensive_yaw_delay, false)
            
            -- New defensive settings visibility
            pui_set_visible(anti_aim_settings[i].defensive_spin_speed, show_state and pui_get(anti_aim_settings[i].defensive_anti_aimbot) and pui_get(anti_aim_settings[i].defensive_yaw) and pui_get(anti_aim_settings[i].defensive_yaw1) == 'Spin')
            pui_set_visible(anti_aim_settings[9].defensive_spin_speed, false)
            pui_set_visible(anti_aim_settings[i].defensive_random_speed, show_state and pui_get(anti_aim_settings[i].defensive_anti_aimbot) and pui_get(anti_aim_settings[i].defensive_yaw) and pui_get(anti_aim_settings[i].defensive_yaw1) == 'Random')
            pui_set_visible(anti_aim_settings[9].defensive_random_speed, false)
            pui_set_visible(anti_aim_settings[i].defensive_activation_delay, show_state and pui_get(anti_aim_settings[i].defensive_anti_aimbot))
            pui_set_visible(anti_aim_settings[9].defensive_activation_delay, false)
        end
    end
end)

-- Net update end for defensive detection
client.set_event_callback('net_update_end', function()
    if entity.get_local_player() ~= nil then
        is_defensive_active = is_defensive(entity.get_local_player())
    end
end)

-- Warmup disabler
client.set_event_callback("setup_command", function()
    if not ui.get(settings.aa_builder_enable) then return end
    if entity.get_local_player() == nil then return end

    gamerulesproxy = entity.get_all("CCSGameRulesProxy")[1]
    warmup = entity.get_prop(gamerulesproxy,"m_bWarmupPeriod")
  
    if ui.get(settings.warmup_disabler) and warmup == 1 then
        ui.set(reference.body_yaw[1], 'Off')
        ui.set(reference.yaw[2], math.random(-180, 180))
        ui.set(reference.yaw_jitter[1], 'Random')
        ui.set(reference.pitch[1], 'Off')
    end
end)

-- Visual World helper functions
local function rgb_to_int(r, g, b)
    local function decimal_to_byte(integer)
        local bin = ''
        while integer ~= 0 do
            bin = (integer % 2 == 0 and '0' or '1') .. bin
            integer = math.floor(integer / 2)
        end
        local byte = ''
        for _ = 1, 8 - #bin do
            byte = byte .. '0'
        end
        return byte .. bin
    end
    
    local function binary_to_decimal(binary)
        binary = string.reverse(binary)
        local sum = 0
        for i = 1, #binary do
            local num = string.sub(binary, i, i) == "1" and 1 or 0
            sum = sum + num * math.pow(2, i-1)
        end
        return sum
    end
    
    return binary_to_decimal(decimal_to_byte(b) .. decimal_to_byte(g) .. decimal_to_byte(r))
end

local function reset_bloom(tone_map_controller)
    if bloom_default == -1 then
        entity.set_prop(tone_map_controller, "m_bUseCustomBloomScale", 0)
        entity.set_prop(tone_map_controller, "m_flCustomBloomScale", 0)
    else
        entity.set_prop(tone_map_controller, "m_bUseCustomBloomScale", 1)
        entity.set_prop(tone_map_controller, "m_flCustomBloomScale", bloom_default)
    end
end

local function reset_exposure(tone_map_controller)
    if exposure_min_default == -1 then
        entity.set_prop(tone_map_controller, "m_bUseCustomAutoExposureMin", 0)
        entity.set_prop(tone_map_controller, "m_flCustomAutoExposureMin", 0)
    else
        entity.set_prop(tone_map_controller, "m_bUseCustomAutoExposureMin", 1)
        entity.set_prop(tone_map_controller, "m_flCustomAutoExposureMin", exposure_min_default)
    end
    if exposure_max_default == -1 then
        entity.set_prop(tone_map_controller, "m_bUseCustomAutoExposureMax", 0)
        entity.set_prop(tone_map_controller, "m_flCustomAutoExposureMax", 0)
    else
        entity.set_prop(tone_map_controller, "m_bUseCustomAutoExposureMax", 1)
        entity.set_prop(tone_map_controller, "m_flCustomAutoExposureMax", exposure_max_default)
    end
end

-- ============================================
-- WATERMARK FUNCTIONS
-- ============================================

local function calculate_fps()
    local current_time = globals.realtime()
    watermark_vars.fps_data.frame_count = watermark_vars.fps_data.frame_count + 1
    
    if current_time - watermark_vars.fps_data.last_time >= 0.5 then
        watermark_vars.fps_data.current_fps = math.floor(watermark_vars.fps_data.frame_count / (current_time - watermark_vars.fps_data.last_time))
        watermark_vars.fps_data.frame_count = 0
        watermark_vars.fps_data.last_time = current_time
    end
    
    return watermark_vars.fps_data.current_fps
end

local function get_latency()
    local latency = client.latency()
    if latency == nil then return 0, 0 end
    return math.floor(latency * 1000), math.floor(math.random(10, 20))
end

local function get_time()
    local hours, minutes, seconds = client.system_time()
    return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

local function watermark_contains(table, element)
    for i = 1, #table do
        if table[i] == element then return true end
    end
    return false
end

local function add_hit_log(text)
    local position_mode = ui.get(settings.hitlogs_position)
    local max_logs = (position_mode == "Top Left") and max_logs_topleft or max_logs_center
    
    table.insert(hit_logs, 1, {text = text, time = globals.realtime(), alpha = 255})
    
    while #hit_logs > max_logs do
        table.remove(hit_logs)
    end
end

-- Advanced Panel paint callback
client.set_event_callback('paint', function()
    -- FPS improvements
    local fps_settings = ui.get(settings.fps_boosters)
    if fps_settings then
        mat_postprocess_enable:set_raw_int(contains(fps_settings, 'Post Processing') and 0 or 1)
        mat_vignette_enable:set_int(contains(fps_settings, 'Vignette') and 0 or 1)
        mat_bloom_scalefactor_scalar:set_int(contains(fps_settings, 'Bloom') and 0 or 1)
        cl_csm_shadows:set_int(contains(fps_settings, 'Shadows') and 0 or 1)
        r_dynamic:set_int(contains(fps_settings, 'Shadows') and 0 or 1)
        r_shadows:set_int(contains(fps_settings, 'Shadows') and 0 or 1)
        cl_csm_static_prop_shadows:set_int(contains(fps_settings, 'Shadows') and 0 or 1)
        cl_csm_world_shadows:set_int(contains(fps_settings, 'Shadows') and 0 or 1)
        cl_foot_contact_shadows:set_int(contains(fps_settings, 'Shadows') and 0 or 1)
        cl_csm_viewmodel_shadows:set_int(contains(fps_settings, 'Shadows') and 0 or 1)
        cl_csm_rope_shadows:set_int(contains(fps_settings, 'Shadows') and 0 or 1)
        cl_csm_sprite_shadows:set_int(contains(fps_settings, 'Shadows') and 0 or 1)
        cl_csm_world_shadows_in_viewmodelcascade:set_int(contains(fps_settings, 'Shadows') and 0 or 1)
        violence_ablood:set_int(contains(fps_settings, 'Blood') and 0 or 1)
        violence_hblood:set_int(contains(fps_settings, 'Blood') and 0 or 1)
        cl_disable_ragdolls:set_int(contains(fps_settings, 'Ragdolls') and 1 or 0)
        fog_enable:set_int(contains(fps_settings, 'Fog') and 0 or 1)
        fog_enable_water_fog:set_int(contains(fps_settings, 'Fog') and 0 or 1)
        fog_enableskybox:set_int(contains(fps_settings, 'Fog') and 0 or 1)
        r_3dsky:set_int(contains(fps_settings, '3D skybox') and 0 or 1)
    end
    
    -- Damage Indicator
    local min_damage_indicator = ui.get(settings.minimum_damage_indicator)
    if min_damage_indicator ~= 'Off' then
        local local_player = entity.get_local_player()
        if local_player and entity.is_alive(local_player) then
            local _x, _y = client.screen_size()
            local center_x, center_y = _x / 2, _y / 2
            
            local player_weapon = entity.get_player_weapon(local_player)
            if player_weapon then
                local player_weapon_classname = entity.get_classname(player_weapon)
                
                local grenade_and_knife_classes = {
                    CKnife = true,
                    CWeaponTaser = true,
                    CHEGrenade = true,
                    CMolotovGrenade = true,
                    CIncendiaryGrenade = true,
                    CFlashbang = true,
                    CSmokeGrenade = true,
                    CDecoyGrenade = true,
                }
                
                if not grenade_and_knife_classes[player_weapon_classname] then
                    -- Handle dragging
                    if client.key_state then
                        local mouse_pressed = client.key_state(0x01)
                        local mouse_x, mouse_y = ui.mouse_position()
                        
                        if mouse_x and mouse_y then
                            local indicator_x = center_x + damage_indicator_vars.offset_x
                            local indicator_y = center_y + damage_indicator_vars.offset_y
                            
                            local in_zone = math.abs(mouse_x - center_x) <= damage_indicator_vars.zone_size and 
                                           math.abs(mouse_y - center_y) <= damage_indicator_vars.zone_size
                            
                            if in_zone and ui.is_menu_open() then
                                local zone_x = center_x - damage_indicator_vars.zone_size
                                local zone_y = center_y - damage_indicator_vars.zone_size
                                local zone_w = damage_indicator_vars.zone_size * 2
                                local zone_h = damage_indicator_vars.zone_size * 2
                                
                                renderer.rectangle(zone_x, zone_y, zone_w, zone_h, 50, 50, 50, 100)
                                renderer.rectangle(zone_x, zone_y, zone_w, 1, 100, 100, 100, 200)
                                renderer.rectangle(zone_x, zone_y, 1, zone_h, 100, 100, 100, 200)
                                renderer.rectangle(zone_x + zone_w - 1, zone_y, 1, zone_h, 100, 100, 100, 200)
                                renderer.rectangle(zone_x, zone_y + zone_h - 1, zone_w, 1, 100, 100, 100, 200)
                            end
                            
                            local mouse_clicked = mouse_pressed and not damage_indicator_vars.mouse_was_pressed_dmg
                            damage_indicator_vars.mouse_was_pressed_dmg = mouse_pressed
                            
                            if mouse_clicked and in_zone and ui.is_menu_open() then
                                damage_indicator_vars.dragging = true
                                damage_indicator_vars.drag_offset_x = mouse_x - indicator_x
                                damage_indicator_vars.drag_offset_y = mouse_y - indicator_y
                            elseif not mouse_pressed then
                                damage_indicator_vars.dragging = false
                            end
                            
                            if damage_indicator_vars.dragging and mouse_pressed then
                                local new_x = mouse_x - damage_indicator_vars.drag_offset_x - center_x
                                local new_y = mouse_y - damage_indicator_vars.drag_offset_y - center_y
                                
                                damage_indicator_vars.offset_x = math.max(-damage_indicator_vars.zone_size, math.min(new_x, damage_indicator_vars.zone_size))
                                damage_indicator_vars.offset_y = math.max(-damage_indicator_vars.zone_size, math.min(new_y, damage_indicator_vars.zone_size))
                            end
                        end
                    end
                    
                    local damage_override_active = ui.get(reference.damage_override[1]) and ui.get(reference.damage_override[2])
                    local damage_string = min_damage_indicator == 'Always' and (damage_override_active and ui.get(reference.damage_override[3]) or ui.get(reference.damage[1]))
                            or (min_damage_indicator == 'On override' and damage_override_active and ui.get(reference.damage_override[3]) or nil)
                    
                    if damage_string ~= nil then
                        renderer.text(center_x + damage_indicator_vars.offset_x, center_y + damage_indicator_vars.offset_y, 255, 255, 255, 255, "", 0, tostring(damage_string))
                    end
                end
            end
        end
    end
    
    -- Crosshair Indicator (from senkotech) - MOVED OUTSIDE
    if ui.get(settings.crosshair_indicator) then
        local me = entity.get_local_player()
        if me and entity.is_alive(me) then
            local _x, _y = client.screen_size()
            local center_x, center_y = _x / 2, _y / 2
            
            -- Get current state
            local function get_player_state()
                local flags = entity.get_prop(me, "m_fFlags")
                local velocity = {entity.get_prop(me, "m_vecVelocity")}
                local speed = math.sqrt(velocity[1]^2 + velocity[2]^2)
                local duck_amount = entity.get_prop(me, "m_flDuckAmount")
                
                if bit.band(flags, 1) == 0 then
                    return "AIR"
                elseif duck_amount > 0.8 then
                    return "DUCK"
                elseif speed > 2 and ui.get(reference.slow_motion[1]) and ui.get(reference.slow_motion[2]) then
                    return "SLOW"
                elseif speed > 2 then
                    return "MOVE"
                else
                    return "STAND"
                end
            end
            
            local current_state = get_player_state()
            
            -- Update animations
            local target_alpha = 1.0
            local wpn = entity.get_player_weapon(me)
            if wpn then
                local wpn_type = entity.get_prop(wpn, "m_iItemDefinitionIndex")
                -- Check if grenade (43-48 are grenades)
                if wpn_type >= 43 and wpn_type <= 48 then
                    target_alpha = 0.25
                end
            end
            
            if entity.get_prop(me, "m_bIsScoped") == 1 then
                target_alpha = 0.75
                crosshair_indicator.align = lerp(crosshair_indicator.align, 1.0, 0.05)
            else
                crosshair_indicator.align = lerp(crosshair_indicator.align, 0.0, 0.05)
            end
            
            crosshair_indicator.alpha = lerp(crosshair_indicator.alpha, target_alpha, 0.05)
            
            if crosshair_indicator.alpha > 0.01 then
                -- Update feature animations
                crosshair_indicator.state_alpha = lerp(crosshair_indicator.state_alpha, 1.0, 0.05)
                crosshair_indicator.state_value = lerp(crosshair_indicator.state_value, current_state == crosshair_indicator.last_state and 1.0 or 0.0, 0.075)
                
                local dmg_override = ui.get(reference.damage_override[1]) and ui.get(reference.damage_override[2])
                crosshair_indicator.dmg_alpha = lerp(crosshair_indicator.dmg_alpha, dmg_override and 1.0 or 0.0, 0.05)
                crosshair_indicator.dmg_value = lerp(crosshair_indicator.dmg_value, 1.0, 0.05)
                
                local dt_active = ui.get(reference.double_tap[1]) and ui.get(reference.double_tap[2])
                crosshair_indicator.dt_alpha = lerp(crosshair_indicator.dt_alpha, dt_active and 1.0 or 0.0, 0.05)
                crosshair_indicator.dt_value = lerp(crosshair_indicator.dt_value, dt_active and 1.0 or 0.0, 0.05)
                
                local osaa_active = ui.get(reference.on_shot_anti_aim[1]) and ui.get(reference.on_shot_anti_aim[2])
                crosshair_indicator.osaa_alpha = lerp(crosshair_indicator.osaa_alpha, osaa_active and 1.0 or 0.0, 0.05)
                crosshair_indicator.osaa_value = lerp(crosshair_indicator.osaa_value, osaa_active and 1.0 or 0.0, 0.05)
                
                local fs_active = ui.get(settings.freestanding)
                crosshair_indicator.fs_alpha = lerp(crosshair_indicator.fs_alpha, fs_active and 1.0 or 0.0, 0.05)
                crosshair_indicator.fs_value = lerp(crosshair_indicator.fs_value, fs_active and 1.0 or 0.0, 0.05)
                
                if crosshair_indicator.state_value < 0.1 then
                    crosshair_indicator.last_state = current_state
                end
                
                -- Draw indicators
                local r, g, b, a = ui.get(settings.label_color2)  -- Первый цвет
                local r0, g0, b0, a0 = ui.get(settings.label_color1)  -- Второй цвет для переливания
                
                a = math.max(a, 55)
                a0 = math.max(a0, 55)
                
                local clock = globals.realtime() * 1.25
                
                local pos_x = center_x + math.floor(10 * crosshair_indicator.align)
                local pos_y = center_y + 18
                
                -- Draw "aimplay" text with wave effect (ТОЛЬКО ТУТ ПЕРЕЛИВАНИЕ)
                local text_alpha = crosshair_indicator.alpha
                local text = "aimplay"
                local text_w, text_h = renderer.measure_text("db", text)
                local offset = (text_w * 0.5) * (1 - crosshair_indicator.align)
                pos_x = math.floor(pos_x - offset)
                
                -- Переливание между двумя цветами label_color2 и label_color1
                text = wave_text(text, clock, r, g, b, a * text_alpha, r0, g0, b0, a0 * text_alpha)
                renderer.text(pos_x, pos_y, r, g, b, a * text_alpha, "db", 0, text)
                pos_y = pos_y + text_h
                
                -- Draw state (БЕЗ ПЕРЕЛИВАНИЯ - статичный цвет)
                if crosshair_indicator.state_alpha > 0.01 then
                    local state_alpha = crosshair_indicator.alpha * crosshair_indicator.state_alpha
                    local state_text = crosshair_indicator.last_state
                    local state_w, state_h = renderer.measure_text("-d", state_text)
                    local state_offset = (state_w * 0.5) * (1 - crosshair_indicator.align)
                    local state_x = math.floor(center_x + math.floor(10 * crosshair_indicator.align) - state_offset) - 1
                    
                    renderer.text(state_x, pos_y, r, g, b, a * state_alpha, "-d", 0, state_text)
                    pos_y = pos_y + math.floor(state_h * crosshair_indicator.state_alpha)
                end
                
                -- Draw DMG (БЕЗ ПЕРЕЛИВАНИЯ - статичный цвет)
                if crosshair_indicator.dmg_alpha > 0.01 then
                    local dmg_alpha = crosshair_indicator.alpha * crosshair_indicator.dmg_alpha
                    local dmg_text = "DMG"
                    local dmg_w, dmg_h = renderer.measure_text("-d", dmg_text)
                    local dmg_offset = (dmg_w * 0.5) * (1 - crosshair_indicator.align)
                    local dmg_x = math.floor(center_x + math.floor(10 * crosshair_indicator.align) - dmg_offset) - 1
                    
                    renderer.text(dmg_x, pos_y, r, g, b, a * dmg_alpha, "-d", 0, dmg_text)
                    pos_y = pos_y + math.floor(dmg_h * crosshair_indicator.dmg_alpha)
                end
                
                -- Draw DT (БЕЗ ПЕРЕЛИВАНИЯ - статичный цвет)
                if crosshair_indicator.dt_alpha > 0.01 then
                    local dt_alpha = crosshair_indicator.alpha * crosshair_indicator.dt_alpha
                    local dt_text = "DT"
                    local dt_w, dt_h = renderer.measure_text("-d", dt_text)
                    local dt_offset = (dt_w * 0.5) * (1 - crosshair_indicator.align)
                    local dt_x = math.floor(center_x + math.floor(10 * crosshair_indicator.align) - dt_offset) - 1
                    
                    renderer.text(dt_x, pos_y, r, g, b, a * dt_alpha, "-d", 0, dt_text)
                    pos_y = pos_y + math.floor(dt_h * crosshair_indicator.dt_alpha)
                end
                
                -- Draw OSAA (БЕЗ ПЕРЕЛИВАНИЯ - статичный цвет)
                if crosshair_indicator.osaa_alpha > 0.01 then
                    local osaa_alpha = crosshair_indicator.alpha * crosshair_indicator.osaa_alpha
                    local osaa_text = "OSAA"
                    local osaa_w, osaa_h = renderer.measure_text("-d", osaa_text)
                    local osaa_offset = (osaa_w * 0.5) * (1 - crosshair_indicator.align)
                    local osaa_x = math.floor(center_x + math.floor(10 * crosshair_indicator.align) - osaa_offset) - 1
                    
                    renderer.text(osaa_x, pos_y, r, g, b, a * osaa_alpha, "-d", 0, osaa_text)
                    pos_y = pos_y + math.floor(osaa_h * crosshair_indicator.osaa_alpha)
                end
                
                -- Draw FS (БЕЗ ПЕРЕЛИВАНИЯ - статичный цвет)
                if crosshair_indicator.fs_alpha > 0.01 then
                    local fs_alpha = crosshair_indicator.alpha * crosshair_indicator.fs_alpha
                    local fs_text = "FS"
                    local fs_w, fs_h = renderer.measure_text("-d", fs_text)
                    local fs_offset = (fs_w * 0.5) * (1 - crosshair_indicator.align)
                    local fs_x = math.floor(center_x + math.floor(10 * crosshair_indicator.align) - fs_offset) - 1
                    
                    fs_text = fade_text(fs_text, crosshair_indicator.fs_value, r, g, b, a * fs_alpha, r0, g0, b0, a0 * fs_alpha)
                    renderer.text(fs_x, pos_y, r, g, b, a * fs_alpha, "-d", 0, fs_text)
                end
            end
        end
    end
    
    if not ui.get(settings.advanced_panel_enabled) then
        return
    end
    
    -- Handle dragging
    if client.key_state then
        local mouse_1_pressed = client.key_state(0x01)
        local mouse_x, mouse_y = ui.mouse_position()
        
        if mouse_x and mouse_y then
            if mouse_1_pressed and not panel_dragging then
                if mouse_x >= panel_x and mouse_x <= panel_x + panel_width and
                   mouse_y >= panel_y and mouse_y <= panel_y + panel_header_height then
                    panel_dragging = true
                    panel_drag_offset_x = mouse_x - panel_x
                    panel_drag_offset_y = mouse_y - panel_y
                end
            elseif not mouse_1_pressed then
                panel_dragging = false
            end
            
            if panel_dragging and mouse_1_pressed then
                panel_x = mouse_x - panel_drag_offset_x
                panel_y = mouse_y - panel_drag_offset_y
                
                local screen_w, screen_h = client.screen_size()
                panel_x = math.max(0, math.min(panel_x, screen_w - panel_width))
                panel_y = math.max(0, math.min(panel_y, screen_h - panel_height))
            end
        end
    end
    
    if panel_dragging then
        panel_blur_target = 80
    else
        panel_blur_target = 0
    end
    
    local frametime = globals.frametime()
    panel_blur_alpha = panel_blur_alpha + (panel_blur_target - panel_blur_alpha) * panel_blur_speed * frametime
    
    if panel_blur_alpha > 1 then
        local screen_w, screen_h = client.screen_size()
        renderer.rectangle(0, 0, screen_w, screen_h, 0, 0, 0, math.floor(panel_blur_alpha))
    end
    
    local text_r, text_g, text_b, text_a = 255, 255, 255, 255
    local accent_r, accent_g, accent_b, accent_a = ui.get(settings.advanced_panel_accent_color)
    
    local y_offset = panel_y + 5
    
    renderer.text(panel_x + 5, y_offset, accent_r, accent_g, accent_b, accent_a, "-", 0, "AIMPLAY [NIGHTLY] - STATUS DISPLAY")
    y_offset = y_offset + 12
    
    local header_text_width = renderer.measure_text("-", "AIMPLAY [NIGHTLY] - STATUS DISPLAY")
    draw_panel_gradient_line(panel_x + 5, y_offset, header_text_width)
    y_offset = y_offset + 2
    
    local target = get_nearest_target()
    local target_name = "UNKNOWN"
    if target then
        target_name = string.upper(entity.get_player_name(target) or "UNKNOWN")
    end
    
    local condition = get_player_condition()
    local exploit_charge = get_exploit_charge()
    local desync_amt = get_desync_amount()
    local hit_ratio = "0%"
    
    if panel_shots_fired > 0 then
        hit_ratio = string.format("%.0f%%", (panel_shots_hit / panel_shots_fired) * 100)
    end
    
    local condition_width = renderer.measure_text("-", "CONDITION:")
    renderer.text(panel_x + 5, y_offset, text_r, text_g, text_b, text_a, "-", 0, "CONDITION:")
    renderer.text(panel_x + 5 + condition_width + 2, y_offset, accent_r, accent_g, accent_b, accent_a, "-", 0, condition)
    y_offset = y_offset + 10
    
    local target_width = renderer.measure_text("-", "TARGET:")
    renderer.text(panel_x + 5, y_offset, text_r, text_g, text_b, text_a, "-", 0, "TARGET:")
    renderer.text(panel_x + 5 + target_width + 2, y_offset, accent_r, accent_g, accent_b, accent_a, "-", 0, target_name)
    y_offset = y_offset + 10
    
    local exploit_width = renderer.measure_text("-", "EXPLOIT CHARGE:")
    renderer.text(panel_x + 5, y_offset, text_r, text_g, text_b, text_a, "-", 0, "EXPLOIT CHARGE:")
    renderer.text(panel_x + 5 + exploit_width + 2, y_offset, accent_r, accent_g, accent_b, accent_a, "-", 0, exploit_charge)
    y_offset = y_offset + 10
    
    local desync_width = renderer.measure_text("-", "DESYNC AMT:")
    renderer.text(panel_x + 5, y_offset, text_r, text_g, text_b, text_a, "-", 0, "DESYNC AMT:")
    renderer.text(panel_x + 5 + desync_width + 2, y_offset, accent_r, accent_g, accent_b, accent_a, "-", 0, desync_amt)
    y_offset = y_offset + 10
    
    local shots_hit_width = renderer.measure_text("-", "SHOTS HIT:")
    renderer.text(panel_x + 5, y_offset, text_r, text_g, text_b, text_a, "-", 0, "SHOTS HIT:")
    renderer.text(panel_x + 5 + shots_hit_width + 2, y_offset, accent_r, accent_g, accent_b, accent_a, "-", 0, tostring(panel_shots_hit))
    y_offset = y_offset + 10
    
    local shots_missed_width = renderer.measure_text("-", "SHOTS MISSED:")
    renderer.text(panel_x + 5, y_offset, text_r, text_g, text_b, text_a, "-", 0, "SHOTS MISSED:")
    renderer.text(panel_x + 5 + shots_missed_width + 2, y_offset, accent_r, accent_g, accent_b, accent_a, "-", 0, tostring(panel_shots_missed))
    y_offset = y_offset + 10
    
    local hit_ratio_width = renderer.measure_text("-", "HIT RATIO:")
    renderer.text(panel_x + 5, y_offset, text_r, text_g, text_b, text_a, "-", 0, "HIT RATIO:")
    renderer.text(panel_x + 5 + hit_ratio_width + 2, y_offset, accent_r, accent_g, accent_b, accent_a, "-", 0, hit_ratio)
end)

-- Advanced Panel aim events
client.set_event_callback('aim_fire', function(e)
    panel_shots_fired = panel_shots_fired + 1
end)

client.set_event_callback('aim_hit', function(e)
    panel_shots_hit = panel_shots_hit + 1
end)

client.set_event_callback('aim_miss', function(e)
    panel_shots_missed = panel_shots_missed + 1
end)

-- ============================================
-- WATERMARK PAINT CALLBACK
-- ============================================
client.set_event_callback('paint', function()
    if not ui.get(settings.watermark_enable) then return end
    
    local elements = ui.get(settings.watermark_elements)
    local screen_w, screen_h = client.screen_size()
    local base_x = ui.get(settings.watermark_x)
    local base_y = ui.get(settings.watermark_y)
    
    local menu_r, menu_g, menu_b, menu_a = ui.get(settings.label_color2)
    local gamesense_text = "game\a" .. string.format("%02X%02X%02X%02X", menu_r, menu_g, menu_b, 255) .. "sense"
    
    local parts = {}
    table.insert(parts, {text = gamesense_text, flags = ""})
    
    if watermark_contains(elements, "FPS") then
        local fps = calculate_fps()
        table.insert(parts, {text = tostring(fps), flags = "", color = {menu_r, menu_g, menu_b, 255}})
        table.insert(parts, {text = "FPS", flags = "-", color = {255, 255, 255, 255}})
    end
    
    if watermark_contains(elements, "PING") then
        local ping, var = get_latency()
        table.insert(parts, {text = tostring(ping), flags = "", color = {menu_r, menu_g, menu_b, 255}})
        table.insert(parts, {text = "PING", flags = "-", color = {255, 255, 255, 255}})
    end
    
    if watermark_contains(elements, "DELAY") then
        local ping, var = get_latency()
        table.insert(parts, {text = tostring(var), flags = "", color = {menu_r, menu_g, menu_b, 255}})
        table.insert(parts, {text = "DELAY", flags = "-", color = {255, 255, 255, 255}})
    end
    
    if watermark_contains(elements, "CPU") then
        table.insert(parts, {text = tostring(watermark_vars.cpu_usage) .. "%", flags = "", color = {menu_r, menu_g, menu_b, 255}})
        table.insert(parts, {text = "CPU", flags = "-", color = {255, 255, 255, 255}})
    end
    
    if watermark_contains(elements, "GPU") then
        table.insert(parts, {text = tostring(watermark_vars.gpu_usage) .. "%", flags = "", color = {menu_r, menu_g, menu_b, 255}})
        table.insert(parts, {text = "GPU", flags = "-", color = {255, 255, 255, 255}})
    end
    
    if watermark_contains(elements, "Time") then
        local time_str = get_time()
        table.insert(parts, {text = time_str, flags = "", color = {255, 255, 255, 255}})
    end
    
    local padding_x = 5
    local padding_y = 4
    local spacing = 12
    local no_spacing = 1
    local total_width = padding_x * 2
    local max_height = 0
    
    for i, part in ipairs(parts) do
        local w, h = renderer.measure_text(part.flags, part.text)
        total_width = total_width + w
        if i < #parts then
            local next_part = parts[i + 1]
            if next_part and next_part.flags == "-" then
                total_width = total_width + no_spacing
            else
                total_width = total_width + spacing
            end
        end
        max_height = math.max(max_height, h)
    end
    
    local box_height = max_height + padding_y * 2
    
    local bg_r, bg_g, bg_b, bg_a = ui.get(settings.watermark_bg_color)
    local border_r, border_g, border_b, border_a = ui.get(settings.watermark_border_color)
    
    -- Рисуем фон
    renderer.rectangle(base_x, base_y, total_width, box_height, bg_r, bg_g, bg_b, bg_a)
    
    -- Градиент фона по бокам
    local gradient_bg_width = 25
    for i = 1, gradient_bg_width do
        local alpha = math.floor(bg_a * (1 - i / gradient_bg_width))
        local x_left = base_x - i
        if x_left >= 0 then
            renderer.rectangle(x_left, base_y, 1, box_height, bg_r, bg_g, bg_b, alpha)
        end
        local x_right = base_x + total_width + i - 1
        renderer.rectangle(x_right, base_y, 1, box_height, bg_r, bg_g, bg_b, alpha)
    end
    
    -- Рисуем линии сверху и снизу с градиентом
    local gradient_line_width = 30
    
    renderer.rectangle(base_x, base_y, total_width, 1, border_r, border_g, border_b, border_a)
    renderer.rectangle(base_x, base_y + box_height - 1, total_width, 1, border_r, border_g, border_b, border_a)
    
    for i = 1, gradient_line_width do
        local alpha = math.floor(border_a * (1 - i / gradient_line_width))
        local x_pos = base_x - i
        if x_pos >= 0 then
            renderer.rectangle(x_pos, base_y, 1, 1, border_r, border_g, border_b, alpha)
            renderer.rectangle(x_pos, base_y + box_height - 1, 1, 1, border_r, border_g, border_b, alpha)
        end
    end
    
    for i = 1, gradient_line_width do
        local alpha = math.floor(border_a * (1 - i / gradient_line_width))
        local x_pos = base_x + total_width + i - 1
        renderer.rectangle(x_pos, base_y, 1, 1, border_r, border_g, border_b, alpha)
        renderer.rectangle(x_pos, base_y + box_height - 1, 1, 1, border_r, border_g, border_b, alpha)
    end
    
    -- Рисуем текст
    local current_x = base_x + padding_x
    local text_y = base_y + padding_y
    
    for i, part in ipairs(parts) do
        local offset_y = (part.flags == "-") and 2 or 0
        if part.color then
            renderer.text(current_x, text_y + offset_y, part.color[1], part.color[2], part.color[3], part.color[4], part.flags, 0, part.text)
        else
            renderer.text(current_x, text_y + offset_y, 255, 255, 255, 255, part.flags, 0, part.text)
        end
        local w, h = renderer.measure_text(part.flags, part.text)
        current_x = current_x + w
        if i < #parts then
            local next_part = parts[i + 1]
            if next_part and next_part.flags == "-" then
                current_x = current_x + no_spacing
            else
                current_x = current_x + spacing
            end
        end
    end
end)

-- ============================================
-- HIT LOGS PAINT CALLBACK
-- ============================================
client.set_event_callback('paint', function()
    if not ui.get(settings.hitlogs_enable) then return end
    
    local screen_w, screen_h = client.screen_size()
    local position_mode = ui.get(settings.hitlogs_position)
    local log_lifetime = (position_mode == "Top Left") and log_lifetime_topleft or log_lifetime_center
    local current_time = globals.realtime()
    local bg_r, bg_g, bg_b, bg_a = ui.get(settings.watermark_bg_color)
    local border_r, border_g, border_b, border_a = ui.get(settings.watermark_border_color)
    local menu_r, menu_g, menu_b = ui.get(settings.label_color2)
    
    -- Удаляем старые логи
    for i = #hit_logs, 1, -1 do
        local log = hit_logs[i]
        local age = current_time - log.time
        
        if age > log_lifetime then
            table.remove(hit_logs, i)
            log_positions[i] = nil
        end
    end
    
    -- Рисуем логи
    for i = #hit_logs, 1, -1 do
        local log = hit_logs[i]
        local age = current_time - log.time
        
        -- Анимация появления (первые 0.3 секунды)
        local appear_time = 0.3
        local appear_mult = 1
        if age < appear_time then
            appear_mult = age / appear_time
        end
        
        -- Анимация исчезновения (последняя секунда)
        local fade_time = 1
        local fade_mult = 1
        if age > log_lifetime - fade_time then
            fade_mult = 1 - (age - (log_lifetime - fade_time)) / fade_time
        end
        
        local alpha_mult = appear_mult * fade_mult
        
        -- Размеры
        local padding_x = 8
        local padding_y = 4
        local text_w, text_h = renderer.measure_text("", log.text)
        local box_w = text_w + padding_x * 2
        local box_h = text_h + padding_y * 2
        
        -- Целевая позиция в зависимости от режима
        local log_x, target_log_y
        
        if position_mode == "Top Left" then  -- Top Left
            log_x = 10
            target_log_y = 4 + (#hit_logs - i) * (box_h + 4)  -- Начинаем с Y=4, новые логи снизу
        else  -- Center
            local center_x = screen_w / 2
            local y_offset = ui.get(settings.hitlogs_y_offset)
            local start_y = screen_h / 2 + y_offset
            log_x = center_x - box_w / 2
            target_log_y = start_y + (#hit_logs - i) * (box_h + 4)  -- Новые логи снизу
        end
        
        -- Инициализация позиции для нового лога
        if not log_positions[i] then
            log_positions[i] = target_log_y - 20  -- Начинаем выше для анимации появления
        end
        
        -- Плавная интерполяция позиции
        local lerp_speed = 0.25  -- Скорость интерполяции (чем больше, тем быстрее)
        log_positions[i] = log_positions[i] + (target_log_y - log_positions[i]) * lerp_speed
        
        local log_y = log_positions[i]
        
        -- Рисуем фон
        local final_bg_a = math.floor(bg_a * alpha_mult)
        renderer.rectangle(log_x, log_y, box_w, box_h, bg_r, bg_g, bg_b, final_bg_a)
        
        -- Градиент фона по бокам
        local gradient_bg_width = 25
        for j = 1, gradient_bg_width do
            local alpha = math.floor(final_bg_a * (1 - j / gradient_bg_width))
            local x_left = log_x - j
            if x_left >= 0 then
                renderer.rectangle(x_left, log_y, 1, box_h, bg_r, bg_g, bg_b, alpha)
            end
            local x_right = log_x + box_w + j - 1
            renderer.rectangle(x_right, log_y, 1, box_h, bg_r, bg_g, bg_b, alpha)
        end
        
        -- Рисуем линии сверху и снизу
        local gradient_line_width = 30
        local final_border_a = math.floor(border_a * alpha_mult)
        
        -- Центральная часть линий
        renderer.rectangle(log_x, log_y, box_w, 1, border_r, border_g, border_b, final_border_a)
        renderer.rectangle(log_x, log_y + box_h - 1, box_w, 1, border_r, border_g, border_b, final_border_a)
        
        -- Левый градиент линий
        for j = 1, gradient_line_width do
            local alpha = math.floor(final_border_a * (1 - j / gradient_line_width))
            local x_pos = log_x - j
            if x_pos >= 0 then
                renderer.rectangle(x_pos, log_y, 1, 1, border_r, border_g, border_b, alpha)
                renderer.rectangle(x_pos, log_y + box_h - 1, 1, 1, border_r, border_g, border_b, alpha)
            end
        end
        
        -- Правый градиент линий
        for j = 1, gradient_line_width do
            local alpha = math.floor(final_border_a * (1 - j / gradient_line_width))
            local x_pos = log_x + box_w + j - 1
            renderer.rectangle(x_pos, log_y, 1, 1, border_r, border_g, border_b, alpha)
            renderer.rectangle(x_pos, log_y + box_h - 1, 1, 1, border_r, border_g, border_b, alpha)
        end
        
        -- Рисуем текст с динамической альфой для цветных частей
        local final_text_a = math.floor(255 * alpha_mult)
        
        -- Заменяем альфу во ВСЕХ цветных кодах текста
        -- В Lua строках \a это символ 0x07, поэтому ищем его напрямую
        local animated_text = log.text:gsub("\a(%x%x%x%x%x%x)%x%x", function(rgb)
            return "\a" .. rgb .. string.format("%02X", final_text_a)
        end)
        
        renderer.text(log_x + padding_x, log_y + padding_y, 255, 255, 255, final_text_a, "", 0, animated_text)
    end
end)

-- Hit logs event callbacks
client.set_event_callback('aim_hit', function(e)
    if not ui.get(settings.hitlogs_enable) then return end
    
    local target_name = entity.get_player_name(e.target)
    local hitgroup_names = {"generic", "head", "chest", "stomach", "left arm", "right arm", "left leg", "right leg", "neck", "?", "gear"}
    local hitgroup = hitgroup_names[e.hitgroup + 1] or "body"
    local remaining_hp = entity.get_prop(e.target, "m_iHealth") or 0
    
    local menu_r, menu_g, menu_b = ui.get(settings.label_color2)
    local color_hex = string.format("%02X%02X%02X%02X", menu_r, menu_g, menu_b, 255)
    
    local log_text = string.format("Hit \a%s%s\aFFFFFFFF in the \a%s%s\aFFFFFFFF for \a%s%d\aFFFFFFFF damage (\a%s%d\aFFFFFFFF health remaining)", 
        color_hex, target_name, color_hex, hitgroup, color_hex, e.damage, color_hex, remaining_hp)
    
    add_hit_log(log_text)
end)

client.set_event_callback('aim_miss', function(e)
    if not ui.get(settings.hitlogs_enable) then return end
    
    local target_name = entity.get_player_name(e.target)
    local reason = e.reason
    
    local menu_r, menu_g, menu_b = ui.get(settings.label_color2)
    local color_hex = string.format("%02X%02X%02X%02X", menu_r, menu_g, menu_b, 255)
    
    local log_text = string.format("Missed \a%s%s\aFFFFFFFF due to %s", color_hex, target_name, reason)
    
    add_hit_log(log_text)
end)

-- Visual World paint callback
client.set_event_callback('paint', function()
    local me = entity.get_local_player()
    if not me then return end
    
    -- Fog
    if fog_controller.entity == nil then
        fog_controller.entity = entity.get_all("CFogController")[1]
    end
    
    if fog_controller.entity then
        local fog_enabled = ui.get(settings.fog_enable)
        entity.set_prop(fog_controller.entity, "m_fog.enable", fog_enabled and 1 or 0)
        entity.set_prop(me, "m_skybox3d.fog.enable", fog_enabled and 1 or 0)
        
        if fog_enabled then
            entity.set_prop(fog_controller.entity, "m_fog.start", fog_controller.fog_start)
            entity.set_prop(me, "m_skybox3d.fog.start", fog_controller.fog_start)
            
            entity.set_prop(fog_controller.entity, "m_fog.end", fog_controller.fog_end)
            entity.set_prop(me, "m_skybox3d.fog.end", fog_controller.fog_end)
            
            entity.set_prop(fog_controller.entity, "m_fog.maxdensity", fog_controller.fog_max_density)
            entity.set_prop(me, "m_skybox3d.fog.maxdensity", fog_controller.fog_max_density)
            
            entity.set_prop(fog_controller.entity, "m_fog.colorPrimary", fog_controller.fog_color)
            entity.set_prop(me, "m_skybox3d.fog.colorPrimary", fog_controller.fog_color)
        end
    end
    
    -- Wall Color
    local wallcolor = ui.get(settings.wall_color_enable)
    if wallcolor or wallcolor_prev then
        if wallcolor then
            local r, g, b, a = ui.get(settings.wall_color)
            r, g, b = r/255, g/255, b/255
            local a_temp = a / 128 - 1
            local r_res, g_res, b_res
            if a_temp > 0 then
                local multiplier = 900^(a_temp) - 1
                a_temp = a_temp * multiplier
                r_res, g_res, b_res = r*a_temp, g*a_temp, b*a_temp
            else
                a_temp = a_temp * 1
                r_res, g_res, b_res = (1-r)*a_temp, (1-g)*a_temp, (1-b)*a_temp
            end
            mat_ambient_light_r:set_raw_float(r_res)
            mat_ambient_light_g:set_raw_float(g_res)
            mat_ambient_light_b:set_raw_float(b_res)
        else
            mat_ambient_light_r:set_raw_float(0)
            mat_ambient_light_g:set_raw_float(0)
            mat_ambient_light_b:set_raw_float(0)
        end
    end
    wallcolor_prev = wallcolor
    
    -- Model Ambient Min
    local model_ambient_min = ui.get(settings.model_ambient_min)
    if model_ambient_min > 0 or (model_ambient_min_prev ~= nil and model_ambient_min_prev > 0) then
        r_modelAmbientMin:set_raw_float(model_ambient_min*0.05)
    end
    model_ambient_min_prev = model_ambient_min
    
    -- Bloom and Exposure
    local bloom_enabled = ui.get(settings.bloom_enable)
    local bloom = bloom_enabled and ui.get(settings.bloom_scale) or -1
    local exposure = ui.get(settings.auto_exposure)
    if bloom ~= -1 or exposure ~= -1 or bloom_prev ~= -1 or exposure_prev ~= -1 then
        local tone_map_controllers = entity.get_all("CEnvTonemapController")
        for i=1, #tone_map_controllers do
            local tone_map_controller = tone_map_controllers[i]
            if bloom ~= -1 then
                if bloom_default == nil then
                    if entity.get_prop(tone_map_controller, "m_bUseCustomBloomScale") == 1 then
                        bloom_default = entity.get_prop(tone_map_controller, "m_flCustomBloomScale")
                    else
                        bloom_default = -1
                    end
                end
                entity.set_prop(tone_map_controller, "m_bUseCustomBloomScale", 1)
                entity.set_prop(tone_map_controller, "m_flCustomBloomScale", bloom*0.01)
            elseif bloom_prev ~= nil and bloom_prev ~= -1 and bloom_default ~= nil then
                reset_bloom(tone_map_controller)
            end
            if exposure ~= -1 then
                if exposure_min_default == nil then
                    if entity.get_prop(tone_map_controller, "m_bUseCustomAutoExposureMin") == 1 then
                        exposure_min_default = entity.get_prop(tone_map_controller, "m_flCustomAutoExposureMin")
                    else
                        exposure_min_default = -1
                    end
                    if entity.get_prop(tone_map_controller, "m_bUseCustomAutoExposureMax") == 1 then
                        exposure_max_default = entity.get_prop(tone_map_controller, "m_flCustomAutoExposureMax")
                    else
                        exposure_max_default = -1
                    end
                end
                entity.set_prop(tone_map_controller, "m_bUseCustomAutoExposureMin", 1)
                entity.set_prop(tone_map_controller, "m_bUseCustomAutoExposureMax", 1)
                entity.set_prop(tone_map_controller, "m_flCustomAutoExposureMin", math.max(0.0000, exposure*0.001))
                entity.set_prop(tone_map_controller, "m_flCustomAutoExposureMax", math.max(0.0000, exposure*0.001))
            elseif exposure_prev ~= nil and exposure_prev ~= -1 and exposure_min_default ~= nil then
                reset_exposure(tone_map_controller)
            end
        end
    end
    bloom_prev = bloom
    exposure_prev = exposure
    
    -- Color Correction
    if ui.get(settings.color_correction_enable) then
        local screen_width, screen_height = client.screen_size()
        local r, g, b, a = ui.get(settings.color_correction_color)
        renderer.gradient(0, 0, screen_width, screen_height, r, g, b, a, r, g, b, a, false)
    end
end)

-- Fog callbacks
ui.set_callback(settings.fog_start, function()
    local fog_start_value = ui.get(settings.fog_start)
    local fog_end_value = ui.get(settings.fog_end)
    if fog_start_value > fog_end_value then
        ui.set(settings.fog_end, fog_start_value)
    end
    fog_controller.fog_start = fog_start_value
end)

ui.set_callback(settings.fog_end, function()
    local fog_start_value = ui.get(settings.fog_start)
    local fog_end_value = ui.get(settings.fog_end)
    if fog_end_value < fog_start_value then
        ui.set(settings.fog_start, fog_end_value)
    end
    fog_controller.fog_end = fog_end_value
end)

ui.set_callback(settings.fog_max_density, function()
    fog_controller.fog_max_density = ui.get(settings.fog_max_density) / 100
end)

ui.set_callback(settings.fog_color, function()
    local r, g, b = ui.get(settings.fog_color)
    fog_controller.fog_color = rgb_to_int(r, g, b)
end)

-- Watermark and Hit Logs callbacks
ui.set_callback(settings.watermark_enable, function()
    -- Trigger UI visibility update
    if update_ui_visibility then
        update_ui_visibility()
    end
end)

ui.set_callback(settings.hitlogs_enable, function()
    -- Trigger UI visibility update
    if update_ui_visibility then
        update_ui_visibility()
    end
end)

ui.set_callback(settings.hitlogs_position, function()
    -- Trigger UI visibility update
    if update_ui_visibility then
        update_ui_visibility()
    end
end)

-- Player connect callback for fog
client.set_event_callback("player_connect_full", function(data)
    local player = client.userid_to_entindex(data.userid)
    if player == entity.get_local_player() then
        fog_controller.entity = entity.get_all("CFogController")[1]
    end
end)

-- Reset bloom/exposure on map change
local reset_on_map_change
reset_on_map_change = function()
    if globals.mapname() == nil then
        bloom_default, exposure_min_default, exposure_max_default = nil, nil, nil
    end
    client.delay_call(0.5, reset_on_map_change)
end
reset_on_map_change()

-- Config system (Simple and working)

-- Helper: split string
local function split_string(str, delimiter)
    local result = {}
    for match in string.gmatch(str, "([^" .. delimiter .. "]+)") do
        result[#result + 1] = match
    end
    return result
end

-- Get all field names in consistent order
local function get_aa_field_order()
    return {
        'override_state', 'pitch1', 'pitch2', 'yaw_base', 'yaw1', 'yaw2_left', 'yaw2_right', 'yaw2_randomize',
        'yaw_jitter1', 'yaw_jitter2_left', 'yaw_jitter2_right', 'yaw_jitter2_randomize', 'yaw_jitter2_delay',
        'body_yaw1', 'body_yaw2', 'freestanding_body_yaw', 'roll',
        'force_defensive', 'defensive_anti_aimbot', 'defensive_pitch', 'defensive_pitch1', 'defensive_pitch2', 
        'defensive_pitch3', 'defensive_pitch_delay', 'defensive_yaw', 'defensive_yaw1', 'defensive_yaw2', 
        'defensive_yaw3', 'defensive_yaw_delay'
    }
end

-- Get config files list
local function get_config_files()
    local files = {}
    -- Check numbered configs
    for i = 1, 100 do
        local filename = i .. ".cfg"
        local success, content = pcall(readfile, filename)
        if success and content and content ~= "" then
            files[#files + 1] = filename
        end
    end
    -- Check named configs (scan common names)
    local common_names = {"test", "main", "default", "hvh", "legit", "rage"}
    for _, name in ipairs(common_names) do
        local filename = name .. ".cfg"
        local success, content = pcall(readfile, filename)
        if success and content and content ~= "" then
            -- Check if not already in list
            local found = false
            for _, existing in ipairs(files) do
                if existing == filename then
                    found = true
                    break
                end
            end
            if not found then
                files[#files + 1] = filename
            end
        end
    end
    return files
end

-- Update config list for UI
function update_cfg()
    local files = get_config_files()
    local names = {}
    for i = 1, #files do
        local name = files[i]:gsub('.cfg', '')
        names[i] = name
    end
    return names
end

-- Create config
local function create_config()
    local name = ui.get(settings.config_name)
    if not name or name == "" then
        client.color_log(173, 255, 47, 'aimplay ')
        client.color_log(255, 100, 100, '› empty config name')
        return
    end
    
    local filename = name .. ".cfg"
    
    -- Check if config already exists
    local success, existing_content = pcall(readfile, filename)
    if success and existing_content and existing_content ~= "" then
        client.color_log(173, 255, 47, 'aimplay ')
        client.color_log(255, 100, 100, '› config already exists')
        return
    end
    
    -- Create blank config
    local success_write = pcall(writefile, filename, "blank")
    if not success_write then
        client.color_log(173, 255, 47, 'aimplay ')
        client.color_log(255, 100, 100, '› failed to create config')
        return
    end
    
    client.color_log(173, 255, 47, 'aimplay ')
    client.color_log(255, 255, 255, '› config ')
    client.color_log(173, 255, 47, name)
    client.color_log(255, 255, 255, ' created')
end

-- Save config
local function save_config()
    local files = get_config_files()
    local selected = ui.get(settings.config_list)
    if not selected or selected < 0 or not files[selected + 1] then
        client.color_log(173, 255, 47, 'aimplay ')
        client.color_log(255, 100, 100, '› no config selected')
        return
    end
    
    local data = {}
    local field_order = get_aa_field_order()
    
    -- Save anti-aim settings (10 states × 29 fields = 290 values)
    for state_id = 1, #anti_aim_states do
        if anti_aim_settings[state_id] then
            for _, field_name in ipairs(field_order) do
                if anti_aim_settings[state_id][field_name] then
                    local value = pui_get(anti_aim_settings[state_id][field_name])
                    if type(value) == "boolean" then
                        table.insert(data, value and "true" or "false")
                    elseif type(value) == "number" then
                        table.insert(data, tostring(value))
                    elseif type(value) == "string" then
                        table.insert(data, value)
                    else
                        table.insert(data, "nil")
                    end
                else
                    table.insert(data, "nil")
                end
            end
        end
    end
    
    -- Save other settings (checkboxes, sliders, comboboxes)
    local other_settings = {
        'aa_builder_enable', 'warmup_disabler', 'avoid_backstab', 'safe_head_in_air',
        'fog_enable', 'fog_start', 'fog_end', 'fog_max_density',
        'bloom_enable', 'bloom_scale', 'auto_exposure', 'model_ambient_min',
        'wall_color_enable', 'color_correction_enable',
        'advanced_panel_enabled', 'minimum_damage_indicator', 'crosshair_indicator'
    }
    
    for _, setting_name in ipairs(other_settings) do
        if settings[setting_name] then
            local value = ui.get(settings[setting_name])
            if type(value) == "boolean" then
                table.insert(data, value and "true" or "false")
            elseif type(value) == "number" then
                table.insert(data, tostring(value))
            elseif type(value) == "string" then
                table.insert(data, value)
            else
                table.insert(data, "nil")
            end
        else
            table.insert(data, "nil")
        end
    end
    
    -- Save damage indicator position
    table.insert(data, tostring(damage_indicator_vars.offset_x))
    table.insert(data, tostring(damage_indicator_vars.offset_y))
    
    -- Save color pickers (ALL color pickers)
    local color_settings = {
        'label_color1', 
        'label_color2', 
        'fog_color', 
        'wall_color', 
        'color_correction_color', 
        'advanced_panel_accent_color',
        'watermark_bg_color',
        'watermark_border_color'
    }
    for _, setting_name in ipairs(color_settings) do
        if settings[setting_name] then
            local r, g, b, a = ui.get(settings[setting_name])
            table.insert(data, string.format("%d,%d,%d,%d", r, g, b, a))
        else
            table.insert(data, "255,255,255,255")
        end
    end
    
    -- Save hotkeys (both mode and key)
    local hotkey_settings = {'manual_forward', 'manual_right', 'manual_left', 'edge_yaw', 'freestanding'}
    for _, setting_name in ipairs(hotkey_settings) do
        if settings[setting_name] then
            local mode, key = ui.get(settings[setting_name])
            table.insert(data, string.format("%d,%d", mode or 0, key or 0))
        else
            table.insert(data, "0,0")
        end
    end
    
    -- Save multiselect
    local multi_settings = {'freestanding_conditions', 'tweaks', 'fps_boosters', 'anim_breakers'}
    for _, setting_name in ipairs(multi_settings) do
        if settings[setting_name] then
            local value = ui.get(settings[setting_name])
            if type(value) == "table" then
                local items = {}
                for i = 1, #value do
                    items[i] = tostring(value[i])
                end
                table.insert(data, table.concat(items, ";"))
            else
                table.insert(data, "")
            end
        else
            table.insert(data, "")
        end
    end
    
    local data_string = table.concat(data, "|")
    local encoded = base64.encode(data_string)
    
    local success = pcall(writefile, files[selected + 1], encoded)
    if not success then
        client.color_log(173, 255, 47, 'aimplay ')
        client.color_log(255, 100, 100, '› failed to save config')
        return
    end
    
    local name = files[selected + 1]:gsub('.cfg', '')
    client.color_log(173, 255, 47, 'aimplay ')
    client.color_log(255, 255, 255, '› config ')
    client.color_log(173, 255, 47, name)
    client.color_log(255, 255, 255, ' saved')
end

-- Load config
local function load_config()
    local files = get_config_files()
    local selected = ui.get(settings.config_list)
    if not selected or selected < 0 or not files[selected + 1] then
        client.color_log(173, 255, 47, 'aimplay ')
        client.color_log(255, 100, 100, '› no config selected')
        return
    end
    
    local success, content = pcall(readfile, files[selected + 1])
    if not success or not content or content == "" then
        client.color_log(173, 255, 47, 'aimplay ')
        client.color_log(255, 100, 100, '› failed to read config')
        return
    end
    
    if content == "blank" then
        client.color_log(173, 255, 47, 'aimplay ')
        client.color_log(255, 100, 100, '› config is blank, save it first')
        return
    end
    
    local success_decode, decoded = pcall(base64.decode, content)
    if not success_decode then
        client.color_log(173, 255, 47, 'aimplay ')
        client.color_log(255, 100, 100, '› invalid config data')
        return
    end
    
    local data = split_string(decoded, "|")
    local index = 1
    local field_order = get_aa_field_order()
    
    -- Calculate expected data size
    local expected_aa_values = #anti_aim_states * #field_order  -- 10 * 29 = 290
    local expected_other_values = 16  -- other_settings count
    local expected_hotkey_values = 5  -- hotkey_settings count
    local expected_color_values = 8   -- color_settings count (added watermark colors)
    local expected_multi_values = 4   -- multi_settings count
    local expected_total_new = expected_aa_values + expected_other_values + expected_hotkey_values + expected_color_values + expected_multi_values
    local expected_total_old = expected_aa_values + expected_other_values + expected_color_values + expected_multi_values  -- old format without hotkeys
    
    local is_old_format = #data < expected_total_new
    
    -- Load anti-aim settings
    for state_id = 1, #anti_aim_states do
        if anti_aim_settings[state_id] then
            for _, field_name in ipairs(field_order) do
                if anti_aim_settings[state_id][field_name] and data[index] and data[index] ~= "nil" then
                    local value = data[index]
                    if value == "true" then
                        pui_set(anti_aim_settings[state_id][field_name], true)
                    elseif value == "false" then
                        pui_set(anti_aim_settings[state_id][field_name], false)
                    else
                        local num = tonumber(value)
                        if num then
                            pui_set(anti_aim_settings[state_id][field_name], num)
                        else
                            pui_set(anti_aim_settings[state_id][field_name], value)
                        end
                    end
                end
                index = index + 1
            end
        end
    end
    
    -- Load other settings (checkboxes, sliders, comboboxes)
    local other_settings = {
        'aa_builder_enable', 'warmup_disabler', 'avoid_backstab', 'safe_head_in_air',
        'fog_enable', 'fog_start', 'fog_end', 'fog_max_density',
        'bloom_enable', 'bloom_scale', 'auto_exposure', 'model_ambient_min',
        'wall_color_enable', 'color_correction_enable',
        'advanced_panel_enabled', 'minimum_damage_indicator'
    }
    
    for _, setting_name in ipairs(other_settings) do
        if settings[setting_name] and data[index] and data[index] ~= "nil" then
            local value = data[index]
            if value == "true" then
                ui.set(settings[setting_name], true)
            elseif value == "false" then
                ui.set(settings[setting_name], false)
            else
                local num = tonumber(value)
                if num then
                    ui.set(settings[setting_name], num)
                else
                    ui.set(settings[setting_name], value)
                end
            end
        end
        index = index + 1
    end
    
    -- Load damage indicator position (only if new format)
    if not is_old_format and data[index] and data[index + 1] then
        damage_indicator_vars.offset_x = tonumber(data[index]) or 5
        damage_indicator_vars.offset_y = tonumber(data[index + 1]) or -20
        index = index + 2
    end
    
    -- Load color pickers (ALL color pickers)
    local color_settings = {
        'label_color1', 
        'label_color2', 
        'fog_color', 
        'wall_color', 
        'color_correction_color', 
        'advanced_panel_accent_color',
        'watermark_bg_color',
        'watermark_border_color'
    }
    for _, setting_name in ipairs(color_settings) do
        if settings[setting_name] and data[index] and data[index] ~= "nil" then
            local colors = split_string(data[index], ",")
            if #colors == 4 then
                local r = tonumber(colors[1]) or 255
                local g = tonumber(colors[2]) or 255
                local b = tonumber(colors[3]) or 255
                local a = tonumber(colors[4]) or 255
                ui.set(settings[setting_name], r, g, b, a)
            end
        end
        index = index + 1
    end
    
    -- Load hotkeys (only if new format)
    if not is_old_format then
        local hotkey_settings = {'manual_forward', 'manual_right', 'manual_left', 'edge_yaw', 'freestanding'}
        for _, setting_name in ipairs(hotkey_settings) do
            if settings[setting_name] and data[index] and data[index] ~= "nil" then
                local hotkey_data = split_string(data[index], ",")
                if #hotkey_data == 2 then
                    local mode = tonumber(hotkey_data[1]) or 0
                    local key = tonumber(hotkey_data[2]) or 0
                    ui.set(settings[setting_name], mode, key)
                end
            end
            index = index + 1
        end
    end
    
    -- Load multiselect
    local multi_settings = {'freestanding_conditions', 'tweaks', 'fps_boosters', 'anim_breakers'}
    for _, setting_name in ipairs(multi_settings) do
        if settings[setting_name] and data[index] and data[index] ~= "" then
            local items = split_string(data[index], ";")
            ui.set(settings[setting_name], items)
        end
        index = index + 1
    end
    
    local name = files[selected + 1]:gsub('.cfg', '')
    client.color_log(173, 255, 47, 'aimplay ')
    client.color_log(255, 255, 255, '› config ')
    client.color_log(173, 255, 47, name)
    if is_old_format then
        client.color_log(255, 255, 100, ' loaded (old format, resave to update)')
    else
        client.color_log(255, 255, 255, ' loaded')
    end
end

-- Delete config
local function delete_config()
    local files = get_config_files()
    local selected = ui.get(settings.config_list)
    if not selected or selected < 0 or not files[selected + 1] then
        client.color_log(173, 255, 47, 'aimplay ')
        client.color_log(255, 100, 100, '› no config selected')
        return
    end
    
    local name = files[selected + 1]:gsub('.cfg', '')
    
    -- Delete by writing empty string
    local success = pcall(writefile, files[selected + 1], "")
    if not success then
        client.color_log(173, 255, 47, 'aimplay ')
        client.color_log(255, 100, 100, '› failed to delete config')
        return
    end
    
    client.color_log(173, 255, 47, 'aimplay ')
    client.color_log(255, 255, 255, '› config ')
    client.color_log(173, 255, 47, name)
    client.color_log(255, 255, 255, ' deleted')
end

-- Import from clipboard
local function import_config()
    local encoded = clipboard.get()
    if not encoded or encoded == "" then
        client.color_log(173, 255, 47, 'aimplay ')
        client.color_log(255, 100, 100, '› clipboard is empty')
        return
    end
    
    local success, decoded = pcall(base64.decode, encoded)
    if not success then
        client.color_log(173, 255, 47, 'aimplay ')
        client.color_log(255, 100, 100, '› invalid config data')
        return
    end
    
    local data = split_string(decoded, "|")
    local index = 1
    local field_order = get_aa_field_order()
    
    -- Calculate expected data size
    local expected_aa_values = #anti_aim_states * #field_order
    local expected_other_values = 16
    local expected_hotkey_values = 5
    local expected_color_values = 6
    local expected_multi_values = 4
    local expected_total_new = expected_aa_values + expected_other_values + expected_hotkey_values + expected_color_values + expected_multi_values
    
    local is_old_format = #data < expected_total_new
    
    -- Load anti-aim settings
    for state_id = 1, #anti_aim_states do
        if anti_aim_settings[state_id] then
            for _, field_name in ipairs(field_order) do
                if anti_aim_settings[state_id][field_name] and data[index] and data[index] ~= "nil" then
                    local value = data[index]
                    if value == "true" then
                        pui_set(anti_aim_settings[state_id][field_name], true)
                    elseif value == "false" then
                        pui_set(anti_aim_settings[state_id][field_name], false)
                    else
                        local num = tonumber(value)
                        if num then
                            pui_set(anti_aim_settings[state_id][field_name], num)
                        else
                            pui_set(anti_aim_settings[state_id][field_name], value)
                        end
                    end
                end
                index = index + 1
            end
        end
    end
    
    -- Load other settings (checkboxes, sliders, comboboxes)
    local other_settings = {
        'aa_builder_enable', 'warmup_disabler', 'avoid_backstab', 'safe_head_in_air',
        'fog_enable', 'fog_start', 'fog_end', 'fog_max_density',
        'bloom_enable', 'bloom_scale', 'auto_exposure', 'model_ambient_min',
        'wall_color_enable', 'color_correction_enable',
        'advanced_panel_enabled', 'minimum_damage_indicator'
    }
    
    for _, setting_name in ipairs(other_settings) do
        if settings[setting_name] and data[index] and data[index] ~= "nil" then
            local value = data[index]
            if value == "true" then
                ui.set(settings[setting_name], true)
            elseif value == "false" then
                ui.set(settings[setting_name], false)
            else
                local num = tonumber(value)
                if num then
                    ui.set(settings[setting_name], num)
                else
                    ui.set(settings[setting_name], value)
                end
            end
        end
        index = index + 1
    end
    
    -- Load damage indicator position (only if new format)
    if not is_old_format and data[index] and data[index + 1] then
        damage_indicator_vars.offset_x = tonumber(data[index]) or 5
        damage_indicator_vars.offset_y = tonumber(data[index + 1]) or -20
        index = index + 2
    end
    
    -- Load hotkeys (only if new format)
    if not is_old_format then
        local hotkey_settings = {'manual_forward', 'manual_right', 'manual_left', 'edge_yaw', 'freestanding'}
        for _, setting_name in ipairs(hotkey_settings) do
            if settings[setting_name] and data[index] and data[index] ~= "nil" then
                local mode = tonumber(data[index])
                if mode then
                    ui.set(settings[setting_name], mode)
                end
            end
            index = index + 1
        end
    end
    
    -- Load color pickers
    local color_settings = {'label_color1', 'label_color2', 'fog_color', 'wall_color', 'color_correction_color', 'advanced_panel_accent_color'}
    for _, setting_name in ipairs(color_settings) do
        if settings[setting_name] and data[index] then
            local colors = split_string(data[index], ",")
            if #colors == 4 then
                ui.set(settings[setting_name], tonumber(colors[1]), tonumber(colors[2]), tonumber(colors[3]), tonumber(colors[4]))
            end
        end
        index = index + 1
    end
    
    -- Load multiselect
    local multi_settings = {'freestanding_conditions', 'tweaks', 'fps_boosters', 'anim_breakers'}
    for _, setting_name in ipairs(multi_settings) do
        if settings[setting_name] and data[index] and data[index] ~= "" then
            local items = split_string(data[index], ";")
            ui.set(settings[setting_name], items)
        end
        index = index + 1
    end
    
    client.color_log(173, 255, 47, 'aimplay ')
    if is_old_format then
        client.color_log(255, 255, 255, '› imported config (old format)')
    else
        client.color_log(255, 255, 255, '› imported config')
    end
end

-- Export to clipboard
local function export_config()
    local files = get_config_files()
    local selected = ui.get(settings.config_list)
    if not selected or selected < 0 or not files[selected + 1] then
        client.color_log(173, 255, 47, 'aimplay ')
        client.color_log(255, 100, 100, '› no config selected')
        return
    end
    
    local content = readfile(files[selected + 1])
    if content == "blank" or content == "" then
        client.color_log(173, 255, 47, 'aimplay ')
        client.color_log(255, 100, 100, '› config is empty')
        return
    end
    
    clipboard.set(content)
    
    local name = files[selected + 1]:gsub('.cfg', '')
    client.color_log(173, 255, 47, 'aimplay ')
    client.color_log(255, 255, 255, '› config ')
    client.color_log(173, 255, 47, name)
    client.color_log(255, 255, 255, ' exported')
end

-- Config list callback
ui.set_callback(settings.config_list, function(value)
    local files = get_config_files()
    local selected = ui.get(settings.config_list) + 1
    if files[selected] then
        local name = files[selected]:gsub('.cfg', '')
        ui.set(settings.config_name, name)
    end
end)

-- Create button callback
ui.set_callback(settings.config_create, function()
    client.exec("play buttons/button9")
    create_config()
    -- Update list after creation
    client.delay_call(0.1, function()
        ui.update(settings.config_list, update_cfg())
    end)
end)

-- Save button callback
ui.set_callback(settings.config_save, function()
    client.exec("play buttons/button9")
    save_config()
end)

-- Load button callback
ui.set_callback(settings.config_load, function()
    client.exec("play buttons/button9")
    load_config()
end)

-- Delete button callback
ui.set_callback(settings.config_delete, function()
    client.exec("play buttons/button9")
    delete_config()
    -- Update list after deletion
    client.delay_call(0.1, function()
        ui.update(settings.config_list, update_cfg())
    end)
end)

-- Import button callback
ui.set_callback(settings.config_import, function()
    client.exec("play buttons/button9")
    import_config()
end)

-- Export button callback
ui.set_callback(settings.config_export, function()
    client.exec("play buttons/button9")
    export_config()
end)

-- Initialize config list on script load
client.delay_call(0.1, function()
    ui.update(settings.config_list, update_cfg())
end)

-- Shutdown callback
client.set_event_callback('shutdown', function()
    -- Save statistics before shutdown
    save_stats()
    
    ui.set_visible(reference.pitch[1], true)
    ui.set_visible(reference.yaw_base, true)
    ui.set_visible(reference.yaw[1], true)
    ui.set_visible(reference.body_yaw[1], true)
    ui.set_visible(reference.edge_yaw, true)
    ui.set_visible(reference.freestanding[1], true)
    ui.set_visible(reference.freestanding[2], true)
    ui.set_visible(reference.roll, true)

    ui.set(reference.pitch[1], 'Off')
    ui.set(reference.pitch[2], 0)
    ui.set(reference.yaw_base, 'Local view')
    ui.set(reference.yaw[1], 'Off')
    ui.set(reference.yaw[2], 0)
    ui.set(reference.yaw_jitter[1], 'Off')
    ui.set(reference.yaw_jitter[2], 0)
    ui.set(reference.body_yaw[1], 'Off')
    ui.set(reference.body_yaw[2], 0)
    ui.set(reference.freestanding_body_yaw, false)
    ui.set(reference.edge_yaw, false)
    ui.set(reference.freestanding[1], false)
    ui.set(reference.freestanding[2], 'On hotkey')
    ui.set(reference.roll, 0)
    
    -- Reset Visual World settings
    local tone_map_controllers = entity.get_all("CEnvTonemapController")
    for i=1, #tone_map_controllers do
        local tone_map_controller = tone_map_controllers[i]
        if bloom_prev ~= -1 and bloom_default ~= nil then
            reset_bloom(tone_map_controller)
        end
        if exposure_prev ~= -1 and exposure_min_default ~= nil then
            reset_exposure(tone_map_controller)
        end
    end
    mat_ambient_light_r:set_raw_float(0)
    mat_ambient_light_g:set_raw_float(0)
    mat_ambient_light_b:set_raw_float(0)
    r_modelAmbientMin:set_raw_float(0)
end)

-- Player death event for statistics
client.set_event_callback('player_death', function(e)
    local me = entity.get_local_player()
    if not me then return end
    
    local victim = client.userid_to_entindex(e.userid)
    local attacker = client.userid_to_entindex(e.attacker)
    
    if attacker == me and victim ~= me then
        stats.kills = stats.kills + 1
        save_stats()
    elseif victim == me then
        stats.deaths = stats.deaths + 1
        save_stats()
    end
end)

-- Track enemy misses on me
-- Only count shots that were aimed at me (bullet passed close to me)
local pending_shots = {}

client.set_event_callback('bullet_impact', function(e)
    local me = entity.get_local_player()
    if not me then return end
    
    local shooter = client.userid_to_entindex(e.userid)
    
    -- Only track enemy shots (not teammates, not me)
    if shooter and shooter ~= me and entity.is_alive(shooter) and entity.is_enemy(shooter) then
        -- Get bullet impact position
        local impact_pos = vector(e.x, e.y, e.z)
        
        -- Get my position (head position for better accuracy)
        local my_x, my_y, my_z = entity.hitbox_position(me, 0)
        if not my_x then
            my_x, my_y, my_z = entity.get_prop(me, "m_vecOrigin")
            my_z = my_z + 64 -- approximate head height
        end
        local my_pos = vector(my_x, my_y, my_z)
        
        -- Calculate distance from bullet impact to me
        local distance = impact_pos:dist(my_pos)
        
        -- Only count if bullet was close (within 150 units = aimed at me)
        if distance < 150 then
            table.insert(pending_shots, {
                shooter = shooter,
                time = globals.realtime(),
                distance = distance
            })
        end
    end
end)

client.set_event_callback('player_hurt', function(e)
    local me = entity.get_local_player()
    if not me then return end
    
    local victim = client.userid_to_entindex(e.userid)
    local attacker = client.userid_to_entindex(e.attacker)
    
    -- If I got hit, remove the most recent shot from this attacker (it was a hit, not a miss)
    if victim == me and attacker and attacker ~= me then
        for i = #pending_shots, 1, -1 do
            if pending_shots[i].shooter == attacker then
                table.remove(pending_shots, i)
                break
            end
        end
    end
end)

-- Process old shots as misses
client.set_event_callback('paint', function()
    local me = entity.get_local_player()
    if not me then return end
    
    local current_time = globals.realtime()
    
    -- Check shots older than 0.3 seconds - they are misses
    for i = #pending_shots, 1, -1 do
        if current_time - pending_shots[i].time > 0.3 then
            stats.misses = stats.misses + 1
            save_stats()
            table.remove(pending_shots, i)
        end
    end
end)



-- Shutdown callback to restore cheat UI elements
client.set_event_callback("shutdown", function()
    -- Restore all AA elements
    ui.set_visible(reference.aa_enabled, true)
    ui.set_visible(reference.pitch[1], true)
    ui.set_visible(reference.pitch[2], true)
    ui.set_visible(reference.yaw_base, true)
    ui.set_visible(reference.yaw[1], true)
    ui.set_visible(reference.yaw[2], true)
    ui.set_visible(reference.yaw_jitter[1], true)
    ui.set_visible(reference.yaw_jitter[2], true)
    ui.set_visible(reference.body_yaw[1], true)
    ui.set_visible(reference.body_yaw[2], true)
    ui.set_visible(reference.freestanding_body_yaw, true)
    ui.set_visible(reference.edge_yaw, true)
    ui.set_visible(reference.freestanding[1], true)
    ui.set_visible(reference.freestanding[2], true)
    ui.set_visible(reference.roll, true)
    ui.set_visible(reference.other_on_shot[1], true)
    ui.set_visible(reference.other_on_shot[2], true)
    ui.set_visible(reference.other_slow_motion[1], true)
    ui.set_visible(reference.other_slow_motion[2], true)
    ui.set_visible(reference.other_leg_movement, true)
    -- Duck peek assist visibility is managed by user, don't force show
    ui.set_visible(reference.other_fake_peek[1], true)
    ui.set_visible(reference.other_fake_peek[2], true)
    
    -- Restore fake lag elements
    ui.set_visible(reference.fake_lag_enabled, true)
    ui.set_visible(reference.fake_lag_amount, true)
    ui.set_visible(reference.fake_lag_variance, true)
    ui.set_visible(reference.fake_lag_limit, true)
end)


-- Initialize watermark elements
ui.set(settings.watermark_elements, {"FPS", "PING", "DELAY", "CPU", "GPU", "Time"})
