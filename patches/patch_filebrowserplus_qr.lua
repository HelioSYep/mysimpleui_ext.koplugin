-- FileBrowserPlus quick action with a centered QR endpoint dialog.

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local PLUGIN_ID = "filebrowserplus"
local LEGACY_ACTION_ID = "filebrowserplus"
local ACTION_ID = "mysui_filebrowserplus_qr"
local SLOTS_KEY = "simpleui_qs_bar_slots"
local AUTO_SHOW_KEY = "FilebrowserPlus_auto_show_qr"

local P = {
    id              = "filebrowserplus_qr",
    name            = "文件管理：FileBrowserPlus",
    description     = "在 SimpleUI 快捷设置栏注册 FileBrowserPlus 文件管理快捷操作；单击切换服务并显示二维码，长按再次显示正在运行的服务二维码。",
    default_enabled = true,
}

local SUISettings

local function autoShowEnabled()
    local value = G_reader_settings:readSetting(AUTO_SHOW_KEY)
    if value == nil then
        G_reader_settings:saveSetting(AUTO_SHOW_KEY, true)
        return true
    end
    return value == true
end

local function unavailable(message)
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{ text = message, timeout = 3 })
end

local function resolveFilebrowser(ctx)
    local fm = ctx and ctx.fm
    if not fm then
        local FM = package.loaded["apps/filemanager/filemanager"]
        fm = FM and FM.instance
    end
    if fm and fm.filebrowserplus then return fm.filebrowserplus end

    local RUI = package.loaded["apps/reader/readerui"]
    local readerui = RUI and RUI.instance
    if readerui and readerui.filebrowserplus then return readerui.filebrowserplus end

    -- This also works while a FileManager/ReaderUI instance is being rebuilt.
    local ok_loader, PluginLoader = pcall(require, "pluginloader")
    if ok_loader and PluginLoader and type(PluginLoader.getPluginInstance) == "function" then
        local ok_instance, instance = pcall(PluginLoader.getPluginInstance, PluginLoader, PLUGIN_ID)
        if ok_instance and instance then return instance end
    end
    return nil
end

local function usableIP(value)
    if type(value) ~= "string" then return nil end
    value = value:match("^%s*(.-)%s*$")
    if value == "" then return nil end
    return value:match("(%d+%.%d+%.%d+%.%d+)") or value
end

local function getIPAddress(plugin)
    local ip
    if type(plugin.getIPAddress) == "function" then
        local ok, value = pcall(plugin.getIPAddress, plugin)
        if ok then ip = usableIP(value) end
    end

    -- FileBrowserPlus releases do not consistently expose getIPAddress().
    -- Use the same device/network fallbacks as the QR-enabled fork.
    if not ip and type(Device.retrieveNetworkInfo) == "function" then
        local ok, net_info = pcall(Device.retrieveNetworkInfo, Device)
        if ok and type(net_info) == "table" then
            ip = usableIP(net_info.ip)
        elseif ok then
            ip = usableIP(net_info)
        end
    end

    if not ip then
        local ok_network, NetworkMgr = pcall(require, "ui/network/manager")
        if ok_network and NetworkMgr then
            for _, method_name in ipairs({ "getIPAddress", "getLocalIpAddress" }) do
                local method = NetworkMgr[method_name]
                if type(method) == "function" then
                    local ok, value = pcall(method, NetworkMgr)
                    if ok then ip = usableIP(value) end
                    if ip then break end
                end
            end
        end
    end

    return ip
end

local function endpointFor(plugin)
    local ip = getIPAddress(plugin)
    if not ip then return nil end
    local port = tostring(plugin.filebrowserplus_port or "80")
    local display = ip .. ":" .. port
    return display, "http://" .. display
end

local function closeQRCode()
    if P._qr_dialog then
        UIManager:close(P._qr_dialog)
        P._qr_dialog = nil
    end
end

