-- Selectable slider style for the SimpleUI Quick Settings panel.

local BD         = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Device     = require("device")
local Geom       = require("ui/geometry")
local UIManager  = require("ui/uimanager")
local logger     = require("logger")

local Screen = Device.screen

local P = {
    id              = "qs_slider_style",
    name            = "快捷设置栏：滑块样式",
    description     = "为 SimpleUI 快捷设置栏添加“原版 / 细线”滑块样式选择；自动兼容仅亮度和亮度＋色温设备。",
    default_enabled = true,
}

local STYLE_KEY      = "simpleui_qs_bar_slider_style"
local STYLE_ORIGINAL = "original"
local STYLE_THIN     = "thin"
local TRACK_HEIGHT   = Screen:scaleBySize(2)
local THUMB_WIDTH    = Screen:scaleBySize(3)
local THUMB_HEIGHT   = Screen:scaleBySize(14)

local SUISettings

local function requireFirst(...)
    local names = { ... }
    local last_error
    for _, name in ipairs(names) do
        local ok, module = pcall(require, name)
        if ok then return module end
        last_error = module
    end
    error(last_error or "module not found")
end

local function getStyle()
    return SUISettings:readSetting(STYLE_KEY) == STYLE_THIN
        and STYLE_THIN or STYLE_ORIGINAL
end

local function mirroredFor(widget)
    local mirrored = widget.allow_mirroring ~= false and BD.mirroredUILayout() or false
    if widget.invert_direction then mirrored = not mirrored end
    return mirrored
end

local function clampPercentage(value)
    return math.max(0, math.min(1, tonumber(value) or 0))
end

local function paintThinTrack(widget, bb, x, y, width, height, percentage, clear_first)
    width = math.max(0, math.floor(tonumber(width) or 0))
    height = math.max(0, math.floor(tonumber(height) or 0))
    if clear_first and width > 0 and height > 0 then
        bb:paintRect(x, y, width, height, Blitbuffer.COLOR_WHITE)
    end
    if width <= 0 or height <= 0 then return end

    local percentage_value = clampPercentage(percentage)
    local mirrored = mirroredFor(widget)
    local center_y = y + math.floor(height / 2)
    local track_y = center_y - math.floor(TRACK_HEIGHT / 2)
    bb:paintRect(x, track_y, width, TRACK_HEIGHT, Blitbuffer.COLOR_LIGHT_GRAY)

    local marker_x
    if mirrored then
        marker_x = x + math.floor(width * (1 - percentage_value))
        local fill_width = x + width - marker_x
        if fill_width > 0 then
            bb:paintRect(marker_x, track_y, fill_width, TRACK_HEIGHT, Blitbuffer.COLOR_BLACK)
        end
    else
        marker_x = x + math.floor(width * percentage_value)
        local fill_width = marker_x - x
        if fill_width > 0 then
            bb:paintRect(x, track_y, fill_width, TRACK_HEIGHT, Blitbuffer.COLOR_BLACK)
        end
    end

    local thumb_x = marker_x - math.floor(THUMB_WIDTH / 2)
    thumb_x = math.max(x, math.min(x + width - THUMB_WIDTH, thumb_x))
    bb:paintRect(
        thumb_x,
        center_y - math.floor(THUMB_HEIGHT / 2),
        THUMB_WIDTH,
        THUMB_HEIGHT,
        Blitbuffer.COLOR_BLACK
    )
end

local function applyThinBrightnessStyle(progress)
    if not progress or progress._mysui_thin_slider then return end
    progress._mysui_thin_slider = true
    progress.margin_h = 0
    progress.margin_v = 0
    progress.bordersize = 0
    progress.ticks = nil

    progress.paintTo = function(self, bb, x, y)
        local width = self.width or 0
        local height = self.height or 0
        if not self.dimen then
            self.dimen = Geom:new{ x = x, y = y, w = width, h = height }
        else
            self.dimen.x, self.dimen.y = x, y
            self.dimen.w, self.dimen.h = width, height
        end
        paintThinTrack(self, bb, x, y, width, height, self.percentage, false)
    end
end

local function applyThinWarmthStyle(progress)
    if not progress or progress._mysui_thin_slider then return end
    local original_paintTo = progress.paintTo
    if type(original_paintTo) ~= "function" then return end
    progress._mysui_thin_slider = true

    progress.paintTo = function(self, bb, x, y)
        -- Preserve child layout and hit boxes, then cover the segmented visual.
        original_paintTo(self, bb, x, y)
        local width = self.dimen and self.dimen.w or self.width or 0
        local height = self.dimen and self.dimen.h or self.height or 0
        local button_count = tonumber(self.num_buttons) or 0
        local position = tonumber(self.position) or 0
        local percentage = button_count > 0 and position / button_count or 0
        paintThinTrack(self, bb, x, y, width, height, percentage, true)
    end
end

