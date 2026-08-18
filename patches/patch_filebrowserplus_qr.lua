-- Direct FileBrowserPlus 1.2.x QR enhancement.
-- This patch does not depend on or register anything with SimpleUI.

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local PLUGIN_ID = "filebrowserplus"
local AUTO_SHOW_KEY = "FilebrowserPlus_auto_show_qr"

local P = {
    id = "filebrowserplus_qr",
    name = "FileBrowserPlus：二维码增强",
    description = "直接增强 FileBrowserPlus 1.2.x：在插件菜单中增加二维码显示和启动后自动显示选项。",
    default_enabled = true,
}

local function showMessage(text, timeout)
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{ text = text, timeout = timeout or 3 })
end

local function autoShowEnabled()
    local value = G_reader_settings:readSetting(AUTO_SHOW_KEY)
    if value == nil then
        G_reader_settings:saveSetting(AUTO_SHOW_KEY, true)
        return true
    end
    return value == true
end

local function getPluginModule()
    local ok_loader, PluginLoader = pcall(require, "pluginloader")
    if not ok_loader or not PluginLoader then return nil, nil end
    for _, plugin_module in ipairs(PluginLoader.enabled_plugins or {}) do
        if plugin_module and plugin_module.name == PLUGIN_ID then
            return plugin_module, PluginLoader
        end
    end
    return nil, PluginLoader
end

local function getPluginInstance(PluginLoader)
    if PluginLoader and type(PluginLoader.getPluginInstance) == "function" then
        local ok, instance = pcall(PluginLoader.getPluginInstance, PluginLoader, PLUGIN_ID)
        if ok then return instance end
    end
    return nil
end

local function invalidateMenu(instance)
    local menu = instance and instance.ui and instance.ui.menu
    if not menu then return end
    menu.tab_item_table = nil
    if type(menu.menu_items) == "table" then
        menu.menu_items[PLUGIN_ID] = nil
    end
end

local function installQRCodeMethods(target)
    function target:closeQRCode()
        if self._filebrowserplus_qr_widget then
            UIManager:close(self._filebrowserplus_qr_widget)
            self._filebrowserplus_qr_widget = nil
        end
    end

    function target:showQRCode()
        local ok_running, running = pcall(self.isRunning, self)
        if not ok_running or not running then
            showMessage("FileBrowserPlus 服务尚未运行。", 2)
            return
        end

        local ip
        if type(self.getIPAddress) == "function" then
            local ok_ip, value = pcall(self.getIPAddress, self)
            if ok_ip and type(value) == "string" and value ~= "" then ip = value end
        end
        if not ip and type(Device.retrieveNetworkInfo) == "function" then
            local ok_info, info = pcall(Device.retrieveNetworkInfo, Device)
            if ok_info and type(info) == "table" then
                ip = info.ip
            elseif ok_info and type(info) == "string" then
                ip = info:match("(%d+%.%d+%.%d+%.%d+)")
            end
        end
        if not ip then
            showMessage("无法获取设备 IP 地址，请确认 Wi-Fi 已连接。")
            return
        end

        local display = ip .. ":" .. tostring(self.filebrowserplus_port or "80")
        local url = "http://" .. display
        local ok_qr, QRWidget = pcall(require, "ui/widget/qrwidget")
        if not ok_qr or not QRWidget then
            showMessage("当前 KOReader 不支持二维码，请使用 " .. display .. " 连接。", 5)
            return
        end

        self:closeQRCode()
        local screen = Device.screen
        local side = math.floor(math.min(screen:getWidth() * 0.62, screen:getHeight() * 0.56))
        side = math.max(120, side)
        local ok_widget, qr = pcall(function()
            return QRWidget:new{ text = url, width = side, height = side }
        end)
        if not ok_widget or not qr or not qr.image then
            showMessage("二维码生成失败，请使用 " .. display .. " 连接。", 5)
            return
        end

        local CenterContainer = require("ui/widget/container/centercontainer")
        local FrameContainer = require("ui/widget/container/framecontainer")
        local InputContainer = require("ui/widget/container/inputcontainer")
        local Size = require("ui/size")
        local TextWidget = require("ui/widget/textwidget")
        local VerticalGroup = require("ui/widget/verticalgroup")
        local VerticalSpan = require("ui/widget/verticalspan")

        local content = VerticalGroup:new{
            align = "center",
            qr,
            VerticalSpan:new{ width = screen:scaleBySize(10) },
            TextWidget:new{
                text = url,
                face = Font:getFace("cfont", screen:scaleBySize(18)),
                fgcolor = Blitbuffer.COLOR_BLACK,
                max_width = math.floor(screen:getWidth() * 0.9),
            },
        }
        local dialog = InputContainer:new{
            modal = true,
            covers_fullscreen = true,
        }
        dialog[1] = CenterContainer:new{
            dimen = screen:getSize(),
            FrameContainer:new{
                background = Blitbuffer.COLOR_WHITE,
                padding = Size.padding.default,
                content,
            },
        }
        if Device:isTouchDevice() then
            dialog.ges_events.TapClose = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{
                        x = 0, y = 0,
                        w = screen:getWidth(), h = screen:getHeight(),
                    },
                },
            }
        end
        function dialog:onTapClose()
            UIManager:close(self)
            return true
        end
        function dialog:onCloseWidget()
            if self._manager and self._manager._filebrowserplus_qr_widget == self then
                self._manager._filebrowserplus_qr_widget = nil
            end
            UIManager:setDirty(nil, "full")
        end
        dialog._manager = self
        self._filebrowserplus_qr_widget = dialog
        UIManager:show(dialog)
    end