local function showQRCode(plugin)
    if not plugin then
        unavailable("FileBrowserPlus 插件未启用或未加载。")
        return
    end

    local ok_running, running = pcall(plugin.isRunning, plugin)
    if not ok_running or not running then
        unavailable("FileBrowserPlus 服务尚未运行。")
        return
    end

    -- Prefer the QR screen supplied by QR-enabled FileBrowserPlus builds.
    -- Besides matching that plugin's UI, this also lets it use its own
    -- version-specific network discovery and close/stop handling. The local
    -- dialog below remains a fallback for the regular upstream plugin.
    if type(plugin.showQRCode) == "function" then
        local ok_native, err = pcall(plugin.showQRCode, plugin)
        if ok_native then return end
        logger.warn("mysimpleui_ext: native FileBrowserPlus QR failed", tostring(err))
    end

    local display, url = endpointFor(plugin)
    if not display then
        unavailable("无法获取设备 IP 地址，请确认 Wi-Fi 已连接。")
        return
    end

    local ok_qr, QRWidget = pcall(require, "ui/widget/qrwidget")
    if not ok_qr or not QRWidget then
        unavailable("当前 KOReader 不支持二维码显示，请使用 " .. display .. " 连接。")
        return
    end

    closeQRCode()
    local side = math.floor(math.min(
        Device.screen:getWidth() * 0.62,
        Device.screen:getHeight() * 0.56
    ))
    side = math.max(120, side)

    local ok_widget, qr = pcall(function()
        return QRWidget:new{ text = url, width = side, height = side }
    end)
    if not ok_widget or not qr or not qr.image then
        logger.warn("mysimpleui_ext: failed to create FileBrowserPlus QR widget")
        unavailable("二维码生成失败，请使用 " .. display .. " 连接。")
        return
    end

    local InputContainer = require("ui/widget/container/inputcontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local Size = require("ui/size")
    local TextWidget = require("ui/widget/textwidget")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")

    local label = TextWidget:new{
        text      = display,
        face      = Font:getFace("cfont", Device.screen:scaleBySize(18)),
        fgcolor   = Blitbuffer.COLOR_BLACK,
        max_width = side,
    }
    local content = VerticalGroup:new{
        align = "center",
        qr,
        VerticalSpan:new{ width = Device.screen:scaleBySize(10) },
        label,
    }
    local dialog = InputContainer:new{
        modal           = true,
        covers_fullscreen = true,
    }
    dialog[1] = CenterContainer:new{
        dimen = Device.screen:getSize(),
        FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            padding    = Size.padding.default,
            content,
        },
    }
    if Device:hasKeys() then
        dialog.key_events.AnyKeyPressed = { { Device.input.group.Any } }
    end
    if Device:isTouchDevice() then
        dialog.ges_events.TapClose = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = 0, y = 0,
                    w = Device.screen:getWidth(),
                    h = Device.screen:getHeight(),
                },
            },
        }
    end
    function dialog:onTapClose()
        UIManager:close(self)
        return true
    end
    dialog.onAnyKeyPressed = dialog.onTapClose
    function dialog:onCloseWidget()
        if self[1] and self[1][1] and self[1][1].dimen then
            UIManager:setDirty(nil, function()
                return "ui", self[1][1].dimen
            end)
        end
        if P._qr_dialog == self then P._qr_dialog = nil end
    end

    P._qr_dialog = dialog
    UIManager:show(dialog)
end

local function showWhenRunning(plugin, attempts_left, report_failure)
    local ok_running, running = pcall(plugin.isRunning, plugin)
    if ok_running and running then
        showQRCode(plugin)
    elseif attempts_left > 0 then
        UIManager:scheduleIn(0.2, function()
            showWhenRunning(plugin, attempts_left - 1, report_failure)
        end)
    elseif report_failure then
        unavailable("FileBrowserPlus 启动后未检测到服务，请检查插件设置和日志。")
    end
end

local function ensureRunningAndShow(ctx)
    local plugin = resolveFilebrowser(ctx)
    if not plugin then
        unavailable("FileBrowserPlus 插件未启用或未加载。")
        return
    end

    local ok_running, running = pcall(plugin.isRunning, plugin)
    if ok_running and running then
        showQRCode(plugin)
        return
    end

    -- The injected start() wrapper normally follows the auto-show setting.
    -- A SimpleUI QR quick action always shows QR, so suppress that wrapper's
    -- own scheduling and manage this invocation explicitly.
    plugin._mysui_qr_start_managed = true
    local ok_start, err = pcall(plugin.start, plugin)
    plugin._mysui_qr_start_managed = nil
    if not ok_start then
        logger.warn("mysimpleui_ext: FileBrowserPlus start failed", tostring(err))
        unavailable("FileBrowserPlus 启动失败。")
        return
    end

    -- Slower devices may need a few seconds for the process and pid file to
    -- settle after start(). Poll for up to five seconds before reporting a
    -- failure.
    showWhenRunning(plugin, 25, true)
