-- Shared slider style for the SimpleUI Quick Settings panel and KOReader's
-- native frontlight dialog.

local BD         = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Device     = require("device")
local Geom       = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local UIManager  = require("ui/uimanager")
local logger     = require("logger")

local Screen = Device.screen

local P = {
    id              = "qs_slider_style",
    name            = "前光灯：滑块样式",
    plugin_name     = "SimpleUI",
    plugin_order    = 10,
    description     = "为 SimpleUI 快捷设置栏添加“原版 / 细线 / 圆形”滑块样式选择，同步到 KOReader 原生前光灯窗口，并为亮度和色温提供跟手实时拖动。",
    default_enabled = true,
}

local STYLE_KEY      = "simpleui_qs_bar_slider_style"
local STYLE_ORIGINAL = "original"
local STYLE_THIN     = "thin"
local STYLE_CIRCLE   = "circle"
local TRACK_HEIGHT   = Screen:scaleBySize(2)
local THUMB_WIDTH    = Screen:scaleBySize(3)
local THUMB_HEIGHT   = Screen:scaleBySize(14)
local CIRCLE_DIAMETER = Screen:scaleBySize(26)
local CIRCLE_BORDER   = math.max(1, Screen:scaleBySize(1))
local SMALL_BUTTON_WIDTH = Screen:scaleBySize(40)
local MAX_BUTTON_WIDTH   = Screen:scaleBySize(50)
-- Narrow only the step-button hit boxes in circle mode. The released width is
-- reassigned to the progress widget, keeping the complete row within bounds.
local CIRCLE_STEP_BUTTON_WIDTH = Screen:scaleBySize(28)
local CIRCLE_STEP_BUTTON_REDUCTION = SMALL_BUTTON_WIDTH - CIRCLE_STEP_BUTTON_WIDTH

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
    local style = SUISettings:readSetting(STYLE_KEY)
    if style == STYLE_THIN or style == STYLE_CIRCLE then return style end
    return STYLE_ORIGINAL
end

local function mirroredFor(widget)
    local mirrored = widget.allow_mirroring ~= false and BD.mirroredUILayout() or false
    if widget.invert_direction then mirrored = not mirrored end
    return mirrored
end

local function clampPercentage(value)
    return math.max(0, math.min(1, tonumber(value) or 0))
end

local function positionIntersects(pos, dimen)
    if not pos or not dimen then return false end
    if type(pos.intersectWith) == "function" then
        return pos:intersectWith(dimen)
    end
    return pos.x and pos.y
        and pos.x >= (dimen.x or 0)
        and pos.x <= (dimen.x or 0) + (dimen.w or 0)
        and pos.y >= (dimen.y or 0)
        and pos.y <= (dimen.y or 0) + (dimen.h or 0)
end

local function percentageFromPosition(widget, pos)
    local dimen = widget and widget.dimen
    if not dimen or not pos or not pos.x then return nil end
    local width = tonumber(dimen.w) or tonumber(widget.width) or 0
    if width <= 0 then return nil end
    local percentage = (pos.x - (dimen.x or 0)) / width
    if mirroredFor(widget) then percentage = 1 - percentage end
    return clampPercentage(percentage)
end

local function sliderAtPosition(refs, pos)
    if refs and refs.fl_progress
            and positionIntersects(pos, refs.fl_progress.dimen) then
        return "brightness"
    end
    if refs and refs.nl_progress
            and positionIntersects(pos, refs.nl_progress.dimen) then
        return "warmth"
    end
end

