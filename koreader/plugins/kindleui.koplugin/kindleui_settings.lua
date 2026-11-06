--[[--
Settings: the handful of things worth changing, as grouped lists, with one
row leading to all of KOReader's settings. Includes the Sleep Screen page.

@module kindleui_settings
--]]--

local Device = require("device")
local Event = require("ui/event")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local ImageWidget = require("ui/widget/imagewidget")
local K = require("kindleui_toolkit")
local LeftContainer = require("ui/widget/container/leftcontainer")
local NetworkMgr = require("ui/network/manager")
local OverlapGroup = require("ui/widget/overlapgroup")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local lfs = require("libs/libkoreader-lfs")
local T = require("ffi/util").template
local _ = require("gettext")
local Screen = Device.screen
local S = K.S

local SCREENSAVERS = "/mnt/us/screensavers"
local SCREENSAVERS_HIDDEN = "/mnt/us/screensavers-hidden"
local SCREENSAVER_THUMBS = "/mnt/us/screensavers-thumbs"
local SYNC_STATUS = "/mnt/us/rclone/status"
local LAST_SYNC = "/mnt/us/rclone/last_sync"

local SLEEP_TYPES = { "random_image", "cover", "disable" }
local SLEEP_LABELS = { _("Abstract"), _("Book Cover"), _("Off") }

local function readFirstLine(path)
    local f = io.open(path, "r")
    if not f then return end
    local line = f:read("*l")
    f:close()
    return line
end

local function timeAgo(seconds)
    if seconds < 60 then return _("just now") end
    if seconds < 3600 then return T(_("%1 min ago"), math.floor(seconds / 60)) end
    if seconds < 86400 then return T(_("%1 h ago"), math.floor(seconds / 3600)) end
    return T(_("%1 days ago"), math.floor(seconds / 86400))
end

local function wifiName()
    if not NetworkMgr:isWifiOn() then return _("Off") end
    local ok, network = pcall(NetworkMgr.getCurrentNetwork, NetworkMgr)
    return ok and network and network.ssid or _("Not connected")
end

local function isCover(name)
    return name:match("%-cover%-") ~= nil
end

-- Sleep screen images, visible ones first, in name order
local function screensaverImages()
    local images = {}
    for _, dir in ipairs({ SCREENSAVERS, SCREENSAVERS_HIDDEN }) do
        local ok, iter, dir_obj = pcall(lfs.dir, dir)
        if ok then
            for name in iter, dir_obj do
                if name:match("%.png$") or name:match("%.jpe?g$") then
                    table.insert(images, { name = name, active = dir == SCREENSAVERS })
                end
            end
        end
    end
    table.sort(images, function(a, b) return a.name < b.name end)
    return images
end

local function setImageActive(name, active)
    lfs.mkdir(SCREENSAVERS_HIDDEN)
    local from = (active and SCREENSAVERS_HIDDEN or SCREENSAVERS) .. "/" .. name
    local to = (active and SCREENSAVERS or SCREENSAVERS_HIDDEN) .. "/" .. name
    os.rename(from, to)
end

local SettingsScreen = K.Page:extend{
    background = K.GROUPED,
    plugin = nil,
    page = "main",
}

function SettingsScreen:init()
    self.on_back = function() self:back() end
    K.Page.init(self)
end

function SettingsScreen:back()
    if self.page == "main" then
        self:close()
    else
        self.page = "main"
        self:refresh("flashui")
    end
end

function SettingsScreen:build()
    local cw = Screen:getWidth() - 2 * S(24)
    local content = self.page == "sleep" and self:buildSleep(cw) or self:buildMain(cw)
    return FrameContainer:new{
        bordersize = 0, margin = 0, padding = 0,
        padding_left = S(24), padding_right = S(24),
        content,
    }
end

-- Rows -----------------------------------------------------------------------

function SettingsScreen:switchRow(cw, label, on, toggle)
    return self:hit(K.row(cw, label, K.switch(on), { pad_right = 12 }), {
        on_tap = function()
            toggle()
            self:refresh("ui")
        end,
    })
end

function SettingsScreen:linkRow(cw, label, value, callback)
    return self:hit(K.row(cw, label, K.disclosure(value)), { on_tap = callback })
end

function SettingsScreen:sliderRow(cw, label, fraction, on_change)
    local label_w = S(110)
    local slider_w = cw - S(16) - label_w - S(16)
    return HorizontalGroup:new{
        align = "center",
        K.hspan(16),
        LeftContainer:new{ dimen = Geom:new{ w = label_w, h = S(52) }, K.text(label, "sans", 16) },
        self:hit(K.slider(slider_w, fraction), {
            on_drag = function(f, final)
                if on_change(f) or final then
                    -- Fast refresh while dragging, a clean one on release
                    self:refresh(final and "ui" or "fast")
                end
            end,
        }),
    }
