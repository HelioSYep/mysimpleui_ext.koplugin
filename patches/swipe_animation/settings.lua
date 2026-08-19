local Device = require("device")
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template

local M = {}

local defaults = {
    landscape = 10,
    portrait = 20,
}

local function isAnimationEnabled()
    return G_reader_settings:isTrue("swipe_animations")
end

local function setAnimationEnabled(enabled)
    if enabled then
        G_reader_settings:saveSetting("swipe_animations", true)
    else
        G_reader_settings:delSetting("swipe_animations")
    end
end

local function getRefreshMode()
    return G_reader_settings:readSetting("swipe_animation_refresh_mode") == "fast" and "fast" or "ui"
end

local function setRefreshMode(mode)
    if mode == "fast" then
        G_reader_settings:saveSetting("swipe_animation_refresh_mode", "fast")
    else
        G_reader_settings:delSetting("swipe_animation_refresh_mode")
    end
end

local function getDelay(key)
    local value = tonumber(G_reader_settings:readSetting(key))
    if value == nil or value < 0 then
        return nil
    end
    return value
end

local function setDelay(key, value)
    if value == nil or value < 0 then
        G_reader_settings:delSetting(key)
    else
        G_reader_settings:saveSetting(key, value)
    end
end

local function updateMenu(touchmenu_instance)
    if touchmenu_instance then
        touchmenu_instance:updateItems()
    end
end

local function showDelayDialog(key, label, default_value, touchmenu_instance)
    local InputDialog = require("ui/widget/inputdialog")
    local configured = getDelay(key)
    local input_dialog

    input_dialog = InputDialog:new{
        title = label .. "动画帧延迟",
        input = tostring(configured or default_value),
        input_type = "number",
        description = T([[
输入每一帧之间的延迟，单位为毫秒。
0 = 不额外停顿；数值越低速度越快。

%1默认值：%2 毫秒]], label, default_value),
        buttons = {
            {
                {
                    text = "取消",
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = "恢复默认",
                    callback = function()
                        setDelay(key, nil)
                        updateMenu(touchmenu_instance)
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = "保存",
                    is_enter_default = true,
                    callback = function()
                        local value = tonumber(input_dialog:getInputValue())
                        setDelay(key, value)
                        updateMenu(touchmenu_instance)
                        UIManager:close(input_dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

local function delayMenuItem(key, label, default_value)
    return {
        text_func = function()
            local configured = getDelay(key)
            if configured ~= nil then
                return T("%1动画帧延迟：%2 毫秒", label, configured)
            end
            return T("%1动画帧延迟：默认 %2 毫秒", label, default_value)
        end,
        enabled_func = isAnimationEnabled,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            showDelayDialog(key, label, default_value, touchmenu_instance)
        end,
        help_text = "设置" .. label .. "模式下每一帧之间的延迟。0 表示不额外停顿。",
    }
end

local function buildSettingsItems()
    return {
        {
            text = "刷新模式",
            enabled_func = isAnimationEnabled,
            help_text = "选择动画逐条刷新时使用的刷新模式。UI 刷新画质更平衡；Fast 刷新速度更快，但残影可能更多。",
            sub_item_table = {
                {
                    text = "UI 刷新",
                    checked_func = function() return getRefreshMode() == "ui" end,
                    callback = function(touchmenu_instance)
                        setRefreshMode("ui")
                        updateMenu(touchmenu_instance)
                    end,
                },
                {
                    text = "Fast 刷新",
                    checked_func = function() return getRefreshMode() == "fast" end,
                    callback = function(touchmenu_instance)
                        setRefreshMode("fast")
                        updateMenu(touchmenu_instance)
                    end,
                },
            },
        },
        delayMenuItem("swipe_animation_delay_ms_vertical", "竖屏", defaults.portrait),
        delayMenuItem("swipe_animation_delay_ms_horizontal", "横屏", defaults.landscape),
        {
            text = "轻度全局刷新",
            enabled_func = isAnimationEnabled,
            checked_func = function()
                return G_reader_settings:isTrue("swipe_animation_mild_global_refresh")
            end,
            callback = function(touchmenu_instance)
                if G_reader_settings:isTrue("swipe_animation_mild_global_refresh") then
                    G_reader_settings:delSetting("swipe_animation_mild_global_refresh")
                else
                    G_reader_settings:saveSetting("swipe_animation_mild_global_refresh", true)
                end
                updateMenu(touchmenu_instance)
            end,
            help_text = "勾选后，周期性清屏以及图像或章节边界刷新使用 Partial；关闭时使用 Full。",
        },
    }
end

function M.install()
    if M._installed then
        return true
    end
    M._installed = true

    -- The animation is implemented in software, so expose KOReader's page
    -- animation event path even when the framebuffer has no native support.
    Device.canDoSwipeAnimation = function()
        return true
    end

    -- Migrate the legacy shared delay once, preserving explicit zero values.
    local legacy = tonumber(G_reader_settings:readSetting("swipe_animation_delay_ms"))
    if legacy ~= nil and legacy >= 0 then
        if getDelay("swipe_animation_delay_ms_vertical") == nil then
            setDelay("swipe_animation_delay_ms_vertical", legacy)
        end
        if getDelay("swipe_animation_delay_ms_horizontal") == nil then
            setDelay("swipe_animation_delay_ms_horizontal", legacy)
        end
        G_reader_settings:delSetting("swipe_animation_delay_ms")
    end

    return true
end

function M.buildMenuItems(runtime_error)
    local operational = runtime_error == nil
    local error_help = runtime_error and ("\n\n当前启动错误：" .. runtime_error) or ""

    return {
        {
            text = "擦除渐显翻页动画",
            enabled = operational,
            checked_func = isAnimationEnabled,
            callback = function(touchmenu_instance)
                setAnimationEnabled(not isAnimationEnabled())
                updateMenu(touchmenu_instance)
            end,
            help_text = "启用软件擦除渐显翻页动画。支持文字排版以及 PDF、DjVu、CBZ 等固定排版文档。" .. error_help,
        },
        {
            text = "翻页动画设置",
            enabled_func = function()
                return operational and isAnimationEnabled()
            end,
            sub_item_table = buildSettingsItems(),
            help_text = "设置动画刷新模式、横竖屏帧延迟和周期性清屏方式。" .. error_help,
        },
    }
end

return M
