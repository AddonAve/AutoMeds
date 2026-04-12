--[[
Copyright (c) 2025, Addon Ave
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright
notice, this list of conditions and the following disclaimer in the
documentation and/or other materials provided with the distribution.
* Neither the name of [AutoMeds] nor the names of its contributors
may be used to endorse or promote products derived from this software
without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL [Addon Ave] BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

_addon.name = 'AutoMeds'
_addon.version = '1.8.0'
_addon.author = 'Addon Ave'
_addon.commands = {'ameds'}

require('tables')
require('strings')
require('logger')
require('sets')
config = require('config')
chat = require('chat')
res = require('resources')

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local defaults = {}
defaults.buffs = S{"curse","disease","doom","paralysis","silence"}
defaults.alttrack = false
defaults.sitrack = false

defaults.global = {
aura = {
enabled = true,			-- Aura Awareness
distance = 20,
-- Default sources list
-- Use //ameds auraadd "target" [debuff|*] to add additional targets, use * for all debuffs the target inflicts
sources_list = {
"biune ice elemental|paralysis","naga raja|paralysis","numbing blossom|paralysis","triboulex|paralysis"},
smart = {
enabled = true,			-- Smart Aura Block
attempt_window = 8,   	-- Triggers Smart Aura Block features after the failed [max_attempts] within the [attempt_window] in seconds
max_attempts = 2,     	-- If an item is used at least this many times with debuff still present then aura is assumed
block_time = 120       	-- Seconds to pause item use when aura is assumed
}
}
}

local AutoMeds = true

-- Settings (per-character)
local settings = nil
local settings_name = nil

-- Forward declaration (used in login handler before the function body appears)
local rebuild_aura_rt_map

local function load_settings()
local p = windower.ffxi.get_player()
local char = (p and p.name) or 'global'

-- New desired filename: data/<char>.xml
local legacy_rel = 'data/' .. char
local xml_rel    = legacy_rel .. '.xml'

local legacy_abs = windower.addon_path .. legacy_rel
local xml_abs    = windower.addon_path .. xml_rel

-- If the old no-extension file exists and the .xml doesn't yet, rename it
if windower.file_exists(legacy_abs) and not windower.file_exists(xml_abs) then
os.rename(legacy_abs, xml_abs)
end

-- Only (re)load when the target settings file changes
if settings and settings_name == xml_rel then
return false
end

settings_name = xml_rel
settings = config.load(xml_rel, defaults)
return true
end

-- Load immediately (may be 'global' if not logged in yet)
load_settings()

windower.register_event('login', function()
if load_settings() then
rebuild_aura_rt_map()
end
end)

-- Debuff Item Map
local debuff_items = {
["curse"] = "Holy Water",
["disease"] = "Remedy",
["doom"] = "Holy Water",
["paralysis"] = "Remedy",
["silence"] = "Echo Drops",
["slow"] = nil,
}

-- Debuff Priority (highest to lowest)
local debuff_priority = {
'paralysis',
'doom',
'silence',
'curse',
'disease',
}

-- State
local retry_delay = 4
local last_retry_time = 0
local active_debuff = nil
local missing_item_alerts = {}
local aura_skip_alerts = {}
local aura_rt_map = {}

-- Smart Aura Block runtime state
local use_attempts = {}
local aura_block_until = {}
local aura_block_alerted = {}
local aura_last_reminder = {} -- Throttled reminder prints per debuff
local aura_reminder_interval = 20 -- Pause duration in seconds between reminder messages

-- Pending item-use tracking for Smart Aura Block (count attempts only when item actually fires)
local pending_item_use = nil -- {buff=string, item=string, issued_at=number}
local pending_item_timeout = 6 -- seconds to wait for the action packet before giving up

-- Utilities
local function norm(s) return (s or ''):lower():trim() end

--------------------------------------------------------------------------------
-- Inventory Cache
--------------------------------------------------------------------------------

local required_items = S{}
for _, v in pairs(debuff_items) do
if v and type(v) == 'string' then
required_items:add(v:lower())
end
end

local item_cache = T{} 
local item_cache_invalid = true
local item_cache_last_rebuild = 0
local item_cache_min_interval = 0.5

local function mark_item_cache_invalid()
item_cache_invalid = true
end

local function rebuild_item_cache(force)
local now = os.clock()
if not force and not item_cache_invalid then return end
if not force and (now - item_cache_last_rebuild) < item_cache_min_interval then return end

local items = windower.ffxi.get_items()
local inv = items and items.inventory
local cache = T{}

if inv then
for _, slot in pairs(inv) do
if type(slot) == 'table' and slot.id and slot.id > 0 and (slot.count or 0) > 0 then
local it = res.items[slot.id]
if it and it.name then
local n = it.name:lower()
if required_items:contains(n) then
cache[n] = true
end
end
end
end
end

item_cache = cache
item_cache_invalid = false
item_cache_last_rebuild = now
end

local function have_item(item_name)
if not item_name or item_name == '' then return false end
rebuild_item_cache(false)
return item_cache[item_name:lower()] == true
end

rebuild_item_cache(true)

windower.register_event('incoming chunk', function(id, data)
if id == 0x01D or id == 0x01E or id == 0x01F or id == 0x020 then
mark_item_cache_invalid()
end
end)

windower.register_event('job change', 'logout', 'zone change', function()
mark_item_cache_invalid()
end)

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function player_has_debuff(buff_lc)
local p = windower.ffxi.get_player()
if not p or not p.buffs then return false end
for _, bid in ipairs(p.buffs) do
local bn = res.buffs[bid] and res.buffs[bid].english and res.buffs[bid].english:lower()
if bn == buff_lc then return true end
end
return false
end

local function clean_chat_line(s)
s = tostring(s or ''):lower()
s = s:gsub('[%c]', '')
return s
end

local function get_global_aura()
settings.global = settings.global or {}
local g = settings.global

g.aura = g.aura or {
enabled = true,
distance = 20,
sources_list = {},
smart = { enabled = true, attempt_window = 8, max_attempts = 2, block_time = 60 },
}

if settings.aura then
local a = settings.aura
if a.enabled ~= nil then g.aura.enabled = a.enabled end
if a.distance ~= nil then g.aura.distance = a.distance end
if type(a.sources_list) == 'table' and next(a.sources_list) ~= nil then
g.aura.sources_list = a.sources_list
end
if type(a.smart) == 'table' then
g.aura.smart = g.aura.smart or {}
for k,v in pairs(a.smart) do g.aura.smart[k] = v end
end
settings.aura = nil
end
if settings.sources and settings.sources.list then
local tmp = {}
for k, v in pairs(settings.sources.list) do
local s = tostring(v)
if s:find('|') then table.insert(tmp, s) end
settings.sources.list[k] = nil
end
if #tmp > 0 then g.aura.sources_list = tmp end
settings.sources = nil
end

g.aura.sources_list = g.aura.sources_list or {}
g.aura.smart = g.aura.smart or { enabled = true, attempt_window = 8, max_attempts = 2, block_time = 60 }

return g.aura
end

local function set_to_sorted_list(s)
local t = T{}
if s then
for v in s:it() do t:append(v) end
end
t:sort()
return t
end

-- Distance helpers
local function dist2(a, b)
if not a or not b or a.x == nil or b.x == nil then return 1e12 end
local dx, dy = a.x - b.x, a.y - b.y
return dx*dx + dy*dy
end

local function within(mob, player, yalms)
local r2 = (yalms or 20)^2
return dist2(mob, player) <= r2
end

-- Return target name if nearby aura source exists for buff, else nil
local function aura_source_nearby_for(buffname)
local aura = get_global_aura()
if not aura.enabled then return nil end
local buff_l = norm(buffname); if buff_l == '' then return nil end
local me = windower.ffxi.get_mob_by_target('me'); if not me then return nil end

local mobs = windower.ffxi.get_mob_array() or {}
for _, m in pairs(mobs) do
if m and m.is_npc and m.valid_target and m.hpp and m.hpp > 0 and m.spawn_type == 16 then
local name_l = norm(m.name)
local set = aura_rt_map[name_l]
-- Wildcard debuff
if set and (set[buff_l] or set['*']) and within(m, me, aura.distance or 20) then
return name_l
end
end
end
return nil
end

-- Parser for: auraadd "<target name>" buff
local function parse_target_and_buff(args, start_idx)
local n = #args
if n < start_idx then return nil, nil end

local first = args[start_idx] or ''
local q = first:sub(1,1)
local target = nil
local next_idx = start_idx + 1

if q == '"' or q == "'" then
local acc = first
local i = start_idx + 1
while i <= n and not acc:match(q..'%s*$') do
acc = acc .. ' ' .. (args[i] or '')
i = i + 1
end
target = acc:gsub('^'..q, ''):gsub(q..'%s*$', '')
next_idx = i
else
target = first
next_idx = start_idx + 1
end

if next_idx > n then return nil, nil end
local buff = table.concat(args, ' ', next_idx)

target = norm(target)
buff = norm(buff)

if target == '' or buff == '' then return nil, nil end
return target, buff
end

-- Aura Map Settings
rebuild_aura_rt_map = function()
aura_rt_map = {}
local aura = get_global_aura()
local list = aura.sources_list or {}

local tmp = {}
for k, line in pairs(list) do
local idx = tonumber(k)
if idx then
tmp[idx] = tostring(line)
else
table.insert(tmp, tostring(line))
end
end

for i = 1, #tmp do
local line = tmp[i]
if type(line) == 'string' then
local target, buffs = tostring(line):match('^%s*(.-)%s*|%s*(.-)%s*$')
if target and buffs then
local m = norm(target)
if m ~= '' then
aura_rt_map[m] = aura_rt_map[m] or S{}
for b in tostring(buffs):gmatch('[^,]+') do
local nb = norm(b)
if nb ~= '' then aura_rt_map[m]:add(nb) end
end
end
end
end
end
end

local function save_aura_rt_map()
local aura = get_global_aura()

local mons = {}
for m,_ in pairs(aura_rt_map) do
table.insert(mons, tostring(m))
end
table.sort(mons)

local out = {}
for _, m in ipairs(mons) do
local buffs = set_to_sorted_list(aura_rt_map[m])
table.insert(out, string.format('%s|%s', m, table.concat(buffs, ',')))
end

aura.sources_list = out
settings:save()
rebuild_aura_rt_map()
end

-- Smart Aura Block attempt tracking
local function trim_attempts(buff, now, window_s)
local t = use_attempts[buff]
if not t then return end
local i = 1
while i <= #t do
if now - t[i] > window_s then
table.remove(t, i)
else
i = i + 1
end
end
end

local function record_attempt(buff, now)
use_attempts[buff] = use_attempts[buff] or {}
table.insert(use_attempts[buff], now)
end

--------------------------------------------------------------------------------
-- Smart Aura Block
-- Counts failed attempts only when the item actually fires
-- Verifies the debuff is still present
--------------------------------------------------------------------------------

local smart_fail_checks = {} -- { {buff=string, at=number} }

windower.register_event('action', function(act)
if not pending_item_use then return end
if not act then return end

local me = windower.ffxi.get_player()
if not me or not me.id then return end
if act.actor_id ~= me.id then return end

-- Item usage is typically category 5 in Windower's action event
if act.category ~= 5 then return end

-- Confirm we targeted ourselves (most meds are used on <me>)
local targeted_me = false
if act.targets then
for _, t in ipairs(act.targets) do
if t.id == me.id then
targeted_me = true
break
end
end
end
if not targeted_me then return end

local now = os.clock()
-- Ignore stale pending states (lag / mismatch)
if (now - (pending_item_use.issued_at or 0)) > pending_item_timeout then
pending_item_use = nil
return
end

table.insert(smart_fail_checks, { buff = pending_item_use.buff, at = now + 0.8 })
pending_item_use = nil
end)

-- Main loop
windower.register_event('prerender', function()
if not AutoMeds then return end

local player = windower.ffxi.get_player()
if not player or not player.buffs then return end

local now = os.clock()
-- Clear stale pending item use (no chat confirmation received)
if pending_item_use and (now - (pending_item_use.issued_at or 0)) > pending_item_timeout then
pending_item_use = nil
end

-- Process packet-scheduled Smart Aura fail checks
if #smart_fail_checks > 0 then
for i = #smart_fail_checks, 1, -1 do
local entry = smart_fail_checks[i]
if now >= (entry.at or 0) then
table.remove(smart_fail_checks, i)
local buff_lc = norm(entry.buff)
if buff_lc ~= '' and player_has_debuff(buff_lc) then
local aura = get_global_aura()
local smart = (aura and aura.smart) or {enabled=true, attempt_window=8, max_attempts=2, block_time=60}
if smart.enabled then
record_attempt(buff_lc, now)
trim_attempts(buff_lc, now, smart.attempt_window or 8)
end
end
end
end
end

local aura = get_global_aura()
local smart = aura.smart or {enabled=true, attempt_window=8, max_attempts=2, block_time=60}

local found_buff = false

-- Build a set of tracked debuffs currently on the player
local present = {}
local first_found = nil
for _, buff_id in ipairs(player.buffs) do
local bn = res.buffs[buff_id] and res.buffs[buff_id].english:lower()
if bn and settings.buffs:contains(bn) then
present[bn] = true
if not first_found then first_found = bn end
end
end

-- Pick which debuff to act using priority order
local buff_name = nil
for _, name in ipairs(debuff_priority) do
if present[name] then
buff_name = name
break
end
end
if not buff_name then
buff_name = first_found
end

if buff_name then
found_buff = true
local item = debuff_items[buff_name]

-- Aura Awareness: skip if aura source is nearby
local src = aura_source_nearby_for(buff_name)
if src then
if not aura_skip_alerts[buff_name] then
windower.add_to_chat(2, ('[AutoMeds] Skipping item use for %s due to nearby aura source: %s'):format(buff_name, src))
aura_skip_alerts[buff_name] = true
end
active_debuff = buff_name
else
aura_skip_alerts[buff_name] = nil

-- Smart Aura Block: temporary pause if items use >= max_attempts and still have debuff
if smart.enabled then
if aura_block_until[buff_name] and now >= aura_block_until[buff_name] then
aura_block_until[buff_name] = nil
aura_block_alerted[buff_name] = nil
use_attempts[buff_name] = nil
aura_last_reminder[buff_name] = nil
end

trim_attempts(buff_name, now, smart.attempt_window or 8)

-- Show remaining time every aura_reminder_interval while blocked
if aura_block_until[buff_name] then
local last = aura_last_reminder[buff_name] or 0
if (now - last) >= aura_reminder_interval or not aura_block_alerted[buff_name] then
local remaining = math.max(0, math.floor(aura_block_until[buff_name] - now))
windower.add_to_chat(2, ('[AutoMeds] Pausing %s item use for %d seconds'):format(buff_name, remaining))
aura_block_alerted[buff_name] = true
aura_last_reminder[buff_name] = now
end
active_debuff = buff_name
return
end

-- Trigger item block
local attempts = use_attempts[buff_name] and #use_attempts[buff_name] or 0
if attempts >= (smart.max_attempts or 2) then
aura_block_until[buff_name] = now + (smart.block_time or 60)
local remaining = math.max(0, math.floor((smart.block_time or 60)))
windower.add_to_chat(2, ('[AutoMeds] Pausing %s item use for %d seconds (assumed aura after %d attempts)'):format(buff_name, remaining, attempts))
aura_block_alerted[buff_name] = true
aura_last_reminder[buff_name] = now
active_debuff = buff_name
return
end
end

-- Use item if available
if item and (now - last_retry_time) > retry_delay then
local has_item = have_item(item)

if has_item then
windower.add_to_chat(2, '[AutoMeds] Using '..item..' for '..buff_name..'')
windower.send_command('input /item "'..item..'" '..player.name)
last_retry_time = now
missing_item_alerts[buff_name] = nil

-- Smart Aura Block: count an attempt only if the item actually fires
if smart.enabled then
pending_item_use = { buff = buff_name, item = item, issued_at = now }
end
elseif not missing_item_alerts[buff_name] then
windower.add_to_chat(2, '[AutoMeds] Missing item "'..(item or '?')..'" for debuff: '..buff_name..'')
missing_item_alerts[buff_name] = true
end
end

active_debuff = buff_name
end
end

if not found_buff then
active_debuff = nil
end
end)

windower.register_event('lose buff', function(id)
local name = res.buffs[id] and res.buffs[id].english:lower()
if name == active_debuff then
windower.add_to_chat(2, '[AutoMeds] Debuff "'..name..'" cleared')
active_debuff = nil
use_attempts[name] = nil
aura_block_until[name] = nil
aura_block_alerted[name] = nil
aura_last_reminder[name] = nil
end
end)

windower.register_event('gain buff', function(id)
local name = res.buffs[id] and res.buffs[id].english:lower()
if name and settings.buffs:contains(name) then
if settings.alttrack then
windower.send_command('send @others atc '..windower.ffxi.get_player().name..' - '..name)
end
end
end)

--------------------------------------------------------------------------------
-- Smart Aura Block
--------------------------------------------------------------------------------

local smart_fail_checks = {} -- { {buff=string, at=number} }

windower.register_event('action', function(act)
if not pending_item_use then return end
if not act then return end

local me = windower.ffxi.get_player()
if not me or not me.id then return end
if act.actor_id ~= me.id then return end

-- Item usage
if act.category ~= 5 then return end

-- Confirm we targeted ourselves
local targeted_me = false
if act.targets then
for _, t in ipairs(act.targets) do
if t.id == me.id then
targeted_me = true
break
end
end
end
if not targeted_me then return end

local now = os.clock()
-- Ignore stale pending states (lag/mismatch)
if (now - (pending_item_use.issued_at or 0)) > pending_item_timeout then
pending_item_use = nil
return
end

table.insert(smart_fail_checks, { buff = pending_item_use.buff, at = now + 0.8 })
pending_item_use = nil
end)

--------------------------------------------------------------------------------
-- IPC Support
--------------------------------------------------------------------------------

local IPC_TAG = '__AMEDS_ALL__'
local IPC_SEP = '	' -- robust separator for IPC payloads (avoids quoted/space parsing issues)

-- Apply helpers so both local commands and IPC can reuse the same logic
local function auraadd_apply(mon, buff, silent)
aura_rt_map[mon] = aura_rt_map[mon] or S{}
aura_rt_map[mon]:add(buff)
save_aura_rt_map()
if not silent then
windower.add_to_chat(2, ('[AutoMeds] Added aura: %s - %s'):format(mon, buff))
end
end

local function auraremove_apply(mon, maybe_buff, silent)
local set = aura_rt_map[mon]
if not set then
if not silent then
windower.add_to_chat(2, ('[AutoMeds] No entry for target: %s'):format(mon))
end
return
end

if maybe_buff and maybe_buff ~= '' then
local nb = norm(maybe_buff)
if set[nb] then
set:remove(nb)
if set:length() == 0 then aura_rt_map[mon] = nil end
save_aura_rt_map()
if not silent then
windower.add_to_chat(2, ('[AutoMeds] Removed %s - %s'):format(mon, nb))
end
else
if not silent then
windower.add_to_chat(2, ('[AutoMeds] %s does not have buff: %s'):format(mon, nb))
end
end
else
aura_rt_map[mon] = nil
save_aura_rt_map()
if not silent then
windower.add_to_chat(2, ('[AutoMeds] Removed target entry: %s'):format(mon))
end
end
end

local function watch_apply(buff, silent, from_ipc)
local nb = norm(buff)
if nb == '' then return end
if not settings.buffs:contains(nb) then
settings.buffs:add(nb)
settings:save()
if not silent then
windower.add_to_chat(2, '[AutoMeds] Tracking buff: '..nb)
elseif from_ipc then
windower.add_to_chat(2, '[AutoMeds] *all* Tracking buff: '..nb)
end
else
if not silent then
windower.add_to_chat(2, nb..' is already tracked.')
elseif from_ipc then
windower.add_to_chat(2, '[AutoMeds] *all* '..nb..' is already tracked')
end
end
end

local function unwatch_apply(buff, silent, from_ipc)
local nb = norm(buff)
if nb == '' then return end
if settings.buffs:contains(nb) then
settings.buffs:remove(nb)
settings:save()
if not silent then
windower.add_to_chat(2, '[AutoMeds] Stopped tracking: '..nb)
elseif from_ipc then
windower.add_to_chat(2, '[AutoMeds] *all* Stopped tracking: '..nb)
end
else
if not silent then
windower.add_to_chat(2, '[AutoMeds] '..nb..' is not tracked')
elseif from_ipc then
windower.add_to_chat(2, '[AutoMeds] *all* '..nb..' is not tracked')
end
end
end

local function list_apply(from_ipc)
local prefix = from_ipc and '[AutoMeds] *all* ' or '[AutoMeds] '
windower.add_to_chat(2, prefix..'Tracked debuffs:')
for buff in settings.buffs:it() do
windower.add_to_chat(2, ' - '..buff)
end
end

local function set_onoff_apply(state, from_ipc)
local v = tostring(state or ''):lower()

if v == 'on' then
AutoMeds = true
elseif v == 'off' then
AutoMeds = false
else
return false
end

local state_str = AutoMeds and 'On' or 'Off'
if from_ipc then
windower.add_to_chat(2, '[AutoMeds] *all* Auto medicine: '..state_str)
else
windower.add_to_chat(2, '[AutoMeds] Auto medicine: '..state_str)
end

return true
end

local function sitrack_apply(from_ipc)
settings.sitrack = not settings.sitrack
settings:save()
if from_ipc then
windower.add_to_chat(2, '[AutoMeds] *all* Sneak/Invisible tracker: '..tostring(settings.sitrack))
else
windower.add_to_chat(2, '[AutoMeds] Sneak/Invisible tracker: '..tostring(settings.sitrack))
end
end

local function aura_apply(value, from_ipc)
local aura_cfg = get_global_aura()
local v = norm(value)
if v == 'on' then
aura_cfg.enabled = true
elseif v == 'off' then
aura_cfg.enabled = false
else
return false
end
settings:save()
if from_ipc then
windower.add_to_chat(2, '[AutoMeds] *all* Aura Awareness: '..tostring(aura_cfg.enabled))
else
windower.add_to_chat(2, '[AutoMeds] Aura Awareness: '..tostring(aura_cfg.enabled))
end
return true
end

local function aurasmart_apply(value, from_ipc)
local v = norm(value)
local aura_cfg = get_global_aura()
aura_cfg.smart = aura_cfg.smart or {}
if v == 'on' then
aura_cfg.smart.enabled = true
elseif v == 'off' then
aura_cfg.smart.enabled = false
else
return false
end
settings:save()
if from_ipc then
windower.add_to_chat(2, '[AutoMeds] *all* Smart Aura Block: '..tostring(aura_cfg.smart.enabled))
else
windower.add_to_chat(2, '[AutoMeds] Smart Aura Block: '..tostring(aura_cfg.smart.enabled))
end
return true
end

local function aurablock_apply(value, from_ipc)
local v = tonumber(value)
if not v or v < 60 or v > 600 then return false end
local aura_cfg = get_global_aura()
aura_cfg.smart = aura_cfg.smart or {}
aura_cfg.smart.block_time = v
settings:save()
if from_ipc then
windower.add_to_chat(2, ('[AutoMeds] *all* Aura block time set to %ds'):format(v))
else
windower.add_to_chat(2, ('[AutoMeds] Aura block time set to %ds'):format(v))
end
return true
end

local function auradistance_apply(value, from_ipc)
local v = tonumber(value)
if not v or v < 1 or v > 20 then return false end
local aura_cfg = get_global_aura()
aura_cfg.distance = v
settings:save()
if from_ipc then
windower.add_to_chat(2, ('[AutoMeds] *all* Aura distance set to %d yalms'):format(v))
else
windower.add_to_chat(2, ('[AutoMeds] Aura distance set to %d yalms'):format(v))
end
return true
end

local function auralist_apply(mon, from_ipc)
local prefix = from_ipc and '[AutoMeds] *all* ' or '[AutoMeds] '
local nmon = norm(mon)
if nmon ~= '' then
local set = aura_rt_map[nmon]
if not set then
windower.add_to_chat(2, ('[AutoMeds] %sNo entry for: %s'):format(prefix, nmon))
return
end
local list = set_to_sorted_list(set)
windower.add_to_chat(2, ('[AutoMeds] %s%s - %s'):format(prefix, nmon, table.concat(list, ', ')))
return
end

local mons = {}
for m,_ in pairs(aura_rt_map) do table.insert(mons, m) end
table.sort(mons)
if #mons == 0 then
windower.add_to_chat(2, prefix..'Aura sources: (none)')
else
windower.add_to_chat(2, prefix..'Aura sources:')
for _, m in ipairs(mons) do
local buffs = set_to_sorted_list(aura_rt_map[m])
windower.add_to_chat(2, ('- %s|%s'):format(m, table.concat(buffs, ',')))
end
end
end

local function ipc_broadcast(sub, arg1, arg2)
local sender = (windower.ffxi.get_player() and windower.ffxi.get_player().name) or ''
local ipc_msg = table.concat({sub or '', arg1 or '', arg2 or '', sender}, IPC_SEP)
windower.send_ipc_message(IPC_TAG .. IPC_SEP .. ipc_msg)
end

windower.register_event('ipc message', function(msg)
msg = tostring(msg or '')
if msg:sub(1, #IPC_TAG) ~= IPC_TAG then return end

local payload = msg:sub(#IPC_TAG + 1)
payload = payload:gsub('^[%s]+', '')
if payload == '' then return end
if not payload:find(IPC_SEP, 1, true) then return end

local fields = payload:split(IPC_SEP)
local sub = tostring(fields[1] or ''):lower()
local arg1 = tostring(fields[2] or '')
local arg2 = tostring(fields[3] or '')
local sender = tostring(fields[4] or '')

local p = windower.ffxi.get_player()
local me = (p and p.name) or ''
if sender ~= '' and me ~= '' and sender:lower() == me:lower() then
return
end

if sub == 'auraadd' then
local mon = norm(arg1)
local buff = norm(arg2)
if mon == '' or buff == '' then return end
auraadd_apply(mon, buff, true)
windower.add_to_chat(2, ('[AutoMeds] *all* Added aura: %s - %s'):format(buff, mon))
elseif sub == 'auraremove' then
local mon = norm(arg1)
local buff = norm(arg2)
if mon == '' then return end
auraremove_apply(mon, (buff ~= '' and buff or nil), true)
if buff ~= '' then
windower.add_to_chat(2, ('[AutoMeds] *all* Removed aura: %s - %s'):format(buff, mon))
else
windower.add_to_chat(2, ('[AutoMeds] *all* Removed aura target: %s'):format(mon))
end
elseif sub == 'on' or sub == 'off' then
set_onoff_apply(sub, true)
elseif sub == 'watch' then
watch_apply(arg1, true, true)
elseif sub == 'unwatch' then
unwatch_apply(arg1, true, true)
elseif sub == 'list' then
list_apply(true)
elseif sub == 'sitrack' then
sitrack_apply(true)
elseif sub == 'aura' then
aura_apply(arg1, true)
elseif sub == 'aurasmart' then
aurasmart_apply(arg1, true)
elseif sub == 'aurablock' then
aurablock_apply(arg1, true)
elseif sub == 'auradistance' then
auradistance_apply(arg1, true)
elseif sub == 'auralist' then
auralist_apply(arg1, true)
end
end)

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

windower.register_event('addon command', function(...)
local args = {...}
if not args[1] then return end
local cmd = args[1]:lower()

if cmd == 'all' and args[2] then
local sub = tostring(args[2] or ''):lower()
if sub == 'auraadd' or sub == 'auraremove' then
local mon, buff = parse_target_and_buff(args, 3)
if not mon then
windower.add_to_chat(2, 'Usage: //ameds all '..sub..' "target" [debuff|*]')
return
end
if sub == 'auraadd' and not buff then
windower.add_to_chat(2, 'Usage: //ameds all auraadd "target" [debuff|*]')
return
end
if sub == 'auraadd' then
auraadd_apply(mon, buff, false)
else
auraremove_apply(mon, buff, false)
end
ipc_broadcast(sub, mon, buff or '')
return
elseif sub == 'on' or sub == 'off' then
if not set_onoff_apply(sub, false) then return end
ipc_broadcast(sub, '', '')
return
elseif sub == 'watch' and args[3] then
local buff = table.concat(args, ' ', 3):lower()
watch_apply(buff, false, false)
ipc_broadcast('watch', buff, '')
return
elseif sub == 'unwatch' and args[3] then
local buff = table.concat(args, ' ', 3):lower()
unwatch_apply(buff, false, false)
ipc_broadcast('unwatch', buff, '')
return
elseif sub == 'list' then
list_apply(false)
ipc_broadcast('list', '', '')
return
elseif sub == 'sitrack' then
sitrack_apply(false)
ipc_broadcast('sitrack', '', '')
return
elseif sub == 'aura' and args[3] then
if not aura_apply(args[3], false) then
windower.add_to_chat(2, 'Usage: //ameds all aura [on|off]')
return
end
ipc_broadcast('aura', args[3], '')
return
elseif sub == 'aurasmart' and args[3] then
if not aurasmart_apply(args[3], false) then
windower.add_to_chat(2, 'Usage: //ameds all aurasmart [on|off]')
return
end
ipc_broadcast('aurasmart', args[3], '')
return
elseif sub == 'aurablock' and args[3] then
if not aurablock_apply(args[3], false) then
windower.add_to_chat(2, 'Usage: //ameds all aurablock <60 - 600>')
return
end
ipc_broadcast('aurablock', tostring(args[3]), '')
return
elseif sub == 'auradistance' and args[3] then
if not auradistance_apply(args[3], false) then
windower.add_to_chat(2, 'Usage: //ameds all auradistance <1 - 20>')
return
end
ipc_broadcast('auradistance', tostring(args[3]), '')
return
elseif sub == 'auralist' then
local mon = args[3] and table.concat(args, ' ', 3) or ''
auralist_apply(mon, false)
ipc_broadcast('auralist', mon, '')
return
end
end

if cmd == 'watch' and args[2] then
local buff = table.concat(args, ' ', 2):lower()
watch_apply(buff, false, false)

elseif cmd == 'unwatch' and args[2] then
local buff = table.concat(args, ' ', 2):lower()
unwatch_apply(buff, false, false)

elseif cmd == 'list' then
list_apply(false)

elseif cmd == 'on' or cmd == 'off' then
set_onoff_apply(cmd, false)

elseif cmd == 'trackalt' then
settings.alttrack = not settings.alttrack
settings:save()
windower.add_to_chat(2, 'Alt tracking: '..tostring(settings.alttrack))

elseif cmd == 'sitrack' then
sitrack_apply(false)

elseif cmd == 'aura' and args[2] then
if not aura_apply(args[2], false) then
windower.add_to_chat(2, 'Usage: //ameds aura [on|off]')
return
end

elseif cmd == 'aurasmart' and args[2] then
if not aurasmart_apply(args[2], false) then
windower.add_to_chat(2, 'Usage: //ameds aurasmart [on|off]')
return
end

elseif cmd == 'aurablock' and args[2] then
if not aurablock_apply(args[2], false) then
windower.add_to_chat(2, 'Usage: //ameds aurablock <60 - 600>')
return
end

elseif cmd == 'auradistance' and args[2] then
if not auradistance_apply(args[2], false) then
windower.add_to_chat(2, 'Usage: //ameds auradistance <1 - 20>')
return
end

elseif cmd == 'auraadd' and args[2] then
local mon, buff = parse_target_and_buff(args, 2)
if not mon or not buff then
windower.add_to_chat(2, 'Usage: //ameds auraadd "target" [debuff|*]')
return
end
auraadd_apply(mon, buff, false)

elseif cmd == 'auraremove' and args[2] then
local mon, maybe_buff = parse_target_and_buff(args, 2)
if not mon then
windower.add_to_chat(2, 'Usage: //ameds auraremove "target" [debuff|*]')
return
end
auraremove_apply(mon, maybe_buff, false)

elseif cmd == 'auralist' then
local mon = args[2] and table.concat(args, ' ', 2) or ''
auralist_apply(mon, false)

elseif cmd == 'help' then
windower.add_to_chat(2, '[AutoMeds] Commands:')
windower.add_to_chat(2, '//ameds trackalt - Toggle broadcast for debuffs on your alts')
windower.add_to_chat(2, '//ameds all [command] - Send a command below to all characters')
windower.add_to_chat(2, '//ameds [on|off] - Enable/Disable')
windower.add_to_chat(2, '//ameds watch [buff] - Track a debuff')
windower.add_to_chat(2, '//ameds unwatch [buff] - Untrack a debuff')
windower.add_to_chat(2, '//ameds list - Show tracked debuffs')
windower.add_to_chat(2, '//ameds sitrack - Toggle Sneak/Invisible wear tracker')
windower.add_to_chat(2, '//ameds aura [on|off] - Enable/Disable Aura Awareness')
windower.add_to_chat(2, '//ameds aurasmart [on|off] - Enable/Disable Smart Aura Block')
windower.add_to_chat(2, '//ameds aurablock <seconds> - Set pause duration <60 - 600>')
windower.add_to_chat(2, '//ameds auradistance <yalms> - Set distance detection for Aura Awareness <1 - 20>')
windower.add_to_chat(2, '//ameds auraadd "target" [debuff|*] - Add target and debuff for Aura Awareness')
windower.add_to_chat(2, '//ameds auraremove "target" [debuff|*] - Remove target and debuff from Aura Awareness')
windower.add_to_chat(2, '//ameds auralist - List all aura sources')
windower.add_to_chat(2, '//ameds auralist "target" - List aura sources for target')
end
end)

rebuild_aura_rt_map()
