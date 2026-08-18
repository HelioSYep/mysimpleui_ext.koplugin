-- My SimpleUI Enhancements
--
-- A small, extensible KOReader plugin inspired by simpleui_ext.koplugin.
-- Enhancement patches are auto-discovered from patches/patch_*.lua.

local DataStorage     = require("datastorage")
local InfoMessage     = require("ui/widget/infomessage")
local LuaSettings     = require("luasettings")
local UIManager       = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger          = require("logger")

local PLUGIN_ID = "mysimpleui_ext"

local function settingsPath()
    return DataStorage:getSettingsDir() .. "/" .. PLUGIN_ID .. ".lua"
end

local function discoverPatches(plugin_path)
    local found = {}
    if not plugin_path then return found end

    local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok_lfs then
        logger.warn(PLUGIN_ID .. ": cannot load lfs; patch discovery skipped")
        return found
    end

    local ok_dir, iterator, dir_object = pcall(lfs.dir, plugin_path .. "/patches")
    if not ok_dir then return found end

    for entry in iterator, dir_object do
        local stem = entry:match("^(patch_%a[%w_]*)%.lua$")
        if stem then
            found[#found + 1] = {
                stem = stem,
                path = plugin_path .. "/patches/" .. entry,
            }
        end
    end
    table.sort(found, function(left, right) return left.stem < right.stem end)
    return found
end

local function displayNameFromId(id)
    local words = tostring(id or "enhancement"):gsub("_", " ")
    return (words:gsub("(%a)([%w']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end))
end

local MySimpleUIExt = WidgetContainer:new{
    name          = PLUGIN_ID,
    is_doc_only   = false,
    _settings     = nil,
    _patches_meta = {},
}

function MySimpleUIExt:_getSettings()
    if not self._settings then
        self._settings = LuaSettings:open(settingsPath())
    end
    return self._settings
end

function MySimpleUIExt:_getPatchStates()
    return self:_getSettings():readSetting("patch_states") or {}
end

function MySimpleUIExt:_isPatchEnabled(patch)
    local enabled = self:_getPatchStates()[patch.id]
    if enabled == nil then return patch.default_enabled == true end
    return enabled == true
end

function MySimpleUIExt:_setPatchEnabled(patch_id, enabled)
    local states = self:_getPatchStates()
    states[patch_id] = enabled == true
    local settings = self:_getSettings()
    settings:saveSetting("patch_states", states)
    settings:flush()
end

function MySimpleUIExt:init()
    self.ui.menu:registerToMainMenu(self)

    -- Plugins are instantiated in path order. Deferring by one UI tick makes
    -- this independent of whether SimpleUI is instantiated before or after us.
    UIManager:scheduleIn(0, function()
        local ok, err = pcall(function() self:_loadAndApplyPatches() end)
        if not ok then
            logger.warn(PLUGIN_ID .. ": deferred initialisation failed: " .. tostring(err))
        end
    end)
end

function MySimpleUIExt:_loadAndApplyPatches()
    self._patches_meta = {}
    local states = self:_getPatchStates()
    local existing = {}
    local settings_changed = false

    for _, patch_file in ipairs(discoverPatches(self.path)) do
        local file_id = patch_file.stem:match("patch_([%w_]+)$")
        -- Use dofile instead of require("patches/..."). Multiple KOReader
        -- plugins may have a patches/ directory, and require's global cache
        -- can otherwise resolve or reuse a different plugin's file.
        local ok_load, patch = pcall(dofile, patch_file.path)

        if not ok_load or type(patch) ~= "table" then
            logger.warn(PLUGIN_ID .. ": failed to load " .. patch_file.path .. ": " .. tostring(patch))
        elseif type(patch.id) ~= "string" or patch.id ~= file_id then
            logger.warn(PLUGIN_ID .. ": patch id must match filename: " .. patch_file.path)
        elseif type(patch.apply) ~= "function" then
            logger.warn(PLUGIN_ID .. ": patch has no apply() function: " .. patch.id)
        else
            existing[patch.id] = true
            patch.name = patch.name or displayNameFromId(patch.id)
            self._patches_meta[#self._patches_meta + 1] = patch

            if states[patch.id] == nil then
                states[patch.id] = patch.default_enabled == true
                settings_changed = true
            end

            if states[patch.id] == true then
                local ok_apply, applied, reason = pcall(patch.apply)
                if not ok_apply then
                    patch.runtime_error = tostring(applied)
                    logger.warn(PLUGIN_ID .. ": patch " .. patch.id .. " failed: " .. patch.runtime_error)
                elseif applied == false then
                    patch.runtime_error = tostring(reason or "not applied")
                    logger.warn(PLUGIN_ID .. ": patch " .. patch.id .. ": " .. patch.runtime_error)
                end
            end
        end
    end

    for patch_id in pairs(states) do
        if not existing[patch_id] then
            states[patch_id] = nil
            settings_changed = true
        end
    end

    if settings_changed then
        local settings = self:_getSettings()
        settings:saveSetting("patch_states", states)
        settings:flush()
    end
end

function MySimpleUIExt:_buildPatchMenu()
    local items = {}

    for _, patch in ipairs(self._patches_meta) do
        local item_patch = patch
        items[#items + 1] = {
            text         = item_patch.name,
            help_text    = item_patch.runtime_error
                and (item_patch.description .. "\n\n当前启动错误：" .. item_patch.runtime_error)
                or item_patch.description,
            checked_func = function() return self:_isPatchEnabled(item_patch) end,
            callback     = function()
                local enabled = self:_isPatchEnabled(item_patch)
                self:_setPatchEnabled(item_patch.id, not enabled)
                UIManager:show(InfoMessage:new{
                    text = string.format(
                        "%s已%s。\n\n请重启 KOReader 使更改生效。",
                        item_patch.name,
                        enabled and "关闭" or "开启"
                    ),
                    timeout = 3,
                })
            end,
        }
    end

    if #items == 0 then
        items[1] = { text = "没有发现增强补丁", enabled = false }
    end
    return items
end

function MySimpleUIExt:addToMainMenu(menu_items)
    menu_items[PLUGIN_ID] = {
        text = "Simple UI 增强",
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = "增强功能",
                sub_item_table_func = function() return self:_buildPatchMenu() end,
            },
            {
                text = "关于",
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = "Simple UI 增强 v0.4.1\n\n"
                            .. "用于集中管理提升 SimpleUI 易用性的个人补丁。",
                    })
                end,
            },
        },
    }
end

return MySimpleUIExt
