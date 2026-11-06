-- Match KOReader's menus and popups to the home screen: Inter in place of
-- Noto Sans, smaller menu items, thin frames with rounder corners, light
-- dividers, and no icon on info messages.
local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Screen = require("device").screen
local Size = require("ui/size")

local REGULAR = "home/Inter-Regular.ttf"
local BOLD = "home/Inter-SemiBold.ttf"

for name, file in pairs(Font.fontmap) do
    if file == "NotoSans-Regular.ttf" then
        Font.fontmap[name] = REGULAR
    elseif file == "NotoSans-Bold.ttf" then
        Font.fontmap[name] = BOLD
    end
end
Font.bold_font_variant[REGULAR] = BOLD
Font.regular_font_variant[BOLD] = REGULAR

-- Popups, dialogs and the menu's tab bar read these when they're built
Size.border.window = Screen:scaleBySize(1)
Size.radius.window = Screen:scaleBySize(10)
Size.line.thick = Size.line.medium
require("ui/widget/container/framecontainer").bordersize = Size.border.window
-- Info messages: smaller, centered text and no icon
Font.sizemap.infofont = 20
local InfoMessage = require("ui/widget/infomessage")
InfoMessage.show_icon = false
InfoMessage.alignment = "center"

-- Menu items read this size when the menu module loads, so set it first
Font.sizemap.smallinfofont = 19
local TouchMenu = require("ui/widget/touchmenu")
TouchMenu.item_height = Screen:scaleBySize(44)
TouchMenu.bordersize = Size.border.default
TouchMenu.split_color = Blitbuffer.COLOR_GRAY_D
