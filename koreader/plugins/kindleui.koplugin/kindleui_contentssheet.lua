--[[--
The Contents sheet: the book at the top, then Contents, Bookmarks and
Highlights. Tapping an entry goes there. Long lists page by swiping sideways.

@module kindleui_contentssheet
--]]--

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local ImageWidget = require("ui/widget/imagewidget")
local K = require("kindleui_toolkit")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local T = require("ffi/util").template
local _ = require("gettext")
local Screen = Device.screen
local S = K.S

local TABS = { _("Contents"), _("Bookmarks"), _("Highlights") }
local HEIGHTS = { header = 40, row = 50, quote = 86 }

local ContentsSheet = K.Sheet:extend{
    plugin = nil,
    tab = 1,
    list_page = nil, -- nil: the page holding the current chapter
}

function ContentsSheet:init()
    self.sheet_height = Screen:getHeight() - S(64)
    self.scrim = self.plugin.path .. "/scrims/scrim-contents.png"
    K.Sheet.init(self)
end

-- Entries for the current tab
function ContentsSheet:items()
    local ui = self.plugin.ui
    local items = {}
    if self.tab == 1 then
        ui.toc:fillToc()
        local toc = ui.toc.toc or {}
        local current = ui.toc:getTocIndexByPage(ui:getCurrentPage())
        for i, entry in ipairs(toc) do
            local has_children = toc[i + 1] and toc[i + 1].depth > entry.depth
            local number, name = K.chapterParts(entry.title)
            table.insert(items, {
                kind = has_children and "header" or "row",
                title = has_children and K.sectionTitle(entry.title) or name,
                number = not has_children and number or nil,
                page = entry.page,
                current = i == current,
                go = function() ui:handleEvent(Event:new("GotoPage", entry.page)) end,
            })
        end
    else
        local annotations = ui.annotation and ui.annotation.annotations or {}
        for _, a in ipairs(annotations) do
            local is_highlight = a.drawer ~= nil
            if (self.tab == 3) == is_highlight then
                table.insert(items, {
                    kind = is_highlight and "quote" or "row",
                    title = is_highlight and a.text or T(_("Page %1"), a.pageno or "?"),
                    subtitle = is_highlight and T(_("%1 · p. %2"), a.chapter or "", a.pageno or "?") or a.chapter,
                    go = function() ui.bookmark:gotoBookmark(a.page, a.pos0) end,
                })
            end
        end
    end
    return items
end

-- Split items into pages that fit the list area
local function paginate(items, list_h)
    local pages, page, used = {}, {}, 0
    for _, item in ipairs(items) do
        local h = S(HEIGHTS[item.kind])
        if used + h > list_h and #page > 0 then
            table.insert(pages, page)
            page, used = {}, 0
        end
        table.insert(page, item)
        used = used + h
    end
    if #page > 0 then
        table.insert(pages, page)
    end
    return pages
end

