--[[--
The definition sheet: holding a word while reading slides this up from the
bottom with the word, which dictionary it came from, the definition, and
buttons to highlight the word, find it in the book, or open KOReader's full
lookup window. Swipe sideways to go through results from other dictionaries.

@module kindleui_dictsheet
--]]--

local CenterContainer = require("ui/widget/container/centercontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local K = require("kindleui_toolkit")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Screen = require("device").screen
local T = require("ffi/util").template
local _ = require("gettext")
local S = K.S

local DictSheet = K.Sheet:extend{
    plugin = nil,
    dictionary = nil,     -- ReaderDictionary
    highlight = nil,      -- ReaderHighlight holding the selected word, if any
    word = nil,
    results = nil,
    boxes = nil,
    link = nil,
    dict_close_callback = nil,
    show_full = nil,      -- function() opening KOReader's own window for these results
    index = 1,
    save_highlight = false,
}

-- Sized in mockup pixels; the definition takes whatever the rest leaves
local HANDLE_H, HEADER_H, SOURCE_H, GAP, CHIP_H, BOTTOM = 21, 44, 24, 10, 40, 26

local CSS = [[
    @page { margin: 0; font-family: 'Noto Serif'; }
    body { margin: 0; line-height: 1.4; }
    i { color: #444444; }
    ol, ul { margin: 0.15em 0 0.7em 0; padding: 0 0 0 1.5em; }
    li { margin-bottom: 0.3em; }
    blockquote, dd { margin: 0 1em; }
]]

local function escape(text)
    return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub("\n", "<br/>"))
end

function DictSheet:build()
    self.sheet_height = math.min(S(470), math.floor(Screen:getHeight() * 0.6))
    return K.Sheet.build(self)
end

function DictSheet:buildContent(cw)
    local result = self.results[self.index]
    local headword = result.word and result.word ~= "" and result.word or self.word

    local header = K.sheetHeader(self, cw, nil, function() self:dismiss() end,
        K.text(headword, "serif", 26, K.INK, cw - S(60)))

    -- Which dictionary, and where we are among the results
    local source = OverlapGroup:new{
        dimen = Geom:new{ w = cw, h = S(SOURCE_H) },
        LeftContainer:new{
            dimen = Geom:new{ w = cw, h = S(SOURCE_H) },
            K.text((result.dict or ""):upper(), "sans_medium", 11, K.MUTED, math.floor(cw * 0.7)),
        },
    }
    if #self.results > 1 then
        local function arrow(icon, step)
            return self:hit(CenterContainer:new{
                dimen = Geom:new{ w = S(32), h = S(SOURCE_H) },
                K.icon(icon, 14, { dim = (self.index + step < 1 or self.index + step > #self.results) }),
            }, { on_tap = function() self:go(step) end })
        end
        table.insert(source, RightContainer:new{
            dimen = Geom:new{ w = cw + S(8), h = S(SOURCE_H) },
            HorizontalGroup:new{
                align = "center",
                arrow("chevron.left", -1),
                K.text(T(_("%1 of %2"), self.index, #self.results), "sans", 12, K.MUTED),
                arrow("chevron.right", 1),
            },
        })
    end

    local chips_h = S(CHIP_H)
    local def_h = self.sheet_height
        - S(HANDLE_H) - S(HEADER_H) - S(SOURCE_H) - 2 * S(GAP) - chips_h - S(BOTTOM)
    local body = result.is_html and result.definition or escape(result.definition or "")
    local definition = ScrollHtmlWidget:new{
        html_body = body,
        html_resource_directory = result.dictionary_resource_directory,
        css = CSS .. (result.css or ""),
        default_font_size = S(17),
        width = cw,
        height = def_h,
        dialog = self,
        html_link_tapped_callback = function(link)
            self.dictionary:onHtmlDictionaryLinkTapped(result.dict, link)
        end,
    }

    return VerticalGroup:new{
        align = "left",
        header,
        source,
        K.vspan(GAP),
        definition,
        K.vspan(GAP),
        self:buttons(cw, chips_h, headword),
    }
end

function DictSheet:buttons(cw, h, headword)
    local items = {}
    local selected = self.highlight and self.highlight.selected_text
    if selected then
        table.insert(items, {
            label = self.save_highlight and _("Highlighted") or _("Highlight"),
            on = self.save_highlight,
            tap = function()
                self.save_highlight = not self.save_highlight
                self:refresh("ui")
            end,
        })
    end
    local ui = self.plugin.ui
    if ui.search then
        table.insert(items, {
            label = _("Find in book"),
            tap = function()
                local text = selected and selected.text or headword
                self:dismiss()
                ui.search:searchText(text)
            end,
        })
    end
    table.insert(items, {
        label = _("More"),
        tap = function()
            self.handed_off = true
            self:close()
            self.show_full()
        end,
    })

    local gap = S(8)
    local w = math.floor((cw - gap * (#items - 1)) / #items)
    local row = HorizontalGroup:new{ align = "center" }
    for i, item in ipairs(items) do
        if i > 1 then table.insert(row, K.hspan(8)) end
        table.insert(row, self:hit(K.chip(w, h, item.label, item.on), { on_tap = item.tap }))
    end
    return row
end

function DictSheet:go(step)
    local index = self.index + step
    if index < 1 or index > #self.results then return end
    self.index = index
    self:refresh("ui")
end

function DictSheet:onSheetSwipe(direction)
    self:go(direction == "west" and 1 or -1)
end

-- Closing keeps the selection on screen a moment, so you can see where you were,
-- or turns it into a highlight if asked
function DictSheet:dismiss(no_clear)
    self.no_clear = no_clear
    self:close()
end

function DictSheet:onCloseWidget()
    K.Sheet.onCloseWidget(self)
    if self.plugin.dict_sheet == self then
        self.plugin.dict_sheet = nil
    end
    if self.handed_off then return end
    local highlight = self.highlight
    if highlight then
        if self.save_highlight then
            highlight:saveHighlight()
            highlight:clear()
        elseif not self.no_clear then
            local clear_id = highlight:getClearId()
            UIManager:scheduleIn(G_defaults:readSetting("DELAY_CLEAR_HIGHLIGHT_S"), function()
                highlight:clear(clear_id)
            end)
        end
    end
    if self.dict_close_callback then
        self.dict_close_callback()
    end
end

return DictSheet