end

local function showWhenRunning(plugin, attempts_left)
    local ok, running = pcall(plugin.isRunning, plugin)
    if ok and running then
        plugin:showQRCode()
    elseif attempts_left > 0 then
        UIManager:scheduleIn(0.2, function()
            showWhenRunning(plugin, attempts_left - 1)
        end)
    end
end

local function installPluginPatch(target)
    if target._filebrowserplus_qr_patch_applied then return true end
    if type(target.addToMainMenu) ~= "function"
            or type(target.start) ~= "function"
            or type(target.stop) ~= "function" then
        return false
    end
    target._filebrowserplus_qr_patch_applied = true

    installQRCodeMethods(target)

    local original_start = target.start
    target.start = function(self, ...)
        local results = { original_start(self, ...) }
        if autoShowEnabled() then showWhenRunning(self, 25) end
        return unpack(results)
    end

    local original_stop = target.stop
    target.stop = function(self, ...)
        self:closeQRCode()
        return original_stop(self, ...)
    end

    local original_addToMainMenu = target.addToMainMenu
    target.addToMainMenu = function(self, menu_items)
        local results = { original_addToMainMenu(self, menu_items) }
        local item = menu_items and menu_items[PLUGIN_ID]
        if not item then return unpack(results) end

        -- FileBrowserPlus 1.2 keeps its settings in the long-press callback.
        -- Capture that table and expose it in a regular submenu.
        local settings_items = {}
        if type(item.hold_callback) == "function" then
            local capture = {
                onMenuSelect = function(_, dummy_item)
                    if dummy_item and type(dummy_item.sub_item_table) == "table" then
                        settings_items = dummy_item.sub_item_table
                    end
                end,
            }
            local ok_capture, err = pcall(item.hold_callback, capture)
            if not ok_capture then
                logger.warn("filebrowserplus_qr: cannot capture settings", tostring(err))
            end
        end

        local sub_items = {
            {
                text = "FileBrowserPlus 服务器",
                checked_func = function()
                    local ok, running = pcall(self.isRunning, self)
                    return ok and running == true
                end,
                check_callback_updates_menu = true,
                callback = function(touchmenu_instance)
                    local ok, running = pcall(self.isRunning, self)
                    if ok and running then self:stop() else self:start() end
                    if touchmenu_instance and type(touchmenu_instance.updateItems) == "function" then
                        touchmenu_instance:updateItems()
                    end
                end,
            },
            {
                text = "显示二维码",
                enabled_func = function()
                    local ok, running = pcall(self.isRunning, self)
                    return ok and running == true
                end,
                callback = function() self:showQRCode() end,
            },
        }
        for _, settings_item in ipairs(settings_items) do
            sub_items[#sub_items + 1] = settings_item
        end
        sub_items[#sub_items + 1] = {
            text = "启动时自动显示二维码",
            checked_func = autoShowEnabled,
            callback = function()
                G_reader_settings:saveSetting(AUTO_SHOW_KEY, not autoShowEnabled())
            end,
        }

        item.text = "FileBrowserPlus"
        item.text_func = nil
        item.checked_func = nil
        item.callback = nil
        item.keep_menu_open = nil
        item.hold_callback = nil
        item.hold_keep_menu_open = nil
        item.sub_item_table = sub_items
        return unpack(results)
    end
    return true
end

function P.apply()
    if P._applied then return true end
    local plugin_module, PluginLoader = getPluginModule()
    if not plugin_module then
        return false, "FileBrowserPlus 插件未启用或模块未加载"
    end
    if not installPluginPatch(plugin_module) then
        return false, "FileBrowserPlus 版本不兼容"
    end

    local instance = getPluginInstance(PluginLoader)
    invalidateMenu(instance)
    P._applied = true
    logger.info("filebrowserplus_qr: direct FileBrowserPlus patch applied")
    return true
end

return P