end

-- Main page ------------------------------------------------------------------

function SettingsScreen:buildMain(cw)
    local ui = self.plugin.ui
    local powerd = Device:getPowerDevice()
    local content = VerticalGroup:new{
        align = "left",
        K.vspan(6),
        K.backLink(self, ui.document and _("Book") or _("Library"), function() self:close() end),
        K.vspan(2),
        K.largeTitle(_("Settings")),
    }
    local function add(widget) table.insert(content, widget) end

    if Device:hasFrontlight() then
        local light_rows = {
            self:sliderRow(cw, _("Brightness"),
                (powerd:frontlightIntensity() - powerd.fl_min) / (powerd.fl_max - powerd.fl_min),
                function(f)
                    local level = math.floor(powerd.fl_min + f * (powerd.fl_max - powerd.fl_min) + 0.5)
                    if level == powerd:frontlightIntensity() then return false end
                    powerd:setIntensity(level)
                    return true
                end),
        }
        if Device:hasNaturalLight() then
            table.insert(light_rows, self:sliderRow(cw, _("Warmth"), powerd:frontlightWarmth() / 100, function(f)
                local warmth = math.floor(f * 100 + 0.5)
                if powerd:toNativeWarmth(warmth) == powerd:toNativeWarmth(powerd:frontlightWarmth()) then return false end
                powerd:setWarmth(warmth)
                return true
            end))
        end
        table.insert(light_rows, self:darkModeRow(cw))
        add(K.sectionHeader(_("Light")))
        add(K.card(cw, light_rows))
    else
        add(K.sectionHeader(_("Display")))
        add(K.card(cw, { self:darkModeRow(cw) }))
    end

    add(K.sectionHeader(_("Library")))
    add(K.card(cw, {
        self:linkRow(cw, _("Dropbox"), self:syncStatus(), function()
            if ui.dropboxsync then ui.dropboxsync:syncNow() end
        end),
        self:switchRow(cw, _("Sync on Wi-Fi"), G_reader_settings:nilOrTrue("dropboxsync_auto"), function()
            G_reader_settings:flipNilOrTrue("dropboxsync_auto")
        end),
    }))

    add(K.sectionHeader(_("Reading")))
    add(K.card(cw, {
        self:switchRow(cw, _("Tap to Turn Pages"), not G_reader_settings:isTrue("page_turns_disable_tap"), function()
            G_reader_settings:flipNilOrFalse("page_turns_disable_tap")
        end),
        self:switchRow(cw, _("Swipe to Turn Pages"), not G_reader_settings:isTrue("page_turns_disable_swipe"), function()
            G_reader_settings:flipNilOrFalse("page_turns_disable_swipe")
        end),
    }))

    local sleep_type = G_reader_settings:readSetting("screensaver_type") or "disable"
    local sleep_label = SLEEP_LABELS[#SLEEP_LABELS]
    for i, value in ipairs(SLEEP_TYPES) do
        if value == sleep_type then sleep_label = SLEEP_LABELS[i] end
    end
    add(K.sectionHeader(_("Device")))
    add(K.card(cw, {
        self:linkRow(cw, _("Wi-Fi"), wifiName(), function()
            local done = function() self:refresh("ui") end
            if NetworkMgr:isWifiOn() then
                NetworkMgr:reconnectOrShowNetworkMenu(done, true)
            else
                NetworkMgr:toggleWifiOn(done, nil, true)
            end
        end),
        self:linkRow(cw, _("Sleep Screen"), sleep_label, function()
            self.page = "sleep"
            self:refresh("flashui")
        end),
    }))

    add(K.vspan(26))
    add(K.card(cw, {
        self:linkRow(cw, _("All KOReader Settings"), nil, function()
            self:close()
            ui.menu:onShowMenu()
        end),
    }))
    return content
end

-- KOReader's night mode: the whole screen is inverted, covers and other
-- pictures are kept as they are, and the choice is remembered across restarts
function SettingsScreen:darkModeRow(cw)
    return self:switchRow(cw, _("Dark Mode"), G_reader_settings:isTrue("night_mode"), function()
        self.plugin.ui:handleEvent(Event:new("ToggleNightMode"))
    end)
end

function SettingsScreen:syncStatus()
    local dropboxsync = self.plugin.ui.dropboxsync
    if dropboxsync and dropboxsync:isRunning() then
        return _("Syncing…")
    end
    if readFirstLine(SYNC_STATUS) == "error" then
        return _("Sync failed")
    end
    local last = tonumber(readFirstLine(LAST_SYNC))
    return last and T(_("Synced %1"), timeAgo(os.time() - last)) or _("Sync now")
end

-- Sleep screen page ----------------------------------------------------------

function SettingsScreen:buildSleep(cw)
    local sleep_type = G_reader_settings:readSetting("screensaver_type") or "disable"
    local selected = #SLEEP_TYPES
    for i, value in ipairs(SLEEP_TYPES) do
        if value == sleep_type then selected = i end
    end

    local content = VerticalGroup:new{
        align = "left",
        K.vspan(6),
        K.backLink(self, _("Settings"), function() self:back() end),
        K.vspan(2),
        K.largeTitle(_("Sleep Screen")),
        K.vspan(14),
        K.segmented(self, cw, SLEEP_LABELS, selected, function(i)
            G_reader_settings:saveSetting("screensaver_type", SLEEP_TYPES[i])
            self:refresh("ui")
        end),
        K.vspan(16),
    }
    local function add(widget) table.insert(content, widget) end

    local images = screensaverImages()
    local cols, gap, pad = 6, S(10), S(14)
    local thumb_w = math.floor((cw - 2 * pad - (cols - 1) * gap) / cols)
    local thumb_h = math.floor(thumb_w * 4 / 3)
    local grid = VerticalGroup:new{ align = "left" }
    local row
    for i, image in ipairs(images) do
        if (i - 1) % cols == 0 then
            if row then
                table.insert(grid, K.vspan(10))
            end
            row = HorizontalGroup:new{ align = "top" }
            table.insert(grid, row)
        else
            table.insert(row, K.hspan(10))
        end
        table.insert(row, self:hit(self:thumbnail(image, thumb_w, thumb_h), {
            on_tap = function()
                setImageActive(image.name, not image.active)
                self:refresh("ui")
            end,
        }))
    end
    add(FrameContainer:new{
        background = K.PAPER,
        radius = S(14),
        bordersize = 0,
        margin = 0,
        padding = pad,
        width = cw,
        grid,
    })
    add(K.footnote(_("A different one each time your Kindle sleeps. Tap a piece to leave it out."), cw))

    local covers_on = false
    for _, image in ipairs(images) do
        if isCover(image.name) and image.active then covers_on = true end
    end
    add(K.vspan(22))
    add(K.card(cw, {
        self:switchRow(cw, _("Include Halftone Covers"), covers_on, function()
            for _, image in ipairs(images) do
                if isCover(image.name) and image.active == covers_on then
                    setImageActive(image.name, not covers_on)
                end
            end
        end),
    }))
    return content
end

function SettingsScreen:thumbnail(image, w, h)
    local thumb = SCREENSAVER_THUMBS .. "/" .. image.name
    if lfs.attributes(thumb, "mode") ~= "file" then
        thumb = (image.active and SCREENSAVERS or SCREENSAVERS_HIDDEN) .. "/" .. image.name
    end
    local edge = math.max(1, S(1))
    local picture = FrameContainer:new{
        bordersize = edge,
        color = K.EDGE,
        margin = 0,
        padding = 0,
        ImageWidget:new{
            file = thumb,
            width = w - 2 * edge,
            height = h - 2 * edge,
            scale_factor = 0,
            dim = not image.active,
        },
    }
    local size = S(20)
    local badge
    if image.active then
        badge = OverlapGroup:new{
            dimen = Geom:new{ w = size, h = size },
            K.pill(size, size, K.INK, math.floor(size / 2), K.PAPER),
            FrameContainer:new{
                bordersize = 0, margin = 0, padding = S(4),
                K.icon("check", 12, { invert = true }),
            },
        }
    else
        badge = K.pill(size, size, K.PAPER, math.floor(size / 2), K.EDGE)
    end
    badge.overlap_offset = { w - size - S(5), h - size - S(5) }
    return OverlapGroup:new{ dimen = Geom:new{ w = w, h = h }, picture, badge }
end

-- Events ---------------------------------------------------------------------

function SettingsScreen:onDropboxSyncStateChanged()
    if self.page == "main" then
        self:refresh("ui")
    end
end

function SettingsScreen:onNetworkConnected()
    if self.page == "main" then
        self:refresh("ui")
    end
end

function SettingsScreen:onNetworkDisconnected()
    self:onNetworkConnected()
end

return SettingsScreen
