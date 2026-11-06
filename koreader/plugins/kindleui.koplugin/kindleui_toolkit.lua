--[[--
Shared building blocks for the Kindle UI screens: type, color, grouped lists,
switches, sliders, segmented controls, and a full-screen page that routes
taps and drags to whatever was painted under the finger.

Sizes are given in mockup pixels (a 632 px wide screen) and scaled to the device.

@module kindleui_toolkit
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local time = require("ui/time")
local Screen = Device.screen

local K = {}

K.INK = Blitbuffer.COLOR_BLACK
K.PAPER = Blitbuffer.COLOR_WHITE
K.GROUPED = Blitbuffer.Color8(0xEE)   -- page behind grouped cards
K.SOFT_INK = Blitbuffer.Color8(0x33)
K.MUTED = Blitbuffer.Color8(0x44)
K.SUBTLE = Blitbuffer.Color8(0x66)
K.EDGE = Blitbuffer.Color8(0xAA)
K.CONTROL = Blitbuffer.Color8(0xCC)   -- switch off, segmented track
K.TRACK = Blitbuffer.Color8(0xDD)
K.SEPARATOR = Blitbuffer.Color8(0xDD)

local FONTS = {
    serif = "home/Literata-Regular.ttf",
    serif_italic = "home/Literata-Italic.ttf",
    sans = "home/Inter-Regular.ttf",
    sans_medium = "home/Inter-Medium.ttf",
    sans_semibold = "home/Inter-SemiBold.ttf",
    sans_bold = "home/Inter-Bold.ttf",
}

function K.S(px)
    return math.floor(px * Screen:getWidth() / 632 + 0.5)
end
local S = K.S

function K.face(name, px)
    -- Font:getFace applies Screen:scaleBySize, so divide that back out
    local size_scale = math.min(Screen:getWidth(), Screen:getHeight()) / 600
    return Font:getFace(FONTS[name], S(px) / size_scale)
end

function K.text(str, font, px, color, max_width)
    return TextWidget:new{
        text = str,
        face = K.face(font, px),
        fgcolor = color or K.INK,
        max_width = max_width,
        padding = 0,
    }
end

function K.vspan(px) return VerticalSpan:new{ width = S(px) } end
function K.hspan(px) return HorizontalSpan:new{ width = S(px) } end

function K.rule(w, h, color)
    return LineWidget:new{ dimen = Geom:new{ w = w, h = h }, background = color }
end

-- A filled rounded rectangle of a fixed size. FrameContainer measures itself
-- from its content, so it holds an empty widget of the inside size.
function K.pill(w, h, color, radius, border_color)
    local border = border_color and math.max(1, S(1)) or 0
    return FrameContainer:new{
        width = w,
        height = h,
        radius = radius,
        background = color,
        bordersize = border,
        color = border_color,
        margin = 0,
        padding = 0,
        Widget:new{ dimen = Geom:new{ w = w - 2 * border, h = h - 2 * border } },
    }
end

function K.icon(name, px, opts)
    opts = opts or {}
    return IconWidget:new{
        icon = name,
        width = S(px),
        height = S(px),
        alpha = true, -- keep the background behind it, e.g. on gray pages
        dim = opts.dim,
        invert = opts.invert,
    }
end

-- Hit remembers where it was painted, so the page can route touches to it.
-- on_tap() for buttons; on_drag(fraction) for sliders.
local Hit = WidgetContainer:extend{
    on_tap = nil,
    on_drag = nil,
}

function Hit:paintTo(bb, x, y)
    local size = self[1]:getSize()
    self.dimen = Geom:new{ x = x, y = y, w = size.w, h = size.h }
    self[1]:paintTo(bb, x, y)
end

-- Page -----------------------------------------------------------------------

--- A full-screen screen. Subclasses implement build() and may set on_back.
K.Page = InputContainer:extend{
    covers_fullscreen = true,
    background = nil,
    on_back = nil,
}

function K.Page:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = self.dimen } },
        Pan = { GestureRange:new{ ges = "pan", range = self.dimen } },
        PanRelease = { GestureRange:new{ ges = "pan_release", range = self.dimen } },
        Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } },
        Hold = { GestureRange:new{ ges = "hold", range = self.dimen } },
    }
    self:rebuild()
end

function K.Page:hit(widget, handlers)
    local hit = Hit:new{ widget, on_tap = handlers.on_tap, on_drag = handlers.on_drag }
    table.insert(self.hits, hit)
    return hit
end

function K.Page:rebuild()
    if self[1] then
        self[1]:free()
    end
    self.hits = {}
    self[1] = FrameContainer:new{
        width = self.dimen.w,
        height = self.dimen.h,
        background = self.background or K.PAPER,
        bordersize = 0,
        margin = 0,
        padding = 0,
        self:build(),
    }