function ContentsSheet:buildContent(cw)
    local ui = self.plugin.ui
    local header = self:bookHeader(cw)
    local tabs = K.segmented(self, cw, TABS, self.tab, function(i)
        self.tab = i
        self.list_page = i == 1 and nil or 1
        self:refresh("ui")
    end)

    local list_h = self.sheet_height - S(21) - S(14) - S(90) - S(18) - S(40) - S(8) - S(48) - S(16)
    local items = self:items()
    local pages = paginate(items, list_h)
    self.pages = #pages
    if not self.list_page then
        self.list_page = 1
        for p, page in ipairs(pages) do
            for _, item in ipairs(page) do
                if item.current then self.list_page = p end
            end
        end
    end
    self.list_page = math.max(1, math.min(self.list_page, math.max(1, #pages)))

    local list = VerticalGroup:new{ align = "left" }
    if #items == 0 then
        local empty = self.tab == 2
            and _("No bookmarks yet.\nTap the bookmark at the top of a page to add one.")
            or (self.tab == 3 and _("No highlights yet.\nHold on a word, then drag, to highlight a passage.")
            or _("This book has no table of contents."))
        table.insert(list, CenterContainer:new{
            dimen = Geom:new{ w = cw, h = list_h },
            TextBoxWidget:new{
                text = empty,
                face = K.face("serif_italic", 16),
                fgcolor = K.MUTED,
                width = cw - S(60),
                alignment = "center",
            },
        })
    else
        for _, item in ipairs(pages[self.list_page]) do
            table.insert(list, self:entry(item, cw))
        end
    end

    local pager = HorizontalGroup:new{
        align = "center",
        self:hit(CenterContainer:new{ dimen = Geom:new{ w = S(44), h = S(44) },
            K.icon("chevron.left", 16, { dim = self.list_page <= 1 }) },
            { on_tap = function() self:onSheetSwipe("east") end }),
        K.hspan(12),
        K.text(T(_("%1 of %2"), self.list_page, math.max(1, #pages)), "sans", 12, K.MUTED),
        K.hspan(12),
        self:hit(CenterContainer:new{ dimen = Geom:new{ w = S(44), h = S(44) },
            K.icon("chevron.right", 16, { dim = self.list_page >= #pages }) },
            { on_tap = function() self:onSheetSwipe("west") end }),
    }

    return VerticalGroup:new{
        align = "left",
        K.vspan(14),
        header,
        K.vspan(18),
        tabs,
        K.vspan(8),
        OverlapGroup:new{ dimen = Geom:new{ w = cw, h = list_h }, list },
        -- A pager only when there's more than one page
        #pages > 1 and CenterContainer:new{ dimen = Geom:new{ w = cw, h = S(48) }, pager } or K.vspan(48),
    }
end

function ContentsSheet:bookHeader(cw)
    local ui = self.plugin.ui
    local props = ui.doc_props or {}
    local cover_w, cover_h = S(60), S(90)
    local cover
    local ok, BookInfoManager = pcall(require, "bookinfomanager")
    local info = ok and BookInfoManager:getBookInfo(ui.document.file, true)
    if info and info.cover_bb then
        cover = FrameContainer:new{
            bordersize = math.max(1, S(1)), color = K.EDGE, margin = 0, padding = 0,
            ImageWidget:new{ image = info.cover_bb, width = cover_w, height = cover_h, scale_factor = 0 },
        }
    else
        cover = K.pill(cover_w, cover_h, K.GROUPED, 0, K.EDGE)
    end

    local count = ui.document:getPageCount()
    local page = ui:getCurrentPage()
    local text_w = cw - cover_w - S(16) - S(44)
    local details = VerticalGroup:new{
        align = "left",
        K.text(props.display_title or "", "serif", 21, K.INK, text_w),
        K.vspan(3),
        K.text(props.authors and props.authors:gsub("\n", ", ") or "", "serif_italic", 15, K.SOFT_INK, text_w),
        K.vspan(8),
        K.text(T(_("%1% · Page %2 of %3"), math.floor(page / count * 100 + 0.5), page, count), "sans", 12, K.MUTED, text_w),
    }
    local close = K.sheetHeader(self, S(44), nil, function() self:close() end, K.hspan(0))
    close.overlap_offset = { cw - S(44), 0 }
    return OverlapGroup:new{
        dimen = Geom:new{ w = cw, h = cover_h },
        HorizontalGroup:new{
            align = "center",
            cover,
            K.hspan(16),
            details,
        },
        close,
    }
end

function ContentsSheet:entry(item, cw)
    local h = S(HEIGHTS[item.kind])
    local widget
    if item.kind == "header" then
        widget = OverlapGroup:new{
            dimen = Geom:new{ w = cw, h = h },
            LeftContainer:new{
                dimen = Geom:new{ w = cw, h = h + S(10) },
                K.text(item.title:upper(), "sans_semibold", 11, K.MUTED, cw),
            },
        }
    elseif item.kind == "row" then
        local right
        if item.current then
            local dot = S(8)
            right = HorizontalGroup:new{
                align = "center",
                K.pill(dot, dot, K.INK, math.floor(dot / 2)),
                K.hspan(7),
                K.text(_("Reading"), "sans_semibold", 12),
            }
        elseif item.page then
            right = K.text(tostring(item.page), "sans", 13, K.SUBTLE)
        end
        local text_w = cw - S(110) - (item.number and S(30) or 0)
        local left = VerticalGroup:new{ align = "left", K.text(item.title, "serif", 17, K.INK, text_w) }
        if item.subtitle then
            table.insert(left, K.vspan(2))
            table.insert(left, K.text(item.subtitle, "sans", 12, K.MUTED, text_w))
        end
        if item.number then
            left = HorizontalGroup:new{
                align = "center",
                LeftContainer:new{
                    dimen = Geom:new{ w = S(30), h = S(24) },
                    K.text(item.number, "sans", 13, K.SUBTLE),
                },
                left,
            }
        end
        widget = VerticalGroup:new{
            align = "left",
            OverlapGroup:new{
                dimen = Geom:new{ w = cw, h = h - math.max(1, S(1)) },
                LeftContainer:new{ dimen = Geom:new{ w = cw, h = h }, left },
                right and RightContainer:new{ dimen = Geom:new{ w = cw, h = h }, right } or nil,
            },
            K.rule(cw, math.max(1, S(1)), K.SEPARATOR),
        }
    else -- quote
        widget = VerticalGroup:new{
            align = "left",
            K.vspan(10),
            TextBoxWidget:new{
                text = item.title or "",
                face = K.face("serif", 15),
                width = cw,
                height = math.ceil(S(15) * 1.3 * 2),
                height_overflow_show_ellipsis = true,
            },
            K.vspan(5),
            K.text(item.subtitle or "", "sans", 12, K.MUTED, cw),
            K.vspan(10),
            K.rule(cw, math.max(1, S(1)), K.SEPARATOR),
        }
    end
    return self:hit(widget, {
        on_tap = function()
            self:close()
            item.go()
        end,
    })
end

function ContentsSheet:onSheetSwipe(direction)
    local target = self.list_page + (direction == "west" and 1 or -1)
    if target >= 1 and target <= (self.pages or 1) then
        self.list_page = target
        self:refresh("ui")
    end
end

return ContentsSheet
