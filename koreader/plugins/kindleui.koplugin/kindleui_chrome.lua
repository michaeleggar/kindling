--[[--
Reading controls, shown by tapping the page: a top bar (back to the library,
the title, search, Aa, bookmark, contents) and a bottom bar with the chapter, page and
a scrubber marked at each chapter. Tapping the page again hides them.

@module kindleui_chrome
--]]--

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local K = require("kindleui_toolkit")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local T = require("ffi/util").template
local _ = require("gettext")
local Screen = Device.screen
local S = K.S

local Chrome = K.Overlay:extend{
    plugin = nil,
    preview_page = nil, -- page shown while dragging the scrubber
}

local function iconButton(name, px)
    return CenterContainer:new{ dimen = Geom:new{ w = S(44), h = S(44) }, K.icon(name, px) }
end

function Chrome:build()
    local ui = self.plugin.ui
    local W, H = Screen:getWidth(), Screen:getHeight()

    -- Top bar
    local top_h = S(56)
    local title = ui.doc_props and ui.doc_props.display_title or ""
    local buttons = HorizontalGroup:new{ align = "center" }
    if ui.search then
        -- Find in book: next/previous match, or all matches as a list
        table.insert(buttons, self:hit(iconButton("kindleui.search", 21), {
            on_tap = function() self:close(); ui.search:onShowFulltextSearchInput() end,
        }))
    end
    if ui.rolling then
        table.insert(buttons, self:hit(CenterContainer:new{
            dimen = Geom:new{ w = S(44), h = S(44) },
            K.text("Aa", "serif", 19),
        }, { on_tap = function() self:close(); self.plugin:showTextSheet() end }))
    end
    local bookmarked = ui.bookmark and ui.bookmark:isPageBookmarked()
    table.insert(buttons, self:hit(iconButton(bookmarked and "kindleui.bookmark.fill" or "kindleui.bookmark", 21), {
        on_tap = function()
            ui.bookmark:onToggleBookmark()
            self:refresh("ui")
        end,
    }))
    table.insert(buttons, self:hit(iconButton("kindleui.contents", 22), {
        on_tap = function() self:close(); self.plugin:showContentsSheet() end,
    }))

    local back = self:hit(HorizontalGroup:new{
        align = "center",
        CenterContainer:new{ dimen = Geom:new{ w = S(30), h = S(44) }, K.icon("kindleui.back", 22) },
        K.text(_("Library"), "sans", 16),
        K.hspan(10),
    }, { on_tap = function() self:close(); self.plugin:goToLibrary() end })

    local top = VerticalGroup:new{
        align = "left",
        FrameContainer:new{
            width = W, height = top_h, background = K.PAPER,
            bordersize = 0, margin = 0, padding = 0,
            OverlapGroup:new{
                dimen = Geom:new{ w = W, h = top_h },
                CenterContainer:new{
                    dimen = Geom:new{ w = W, h = top_h },
                    K.text(title, "sans_semibold", 14, K.INK, W - S(420)),
                },
                LeftContainer:new{
                    dimen = Geom:new{ w = W, h = top_h },
                    FrameContainer:new{ bordersize = 0, margin = 0, padding = 0, padding_left = S(6), back },
                },
                RightContainer:new{
                    dimen = Geom:new{ w = W, h = top_h },
                    FrameContainer:new{ bordersize = 0, margin = 0, padding = 0, padding_right = S(10), buttons },
                },
            },
        },
        K.rule(W, math.max(1, S(1)), K.SEPARATOR),
    }
    table.insert(self.insides, Geom:new{ x = 0, y = 0, w = W, h = top_h })

    -- Bottom bar
    local pad_x = S(44)
    local cw = W - 2 * pad_x
    local count = ui.document:getPageCount()
    local page = self.preview_page or ui:getCurrentPage()
    -- "Chapter 1 - Lobsters" -> "Lobsters"; "Part 1 - Slow Takeoff" -> "Part 1 · Slow Takeoff"
    local toc_title = ui.toc and ui.toc:getTocTitleByPage(page) or ""
    local number, chapter = K.chapterParts(toc_title)
    if not number then
        chapter = K.sectionTitle(toc_title)
    end
    local labels = OverlapGroup:new{
        dimen = Geom:new{ w = cw, h = S(18) },
        LeftContainer:new{
            dimen = Geom:new{ w = cw, h = S(18) },
            K.text(chapter, "sans", 12, K.MUTED, math.floor(cw * 0.6)),
        },
        RightContainer:new{
            dimen = Geom:new{ w = cw, h = S(18) },
            K.text(T(_("Page %1 of %2"), page, count), "sans", 12, K.MUTED),
        },
    }
    local bottom = VerticalGroup:new{
        align = "left",
        K.rule(W, math.max(1, S(1)), K.SEPARATOR),
        FrameContainer:new{
            width = W, background = K.PAPER,
            bordersize = 0, margin = 0, padding = 0,
            padding_left = pad_x, padding_right = pad_x, padding_top = S(14), padding_bottom = S(22),
            VerticalGroup:new{
                align = "left",
                labels,
                K.vspan(10),
                self:scrubber(cw, page, count),
            },
        },
    }
    local bottom_h = bottom:getSize().h
    bottom.overlap_offset = { 0, H - bottom_h }
    self.bottom_rect = Geom:new{ x = 0, y = H - bottom_h, w = W, h = bottom_h }
    table.insert(self.insides, self.bottom_rect)

    return OverlapGroup:new{ dimen = Geom:new{ w = W, h = H }, top, bottom }
end

function Chrome:scrubber(width, page, count)
    local ui = self.plugin.ui
    local fraction = count > 1 and (page - 1) / (count - 1) or 0
    local slider = K.slider(width, fraction)
    -- Chapter marks along the track, under the knob
    local knob = S(24)
    local travel = width - knob
    local ticks = {}
    if ui.toc then
        ui.toc:fillToc()
        ticks = K.sectionStarts(ui.toc.toc or {})
    end
    for _, tick_page in ipairs(ticks) do
        if count > 1 and tick_page > 1 then
            local mark = K.rule(math.max(1, S(1)), S(10), K.EDGE)
            mark.overlap_offset = {
                math.floor(knob / 2 + travel * (tick_page - 1) / (count - 1)),
                math.floor((S(28) - S(10)) / 2),
            }
            table.insert(slider, #slider, mark)
        end
    end
    return self:hit(slider, {
        on_drag = function(f, final)
            local target = math.floor(1 + f * (count - 1) + 0.5)
            if final then
                self.preview_page = nil
                if target ~= ui:getCurrentPage() then
                    ui:handleEvent(Event:new("GotoPage", target))
                end
                self:refresh("ui")
            elseif target ~= self.preview_page then
                self.preview_page = target
                self:refresh("fast", self.bottom_rect)
            end
        end,
    })
end

function Chrome:onCloseWidget()
    K.Overlay.onCloseWidget(self)
    if self.plugin.chrome == self then
        self.plugin.chrome = nil
    end
end

return Chrome
