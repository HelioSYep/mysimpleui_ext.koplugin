-- Swipe Animation integration for Plugin_enhancements.

local source = debug.getinfo(1, "S").source
local patch_dir = source:match("^@(.+[\\/])[^\\/]+$")
assert(patch_dir, "cannot resolve Swipe Animation module directory")

local Settings = dofile(patch_dir .. "swipe_animation/settings.lua")

local P = {
    id              = "swipe_animation",
    name            = "擦除渐显翻页动画",
    plugin_name     = "KOReader",
    plugin_order    = 30,
    description     = "为文字及 PDF、DjVu、CBZ 等固定排版文档提供擦除渐显翻页动画。",
    default_enabled = false,
}

function P.apply()
    local Core = dofile(patch_dir .. "swipe_animation/core.lua")
    local ok_core, core_reason = Core.install()
    if not ok_core then
        return false, core_reason
    end

    local Paging = dofile(patch_dir .. "swipe_animation/paging.lua")
    local ok_paging, paging_reason = Paging.install()
    if not ok_paging then
        return false, paging_reason
    end

    Settings.install()
    -- The plugin-level patch toggle is the single source of truth. Once the
    -- patch is enabled and applied, expose the animation as active.
    G_reader_settings:saveSetting("swipe_animations", true)
    return true
end

function P.menu_items_func()
    local items = Settings.buildMenuItems(P.runtime_error)
    -- The first item is the legacy runtime enable switch. Activation is now
    -- controlled by Plugin_enhancements, so only expose detailed settings.
    return { items[2] }
end

return P