end

function K.Page:refresh(mode, region)
    if self.closed then return end
    self:rebuild()
    UIManager:setDirty(self, function() return mode or "ui", region or self.dimen end)
end

function K.Page:hitAt(pos, field)
    for _, hit in ipairs(self.hits) do
        if hit[field] and hit.dimen and hit.dimen:contains(pos) then
            return hit
        end
    end
end

local function dragFraction(hit, pos)
    local knob = S(24)
    local f = (pos.x - hit.dimen.x - knob / 2) / (hit.dimen.w - knob)
    return math.max(0, math.min(1, f))
end

function K.Page:onTap(_, ges)
    local hit = self:hitAt(ges.pos, "on_drag")
    if hit then
        hit.on_drag(dragFraction(hit, ges.pos), true)
        return true
    end
    hit = self:hitAt(ges.pos, "on_tap")
    if hit then
        hit.on_tap()
    end
    return true
end

function K.Page:onPan(_, ges)
    -- Keep dragging the slider the finger started on, even if it drifts off it
    local start = ges.pos
    if ges.relative then
        start = Geom:new{ x = ges.pos.x - ges.relative.x, y = ges.pos.y - ges.relative.y, w = 0, h = 0 }
    end
    self.dragging = self.dragging or self:hitAt(start, "on_drag")
    if self.dragging then
        self.dragging.on_drag(dragFraction(self.dragging, ges.pos), false)
    end
    return true
end

function K.Page:onPanRelease(_, ges)
    if self.dragging then
        self.dragging.on_drag(dragFraction(self.dragging, ges.pos), true)
        self.dragging = nil
    end
    return true
end

function K.Page:onSwipe(_, ges)
    -- Swipe in from the left edge to go back
    if ges.direction == "east" and self.on_back then
        local start_x = ges.pos.x - (ges.relative and ges.relative.x or 0)
        if start_x < S(60) then
            self.on_back()
        end
    end
    return true
end

function K.Page:onHold()
    return true
end

function K.Page:close()
    UIManager:close(self, "flashui")
end

function K.Page:onCloseWidget()
    self.closed = true
    if self[1] then
        self[1]:free()
    end
end

-- Overlay and sheet ----------------------------------------------------------

--- Like a page, but paints only its content over whatever is beneath.
-- Set self.insides to the rects that count as "on" the overlay; taps elsewhere close it.
K.Overlay = K.Page:extend{
    covers_fullscreen = false,
}

function K.Overlay:rebuild()
    if self[1] then
        self[1]:free()
    end
    self.hits = {}
    self.insides = {}
    self[1] = self:build()
end

function K.Overlay:isInside(pos)
    for _, rect in ipairs(self.insides) do
        if rect:contains(pos) then return true end
    end
    return false
end

function K.Overlay:onTap(arg, ges)
    if not self:isInside(ges.pos) then
        self:close()
        return true
    end
    return K.Page.onTap(self, arg, ges)
end

function K.Overlay:init()
    self.shown_at = time.now()
    K.Page.init(self)
end

function K.Overlay:onSwipe(arg, ges)
    -- The swipe that opened this (its pan events came first) ends just after it appears
    if time.to_s(time.since(self.shown_at)) < 1 then
        return true
    end
    if not self:isInside(ges.pos) then
        self:close()
        return true
    end
    if ges.direction == "south" then
        self:close()
    elseif (ges.direction == "west" or ges.direction == "east") and self.onSheetSwipe then
        self:onSheetSwipe(ges.direction)
    end
    return true
end

--- A card that slides up from the bottom, with a halftone shadow over the page above it.
-- Subclasses set sheet_height (px) and scrim (image path), and implement buildContent(width).
-- With scrim_band (px), the shadow is only that tall a strip above the card, leaving the page readable.
K.Sheet = K.Overlay:extend{
    sheet_height = nil,
    scrim = nil,
    scrim_band = nil,
}

function K.Sheet:build()
    local W, H = Screen:getWidth(), Screen:getHeight()
    local radius, edge = S(22), math.max(1, S(1))
    local top = H - self.sheet_height
    table.insert(self.insides, Geom:new{ x = 0, y = top, w = W, h = self.sheet_height })

    local layers = OverlapGroup:new{ dimen = Geom:new{ w = W, h = H } }
    if self.scrim and lfs.attributes(self.scrim, "mode") == "file" then
        local band = self.scrim_band or top
        -- Invert along with the screen in dark mode: keeping the image's original
        -- colors would also flip back the page showing through its transparent parts
        local shadow = ImageWidget:new{ file = self.scrim, alpha = true, width = W, height = band + S(24),
            original_in_nightmode = false }
        shadow.overlap_offset = { 0, top - band }
        table.insert(layers, shadow)
    end
    local cw = W - 2 * S(24)
    -- Wider and taller than the screen so only its rounded top edge shows
    local sheet = FrameContainer:new{
        width = W + 2 * edge,
        height = self.sheet_height + radius,
        background = K.PAPER,
        bordersize = edge,
        color = K.INK,
        radius = radius,
        margin = 0,
        padding = 0,
        padding_left = S(24),
        padding_right = S(24),
        VerticalGroup:new{
            align = "left",
            CenterContainer:new{
                dimen = Geom:new{ w = cw, h = S(21) },
                K.pill(S(40), S(5), K.EDGE, S(3)),
            },
            self:buildContent(cw),
        },
    }
    sheet.overlap_offset = { -edge, top }
    table.insert(layers, sheet)
    return layers
