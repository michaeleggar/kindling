--[[--
Simplified settings, reading controls and sheets in the style of the home
screen. The screens live in their own modules; this plugin opens them and,
in the reader, claims the taps that used to open KOReader's menus.

@module koplugin.KindleUI
--]]--

local Dispatcher = require("dispatcher")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local KindleUI = WidgetContainer:extend{
    name = "kindleui",
    is_doc_only = false,
}

function KindleUI:onDispatcherRegisterActions()
    Dispatcher:registerAction("kindleui_settings", {
        category = "none",
        event = "ShowKindleSettings",
        title = _("Settings (simple)"),
        general = true,
    })
    Dispatcher:registerAction("kindleui_controls", {
        category = "none",
        event = "ShowReadingControls",
        title = _("Reading controls"),
        reader = true,
    })
end

function KindleUI:init()
    self:onDispatcherRegisterActions()
    self:replaceOpeningMessage()
end

-- KOReader shows an "Opening file '…'" message while a book loads; show the
-- book's cover and title instead. Mirrors ReaderUI:showReaderCoroutine.
function KindleUI:replaceOpeningMessage()
    local ReaderUI = require("apps/reader/readerui")
    if ReaderUI._kindleui_opening then return end
    ReaderUI._kindleui_opening = true
    local Device = require("device")
    local InfoMessage = require("ui/widget/infomessage")
    local Opening = require("kindleui_opening")
    ReaderUI.showReaderCoroutine = function(reader, file, provider, seamless)
        local opening
        if not seamless then
            opening = Opening:new{ file = file }
            UIManager:show(opening, "flashui")
        end
        -- doShowReader might block for a long time, so force repaint here
        UIManager:forceRePaint()
        UIManager:nextTick(function()
            if opening then
                UIManager:close(opening)
            end
            local co = coroutine.create(function()
                reader:doShowReader(file, provider, seamless)
            end)
            local ok, err = coroutine.resume(co)
            if err ~= nil or ok == false then
                io.stderr:write("[!] doShowReader coroutine crashed:\n")
                io.stderr:write(debug.traceback(co, err, 1))
                Device:setIgnoreInput(false)
                Device.input:inhibitInputUntil(0.2)
                UIManager:show(InfoMessage:new{
                    text = _("No reader engine for this file or invalid file."),
                })
                reader:showFileManager(file)
            end
        end)
    end
end

-- Comics are pictures, so in dark mode show their pages as drawn rather than
-- as negatives, the way pictures elsewhere are kept
local COMIC_EXTS = { cbz = true, cbr = true, cbt = true, cb7 = true }

function KindleUI:keepComicPagesInDarkMode()
    local doc = self.ui.document
    local file = doc.file or ""
    local ext = (file:match("%.([^./]+)$") or ""):lower()
    if not COMIC_EXTS[ext] and not file:find("/library/Comics/", 1, true) then return end
    if doc._kindleui_comic then return end
    doc._kindleui_comic = true
    local Screen = require("device").screen
    local drawPage = doc.drawPage
    doc.drawPage = function(d, target, x, y, rect, ...)
        local result = drawPage(d, target, x, y, rect, ...)
        if Screen.night_mode then
            target:invertRect(x, y, rect.w, rect.h)
        end
        return result
    end
end

