--[[--
The Aa sheet: text size, typeface, line spacing, margins, justification and
weight for the open book, plus a link to all of KOReader's reading settings.

@module kindleui_textsheet
--]]--

local CenterContainer = require("ui/widget/container/centercontainer")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local K = require("kindleui_toolkit")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local T = require("ffi/util").template
local _ = require("gettext")
local S = K.S

local LINE_SPACINGS = { 100, 115, 130 }
local MARGINS = { 25, 40, 60 }
local JUSTIFY_TWEAK = "text_align_most_justify"
local LEFT_TWEAK = "text_align_most_left"
local FONTS_PER_PAGE = 8

local function nearest(values, value)
    local best, best_i = math.huge, 1
    for i, v in ipairs(values) do
        if math.abs(v - value) < best then
            best, best_i = math.abs(v - value), i
        end
    end
    return best_i
end

local TextSheet = K.Sheet:extend{
    plugin = nil,
    page = "main",
    font_page = 1,
}

-- No shadow on this sheet: the page above it has to stay readable while adjusting it

function TextSheet:build()
    -- Compact for the controls; taller while picking a typeface
    if self.page ~= "fonts" then
        self.sheet_height = S(300)
    else
        self.sheet_height = self.all_fonts and S(610) or S(530)
    end
    return K.Sheet.build(self)
end

-- Good reading fonts, matched to what's installed; the full list is one tap further
local CURATED_FONTS = { "Literata", "Bookerly", "Baskerville", "Caecilia", "Noto Serif", "Atkinson Hyperlegible", "Helvetica" }

--- A readable name for a font: "PMN Caecilia LT" -> "Caecilia"
local function displayName(face)
    for _, wanted in ipairs(CURATED_FONTS) do
        if face ~= wanted and face:find(wanted, 1, true) and wanted ~= "Atkinson Hyperlegible" then
            return wanted
        end
    end
    return face
end

local function curatedFaces(faces)
    local picked = {}
    for _, wanted in ipairs(CURATED_FONTS) do
        local match
        for _, face in ipairs(faces) do
            if face == wanted then
                match = face
                break
            end
        end
        if not match then
            for _, face in ipairs(faces) do
                if face:find(wanted, 1, true) and not face:find("Display") and not face:find("Cond") then
                    match = face
                    break
                end
            end
        end
        if match then
            table.insert(picked, match)
        end
    end
    return picked
end

-- A font's readable name set in that font, falling back to Inter
local function fontLabel(name, px, max_width, label)
    local cre = require("document/credocument"):engineInit()
    local file, index = cre.getFontFaceFilenameAndFaceIndex(name)
    if not file then
        file, index = cre.getFontFaceFilenameAndFaceIndex(name, nil, true)
    end
    if not file then
        return K.text(label or name, "sans", px, K.INK, max_width)
    end
    return TextWidget:new{
        text = label or name,
        face = Font:getFace(file, K.face("sans", px).orig_size, index),
        max_width = max_width,
        padding = 0,
    }
end

function TextSheet:currentFont()
    local ui = self.plugin.ui
    return ui.font.font_face or G_reader_settings:readSetting("cre_font") or ui.document.default_font or ""
end

function TextSheet:send(name, ...)
    self.plugin.ui:handleEvent(Event:new(name, ...))
    self:refresh("ui")
end

function TextSheet:buildContent(cw)
    if self.page == "fonts" then
        return self:buildFonts(cw)
    end
    local ui = self.plugin.ui
    local config = ui.document.configurable
    local gap = S(12)
    local col = math.floor((cw - gap) / 2)

    -- Row 1: smaller / larger as two halves of one control, and the typeface
    local half = math.floor((col - 1) / 2)
    local size_control = FrameContainer:new{
        background = K.GROUPED,
        radius = S(12),
        bordersize = 0, margin = 0, padding = 0,
        HorizontalGroup:new{
            align = "center",
            self:hit(CenterContainer:new{ dimen = Geom:new{ w = half, h = S(52) }, K.text("A", "serif", 15) },
                { on_tap = function() self:send("ChangeSize", -1) end }),
            K.rule(math.max(1, S(1)), S(26), K.CONTROL),
            self:hit(CenterContainer:new{ dimen = Geom:new{ w = half, h = S(52) }, K.text("A", "serif", 25) },
                { on_tap = function() self:send("ChangeSize", 1) end }),
        },
    }
    local typeface = self:hit(OverlapGroup:new{
        dimen = Geom:new{ w = col, h = S(52) },
        K.pill(col, S(52), K.GROUPED, S(12)),
        CenterContainer:new{
            dimen = Geom:new{ w = col, h = S(52) },
            HorizontalGroup:new{
                align = "center",
                fontLabel(self:currentFont(), 17, col - S(60), displayName(self:currentFont())),
                K.hspan(8),
                K.icon("kindleui.chevron", 12, { dim = true }),
            },
        },
    }, {
        on_tap = function()
            self.page = "fonts"
            self:refresh("ui")
        end,
    })

    -- Row 2: line spacing and margins
    local spacing = K.segmented(self, col, {
        { icon = "kindleui.spacing.compact" }, { icon = "kindleui.spacing.normal" }, { icon = "kindleui.spacing.airy" },
    }, nearest(LINE_SPACINGS, config.line_spacing or 100), function(i)
        self:send("SetLineSpace", LINE_SPACINGS[i])
    end)
    local margin = config.h_page_margins and config.h_page_margins[1] or 40
    local margins = K.segmented(self, col, {
        { icon = "kindleui.margins.narrow" }, { icon = "kindleui.margins.medium" }, { icon = "kindleui.margins.wide" },
    }, nearest(MARGINS, margin), function(i)
        self:send("SetPageHorizMargins", { MARGINS[i], MARGINS[i] })
    end)

    -- Row 3: justify and bold, as toggles. Most books justify on their own, so
    -- text counts as justified unless it's being forced left-aligned.
    local styletweak = ui.styletweak
    local justified = not styletweak:isTweakEnabled(LEFT_TWEAK)
    local bold = (config.font_base_weight or 0) > 0
    local justify_chip = self:hit(K.chip(col, S(44), _("Justify"), justified), {
        on_tap = function()
            local on, off = LEFT_TWEAK, JUSTIFY_TWEAK
            if not justified then
                on, off = JUSTIFY_TWEAK, LEFT_TWEAK
            end
            if styletweak:isTweakEnabled(off) then
                styletweak:onToggleStyleTweak(off, nil, true)
            end
            if not styletweak:isTweakEnabled(on) then
                styletweak:onToggleStyleTweak(on, nil, true)
            end
            self:refresh("ui")
        end,
    })
    local bold_chip = self:hit(K.chip(col, S(44), _("Bold"), bold), {
        on_tap = function() self:send("SetFontBaseWeight", bold and 0 or 1) end,
    })

    local more = self:hit(CenterContainer:new{
        dimen = Geom:new{ w = cw, h = S(36) },
        HorizontalGroup:new{
            align = "center",
            K.text(_("Settings"), "sans_medium", 14, K.SOFT_INK),
            K.hspan(6),
            K.icon("kindleui.chevron", 12, { dim = true }),
        },
    }, {
        on_tap = function()
            self:close()
            self.plugin:showSettings()
        end,
    })

    return VerticalGroup:new{
        align = "left",
        K.sheetHeader(self, cw, _("Text & Layout"), function() self:close() end),
        K.vspan(10),
        HorizontalGroup:new{ align = "center", size_control, HorizontalSpan:new{ width = gap }, typeface },
        K.vspan(12),
        HorizontalGroup:new{ align = "center", spacing, HorizontalSpan:new{ width = gap }, margins },
        K.vspan(12),
        HorizontalGroup:new{ align = "center", justify_chip, HorizontalSpan:new{ width = gap }, bold_chip },
        K.vspan(6),
        more,
    }
