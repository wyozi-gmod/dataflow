-- Internal classes
local Flow = {}
Flow.__index = Flow

function Flow:setSynchronizer(sync)
	self._synchronizer = sync
	if sync.onLoad then sync.onLoad(self) end
end

function Flow:getTable()
	return self._raw
end

if SERVER then
	function Flow:subscribe(ply)
		if self:isSubscribed(ply) then return end
		
		table.insert(self._subs, ply)
		self:sendFullUpdateTo({ply})
	end
	function Flow:unsubscribe(ply)
		table.RemoveByValue(self._subs, ply)
	end
	function Flow:unsubscribeAll()
		table.Empty(self._subs)
	end
	
	function Flow:isSubscribed(ply)
		return table.HasValue(self._subs, ply)
	end
	function Flow:getSubscribers()
		return self._subs
	end
	
	-- Adds a PlayerInitialSpawn hook that subscribes user if fn(ply) returns true
	function Flow:addAutoSubscriberHook(fn)
		-- Add all current players instantly
		for _,p in pairs(player.GetAll()) do
			if fn == true or fn(p) then
				self:subscribe(p)
			end
		end
		
		local hookName = "Dataflow_autoSubscriber_" .. os.time() .. "_" .. math.random()
		
		-- Create selfWrapper so we don't prevent gc because of upvalue reference within PlayerInitialSpawn hook
		-- TODO does this even work? lol
		local selfWrapper = setmetatable({ selfRef = self }, {__mode = "kv"})
		
		hook.Add("PlayerInitialSpawn", hookName, function(ply)
			if fn == true or fn(ply) then
				selfWrapper.selfRef:subscribe(ply)
			end
		end)
		
		-- Create a newproxy to remove the hook above if flow gets gc'd
		local proxy = newproxy(true)
		self._gcProxy = proxy
		getmetatable(proxy).__gc = function()
			hook.Remove("PlayerInitialSpawn", hookName)
		end
	end
	
	-- Inspiration from nutscript https://github.com/Chessnut/NutScript/blob/master/gamemode/sh_util.lua#L581
	local function computeTableDelta(old, new)
		local out, del = {}, {}

		for k, v in pairs(new) do
			local oldval = old[k]

			if type(v) == "table" and type(oldval) == "table" then
				local out2, del2 = computeTableDelta(oldval, v)

				for k2,v2 in pairs(out2) do
					out[k] = out[k] or {}
					out[k][k2] = v2
				end
				for k2,v2 in pairs(del2) do
					del[k] = del[k] or {}
					del[k][k2] = v2
				end

			elseif oldval == nil or oldval ~= v then
				out[k] = v
			end
		end

		for k,v in pairs(old) do
			local newval = new[k]

			if type(v) == "table" and type(newval) == "table" then
				local out2, del2 = computeTableDelta(v, newval)

				for k2,v2 in pairs(out2) do
					out[k] = out[k] or {}
					out[k][k2] = v2
				end
				for k2,v2 in pairs(del2) do
					del[k] = del[k] or {}
					del[k][k2] = v2
				end
			elseif v ~= nil and newval == nil then
				del[k] = true
			end
		end

		return out, del
	end
	
	local function deepCopy(tbl)
		local copy = {}

		for k,v in pairs(tbl) do
			if type(v) == "table" then
				v = deepCopy(v)
			end
			copy[k] = v
		end

		return copy
	end
	
	-- Prepare table for sending
	-- This should always be deep copied version of the _raw reference
	function Flow:_prepareTable()
		return deepCopy(self._raw)
	end
	
	-- Sends the full table to given targets
	function Flow:sendFullUpdateTo(targets)
		local preparedTable = self._lastSentTable or self:_prepareTable()
		
		local function netWriter()
			-- send whole table
			net.WriteBool(true)
			net.WriteTable(preparedTable)
		end
		
		self._synchronizer.write(self, netWriter, targets)
	end
	
	-- Sends delta update to subscribed players
	function Flow:commit()
		assert(not not self._synchronizer)
		
		-- Prepare a table for sending
		local preparedTable = self:_prepareTable()
		
		-- Create delta
		local mod, del = computeTableDelta(self._lastSentTable or {}, preparedTable)
		
		local function netWriter()
			-- delta table
			net.WriteBool(false)
			net.WriteTable(mod)
			net.WriteTable(del)
		end
		
		-- Send
		self._synchronizer.write(self, netWriter, self:getSubscribers())
		
		self._lastSentTable = preparedTable
	end