local function adjustSimpleSlider(menu, slider, pos, final)
    local refs = menu and menu._sui_qs_refs
    if not refs then return false end

    if slider == "brightness" then
        local progress = refs.fl_progress
        local percentage = percentageFromPosition(progress, pos)
        local state = refs.fl_state
        if not percentage or not state or type(refs.setBrightness) ~= "function" then
            return false
        end
        local minimum = tonumber(state.min) or 0
        local maximum = tonumber(state.max) or minimum
        local value = math.floor(minimum + percentage * (maximum - minimum) + 0.5)
        if final or value ~= menu._mysui_last_drag_brightness then
            menu._mysui_last_drag_brightness = value
            refs.setBrightness(value)
        end
        return true
    end

    if slider == "warmth" then
        local progress = refs.nl_progress
        local percentage = percentageFromPosition(progress, pos)
        if not percentage or not progress or type(progress.callback) ~= "function" then
            return false
        end

        local powerd = Device:getPowerDevice()
        local minimum = tonumber(powerd.fl_warmth_min) or 0
        local maximum = tonumber(powerd.fl_warmth_max) or minimum
        local steps = maximum - minimum + 1
        local stride = math.ceil(steps * (1 / 25))
        local native_value = math.floor(minimum + percentage * (maximum - minimum) + 0.5)
        if final or native_value ~= menu._mysui_last_drag_warmth then
            menu._mysui_last_drag_warmth = native_value
            -- SimpleUI's callback accepts a numeric step index. A fractional
            -- index maps back to an exact native warmth value, so dragging is
            -- continuous instead of snapping to the visible button segments.
            progress.callback(native_value / stride)
            progress.position = percentage * (tonumber(progress.num_buttons) or 0)
            if (final or getStyle() == STYLE_ORIGINAL)
                    and type(progress.update) == "function" then
                progress:update()
            end
        end
        return true
    end
    return false
end

local function paintCustomTrack(widget, bb, x, y, width, height, percentage, clear_first)
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

    if getStyle() == STYLE_CIRCLE then
        -- Reference style: an outlined white circular thumb over a thin track.
        -- Keep the whole circle inside the progress widget at both endpoints.
        local diameter = math.max(2, math.min(CIRCLE_DIAMETER, width, height))
        local radius = math.floor(diameter / 2)
        local center_x = math.max(x + radius, math.min(x + width - radius, marker_x))
        local circle_x = center_x - radius
        local circle_y = center_y - radius
        bb:paintRoundedRect(
            circle_x, circle_y, diameter, diameter,
            Blitbuffer.COLOR_BLACK, radius
        )

        local border = math.min(CIRCLE_BORDER, math.max(1, radius - 1))
        local inner_diameter = diameter - 2 * border
        if inner_diameter > 0 then
            bb:paintRoundedRect(
                circle_x + border,
                circle_y + border,
                inner_diameter,
                inner_diameter,
                Blitbuffer.COLOR_WHITE,
                math.max(0, radius - border)
            )
        end
    else
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
end

local function applyCustomBrightnessStyle(progress)
    if not progress or progress._mysui_custom_slider then return end
    progress._mysui_custom_slider = true
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
        paintCustomTrack(self, bb, x, y, width, height, self.percentage, false)
    end
end

local function getButtonProgressSize(progress)
    local frame = progress and progress.buttonprogress_frame
    if frame and type(frame.getSize) == "function" then
        local size = frame:getSize()
        if size and size.w and size.h then return size end
    end
    return {
        w = progress and (progress.width or (progress.dimen and progress.dimen.w)) or 0,
        h = progress and (progress.height or (progress.dimen and progress.dimen.h)) or 0,
    }
end

