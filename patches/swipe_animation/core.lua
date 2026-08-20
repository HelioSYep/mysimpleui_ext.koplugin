-- Software wipe animation runtime.
--
-- This adapts Swipe_Animation's KOReader startup patch to a regular plugin:
-- instead of replacing frontend/ui/uimanager.lua, it replaces the private
-- refresh dispatch table captured by UIManager:_repaint. The animation still
-- runs after painting and immediately before the queued screen refreshes.
-- Original Swipe_Animation credits: xhs:5699990012, nuku, Echoes,
-- 小红薯6809667F and 斯普特尼克的漫游. Distributed under GPLv3/AGPLv3.

local M = {}

function M.install()
    local Device = require("device")
    local logger = require("logger")
    local ReaderUI = require("apps/reader/readerui")
    local UIManager = require("ui/uimanager")
    local ffi = require("ffi")
    local Screen = Device.screen

    if not Screen then
        return false, "Device.screen is unavailable"
    end
    if UIManager._mysimpleui_swipe_animation_core_applied then
        return true
    end
    if Screen._swipe_animation_core_patch_applied then
        return false, "检测到原版 Swipe_Animation 启动补丁，请先移除旧补丁并还原 uimanager.lua"
    end

    UIManager.swipe_animation_defaults = UIManager.swipe_animation_defaults or {
        delay_ms = { landscape = 10, portrait = 20 },
        steps = { landscape = 6, portrait = 8 },
    }

    local SwipeAnimation = {}

    function SwipeAnimation.shouldDoClearing(self)
        if not (self.FULL_REFRESH_COUNT and self.FULL_REFRESH_COUNT > 0) then
            return false
        end

        self._swipe_full_refresh_count = (self._swipe_full_refresh_count or 0) + 1
        if self._swipe_full_refresh_count >= self.FULL_REFRESH_COUNT then
            self._swipe_full_refresh_count = 0
            return true
        end
        return false
    end

    function SwipeAnimation.performClearing(self, screen_w, screen_h)
        if G_reader_settings:isTrue("swipe_animation_mild_global_refresh") then
            Screen:refreshPartial(0, 0, screen_w, screen_h)
            logger.dbg("SwipeAnimation: mild clearing refresh")
        else
            Screen:refreshFull(0, 0, screen_w, screen_h)
            logger.dbg("SwipeAnimation: full clearing refresh")
        end
        self.refresh_count = 0
        self._refresh_stack = {}
    end

    function SwipeAnimation.shouldForceFullAfterAnimation(self, prev_page)
        local instance = ReaderUI.instance
        if not instance then
            return false
        end

        local view = instance.view
        if view then
            local current_coverage = view.img_coverage or 0
            local previous_coverage = view._swipe_prev_img_coverage or 0
            local coverage_difference = math.abs(current_coverage - previous_coverage)
            view._swipe_prev_img_coverage = current_coverage

            if (current_coverage >= 0.075 or coverage_difference >= 0.075)
                    and G_reader_settings:nilOrTrue("refresh_on_pages_with_images") then
                return true
            end
        end

        local toc = instance.toc
        if not toc then
            return false
        end
        if not (self.FULL_REFRESH_COUNT == -1
                or G_reader_settings:isTrue("refresh_on_chapter_boundaries")) then
            return false
        end

        local paging = instance.paging
        local rolling = instance.rolling
        local current_page = (paging and paging.current_page)
            or (rolling and rolling.current_page)
        if not current_page then
            return false
        end

        prev_page = prev_page or toc.pageno
        local flash_on_second = G_reader_settings:nilOrFalse("no_refresh_on_second_chapter_page")
        local paging_forward
        local paging_backward
        if flash_on_second and prev_page then
            if current_page > prev_page then
                paging_forward = true
            elseif current_page < prev_page then
                paging_backward = true
            end
        end

        if paging_backward and toc:isChapterEnd(current_page) then
            return true
        elseif toc:isChapterStart(current_page) then
            return true
        elseif paging_forward and toc:isChapterSecondPage(current_page) then
            return true
        end
        return false
    end

    function SwipeAnimation.forceFullAndReset(self, screen_w, screen_h)
        if G_reader_settings:isTrue("swipe_animation_mild_global_refresh") then
            Screen:refreshPartial(0, 0, screen_w, screen_h)
            logger.dbg("SwipeAnimation: mild forced refresh")
        else
            Screen:refreshFull(0, 0, screen_w, screen_h)
            logger.dbg("SwipeAnimation: forced full refresh")
        end
        self._swipe_full_refresh_count = 0
        self.refresh_count = 0
        self._refresh_stack = {}
    end

    local function buildStripEdges(screen_w, steps, align)
        local edges = { 0 }
        local use_alignment = type(align) == "number" and align >= 2
        for index = 1, steps - 1 do
            local raw = screen_w * index / steps
            local cut
            if use_alignment then
                cut = math.floor((raw + align / 2) / align) * align
            else
                cut = math.floor(raw)
            end
            if cut > edges[#edges] and cut < screen_w then
                edges[#edges + 1] = cut
            end
        end
        edges[#edges + 1] = screen_w
        return edges
    end

    function SwipeAnimation.run(self)
        local screen_w = Screen.bb:getWidth()
        local screen_h = Screen.bb:getHeight()
        local instance = ReaderUI.instance
        local prev_page
        if instance then
            if instance.toc then
                prev_page = instance.toc.pageno
            end
            if not prev_page then
                prev_page = (instance.paging and instance.paging.current_page)
                    or (instance.rolling and instance.rolling.current_page)
            end
        end

        local do_clearing = SwipeAnimation.shouldDoClearing(self)
        local force_full = false
        if not do_clearing then
            force_full = SwipeAnimation.shouldForceFullAfterAnimation(self, prev_page)
        end

        local saved_bb = Screen.saved_bb
        Screen.saved_bb = nil

        if do_clearing or force_full then
            if force_full then
                SwipeAnimation.forceFullAndReset(self, screen_w, screen_h)
            else
                SwipeAnimation.performClearing(self, screen_w, screen_h)
            end
            if saved_bb then
                saved_bb:free()
            end
            return true
        end

        if not saved_bb then
            return false
        end

        local new_bb = Screen.bb:copy()
        local is_landscape = screen_w > screen_h
        local delay_defaults = (UIManager.swipe_animation_defaults or {}).delay_ms or {}
        local step_defaults = (UIManager.swipe_animation_defaults or {}).steps or {}
        local refresh_mode = G_reader_settings:readSetting("swipe_animation_refresh_mode") or "ui"
        local delay_key = is_landscape
            and "swipe_animation_delay_ms_horizontal"
            or "swipe_animation_delay_ms_vertical"
        local delay_ms = tonumber(G_reader_settings:readSetting(delay_key))
        if delay_ms == nil then
            delay_ms = tonumber(G_reader_settings:readSetting("swipe_animation_delay_ms"))
        end
        if delay_ms == nil or delay_ms < 0 then
            delay_ms = is_landscape
                and (delay_defaults.landscape or 10)
                or (delay_defaults.portrait or 20)
        end

        local steps = is_landscape
            and (step_defaults.landscape or 6)
            or (step_defaults.portrait or 8)
        local swipe_forward = Screen.swipe_forward
        if swipe_forward == nil then
            swipe_forward = true
        end

        local edges = buildStripEdges(screen_w, steps, Screen.alignment_constraint)
        local slot_count = #edges - 1
        local usleep = ffi and ffi.C and ffi.C.usleep

        Screen.bb:blitFrom(saved_bb, 0, 0, 0, 0, screen_w, screen_h)

        if Device:isKobo() and Device.isMTK and Device:isMTK() then
            if Screen.refreshWaitForLast then
                Screen:refreshWaitForLast()
            end
            if Screen.dont_wait_for_marker == Screen.marker then
                Screen:refreshUI(0, 0, screen_w, screen_h)
                if Screen.refreshWaitForLast then
                    Screen:refreshWaitForLast()
                end
            end
        end

        for index = 1, slot_count do
            local left
            local right
            if swipe_forward then
                local edge_index = slot_count - index + 1
                left = edges[edge_index]
                right = edges[edge_index + 1]
            else
                left = edges[index]
                right = edges[index + 1]
            end

            local strip_w = right - left
            if strip_w > 0 then
                Screen.bb:blitFrom(new_bb, left, 0, left, 0, strip_w, screen_h)
                local refresh_fn = refresh_mode == "fast" and Screen.refreshFast or Screen.refreshUI
                refresh_fn(Screen, left, 0, strip_w, screen_h)
            end
            if index < slot_count and usleep and delay_ms > 0 then
                usleep(delay_ms * 1000)
            end
        end

        self._refresh_stack = {}
        new_bb:free()
        saved_bb:free()
        return true
    end

    -- Find UIManager:_repaint's private refresh dispatcher before mutating any
    -- screen methods. This is stable across the supported KOReader baseline and
    -- avoids vendoring a complete UIManager snapshot.
    local refresh_methods
    local upvalue_index = 1
    while true do
        local name, value = debug.getupvalue(UIManager._repaint, upvalue_index)
        if not name then
            break
        end
        if name == "refresh_methods" and type(value) == "table" then
            refresh_methods = value
            break
        end
        upvalue_index = upvalue_index + 1
    end
    if not refresh_methods then
        return false, "KOReader UIManager refresh dispatcher is incompatible"
    end

    local original_beforePaint = Screen.beforePaint
    local original_afterPaint = Screen.afterPaint
    local original_setSwipeAnimations = Screen.setSwipeAnimations
    local original_setSwipeDirection = Screen.setSwipeDirection

    function Screen:beforePaint()
        if not self.painting then
            self.painting = true
            if self.swipe_animations then
                if self.saved_bb then
                    self.saved_bb:free()
                end
                self.saved_bb = self.bb:copy()
            end
        end
        if original_beforePaint then
            return original_beforePaint(self)
        end
    end

    function Screen:afterPaint()
        self.painting = false
        UIManager._mysimpleui_swipe_animation_suppress_refresh = false
        if original_afterPaint then
            return original_afterPaint(self)
        end
    end

    function Screen:setSwipeAnimations(enabled)
        if original_setSwipeAnimations then
            original_setSwipeAnimations(self, enabled)
        end
        self.swipe_animations = enabled
    end

    function Screen:setSwipeDirection(direction)
        if original_setSwipeDirection then
            original_setSwipeDirection(self, direction)
        end
        self.swipe_forward = direction
    end

    local function wrapRefresh(original_refresh)
        return function(screen, ...)
            if UIManager._mysimpleui_swipe_animation_suppress_refresh then
                return
            end

            if screen.painting and screen.swipe_animations then
                screen.swipe_animations = false
                UIManager.refresh_counted = true
                local ok_animation, consumed = pcall(SwipeAnimation.run, UIManager)
                if not ok_animation then
                    logger.warn("SwipeAnimation: animation failed:", consumed)
                    if screen.saved_bb then
                        screen.saved_bb:free()
                        screen.saved_bb = nil
                    end
                elseif consumed then
                    UIManager._mysimpleui_swipe_animation_suppress_refresh = true
                    return
                end
            end

            return original_refresh(screen, ...)
        end
    end

    for mode, original_refresh in pairs(refresh_methods) do
        if type(original_refresh) == "function" then
            refresh_methods[mode] = wrapRefresh(original_refresh)
        end
    end

    UIManager._mysimpleui_swipe_animation_core_applied = true
    return true
end

return M
