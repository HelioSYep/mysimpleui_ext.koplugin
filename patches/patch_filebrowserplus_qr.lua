-- FileBrowserPlus quick action with a centered QR endpoint dialog.

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local ACTION_ID = "filebrowserplus"
local SLOTS_KEY = "simpleui_qs_bar_slots"

local P = {
    id              = "filebrowserplus_qr",
    name            = "文件管理：FileBrowserPlus",
    description     = "在 SimpleUI 快捷设置栏注册 FileBrowserPlus 文件管理快捷操作；单击切换服务并显示二维码，长按再次显示正在运行的服务二维码。",
    default_enabled = true,
}

local SUISettings

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
        local ok_instance, instance = pcall(PluginLoader.getPluginInstance, PluginLoader, ACTION_ID)
        if ok_instance and instance then return instance end
    end
    return nil
end

local function endpointFor(plugin)
    local ip
    if type(plugin.getIPAddress) == "function" then
        local ok, value = pcall(plugin.getIPAddress, plugin)
        if ok and type(value) == "string" and value ~= "" then ip = value end
    end
    local port = tostring(plugin.filebrowserplus_port or "80")
    local display = (ip and ip or "") .. ":" .. port
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

    local ok_qr, QRWidget = pcall(require, "ui/widget/qrwidget")
    if not ok_qr or not QRWidget then
        unavailable("当前 KOReader 不支持二维码显示，请使用 IP:port 连接。")
        return
    end

    closeQRCode()
    local display, url = endpointFor(plugin)
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

    local ok_start, err = pcall(plugin.start, plugin)
    if not ok_start then
        logger.warn("mysimpleui_ext: FileBrowserPlus start failed", tostring(err))
        unavailable("FileBrowserPlus 启动失败。")
        return
    end

    -- start() launches the process and writes its pid file synchronously, but
    -- the short delay lets the network interface and endpoint settle first.
    local function showWhenRunning(attempts_left)
        local ok_after, running_after = pcall(plugin.isRunning, plugin)
        if ok_after and running_after then
            showQRCode(plugin)
        elseif attempts_left > 0 then
            UIManager:scheduleIn(0.2, function()
                showWhenRunning(attempts_left - 1)
            end)
        end
    end
    showWhenRunning(5)
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
    if not plugin then return "文件管理 / FileBrowserPlus (不可用)" end
    local ok_running, running = pcall(plugin.isRunning, plugin)
    if ok_running and running then
        return "文件管理 / FileBrowserPlus (运行中)"
    end
    return "文件管理 / FileBrowserPlus (已停止)"
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

        local slots = SUISettings and SUISettings:readSetting(SLOTS_KEY) or nil
        if panel and refs and type(slots) == "table" then
            for index, action_id in ipairs(slots) do
                local ref = refs.buttons and refs.buttons[index]
                if action_id == ACTION_ID and ref and ref.widget then
                    local original_onGesture = panel.onGesture
                    panel.onGesture = function(panel_self, event)
                        if event and event.ges == "hold"
                                and event.pos and ref.widget.dimen
                                and event.pos:intersectWith(ref.widget.dimen) then
                            showQRCodeFromHold()
                            return true
                        end
                        return original_onGesture(panel_self, event)
                    end
                    break
                end
            end
        end
        return unpack(results)
    end
    return true
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
        label       = "文件管理 / FileBrowserPlus",
        get_label   = actionLabel,
        icon        = ok_config and Config.ICON and Config.ICON.plugin or nil,
        is_in_place = true,
        is_async_in_place = true,
        execute     = toggleFilebrowser,
    }

    SUISettings = package.loaded["infra/sui_store"] or require("infra/sui_store")
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
