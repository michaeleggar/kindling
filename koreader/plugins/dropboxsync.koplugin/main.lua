--[[--
Syncs the Dropbox library to the Kindle with rclone.

Runs from the Tools menu, and automatically when Wi-Fi connects.

@module koplugin.DropboxSync
--]]--

local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T = require("ffi/util").template
local _ = require("gettext")
local N_ = _.ngettext

local SCRIPT = "/mnt/us/rclone/sync-books.sh"
local STATUS = "/mnt/us/rclone/status"
local AUTO_INTERVAL = 600 -- seconds between automatic syncs
local TIMEOUT = 1800

-- Shared between the FileManager and Reader instances of the plugin
local running = false
local last_auto = 0
local started = false

local DropboxSync = WidgetContainer:extend{
    name = "dropboxsync",
    is_doc_only = false,
}

function DropboxSync:init()
    self.ui.menu:registerToMainMenu(self)
    if not started then
        started = true
        -- Wi-Fi may already be up when KOReader starts
        UIManager:scheduleIn(5, function()
            if NetworkMgr:isConnected() then
                self:onNetworkConnected()
            end
        end)
    end
end

function DropboxSync:addToMainMenu(menu_items)
    menu_items.dropbox_sync = {
        text = _("Sync Dropbox library"),
        sorting_hint = "tools",
        callback = function()
            self:syncNow()
        end,
    }
end

function DropboxSync:syncNow()
    NetworkMgr:runWhenOnline(function() self:sync(false) end)
end

function DropboxSync:isRunning()
    return running
end

function DropboxSync:onNetworkConnected()
    if not G_reader_settings:nilOrTrue("dropboxsync_auto") then return end
    if os.time() - last_auto >= AUTO_INTERVAL then
        last_auto = os.time()
        self:sync(true)
    end
end

local function readStatus()
    local f = io.open(STATUS, "r")
    if not f then return end
    local status = f:read("*l")
    f:close()
    return status
end

function DropboxSync:sync(silent)
    if running then
        if not silent then
            UIManager:show(InfoMessage:new{ text = _("Dropbox sync is already running."), timeout = 2 })
        end
        return
    end
    running = true
    os.remove(STATUS)
    os.execute("sh " .. SCRIPT .. " >/dev/null 2>&1 &")
    UIManager:broadcastEvent(Event:new("DropboxSyncStateChanged"))
    if not silent then
        Notification:notify(_("Syncing Dropbox library…"))
    end
    self:poll(silent, 0)
end

function DropboxSync:poll(silent, elapsed)
    UIManager:scheduleIn(2, function()
        local status = readStatus()
        if (status == nil or status == "running") and elapsed < TIMEOUT then
            return self:poll(silent, elapsed + 2)
        end
        running = false
        UIManager:broadcastEvent(Event:new("DropboxSyncStateChanged"))
        local count = status and tonumber(status:match("^ok (%d+)"))
        local text
        if count then
            if count == 0 and silent then return end
            if count == 0 then
                text = _("Dropbox library is up to date.")
            else
                text = T(N_("Downloaded 1 new file.", "Downloaded %1 new files.", count), count)
            end
            local FileManager = require("apps/filemanager/filemanager")
            if FileManager.instance then
                FileManager.instance:onRefresh()
            end
        else
            text = _("Dropbox sync failed.\nSee /mnt/us/rclone/sync.log")
        end
        UIManager:show(InfoMessage:new{ text = text, timeout = 4 })
    end)
end

return DropboxSync