end

local function toggleFilebrowser(ctx)
    local plugin = resolveFilebrowser(ctx)
    if not plugin then
        unavailable("FileBrowserPlus 插件未启用或未加载。")
        return
    end

    local ok_running, running = pcall(plugin.isRunning, plugin)
    if not ok_running then
        unavailable("无法读取 FileBrowserPlus 服务状态。")
        return
    end

    if running then
        closeQRCode()
        local ok_stop, err = pcall(plugin.stop, plugin)
        if not ok_stop then
            logger.warn("mysimpleui_ext: FileBrowserPlus stop failed", tostring(err))
            unavailable("FileBrowserPlus 停止失败。")
        end
        return
    end

    ensureRunningAndShow(ctx)
end

local function showQRCodeFromHold()
    local plugin = resolveFilebrowser()
    if not plugin then
        unavailable("FileBrowserPlus 插件未启用或未加载。")
        return
    end
    showQRCode(plugin)
end

local function actionLabel()
    local plugin = resolveFilebrowser()
    if not plugin then return "FileBrowserPlus 二维码快捷开关（不可用）" end
    local ok_running, running = pcall(plugin.isRunning, plugin)
    if ok_running and running then
        return "FileBrowserPlus 二维码快捷开关（运行中）"
    end
    return "FileBrowserPlus 二维码快捷开关（已停止）"
end

local function installHoldHandler(TouchMenu)
    if TouchMenu._mysui_filebrowser_qr_hold_patched then return true end
    local original_updateItems = TouchMenu.updateItems
    if type(original_updateItems) ~= "function" then
        return false, "TouchMenu.updateItems is unavailable"
    end

    TouchMenu._mysui_filebrowser_qr_hold_patched = true
    TouchMenu.updateItems = function(self, ...)
        local results = { original_updateItems(self, ...) }
        local refs = self._sui_qs_refs
        local panel
        for _, child in ipairs(self.item_group or {}) do
            if child and child.onHoldPanel and child.ges_events then
                panel = child
                break
            end
        end

        if panel then
            panel._mysui_filebrowser_qr_hold_target = nil
        end

        local slots = SUISettings and SUISettings:readSetting(SLOTS_KEY) or nil
        if panel and refs and type(slots) == "table" then
            for index, action_id in ipairs(slots) do
                local ref = refs.buttons and refs.buttons[index]
                if action_id == ACTION_ID and ref and ref.widget then
                    panel._mysui_filebrowser_qr_hold_target = ref.widget
                    break
                end
            end
        end

        if panel and not panel._mysui_filebrowser_qr_hold_patched then
            local original_onGesture = panel.onGesture
            panel._mysui_filebrowser_qr_hold_patched = true
            panel.onGesture = function(panel_self, event)
                local target = panel_self._mysui_filebrowser_qr_hold_target
                if target and event and event.ges == "hold"
                        and event.pos and target.dimen
                        and event.pos:intersectWith(target.dimen) then
                    showQRCodeFromHold()
                    return true
                end
                if type(original_onGesture) == "function" then
                    return original_onGesture(panel_self, event)
                end
            end
        end
        return unpack(results)
    end
    return true
end

