-- SimpleUI 2.1.1 / 2.5.0 compatibility resolver.
--
-- SimpleUI 2.5.0 kept the public module APIs used by this plugin, but moved
-- the implementation into modules/, infra/, screens/, engines/ and features/.
-- Keep every version-dependent path in this file so modules and patches can
-- target capabilities instead of hard-coding a SimpleUI release layout.

local M = {}

local PATHS = {
    registry       = { "modules/moduleregistry", "desktop_modules/moduleregistry" },
    config         = { "infra/sui_config", "sui_config" },
    store          = { "infra/sui_store", "sui_store" },
    core           = { "infra/sui_core", "sui_core" },
    homescreen     = { "screens/sui_homescreen", "sui_homescreen" },
    screen_engine  = { "engines/sui_screen_engine", "screens/sui_homescreen", "sui_homescreen" },
    custom_screens = { "infra/sui_custom_screens" },
    books_shared   = { "modules/module_books_shared", "desktop_modules/module_books_shared" },
    stats_provider = { "modules/module_stats_provider", "desktop_modules/module_stats_provider" },
    coverdeck      = { "modules/module_coverdeck", "desktop_modules/module_coverdeck" },
    tbr            = { "modules/module_tbr", "desktop_modules/module_tbr" },
    clock          = { "modules/module_clock", "desktop_modules/module_clock" },
    recent         = { "modules/module_recent", "desktop_modules/module_recent" },
    book_rows      = { "modules/module_book_rows", "desktop_modules/module_book_rows" },
    quicksettings  = { "screens/sui_quicksettings_bar", "sui_quicksettings_bar" },
    quickactions   = { "features/sui_quickactions", "sui_quickactions" },
    style          = { "features/sui_style", "sui_style" },
    streak         = { "infra/sui_streak", "sui_streak" },
    window         = { "engines/sui_window", "sui_window" },
}

local function candidates(key)
    return PATHS[key] or { key }
end

function M.tryRequire(key)
    local errors = {}
    for _, path in ipairs(candidates(key)) do
        local loaded = package.loaded[path]
        if loaded ~= nil and loaded ~= false then
            return true, loaded, path
        end
        local ok, mod = pcall(require, path)
        if ok and mod ~= nil then
            return true, mod, path
        end
        errors[#errors + 1] = path .. ": " .. tostring(mod)
    end
    return false, table.concat(errors, " | "), nil
end

function M.require(key)
    local ok, mod_or_err = M.tryRequire(key)
    if ok then return mod_or_err end
    error("SimpleUI component unavailable (" .. tostring(key) .. "): "
          .. tostring(mod_or_err), 2)
end

function M.loaded(key)
    for _, path in ipairs(candidates(key)) do
        local mod = package.loaded[path]
        if mod ~= nil and mod ~= false then return mod, path end
    end
    return nil
end

function M.getLayoutFamily()
    if package.loaded["infra/sui_config"]
        or package.loaded["modules/moduleregistry"]
        or package.loaded["screens/sui_homescreen"] then
        return "2.5"
    end
    if package.loaded["sui_config"]
        or package.loaded["desktop_modules/moduleregistry"]
        or package.loaded["sui_homescreen"] then
        return "2.1"
    end
    local ok, _, path = M.tryRequire("config")
    if not ok then return nil end
    return path == "infra/sui_config" and "2.5" or "2.1"
end

-- Resolve the structured-layout settings key belonging to a module-settings
-- prefix. In 2.1.1 only the built-in Home Screen exists. In 2.5.0 every
-- Custom Screen has an independent prefix and layout key.
function M.getLayoutKeyForPrefix(pfx)
    if pfx and pfx ~= "" and pfx ~= "simpleui_hs_" then
        local ok, CustomScreens = M.tryRequire("custom_screens")
        if ok and CustomScreens and type(CustomScreens.list) == "function" then
            local ok_list, screens = pcall(CustomScreens.list)
            if ok_list then
                for _, screen in ipairs(screens or {}) do
                    if screen.pfx == pfx and screen.layout_key then
                        return screen.layout_key
                    end
                end
            end
        end
    end
    return "simpleui_layout"
end

-- Return every known homescreen-like surface. This is useful for cache
-- invalidation and layout-aware patches while remaining harmless on 2.1.1.
function M.listScreens()
    local screens = {
        { id = "hs", pfx = "simpleui_hs_", layout_key = "simpleui_layout" },
    }
    local ok, CustomScreens = M.tryRequire("custom_screens")
    if ok and CustomScreens and type(CustomScreens.list) == "function" then
        local ok_list, custom = pcall(CustomScreens.list)
        if ok_list then
            for _, screen in ipairs(custom or {}) do
                screens[#screens + 1] = screen
            end
        end
    end
    return screens
end

return M