local function refreshQuickSettings(ctx_menu)
    if ctx_menu and type(ctx_menu.refresh) == "function" then
        pcall(ctx_menu.refresh)
    end

    local function rebuild(menu)
        if not menu then return end
        menu.is_fresh = true
        if menu.item_table and menu.item_table._sui_qs_panel then
            pcall(function() menu:updateItems() end)
        end
    end

    local FM = package.loaded["apps/filemanager/filemanager"]
    if FM and FM.instance then rebuild(FM.instance.menu) end
    local RUI = package.loaded["apps/reader/readerui"]
    if RUI and RUI.instance then rebuild(RUI.instance.menu) end
end

local function makeStyleMenuItem(ctx_menu)
    return {
        text = "滑块样式 / Slider Style",
        enabled_func = function() return Device:hasFrontlight() end,
        sub_item_table = {
            {
                text = "原版 / Original",
                radio = true,
                checked_func = function() return getStyle() == STYLE_ORIGINAL end,
                keep_menu_open = true,
                callback = function()
                    SUISettings:saveSetting(STYLE_KEY, STYLE_ORIGINAL)
                    refreshQuickSettings(ctx_menu)
                end,
            },
            {
                text = "细线 / Thin",
                radio = true,
                checked_func = function() return getStyle() == STYLE_THIN end,
                keep_menu_open = true,
                callback = function()
                    SUISettings:saveSetting(STYLE_KEY, STYLE_THIN)
                    refreshQuickSettings(ctx_menu)
                end,
            },
        },
    }
end

local function patchSettingsMenu(QSBar)
    if QSBar._mysui_slider_menu_patched then return end
    local original_makeMenuItems = QSBar.makeMenuItems
    if type(original_makeMenuItems) ~= "function" then
        error("QSBar.makeMenuItems is unavailable")
    end
    QSBar._mysui_slider_menu_patched = true

    QSBar.makeMenuItems = function(ctx_menu)
        local items = original_makeMenuItems(ctx_menu)
        if type(items) ~= "table" then return items end

        local insert_at = #items + 1
        for index, item in ipairs(items) do
            if item.text == "Warmth Slider" or item.text == "色温滑块" then
                insert_at = index + 1
                break
            end
        end
        table.insert(items, insert_at, makeStyleMenuItem(ctx_menu))
        return items
    end
end

local function patchPanelBuilder()
    local TouchMenu = require("ui/widget/touchmenu")
    if TouchMenu._mysui_slider_style_patched then return true end
    if not TouchMenu._sui_qs_patched then
        return false, "SimpleUI 快捷设置栏当前未启用；启用并重启后补丁会自动生效"
    end

    local original_updateItems = TouchMenu.updateItems
    TouchMenu._mysui_slider_style_patched = true

    TouchMenu.updateItems = function(self, ...)
        local thin_panel = getStyle() == STYLE_THIN
            and self.item_table
            and self.item_table._sui_qs_panel
        local warmth_widgets = {}
        local ButtonProgressWidget
        local original_bpw_init

        if thin_panel and Device:hasNaturalLight() then
            local ok_bpw, BPW = pcall(require, "ui/widget/buttonprogresswidget")
            if ok_bpw and BPW and type(BPW.init) == "function" then
                ButtonProgressWidget = BPW
                original_bpw_init = BPW.init
                BPW.init = function(widget, ...)
                    original_bpw_init(widget, ...)
                    warmth_widgets[#warmth_widgets + 1] = widget
                end
            end
        end

        local results = { pcall(original_updateItems, self, ...) }
        if ButtonProgressWidget and original_bpw_init then
            ButtonProgressWidget.init = original_bpw_init
        end
        if not results[1] then error(results[2]) end

        if thin_panel then
            local refs = self._sui_qs_refs
            if refs then applyThinBrightnessStyle(refs.fl_progress) end
            for _, widget in ipairs(warmth_widgets) do
                applyThinWarmthStyle(widget)
            end
            UIManager:setDirty(self.show_parent or self, "ui")
        end

        table.remove(results, 1)
        return unpack(results)
    end
    return true
end

local applied = false

function P.apply()
    if applied then return true end

    SUISettings = package.loaded["infra/sui_store"]
        or package.loaded["sui_store"]
        or requireFirst("infra/sui_store", "sui_store")
    local QSBar = requireFirst(
        "screens/sui_quicksettings_bar",
        "sui_quicksettings_bar"
    )

    patchSettingsMenu(QSBar)
    local panel_ok, reason = patchPanelBuilder()
    applied = true
    if not panel_ok then
        -- The style menu is already installed. If the Quick Settings Bar is
        -- enabled later, SimpleUI asks for a restart; the panel hook will then
        -- be present on the next boot, so this is not a patch failure.
        logger.info("mysimpleui_ext/qs_slider_style: " .. tostring(reason))
        return true
    end
    logger.info("mysimpleui_ext/qs_slider_style: applied")
    return true
end

return P