end

-- Typeface list, each name set in its own font
-- Typeface list, each name set in its own font: a short list of good reading
-- fonts, with every installed font one row further
function TextSheet:buildFonts(cw)
    local ui = self.plugin.ui
    local cre = require("document/credocument"):engineInit()
    local all = ui.font:sortFaceList(cre.getFontFaces())
    local faces = self.all_fonts and all or curatedFaces(all)
    local per_page = self.all_fonts and FONTS_PER_PAGE or #faces + 1
    local pages = math.max(1, math.ceil(#faces / per_page))
    self.font_pages = pages
    self.font_page = math.min(self.font_page, pages)

    local back = self:hit(HorizontalGroup:new{
        align = "center",
        K.icon("kindleui.back", 20),
        K.hspan(4),
        K.text(self.all_fonts and _("All Fonts") or _("Typeface"), "sans_semibold", 19),
    }, {
        on_tap = function()
            if self.all_fonts then
                self.all_fonts = false
            else
                self.page = "main"
            end
            self.font_page = 1
            self:refresh("ui")
        end,
    })

    local rows = {}
    local first = (self.font_page - 1) * per_page
    for i = first + 1, math.min(first + per_page, #faces) do
        local name = faces[i]
        local label = fontLabel(name, 17, cw - S(80), not self.all_fonts and displayName(name) or nil)
        local selected = name == self:currentFont()
        table.insert(rows, self:hit(K.row(cw, label, selected and K.icon("check", 18) or nil), {
            on_tap = function()
                self.plugin.ui:handleEvent(Event:new("SetFont", name))
                self.page = "main"
                self.all_fonts = false
                self:refresh("ui")
            end,
        }))
    end
    if not self.all_fonts then
        table.insert(rows, self:hit(K.row(cw, _("All Fonts"), K.disclosure(tostring(#all))), {
            on_tap = function()
                self.all_fonts = true
                self.font_page = 1
                self:refresh("ui")
            end,
        }))
    end

    if pages <= 1 then
        return VerticalGroup:new{
            align = "left",
            K.sheetHeader(self, cw, nil, function() self:close() end, back),
            K.vspan(10),
            K.card(cw, rows, K.GROUPED),
        }
    end

    local pager = HorizontalGroup:new{
        align = "center",
        self:hit(CenterContainer:new{ dimen = Geom:new{ w = S(44), h = S(40) },
            K.icon("chevron.left", 16, { dim = self.font_page == 1 }) },
            { on_tap = function() self:onSheetSwipe("east") end }),
        K.text(T(_("%1 of %2"), self.font_page, pages), "sans", 12, K.MUTED),
        self:hit(CenterContainer:new{ dimen = Geom:new{ w = S(44), h = S(40) },
            K.icon("chevron.right", 16, { dim = self.font_page == pages }) },
            { on_tap = function() self:onSheetSwipe("west") end }),
    }

    return VerticalGroup:new{
        align = "left",
        K.sheetHeader(self, cw, nil, function() self:close() end, back),
        K.vspan(10),
        K.card(cw, rows, K.GROUPED),
        CenterContainer:new{ dimen = Geom:new{ w = cw, h = S(44) }, pager },
    }
end

function TextSheet:onSheetSwipe(direction)
    if self.page ~= "fonts" then return end
    local step = direction == "west" and 1 or -1
    local target = self.font_page + step
    if target >= 1 and target <= (self.font_pages or 1) then
        self.font_page = target
        self:refresh("ui")
    end
end

return TextSheet