end

if CLIENT then
	-- Reads delta/fullupdate data from net message
	function Flow:readNet()
		local isFullUpdate = net.ReadBool()
		
		local tbl = self._raw
		
		local mod, del
		
		if isFullUpdate then
			-- If full update, first empty the existing table
			table.Empty(tbl)
			
			mod, del = net.ReadTable(), {}
		else
			mod, del = net.ReadTable(), net.ReadTable()
		end
		
		-- Apply modifications recursively
		local function ApplyMod(mod, t, tid)
			for k,v in pairs(mod) do
				if type(v) == "table" then
					t[k] = t[k] or {}
					ApplyMod(v, t[k], k)
				else
					t[k] = v
				end
			end
		end
		ApplyMod(mod, tbl, "__main")

		-- Apply deletions recursively
		local function ApplyDel(del, t)
			for k,v in pairs(del) do
				if type(v) == "table" then
					t[k] = t[k] or {}
					ApplyDel(v, t[k])
				else
					t[k] = nil
				end
			end
		end
		ApplyDel(del, tbl)
		
		-- Emit change event
		self:_emitChangeEvent { isFullUpdate = isFullUpdate, modified = mod, deleted = del }
	end
	
	function Flow:_emitChangeEvent(e)
		for _,fn in pairs(self._changeListeners or {}) do
			fn(e)
		end
	end
	
	-- Registers a change listener
	-- 'fn' is called with { isFullUpdate: bool, modified: table, deleted: table } on change
	function Flow:onChange(fn)
		self._changeListeners = self._changeListeners or {}
		table.insert(self._changeListeners, fn)
	end
end

-- Public function API
local dataflow = {}

-- Dataflow functions

if SERVER then
	-- Create a new Flow object based on given table
	function dataflow.from(tbl, synchronizer)
		local flow = setmetatable({_subs = {}, _raw = tbl}, Flow)
		
		if synchronizer then
			flow:setSynchronizer(synchronizer)
		end
		
		return flow
	end
end

if CLIENT then
	function dataflow.fromSync(synchronizer)
		local flow = setmetatable({_raw = {}}, Flow)
		flow:setSynchronizer(synchronizer)
		return flow
	end
end

-- Default pluggable networking systems
if SERVER then
	util.AddNetworkString("dataflow_msg")
	
	-- A global (server-wide) synchronizer that identifies
	-- the Flow instance by a text key
	function dataflow.globalIdSynchronizer(key)
		return {
			write = function(flow, flowNetWriter, targets)
				net.Start("dataflow_msg")
				net.WriteString(key)
				flowNetWriter()
				net.Send(targets)
			end
		}
	end
end

if CLIENT then
	-- A weak table to store created globalID flows
	local globalIdFlows = setmetatable({}, {__mode = "v"})
	
	function dataflow.globalIdSynchronizer(key)
		return {
			onLoad = function(flow)
				globalIdFlows[key] = flow
			end
		}
	end
	
	net.Receive("dataflow_msg", function()
		local id = net.ReadString()
		local flow = globalIdFlows[id]
		
		if not flow then
			MsgN("[Dataflow] Warning: received globalidmsg '", id, "' without a clientside flow registered")
			return
		end
		
		flow:readNet()
	end)
end

return dataflow