end

--- Title on the left, a round close button on the right.
function K.sheetHeader(page, width, title, on_close, left_widget)
    local h = S(44)
    local button = OverlapGroup:new{
        dimen = Geom:new{ w = S(44), h = h },
        CenterContainer:new{
            dimen = Geom:new{ w = S(44), h = h },
            OverlapGroup:new{
                dimen = Geom:new{ w = S(30), h = S(30) },
                K.pill(S(30), S(30), K.GROUPED, S(15)),
                CenterContainer:new{ dimen = Geom:new{ w = S(30), h = S(30) }, K.icon("kindleui.close", 13, { dim = true }) },
            },
        },
    }
    return OverlapGroup:new{
        dimen = Geom:new{ w = width, h = h },
        LeftContainer:new{
            dimen = Geom:new{ w = width, h = h },
            left_widget or K.text(title, "sans_semibold", 19),
        },
        RightContainer:new{
            dimen = Geom:new{ w = width + S(8), h = h },
            page:hit(button, { on_tap = on_close }),
        },
    }
end

-- Books ----------------------------------------------------------------------

-- En and em dashes are multi-byte, so turn them into hyphens before matching
local function plainDashes(title)
    return ((title or ""):gsub("\u{2013}", "-"):gsub("\u{2014}", "-"))
end

--- Splits "Chapter 1 - Lobsters" into "1", "Lobsters". Titles without a number come back whole.
function K.chapterParts(title)
    title = title or ""
    local number, name = plainDashes(title):match("^[Cc]hapter%s+(%w+)%s*[%-:.]%s*(.+)$")
    if number then return number, name end
    return nil, title
end

--- "Part 1 - Slow Takeoff" -> "Part 1 · Slow Takeoff"
function K.sectionTitle(title)
    return (plainDashes(title):gsub("%s+%-%s+", " · ", 1))
end

--- Pages where the book's top-level sections start, for scrubber marks.
-- Only sections that contain chapters (Parts), when the book has any.
function K.sectionStarts(toc)
    local parents, all = {}, {}
    local top = math.huge
    for _, entry in ipairs(toc) do
        top = math.min(top, entry.depth)
    end
    for i, entry in ipairs(toc) do
        if entry.depth == top then
            table.insert(all, entry.page)
            if toc[i + 1] and toc[i + 1].depth > entry.depth then
                table.insert(parents, entry.page)
            end
        end
    end
    return #parents > 0 and parents or all
end

-- Pieces ---------------------------------------------------------------------

function K.backLink(page, label, callback)
    return page:hit(HorizontalGroup:new{
        align = "center",
        CenterContainer:new{ dimen = Geom:new{ w = S(28), h = S(44) }, K.icon("chevron.left", 20) },
        K.text(label, "sans", 16),
        K.hspan(12),
    }, { on_tap = callback })
end

function K.largeTitle(str)
    return LeftContainer:new{
        dimen = Geom:new{ w = Screen:getWidth() - 2 * S(24), h = S(48) },
        FrameContainer:new{
            bordersize = 0, margin = 0, padding = 0, padding_left = S(4),
            K.text(str, "sans_bold", 34),
        },
    }
end

function K.sectionHeader(str)
    return FrameContainer:new{
        bordersize = 0, margin = 0, padding = 0,
        padding_left = S(16), padding_top = S(18), padding_bottom = S(7),
        K.text(str:upper(), "sans_medium", 12, K.MUTED),
    }
end

--- Small print under a card, on the grouped page's gray.
function K.footnote(str, width)
    return FrameContainer:new{
        bordersize = 0, margin = 0, padding = 0,
        padding_left = S(16), padding_top = S(8),
        TextBoxWidget:new{
            text = str,
            face = K.face("sans", 13),
            fgcolor = K.MUTED,
            bgcolor = K.GROUPED,
            width = width - S(32),
        },
    }
end

