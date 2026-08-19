-- Swipe Animation integration for My SimpleUI Enhancements.

local source = debug.getinfo(1, "S").source
local patch_dir = source:match("^@(.+[\\/])[^\\/]+$")
assert(patch_dir, "cannot resolve Swipe Animation module directory")

local Settings = dofile(patch_dir .. "swipe_animation/settings.lua")

local P = {
    id              = "swipe_animation",
    name            = "擦除渐显翻页动画",
    plugin_name     = "Swipe Animation",
    plugin_order    = 30,
    description     = "为文字及 PDF、DjVu、CBZ 等固定排版文档提供擦除渐显翻页动画。",
    default_enabled = true,
    always_apply    = true,
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
    return true
end

function P.menu_items_func()
    return Settings.buildMenuItems(P.runtime_error)
end

return P
