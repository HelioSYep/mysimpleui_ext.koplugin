local M = {}

function M.install()
    local ReaderPaging = require("apps/reader/modules/readerpaging")
    local Event = require("ui/event")

    if ReaderPaging._mysimpleui_swipe_animation_paging_applied then
        return true
    end
    ReaderPaging._mysimpleui_swipe_animation_paging_applied = true

    local original_gotoPage = ReaderPaging._gotoPage
    if type(original_gotoPage) ~= "function" then
        return false, "ReaderPaging._gotoPage is unavailable"
    end

    function ReaderPaging:_gotoPage(number, ...)
        if self.current_page
                and self.current_page > 0
                and number ~= self.current_page
                and not self.view.page_scroll
                and G_reader_settings:isTrue("swipe_animations") then
            self.ui:handleEvent(Event:new("PageChangeAnimation", number > self.current_page))
        end
        return original_gotoPage(self, number, ...)
    end

    return true
end

return M
