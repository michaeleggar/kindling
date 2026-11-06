--[[--
Shown while a book opens, in place of KOReader's "Opening file" message:
the cover, title and author, centered on a blank page.

@module kindleui_opening
--]]--

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local ImageWidget = require("ui/widget/imagewidget")
local K = require("kindleui_toolkit")
local TextBoxWidget = require("ui/widget/textboxwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local _ = require("gettext")
local Screen = Device.screen
local S = K.S

local Opening = K.Page:extend{
    file = nil,
}

function Opening:build()
    local W, H = Screen:getWidth(), Screen:getHeight()
    local title, authors, cover_bb
    local ok, BookInfoManager = pcall(require, "bookinfomanager")
    local info = ok and BookInfoManager:getBookInfo(self.file, true)
    if info then
        title = info.title
        authors = info.authors and info.authors:gsub("\n", ", ")
        cover_bb = info.has_cover and info.cover_bb
    end
    title = title or self.file:match("([^/]+)%.[^.]+$") or self.file

    local group = VerticalGroup:new{ align = "center" }
    if cover_bb then
        table.insert(group, FrameContainer:new{
            bordersize = math.max(1, S(1)), color = K.EDGE, margin = 0, padding = 0,
            ImageWidget:new{ image = cover_bb, width = S(200), height = S(300), scale_factor = 0 },
        })
        table.insert(group, K.vspan(28))
    end
    table.insert(group, TextBoxWidget:new{
        text = title,
        face = K.face("serif", 24),
        width = W - S(120),
        alignment = "center",
        line_height = 0.15,
    })
    if authors then
        table.insert(group, K.vspan(8))
        table.insert(group, K.text(authors, "serif_italic", 16, K.SOFT_INK, W - S(120)))
    end
    table.insert(group, K.vspan(30))
    table.insert(group, K.text(_("Opening…"), "sans", 12, K.MUTED))
    return CenterContainer:new{ dimen = Geom:new{ w = W, h = H }, group }
end

-- Not dismissable: it closes itself once the book is ready
function Opening:onTap() return true end

return Opening