-- Reader taps: the top and bottom edges (between the corners) and the middle
-- of the page show the reading controls; the sides still turn pages.
function KindleUI:onReaderReady()
    self:keepComicPagesInDarkMode()
    local show = function(ges)
        -- A link or highlight under the finger comes first
        if self.ui.link and self.ui.link:onTap(nil, ges) then return true end
        if self.ui.highlight and self.ui.highlight:onTap(nil, ges) then return true end
        return self:onShowReadingControls()
    end
    self.ui:registerTouchZones({
        {
            id = "kindleui_tap_top",
            ges = "tap",
            screen_zone = { ratio_x = 1/8, ratio_y = 0, ratio_w = 6/8, ratio_h = 1/8 },
            overrides = { "readermenu_tap", "readermenu_ext_tap", "tap_forward", "tap_backward" },
            handler = show,
        },
        {
            id = "kindleui_tap_middle",
            ges = "tap",
            screen_zone = { ratio_x = 1/3, ratio_y = 1/4, ratio_w = 1/3, ratio_h = 1/2 },
            overrides = { "readermenu_ext_tap", "readerconfigmenu_ext_tap", "tap_forward", "tap_backward" },
            handler = show,
        },
        {
            id = "kindleui_tap_bottom",
            ges = "tap",
            screen_zone = { ratio_x = 1/8, ratio_y = 7/8, ratio_w = 6/8, ratio_h = 1/8 },
            overrides = { "readerconfigmenu_tap", "readerconfigmenu_ext_tap", "readerfooter_tap", "tap_forward", "tap_backward" },
            handler = show,
        },
    })

    -- Pulling down from the top shows the reading controls, pushing up from the
    -- bottom opens Aa, in the same areas KOReader used for its menus. Other
    -- directions fall through, so sideways swipes there still turn pages.
    local function when(direction, action)
        return function(ges)
            if ges.direction ~= direction then return false end
            return action()
        end
    end
    local controls = when("south", function() return self:onShowReadingControls() end)
    local text = when("north", function() return self:showTextSheet() end)
    local top, top_ext = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1/8 }, { ratio_x = 1/4, ratio_y = 0, ratio_w = 2/4, ratio_h = 1/5 }
    local bottom, bottom_ext = { ratio_x = 0, ratio_y = 7/8, ratio_w = 1, ratio_h = 1/8 }, { ratio_x = 1/4, ratio_y = 4/5, ratio_w = 2/4, ratio_h = 1/5 }
    local zones = {}
    for _, ges in ipairs({ "swipe", "pan" }) do
        local paging = ges == "swipe" and { "rolling_swipe", "paging_swipe" } or { "rolling_pan", "paging_pan" }
        table.insert(zones, { id = "kindleui_" .. ges .. "_top", ges = ges, screen_zone = top,
            overrides = { "readermenu_" .. ges, unpack(paging) }, handler = controls })
        table.insert(zones, { id = "kindleui_" .. ges .. "_top_ext", ges = ges, screen_zone = top_ext,
            overrides = { "readermenu_ext_" .. ges, "kindleui_" .. ges .. "_top" }, handler = controls })
        table.insert(zones, { id = "kindleui_" .. ges .. "_bottom", ges = ges, screen_zone = bottom,
            overrides = { "readerconfigmenu_" .. ges, unpack(paging) }, handler = text })
        table.insert(zones, { id = "kindleui_" .. ges .. "_bottom_ext", ges = ges, screen_zone = bottom_ext,
            overrides = { "readerconfigmenu_ext_" .. ges, "kindleui_" .. ges .. "_bottom" }, handler = text })
    end
    self.ui:registerTouchZones(zones)
end

function KindleUI:showSettings()
    local SettingsScreen = require("kindleui_settings")
    UIManager:show(SettingsScreen:new{ plugin = self }, "flashui")
end

function KindleUI:onShowKindleSettings()
    self:showSettings()
    return true
end

function KindleUI:onShowReadingControls()
    if not self.ui.document then return false end
    if self.chrome and not self.chrome.closed then return true end
    local Chrome = require("kindleui_chrome")
    self.chrome = Chrome:new{ plugin = self }
    UIManager:show(self.chrome, "ui")
    return true
end

-- Sheets: one at a time, since a drag sends many pan events
function KindleUI:showSheet(module)
    if self.sheet and not self.sheet.closed then return true end
    local Sheet = require(module)
    self.sheet = Sheet:new{ plugin = self }
    UIManager:show(self.sheet, "flashui")
    return true
end

function KindleUI:showTextSheet()
    -- Text options only apply to reflowable books; others get the controls
    if not self.ui.rolling then
        return self:onShowReadingControls()
    end
    return self:showSheet("kindleui_textsheet")
end

function KindleUI:showContentsSheet()
    return self:showSheet("kindleui_contentssheet")
end

-- Close the book; the file browser opens the home screen
function KindleUI:goToLibrary()
    local file = self.ui.document.file
    self.ui:onClose()
    self.ui:showFileManager(file)
end

return KindleUI