local function installPluginMenuCompatibility(plugin)
    if not plugin then return false end
    if plugin._mysui_filebrowser_menu_patched then return true end
    local original_addToMainMenu = plugin.addToMainMenu
    if type(original_addToMainMenu) ~= "function" then return false end

    plugin._mysui_filebrowser_menu_patched = true
    local original_start = plugin.start
    if type(original_start) == "function" then
        plugin.start = function(self, ...)
            local should_show = autoShowEnabled() and not self._mysui_qr_start_managed
            local results = { original_start(self, ...) }
            if should_show then
                showWhenRunning(self, 25, false)
            end
            return unpack(results)
        end
    end
    local original_stop = plugin.stop
    if type(original_stop) == "function" then
        plugin.stop = function(self, ...)
            closeQRCode()
            return original_stop(self, ...)
        end
    end

    plugin.addToMainMenu = function(self, menu_items)
        local results = { original_addToMainMenu(self, menu_items) }
        local item = menu_items and menu_items[PLUGIN_ID]
        if not item then return unpack(results) end

        -- FileBrowserPlus 1.2.0 keeps its settings table inside the original
        -- hold callback. Capture it without opening a menu, then rebuild the
        -- plugin entry as an ordinary submenu like pre-1.2 releases.
        local settings_items = {}
        local original_hold_callback = item.hold_callback
        if type(original_hold_callback) == "function" then
            local capture_menu = {
                onMenuSelect = function(_, dummy_item)
                    if dummy_item and type(dummy_item.sub_item_table) == "table" then
                        settings_items = dummy_item.sub_item_table
                    end
                end,
            }
            local ok_capture, err = pcall(original_hold_callback, capture_menu)
            if not ok_capture then
                logger.warn("mysimpleui_ext/filebrowserplus_qr: cannot capture 1.2 settings", tostring(err))
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
                    if ok and running then
                        closeQRCode()
                        pcall(self.stop, self)
                    else
                        pcall(self.start, self)
                    end
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
                callback = function()
                    showQRCode(self)
                end,
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
    logger.info("mysimpleui_ext/filebrowserplus_qr: injected FileBrowserPlus 1.2 QR menu")
    return true
end

local function installPluginMenuCompatibilityWhenReady(attempts_left)
    local plugin = resolveFilebrowser()
    if installPluginMenuCompatibility(plugin) then return end
    if attempts_left > 0 then
        UIManager:scheduleIn(0.2, function()
            installPluginMenuCompatibilityWhenReady(attempts_left - 1)
        end)
    end
end

local function migrateLegacySlot()
    if not SUISettings then return end
    local slots = SUISettings:readSetting(SLOTS_KEY)
    if type(slots) ~= "table" then return end

    local changed = false
    for index, action_id in ipairs(slots) do
        if action_id == LEGACY_ACTION_ID then
            slots[index] = ACTION_ID
            changed = true
        end
    end
    if not changed then return end

    if type(SUISettings.saveSetting) ~= "function" then
        logger.warn("mysimpleui_ext/filebrowserplus_qr: cannot migrate legacy slot")
        return
    end
    local ok_save, err = pcall(SUISettings.saveSetting, SUISettings, SLOTS_KEY, slots)
    if not ok_save then
        logger.warn("mysimpleui_ext/filebrowserplus_qr: legacy slot migration failed", tostring(err))
        return
    end
    if type(SUISettings.flush) == "function" then
        pcall(SUISettings.flush, SUISettings)
    end
    logger.info("mysimpleui_ext/filebrowserplus_qr: migrated legacy quick-action slot")
end

function P.apply()
    if P._applied then return true end

    local ok_qa, QA = pcall(require, "features/sui_quickactions")
    if not ok_qa or not QA or type(QA.register) ~= "function" then
        return false, "SimpleUI Quick Actions registry is unavailable"
    end
    local ok_config, Config = pcall(require, "infra/sui_config")
    QA.register{
        id          = ACTION_ID,
        label       = "文件管理 / FileBrowserPlus（二维码快捷开关）",
        get_label   = actionLabel,
        icon        = ok_config and Config.ICON and Config.ICON.plugin or nil,
        is_in_place = true,
        is_async_in_place = true,
        execute     = toggleFilebrowser,
    }

    SUISettings = package.loaded["infra/sui_store"] or require("infra/sui_store")
    migrateLegacySlot()
    installPluginMenuCompatibilityWhenReady(25)
    local ok_tm, TouchMenu = pcall(require, "ui/widget/touchmenu")
    if ok_tm and TouchMenu then
        local ok_hold, reason = installHoldHandler(TouchMenu)
        if not ok_hold then logger.info("mysimpleui_ext/filebrowserplus_qr: " .. tostring(reason)) end
    end

    P._applied = true
    logger.info("mysimpleui_ext/filebrowserplus_qr: applied")
    return true
end

return P
