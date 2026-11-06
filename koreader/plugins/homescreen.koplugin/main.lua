--[[--
A home screen for the library synced from Dropbox.

Shows the book being read, then the library by section: covers for books
and comics, a title list for papers. Opens over the file browser on startup
and whenever a book is closed.

@module koplugin.HomeScreen
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Dispatcher = require("dispatcher")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
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
local ReadHistory = require("readhistory")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local T = require("ffi/util").template
local _ = require("gettext")
local Screen = Device.screen

local LIBRARY = "/mnt/us/library"
local SYNC_STATUS = "/mnt/us/rclone/status"
local LAST_SYNC = "/mnt/us/rclone/last_sync"

local SECTIONS = {
    { label = _("Books"),  dir = "Books",          style = "grid" },
    { label = _("Comics"), dir = "Comics",         style = "grid" },
    { label = _("Papers"), dir = "Art & Research", style = "list" },
    { label = _("Saved"),  dir = "Bookmarks",      style = "list" },
}
local PER_PAGE = 8
local GRID_COLS = 4
local NEW_DAYS = 14
-- When a title exists in several formats, show the first of these
local FORMAT_RANK = { epub = 1, azw3 = 2, mobi = 3, fb2 = 4, pdf = 5, cbz = 6, djvu = 7 }

local INK = Blitbuffer.COLOR_BLACK
local PAPER = Blitbuffer.COLOR_WHITE
local SOFT_INK = Blitbuffer.Color8(0x33)
local MUTED = Blitbuffer.Color8(0x4A)
local SUBTLE = Blitbuffer.Color8(0x6B)
local DISABLED = Blitbuffer.Color8(0xB0)
local COVER_EDGE = Blitbuffer.Color8(0xCF)
local RULE = Blitbuffer.Color8(0xDE)
local RULE_LIGHT = Blitbuffer.Color8(0xEC)

local FONTS = {
    serif = "home/Literata-Regular.ttf",
    serif_italic = "home/Literata-Italic.ttf",
    sans = "home/Inter-Regular.ttf",
    sans_medium = "home/Inter-Medium.ttf",
    sans_semibold = "home/Inter-SemiBold.ttf",
}

-- Sizes are given in mockup pixels (a 632 px wide screen) and scaled to the device
local function S(px)
    return math.floor(px * Screen:getWidth() / 632 + 0.5)
end

local function face(name, px)
    -- Font:getFace applies Screen:scaleBySize, so divide that back out
    local size_scale = math.min(Screen:getWidth(), Screen:getHeight()) / 600
    return Font:getFace(FONTS[name], S(px) / size_scale)
end

local function text(str, font, px, color, max_width)
    return TextWidget:new{
        text = str,
        face = face(font, px),
        fgcolor = color or INK,
        max_width = max_width,
        padding = 0,
    }
end

local function span_v(px) return VerticalSpan:new{ width = S(px) } end
local function span_h(px) return HorizontalSpan:new{ width = S(px) } end

local function rule(w, h, color)
    return LineWidget:new{ dimen = Geom:new{ w = w, h = h }, background = color }
end

local function bookInfoManager()
    local ok, BookInfoManager = pcall(require, "bookinfomanager")
    return ok and BookInfoManager or nil
end

-- Library -------------------------------------------------------------------

local function splitName(filename)
    local stem, ext = filename:match("^(.*)%.([^.]+)$")
    return stem or filename, ext and ext:lower() or ""
end

local function scan(dir, items)
    local ok, iter, dir_obj = pcall(lfs.dir, dir)
    if not ok then return items end
    for name in iter, dir_obj do
        if name:sub(1, 1) ~= "." and not name:match("%.sdr$") then
            local path = dir .. "/" .. name
            local attr = lfs.attributes(path)
            if attr and attr.mode == "directory" then
                scan(path, items)
            elseif attr and attr.mode == "file" and DocumentRegistry:hasProvider(path) then
                local stem, ext = splitName(name)
                table.insert(items, { path = path, dir = dir, stem = stem, ext = ext, mtime = attr.modification })
            end
        end
    end
    return items
end

-- One item per title, newest first
local function loadSection(section)
    local best = {}
    for _, item in ipairs(scan(LIBRARY .. "/" .. section.dir, {})) do
        local key = item.dir .. "/" .. item.stem
        local current = best[key]
        if not current or (FORMAT_RANK[item.ext] or 99) < (FORMAT_RANK[current.ext] or 99) then
            best[key] = item
        end
    end
    local new_since = os.time() - NEW_DAYS * 86400
    local items = {}
    for _, item in pairs(best) do
        local folder = item.dir:match("[^/]+$")
        local author, title = item.stem:match("^(.-) %- (.+)$")
        if section.style == "list" and author then
            -- Papers are named "Author - Title"
            item.author, item.title = author, title
        else
            -- Books live in author folders
            item.title = item.stem
            item.author = folder ~= section.dir and folder or nil
        end
        item.is_new = item.mtime > new_since and not DocSettings:hasSidecarFile(item.path)
        table.insert(items, item)
    end
    table.sort(items, function(a, b)
        if a.mtime ~= b.mtime then return a.mtime > b.mtime end
        return a.title < b.title
    end)
    return items
end

local function currentBook()
    ReadHistory:reload()
    for _, entry in ipairs(ReadHistory.hist) do
        if lfs.attributes(entry.file, "mode") == "file" then
            local stem = splitName(entry.file:match("[^/]+$"))
            return { path = entry.file, title = stem, author = entry.file:match("([^/]+)/[^/]+$") }
        end
    end
end

local function readFirstLine(path)
    local f = io.open(path, "r")
    if not f then return end
    local line = f:read("*l")
    f:close()
    return line
end

local function clock()
    if G_reader_settings:isTrue("twelve_hour_clock") then
        return (os.date("%I:%M %p"):gsub("^0", ""))
    end
    return os.date("%H:%M")
end

local function battery()
    local ok, capacity = pcall(function() return Device:getPowerDevice():getCapacity() end)
    return ok and capacity or nil
end

local function timeAgo(seconds)
    if seconds < 60 then return _("just now") end
    if seconds < 3600 then return T(_("%1 min ago"), math.floor(seconds / 60)) end
    if seconds < 86400 then return T(_("%1 h ago"), math.floor(seconds / 3600)) end
    if seconds < 172800 then return _("yesterday") end
    return T(_("%1 days ago"), math.floor(seconds / 86400))
end

-- Hit records where its child was painted, so taps can be matched to it
local Hit = WidgetContainer:extend{
    callback = nil,
}

function Hit:paintTo(bb, x, y)
    local size = self[1]:getSize()
    self.dimen = Geom:new{ x = x, y = y, w = size.w, h = size.h }
    self[1]:paintTo(bb, x, y)
end

-- Home widget ---------------------------------------------------------------

-- Covers already sent for extraction this session, so failures aren't retried
local attempted = {}

local Home = InputContainer:extend{
    covers_fullscreen = true,
    plugin = nil,
    section = 1,
    page = 1,
}

function Home:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = self.dimen } },
        Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } },
        Hold = { GestureRange:new{ ges = "hold", range = self.dimen } },
    }
    self.cover_specs = { max_cover_w = S(130), max_cover_h = S(195) }
    self:loadData()
    self[1] = self:build()
    self.tick = function() self:updateHeader() end
    UIManager:scheduleIn(61 - os.date("*t").sec, self.tick)
    UIManager:nextTick(function() self:extractMissing() end)