local function applyCustomWarmthStyle(progress)
    if not progress or progress._mysui_custom_slider then return end
    local original_paintTo = progress.paintTo
    if type(original_paintTo) ~= "function" then return end
    progress._mysui_custom_slider = true

    progress.paintTo = function(self, bb, x, y)
        -- Preserve child layout and hit boxes, then cover the segmented visual.
        original_paintTo(self, bb, x, y)
        local size = getButtonProgressSize(self)
        local width = size.w
        local height = size.h
        if self.dimen then
            self.dimen.w, self.dimen.h = width, height
        end
        local button_count = tonumber(self.num_buttons) or 0
        local position = tonumber(self.position) or 0
        local percentage = button_count > 0 and position / button_count or 0
        paintCustomTrack(self, bb, x, y, width, height, percentage, true)
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
            {
                text = "圆形 / Circle",
                radio = true,
                checked_func = function() return getStyle() == STYLE_CIRCLE end,
                keep_menu_open = true,
                callback = function()
                    SUISettings:saveSetting(STYLE_KEY, STYLE_CIRCLE)
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
        local style = getStyle()
        local quick_panel = self.item_table and self.item_table._sui_qs_panel
        local custom_panel = style ~= STYLE_ORIGINAL and quick_panel
        local warmth_widgets = {}
        local ProgressWidget
        local original_progress_init
        local ButtonProgressWidget
        local original_bpw_init
        local Button
        local original_button_init

        -- The circular reference style uses plain −/+ glyphs and has no Max
        -- action. Intercept only the Buttons synchronously created while this
        -- panel is being built; restore the class immediately afterwards.
        if custom_panel and style == STYLE_CIRCLE then
            local ok_progress, ProgressClass = pcall(require, "ui/widget/progresswidget")
            if ok_progress and ProgressClass and type(ProgressClass.init) == "function" then
                ProgressWidget = ProgressClass
                original_progress_init = ProgressClass.init
                ProgressClass.init = function(widget, ...)
                    original_progress_init(widget, ...)
                    if not widget._mysui_circle_layout_width then
                        widget._mysui_circle_layout_width = true
                        widget.width = (widget.width or 0)
                            + MAX_BUTTON_WIDTH
                            + 2 * CIRCLE_STEP_BUTTON_REDUCTION
                        if widget.dimen then
                            widget.dimen.w = widget.width
                        end
                    end
                end
            end

            local ok_button, ButtonClass = pcall(require, "ui/widget/button")
            if ok_button and ButtonClass and type(ButtonClass.init) == "function" then
                Button = ButtonClass
                original_button_init = ButtonClass.init
                ButtonClass.init = function(widget, ...)
                    local text = widget.text
                    local width = widget.width
                    local is_step_button = width == SMALL_BUTTON_WIDTH
                        and (text == "−" or text == "＋" or text == "-" or text == "+")
                    local is_max_button = width == MAX_BUTTON_WIDTH
                        and type(text) == "string"
                        and text ~= ""
                        and not is_step_button

                    if is_step_button then
                        widget.bordersize = 0
                    elseif is_max_button then
                        -- Blank the label before Button:init() creates its
                        -- TextWidget, preventing any glyph/line residue even
                        -- if a parent takes an unexpected paint path.
                        widget.text = ""
                    end
                    original_button_init(widget, ...)

                    if is_step_button then
                        widget.width = CIRCLE_STEP_BUTTON_WIDTH
                        if widget.dimen then
                            widget.dimen.w = CIRCLE_STEP_BUTTON_WIDTH
                        end
                        if widget.frame then
                            widget.frame.bordersize = 0
                            widget.frame.color = Blitbuffer.COLOR_WHITE
                        end
                    elseif is_max_button then
                        local original_size = widget:getSize()
                        widget.callback = nil
                        widget.enabled = false
                        widget.hidden = true
                        widget.no_focus = true
                        widget.focusable = false
                        widget.ges_events = {}
                        if widget.label_widget then
                            widget.label_widget.hide = true
                        end
                        if widget.frame then
                            widget.frame.bordersize = 0
                            widget.frame.background = Blitbuffer.COLOR_WHITE
                            widget.frame.invert = false
                        end
                        widget.dimen.w = 0
                        widget.getSize = function()
                            return { w = 0, h = original_size.h or 0 }
                        end
                        widget.paintTo = function() end
                    end
                end
            end
        end

        if quick_panel and Device:hasNaturalLight() then
            local ok_bpw, BPW = pcall(require, "ui/widget/buttonprogresswidget")
            if ok_bpw and BPW and type(BPW.init) == "function" then
                ButtonProgressWidget = BPW
                original_bpw_init = BPW.init
                BPW.init = function(widget, ...)
                    original_bpw_init(widget, ...)
                    if style == STYLE_CIRCLE and not widget._mysui_circle_layout_width then
                        widget._mysui_circle_layout_width = true
                        widget.width = (widget.width or 0)
                            + MAX_BUTTON_WIDTH
                            + 2 * CIRCLE_STEP_BUTTON_REDUCTION
                        if type(widget.update) == "function" then
                            widget:update()
                        end
                        -- ButtonProgressWidget:update() rebuilds its children,
                        -- but does not refresh the outer geometry created by
                        -- init(). Keep paint bounds and hit testing aligned
                        -- with the expanded circular slider.
                        if widget.dimen then
                            local size = getButtonProgressSize(widget)
                            widget.dimen.w, widget.dimen.h = size.w, size.h
                        end
                    end
                    warmth_widgets[#warmth_widgets + 1] = widget
                end
            end
        end

        local results = { pcall(original_updateItems, self, ...) }
        if ButtonProgressWidget and original_bpw_init then
            ButtonProgressWidget.init = original_bpw_init
        end
        if ProgressWidget and original_progress_init then
            ProgressWidget.init = original_progress_init
        end
        if Button and original_button_init then
            Button.init = original_button_init
        end
        if not results[1] then error(results[2]) end

        if quick_panel then
            local refs = self._sui_qs_refs
            if refs then
                refs.nl_progress = warmth_widgets[#warmth_widgets]
            end
            self._mysui_slider_drag = nil
            self._mysui_last_drag_brightness = nil
            self._mysui_last_drag_warmth = nil
            self.ges_events = self.ges_events or {}
            self.ges_events.MysuiSliderPanRelease = {
                GestureRange:new{ ges = "pan_release", range = self.dimen },
            }
        end

        if custom_panel then
            local refs = self._sui_qs_refs
            if refs then applyCustomBrightnessStyle(refs.fl_progress) end
            for _, widget in ipairs(warmth_widgets) do
                applyCustomWarmthStyle(widget)
            end
            UIManager:setDirty(self.show_parent or self, "ui")
        end

        table.remove(results, 1)
        return unpack(results)
    end

    local original_onTap = TouchMenu.onTapCloseAllMenus
    TouchMenu.onTapCloseAllMenus = function(self, arg, ges_ev)
        local refs = self._sui_qs_refs
        local slider = refs and sliderAtPosition(refs, ges_ev and ges_ev.pos)
        if slider and adjustSimpleSlider(self, slider, ges_ev.pos, true) then
            self._mysui_slider_drag = nil
            return true
        end
        if original_onTap then return original_onTap(self, arg, ges_ev) end
    end

    local original_onPan = TouchMenu.onPan
    TouchMenu.onPan = function(self, arg, ges_ev)
        if self._sui_qs_refs and ges_ev and not ges_ev.mousewheel_direction then
            local slider = self._mysui_slider_drag
                or sliderAtPosition(self._sui_qs_refs, ges_ev.pos)
            if slider then
                self._mysui_slider_drag = slider
                if adjustSimpleSlider(self, slider, ges_ev.pos, false) then
                    return true
                end
            end
        end
        if original_onPan then return original_onPan(self, arg, ges_ev) end
    end

    local original_onSwipe = TouchMenu.onSwipe
    TouchMenu.onSwipe = function(self, arg, ges_ev)
        if self._mysui_slider_drag and ges_ev then
            local slider = self._mysui_slider_drag
            self._mysui_slider_drag = nil
            adjustSimpleSlider(self, slider, ges_ev.pos, true)
            return true
        end
        if original_onSwipe then return original_onSwipe(self, arg, ges_ev) end
    end

    TouchMenu.onMysuiSliderPanRelease = function(self, arg, ges_ev)
        local slider = self._mysui_slider_drag
        self._mysui_slider_drag = nil
        if slider and ges_ev then
            adjustSimpleSlider(self, slider, ges_ev.pos, true)
            return true
        end
    end
    return true
end

local function patchNativeFrontlight()
    local FrontLightWidget = require("ui/widget/frontlightwidget")
    if FrontLightWidget._mysui_slider_style_patched then return true end

    local original_layout = FrontLightWidget.layout
    local original_onTapProgress = FrontLightWidget.onTapProgress
    local original_onPanProgress = FrontLightWidget.onPanProgress
    if type(original_layout) ~= "function" then
        error("FrontLightWidget.layout is unavailable")
    end

    local function adjustNativeWarmth(widget, pos)
        local progress = widget.nl_progress
        local percentage = percentageFromPosition(progress, pos)
        if not percentage or not widget.nl or type(widget.setWarmth) ~= "function" then
            return false
        end

        local minimum = tonumber(widget.nl.min) or 0
        local maximum = tonumber(widget.nl.max) or minimum
        local value = math.floor(minimum + percentage * (maximum - minimum) + 0.5)
        if value ~= widget.nl.cur then
            widget:setWarmth(value, true)
        end
        if getStyle() ~= STYLE_ORIGINAL then
            progress.position = percentage * (tonumber(progress.num_buttons) or 0)
            UIManager:setDirty(widget, "ui")
        end
        return true
    end

    FrontLightWidget._mysui_slider_style_patched = true
    FrontLightWidget.layout = function(self, ...)
        local results = { pcall(original_layout, self, ...) }
        if not results[1] then error(results[2]) end

        local style = getStyle()
        -- Keep KOReader's native button rows and actions intact. Only the two
        -- slider instances share SimpleUI's selected track/thumb style.
        if style ~= STYLE_ORIGINAL then
            applyCustomBrightnessStyle(self.fl_progress)
            applyCustomWarmthStyle(self.nl_progress)
        end

        if self.ges_events then
            self.ges_events.MysuiNativeSliderPanRelease = {
                GestureRange:new{
                    ges = "pan_release",
                    range = Geom:new{
                        x = 0, y = 0,
                        w = self.screen_width,
                        h = self.screen_height,
                    },
                },
            }
        end

        table.remove(results, 1)
        return unpack(results)
    end

    FrontLightWidget.onTapProgress = function(self, arg, ges_ev)
        if self.has_nl and self.nl_progress
                and positionIntersects(ges_ev and ges_ev.pos, self.nl_progress.dimen)
                and adjustNativeWarmth(self, ges_ev.pos) then
            self._mysui_native_slider_drag = nil
            return true
        end
        if original_onTapProgress then
            return original_onTapProgress(self, arg, ges_ev)
        end
    end

    FrontLightWidget.onPanProgress = function(self, arg, ges_ev)
        if self.has_nl and self.nl_progress and ges_ev then
            local dragging_warmth = self._mysui_native_slider_drag == "warmth"
            if dragging_warmth
                    or positionIntersects(ges_ev.pos, self.nl_progress.dimen) then
                self._mysui_native_slider_drag = "warmth"
                if adjustNativeWarmth(self, ges_ev.pos) then return true end
            end
        end
        if original_onPanProgress then
            return original_onPanProgress(self, arg, ges_ev)
        end
    end

    FrontLightWidget.onMysuiNativeSliderPanRelease = function(self, arg, ges_ev)
        local dragging_warmth = self._mysui_native_slider_drag == "warmth"
        self._mysui_native_slider_drag = nil
        if dragging_warmth and ges_ev then
            adjustNativeWarmth(self, ges_ev.pos)
            return true
        end
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
    patchNativeFrontlight()
    applied = true
    if not panel_ok then
        -- The style menu is already installed. If the Quick Settings Bar is
        -- enabled later, SimpleUI asks for a restart; the panel hook will then
        -- be present on the next boot, so this is not a patch failure.
        logger.info("Plugin_enhancements/qs_slider_style: " .. tostring(reason))
        return true
    end
    logger.info("Plugin_enhancements/qs_slider_style: applied")
    return true
end

return P