--- A rounded card holding rows, with inset separators between them.
function K.card(width, rows, background)
    local group = VerticalGroup:new{ align = "left" }
    for i, row in ipairs(rows) do
        if i > 1 then
            table.insert(group, HorizontalGroup:new{
                K.hspan(16),
                K.rule(width - S(16), math.max(1, S(1)), K.SEPARATOR),
            })
        end
        table.insert(group, row)
    end
    return FrameContainer:new{
        background = background or K.PAPER,
        radius = S(14),
        bordersize = 0,
        margin = 0,
        padding = 0,
        group,
    }
end

local ROW_H = 52

--- A row: label (text or a widget) on the left, any widget on the right.
function K.row(width, label, right, opts)
    opts = opts or {}
    local h = S(ROW_H)
    if type(label) == "string" then
        label = K.text(label, "sans", 16, K.INK, width / 2)
    end
    return OverlapGroup:new{
        dimen = Geom:new{ w = width, h = h },
        LeftContainer:new{
            dimen = Geom:new{ w = width, h = h },
            FrameContainer:new{
                bordersize = 0, margin = 0, padding = 0, padding_left = S(16),
                label or VerticalSpan:new{ width = 0 },
            },
        },
        RightContainer:new{
            dimen = Geom:new{ w = width, h = h },
            FrameContainer:new{
                bordersize = 0, margin = 0, padding = 0, padding_right = S(opts.pad_right or 16),
                right or VerticalSpan:new{ width = 0 },
            },
        },
    }
end

--- Value text and a chevron, for rows that open something.
function K.disclosure(value)
    local group = HorizontalGroup:new{ align = "center" }
    if value then
        table.insert(group, K.text(value, "sans", 15, K.MUTED, S(260)))
        table.insert(group, K.hspan(8))
    end
    table.insert(group, K.icon("chevron.right", 14, { dim = true }))
    return group
end

function K.switch(on)
    local w, h, knob = S(51), S(31), S(27)
    local inset = math.floor((h - knob) / 2)
    local thumb = K.pill(knob, knob, K.PAPER, math.floor(knob / 2), not on and K.EDGE or nil)
    thumb.overlap_offset = { on and (w - knob - inset) or inset, inset }
    return OverlapGroup:new{
        dimen = Geom:new{ w = w, h = h },
        K.pill(w, h, on and K.INK or K.CONTROL, math.floor(h / 2)),
        thumb,
    }
end

--- A slider track with a knob at fraction (0..1).
function K.slider(width, fraction)
    local h, track_h, knob = S(28), S(4), S(24)
    local track_y = math.floor((h - track_h) / 2)
    local travel = width - knob
    -- The track runs between the knob's centers at 0% and 100%, so small fills stay under the knob
    local inset = math.floor(knob / 2)
    local track = K.pill(travel, track_h, K.TRACK, math.floor(track_h / 2))
    track.overlap_offset = { inset, track_y }
    local fill = K.pill(math.max(1, math.floor(travel * fraction)), track_h, K.INK, math.floor(track_h / 2))
    fill.overlap_offset = { inset, track_y }
    local thumb = K.pill(knob, knob, K.PAPER, math.floor(knob / 2), K.EDGE)
    thumb.overlap_offset = { math.floor(travel * fraction), math.floor((h - knob) / 2) }
    return OverlapGroup:new{ dimen = Geom:new{ w = width, h = h }, track, fill, thumb }
end

--- A toggle shaped like a button: filled when on.
function K.chip(width, height, label, on)
    return OverlapGroup:new{
        dimen = Geom:new{ w = width, h = height },
        K.pill(width, height, on and K.INK or K.GROUPED, S(12)),
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = height },
            K.text(label, on and "sans_semibold" or "sans", 15, on and K.PAPER or K.INK),
        },
    }
end

--- Segmented control. items: labels, or { icon = name } tables.
function K.segmented(page, width, items, selected, on_select)
    local pad = S(2)
    local cell_w = math.floor((width - 2 * pad) / #items)
    local h = S(36)
    local row = HorizontalGroup:new{ align = "center" }
    for i, item in ipairs(items) do
        local is_selected = i == selected
        local content
        if type(item) == "table" then
            content = K.icon(item.icon, 20, { dim = not is_selected })
        else
            content = K.text(item, is_selected and "sans_semibold" or "sans", 14, is_selected and K.INK or K.SOFT_INK)
        end
        local cell = CenterContainer:new{
            dimen = Geom:new{ w = cell_w, h = h },
            content,
        }
        if is_selected then
            cell = OverlapGroup:new{
                dimen = Geom:new{ w = cell_w, h = h },
                K.pill(cell_w, h, K.PAPER, S(8), K.EDGE),
                cell,
            }
        end
        table.insert(row, page:hit(cell, { on_tap = function() on_select(i) end }))
    end
    return FrameContainer:new{
        background = K.TRACK,
        radius = S(10),
        bordersize = 0,
        margin = 0,
        padding = pad,
        row,
    }
end

return K