end

function Home:loadData()
    self.data = {}
    for i, section in ipairs(SECTIONS) do
        self.data[i] = loadSection(section)
    end
    self.page = math.min(self.page, self:pageCount())
end

function Home:pageCount()
    return math.max(1, math.ceil(#self.data[self.section] / PER_PAGE))
end

function Home:hit(widget, callback)
    local hit = Hit:new{ widget, callback = callback }
    table.insert(self.hits, hit)
    return hit
end

function Home:build()
    local W, H = Screen:getWidth(), Screen:getHeight()
    local pad_x = S(36)
    local cw = W - 2 * pad_x
    self.hits = {}
    self.to_extract = {}

    self.header_hit = self:hit(self:header(cw), function() self:showMenu() end)
    local content = VerticalGroup:new{
        align = "left",
        span_v(14),
        self.header_hit,
        span_v(22),
        self:hero(cw),
        span_v(34),
        self:tabs(cw),
        self:body(cw),
        self:pager(cw),
    }
    return FrameContainer:new{
        width = W,
        height = H,
        bordersize = 0,
        padding = 0,
        margin = 0,
        background = PAPER,
        OverlapGroup:new{
            dimen = Geom:new{ w = W, h = H },
            FrameContainer:new{
                bordersize = 0,
                padding = 0,
                padding_left = pad_x,
                padding_right = pad_x,
                content,
            },
            BottomContainer:new{
                dimen = Geom:new{ w = W, h = H },
                self:footer(cw, pad_x),
            },
        },
    }
end

local function batteryIcon(level)
    local edge = math.max(1, S(1))
    local inner_w, inner_h = S(14), S(5)
    local fill_w = math.max(1, math.floor(inner_w * level / 100 + 0.5))
    return HorizontalGroup:new{
        align = "center",
        FrameContainer:new{
            bordersize = edge,
            color = MUTED,
            margin = 0,
            padding = S(1.5),
            LeftContainer:new{
                dimen = Geom:new{ w = inner_w, h = inner_h },
                rule(fill_w, inner_h, MUTED),
            },
        },
        rule(edge + 1, S(4), MUTED),
    }
end

function Home:header(cw)
    local h = S(36)
    local date = os.date("%A, %d %B"):gsub(" 0", " ")
    local status = HorizontalGroup:new{
        align = "center",
        text(clock(), "sans", 12, MUTED),
    }
    local level = battery()
    if level then
        table.insert(status, span_h(8))
        table.insert(status, text("·", "sans", 12, DISABLED))
        table.insert(status, span_h(8))
        table.insert(status, batteryIcon(level))
        table.insert(status, span_h(5))
        table.insert(status, text(level .. "%", "sans", 12, MUTED))
    end
    return OverlapGroup:new{
        dimen = Geom:new{ w = cw, h = h },
        LeftContainer:new{
            dimen = Geom:new{ w = cw, h = h },
            text(date, "serif_italic", 15),
        },
        RightContainer:new{
            dimen = Geom:new{ w = cw, h = h },
            status,
        },
    }
end

function Home:updateHeader()
    if self.closed then return end
    local cw = Screen:getWidth() - 2 * S(36)
    self.header_hit[1] = self:header(cw)
    UIManager:setDirty(self, function() return "ui", self.header_hit.dimen end)
    UIManager:scheduleIn(60, self.tick)
end

-- Returns a widget sized w×h with the cover centered, plus the cover's own size
function Home:cover(item, w, h)
    local BookInfoManager = bookInfoManager()
    local info = BookInfoManager and BookInfoManager:getBookInfo(item.path, true)
    if BookInfoManager and not attempted[item.path] then
        local missing = not info or info.cover_fetched ~= "Y"
            or (info.has_cover and BookInfoManager.isCachedCoverInvalid(info, self.cover_specs))
        if missing then
            table.insert(self.to_extract, item.path)
        end
    end

    local edge = S(1)
    local inner
    if info and info.has_cover and info.cover_bb and not info.ignore_cover then
        local image = ImageWidget:new{
            image = info.cover_bb,
            width = w - 2 * edge,
            height = h - 2 * edge,
            scale_factor = 0,
        }
        image:_render()
        inner = FrameContainer:new{
            bordersize = edge,
            color = COVER_EDGE,
            padding = 0,
            margin = 0,
            image,
        }
    else
        -- No cover: the title, set in the frame
        inner = FrameContainer:new{
            width = w,
            height = h,
            bordersize = edge,
            color = COVER_EDGE,
            padding = 0,
            margin = 0,
            CenterContainer:new{
                dimen = Geom:new{ w = w - 2 * edge, h = h - 2 * edge },
                TextBoxWidget:new{
                    text = item.title,
                    face = face("serif", 13),
                    width = w - S(20),
                    alignment = "center",
                    line_height = 0.2,
                },
            },
        }
    end
    local size = inner:getSize()
    return CenterContainer:new{ dimen = Geom:new{ w = w, h = h }, inner }, size.w, size.h
end

function Home:hero(cw)
    local cover_w, cover_h = S(120), S(180)
    local item = currentBook()
    local kicker = _("CONTINUE READING")
    if not item then
        item = self.data[1][1]
        kicker = _("NEW IN YOUR LIBRARY")
        if not item then
            return VerticalSpan:new{ width = cover_h }
        end
    end

    local title, author = item.title, item.author
    local BookInfoManager = bookInfoManager()
    local info = BookInfoManager and BookInfoManager:getBookInfo(item.path, false)
    if info and info.has_meta and not info.ignore_meta then
        title = info.title or title
        author = info.authors and info.authors:gsub("\n", ", ") or author
    end

    local cover = self:cover(item, cover_w, cover_h)
    local text_w = cw - cover_w - S(26)
    local column = VerticalGroup:new{
        align = "left",
        text(kicker, "sans_semibold", 11, MUTED),
        span_v(10),
        TextBoxWidget:new{
            text = title,
            face = face("serif", 32),
            width = text_w,
            line_height = 0.12,
            height = math.ceil(S(32) * 1.12 * 2),
            height_adjust = true,
            height_overflow_show_ellipsis = true,
        },
    }
    if author then
        table.insert(column, span_v(8))
        table.insert(column, text(author, "serif_italic", 16, SOFT_INK, text_w))
    end

    if kicker == _("CONTINUE READING") then
        local percent, pages
        if DocSettings:hasSidecarFile(item.path) then
            local doc_settings = DocSettings:open(item.path)
            percent = doc_settings:readSetting("percent_finished")
            pages = doc_settings:readSetting("doc_pages")
        end
        table.insert(column, span_v(22))
        if percent then
            local bar_h = S(3)
            table.insert(column, OverlapGroup:new{
                dimen = Geom:new{ w = text_w, h = bar_h },
                rule(text_w, bar_h, RULE),
                rule(math.max(1, math.floor(text_w * percent)), bar_h, INK),
            })
            table.insert(column, span_v(8))
            local status = T(_("%1%"), math.floor(percent * 100 + 0.5))
            if pages then
                status = T(_("%1 · page %2 of %3"), status, math.max(1, math.floor(percent * pages + 0.5)), pages)
            end
            table.insert(column, text(status, "sans", 12, MUTED, text_w))
        else
            table.insert(column, text(_("Not started"), "sans", 12, MUTED, text_w))
        end
    end

    -- Sit the text on the cover's baseline
    local column_h = column:getSize().h
    column.overlap_offset = { 0, math.max(0, cover_h - column_h - S(4)) }
    return self:hit(HorizontalGroup:new{
        align = "top",
        cover,
        span_h(26),
        OverlapGroup:new{ dimen = Geom:new{ w = text_w, h = cover_h }, column },
    }, function() self:openFile(item.path) end)
end

function Home:tabs(cw)
    local tab_h = S(44)
    local row = HorizontalGroup:new{ align = "top" }
    for i, section in ipairs(SECTIONS) do
        local active = i == self.section
        local label = HorizontalGroup:new{
            align = "center",
            text(section.label, active and "sans_semibold" or "sans", 14, active and INK or MUTED),
            span_h(6),
            text(tostring(#self.data[i]), "sans", 14, active and MUTED or SUBTLE),
        }
        local label_w = label:getSize().w
        local tab = VerticalGroup:new{
            align = "left",
            CenterContainer:new{ dimen = Geom:new{ w = label_w, h = tab_h - S(2) }, label },
            rule(label_w, S(2), active and INK or PAPER),
        }
        if i > 1 then
            table.insert(row, span_h(26))
        end
        table.insert(row, self:hit(tab, function() self:selectSection(i) end))
    end
    return VerticalGroup:new{
        align = "left",
        row,
        rule(cw, S(1), RULE),
    }
end

-- Covers are 2:3, as large as fits between the tabs and the pager
function Home:gridMetrics(cw)
    local gap_y = S(18)
    -- header, hero and tabs above; body padding, pager and footer below
    local fixed = S(14 + 36 + 22 + 180 + 34 + 45) + S(20) + S(54) + S(63) + S(8)
    local cell_h = math.floor((Screen:getHeight() - fixed - gap_y) / 2)
    local cell_w = math.floor((cw - (GRID_COLS - 1) * S(18)) / GRID_COLS)
    if cell_h < math.floor(cell_w * 1.5) then
        cell_w = math.floor(cell_h / 1.5)
    else
        cell_h = math.floor(cell_w * 1.5)
    end
    local gap_x = math.floor((cw - GRID_COLS * cell_w) / (GRID_COLS - 1))
    return cell_w, cell_h, gap_x, gap_y
end

function Home:body(cw)
    local cell_w, cell_h, gap_x, gap = self:gridMetrics(cw)
    local body_h = S(20) + 2 * cell_h + gap
    local items = {}
    local first = (self.page - 1) * PER_PAGE
    for i = 1, PER_PAGE do
        items[i] = self.data[self.section][first + i]
    end

    local content
    local section = SECTIONS[self.section]
    if #items == 0 then
        content = CenterContainer:new{
            dimen = Geom:new{ w = cw, h = body_h },
            TextBoxWidget:new{
                text = T(_("Nothing here yet.\nAdd files to Dropbox › Library › %1."), section.dir),
                face = face("serif_italic", 16),
                fgcolor = MUTED,
                width = cw - S(80),
                alignment = "center",
            },
        }
    elseif section.style == "grid" then
        content = VerticalGroup:new{ align = "left", span_v(20) }
        for r = 0, PER_PAGE / GRID_COLS - 1 do
            local row = HorizontalGroup:new{ align = "top" }
            for c = 1, GRID_COLS do
                local item = items[r * GRID_COLS + c]
                if c > 1 then
                    table.insert(row, HorizontalSpan:new{ width = gap_x })
                end
                if item then
                    table.insert(row, self:hit(self:gridCell(item, cell_w, cell_h), function() self:openFile(item.path) end))
                else
                    table.insert(row, HorizontalSpan:new{ width = cell_w })
                end
            end
            if r > 0 then
                table.insert(content, VerticalSpan:new{ width = gap })
            end
            table.insert(content, row)
        end
    else
        local row_h = math.floor((body_h - S(6)) / PER_PAGE)
        content = VerticalGroup:new{ align = "left", span_v(6) }
        for _, item in ipairs(items) do
            local lines = VerticalGroup:new{
                align = "left",
                text(item.title, "serif", 16, INK, cw),
            }
            if item.author then
                table.insert(lines, span_v(3))
                table.insert(lines, text(item.author:upper(), "sans", 11, MUTED, cw))
            end
            table.insert(content, self:hit(VerticalGroup:new{
                align = "left",
                LeftContainer:new{ dimen = Geom:new{ w = cw, h = row_h - S(1) }, lines },
                rule(cw, S(1), RULE_LIGHT),
            }, function() self:openFile(item.path) end))
        end
    end
    return OverlapGroup:new{ dimen = Geom:new{ w = cw, h = body_h }, content }
end

function Home:gridCell(item, w, h)
    local cover, cover_w, cover_h = self:cover(item, w, h)
    if not item.is_new then
        return cover
    end
    local tag = FrameContainer:new{
        background = INK,
        bordersize = 0,
        margin = 0,
        padding = 0,
        padding_left = S(6),
        padding_right = S(6),
        padding_top = S(3),
        padding_bottom = S(3),
        text(_("NEW"), "sans_semibold", 9, PAPER),
    }
    local tag_w = tag:getSize().w
    tag.overlap_offset = {
        math.floor((w + cover_w) / 2) - tag_w - S(6),
        math.floor((h - cover_h) / 2) + S(6),
    }
    return OverlapGroup:new{ dimen = Geom:new{ w = w, h = h }, cover, tag }
end

function Home:pager(cw)
    local pages = self:pageCount()
    local function arrow(icon, enabled, step)
        local widget = CenterContainer:new{
            dimen = Geom:new{ w = S(44), h = S(44) },
            IconWidget:new{
                icon = icon,
                width = S(18),
                height = S(18),
                dim = not enabled,
            },
        }
        return enabled and self:hit(widget, function() self:turnPage(step) end) or widget
    end
    return VerticalGroup:new{
        span_v(10),
        CenterContainer:new{
            dimen = Geom:new{ w = cw, h = S(44) },
            HorizontalGroup:new{
                align = "center",
                arrow("chevron.left", self.page > 1, -1),
                span_h(18),
                text(T(_("%1 of %2"), self.page, pages), "sans", 12, MUTED),
                span_h(18),
                arrow("chevron.right", self.page < pages, 1),
            },
        },
    }
end

function Home:syncStatus()
    local dropboxsync = self.plugin.ui.dropboxsync
    if dropboxsync and dropboxsync:isRunning() then
        return _("Syncing with Dropbox…")
    end
    if readFirstLine(SYNC_STATUS) == "error" then
        return _("Dropbox sync failed")
    end
    local last = tonumber(readFirstLine(LAST_SYNC))
    if not last then
        return _("Synced with Dropbox")
    end
    return T(_("Synced with Dropbox · %1"), timeAgo(os.time() - last))
end

function Home:footer(cw, pad_x)
    local h = S(44)
    local sync = FrameContainer:new{
        bordersize = 0,
        margin = 0,
        padding = 0,
        padding_left = S(24),
        CenterContainer:new{
            dimen = Geom:new{ w = text(_("Sync now"), "sans_medium", 12):getSize().w, h = h },
            text(_("Sync now"), "sans_medium", 12),
        },
    }
    return FrameContainer:new{
        bordersize = 0,
        margin = 0,
        padding = 0,
        padding_left = pad_x,
        padding_right = pad_x,
        padding_bottom = S(14),
        VerticalGroup:new{
            align = "left",
            rule(cw, S(1), RULE),
            span_v(4),
            OverlapGroup:new{
                dimen = Geom:new{ w = cw, h = h },
                LeftContainer:new{
                    dimen = Geom:new{ w = cw, h = h },
                    text(self:syncStatus(), "sans", 12, MUTED),
                },
                RightContainer:new{
                    dimen = Geom:new{ w = cw, h = h },
                    self:hit(sync, function() self:syncNow() end),
                },
            },
        },
    }
end

-- Actions -------------------------------------------------------------------

function Home:refresh(mode)
    if self.closed then return end
    self[1]:free()
    self[1] = self:build()
    UIManager:setDirty(self, mode or "ui")
    UIManager:nextTick(function() self:extractMissing() end)
end

function Home:turnPage(step)
    local page = self.page + step
    if page < 1 or page > self:pageCount() then return end
    self.page = page
    self:refresh(SECTIONS[self.section].style == "grid" and "flashui" or "ui")
end

function Home:selectSection(i)
    if i == self.section then return end
    self.section = i
    self.page = 1
    self:refresh("flashui")
end

function Home:openFile(path)
    self:close()
    self.plugin.ui:openFile(path)
end

function Home:showMenu()
    -- The simplified Settings, when the Kindle UI plugin is there
    local kindleui = self.plugin.ui.kindleui
    if kindleui then
        kindleui:showSettings()
    else
        self.plugin.ui.menu:onShowMenu()
    end
end

function Home:syncNow()
    local dropboxsync = self.plugin.ui.dropboxsync
    if dropboxsync then
        dropboxsync:syncNow()
    end
end

-- Extract missing covers in the background: this page first, then the rest
function Home:extractMissing()
    if self.closed or #self.to_extract == 0 then return end
    local BookInfoManager = bookInfoManager()
    if not BookInfoManager or BookInfoManager:isExtractingInBackground() then return end

    local files, queued = {}, {}
    local function queue(path)
        if not attempted[path] and not queued[path] then
            queued[path] = true
            attempted[path] = true
            table.insert(files, { filepath = path, cover_specs = self.cover_specs })
        end
    end
    for _, path in ipairs(self.to_extract) do
        queue(path)
    end
    for i, section in ipairs(SECTIONS) do
        if section.style == "grid" then
            for _, item in ipairs(self.data[i]) do
                if not BookInfoManager:getBookInfo(item.path, false) then
                    queue(item.path)
                end
            end
        end
    end
    if #files > 0 and BookInfoManager:extractInBackground(files) then
        self:waitForCovers()
    end
end

function Home:waitForCovers()
    UIManager:scheduleIn(2, function()
        if self.closed then return end
        if bookInfoManager():isExtractingInBackground() then
            return self:waitForCovers()
        end
        self:refresh("flashui")
    end)
end

function Home:close()
    UIManager:close(self)
end

function Home:onTap(_, ges)
    for _, hit in ipairs(self.hits) do
        if hit.dimen and hit.dimen:contains(ges.pos) then
            hit.callback()
            return true
        end
    end
    return true
end

function Home:onSwipe(_, ges)
    if ges.direction == "west" then
        self:turnPage(1)
    elseif ges.direction == "east" then
        self:turnPage(-1)
    elseif ges.direction == "south" and ges.pos.y < S(80) then
        self:showMenu()
    end
    return true
end

function Home:onHold()
    return true
end

function Home:onDropboxSyncStateChanged()
    self:loadData()
    self:refresh("ui")
end

function Home:onResume()
    self:refresh("full")
end

function Home:onCloseWidget()
    self.closed = true
    UIManager:unschedule(self.tick)
    self[1]:free()
end

-- Plugin --------------------------------------------------------------------

local HomeScreen = WidgetContainer:extend{
    name = "homescreen",
    is_doc_only = false,
}

-- The plugin loads in both the file browser and the reader; only the reader has a document
function HomeScreen:inFileManager()
    return self.ui.document == nil
end

function HomeScreen:onDispatcherRegisterActions()
    Dispatcher:registerAction("homescreen_show", {
        category = "none",
        event = "ShowHomeScreen",
        title = _("Home screen"),
        general = true,
    })
end

function HomeScreen:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

-- Sent as the file browser appears: opening here keeps the folder view from flashing first
function HomeScreen:onShow()
    if self:inFileManager() and not self.shown_once and G_reader_settings:nilOrTrue("homescreen_enabled") then
        self.shown_once = true
        self:show()
    end
end

function HomeScreen:show()
    if self.home and not self.home.closed then return end
    self.home = Home:new{ plugin = self }
    UIManager:show(self.home, "full")
end

function HomeScreen:onShowHomeScreen()
    if self:inFileManager() then
        if self.home and not self.home.closed then
            -- The top-left corner gesture overlaps the date, so act like a tap on it
            self.home:showMenu()
        else
            self:show()
        end
    else
        -- From a book: return to the file browser, which opens the home screen
        local file = self.ui.document.file
        self.ui:onClose()
        self.ui:showFileManager(file)
    end
    return true
end

function HomeScreen:addToMainMenu(menu_items)
    menu_items.home_screen = {
        text = _("Home screen"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Show home screen"),
                callback = function(touchmenu_instance)
                    touchmenu_instance:closeMenu()
                    self:onShowHomeScreen()
                end,
            },
            {
                text = _("Browse files"),
                enabled_func = function() return self.home ~= nil and not self.home.closed end,
                callback = function(touchmenu_instance)
                    touchmenu_instance:closeMenu()
                    self.home:close()
                end,
            },
            {
                text = _("Show home screen on startup"),
                checked_func = function() return G_reader_settings:nilOrTrue("homescreen_enabled") end,
                callback = function() G_reader_settings:flipNilOrTrue("homescreen_enabled") end,
            },
        },
    }
end

return HomeScreen
