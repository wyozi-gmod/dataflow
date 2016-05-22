## dataflow

Dataflow is a Garry's Mod addon intended to make synchronization of non-primitives easier.

__Example usecases:__
- Inventory system
- Global data that all players should have but cannot be stored in a shared `.lua` file because it's loaded dynamically.

### Example code

```lua
local dataflow = include("dataflow.lua")

if SERVER then
	local myGlobalData = {}
	
	-- Create a new Flow using myGlobalData as the backing table
	local flow = dataflow.from(myGlobalData)
	
	-- Use a globalIdSynchronizer, which is a bundled data synchronizer
	-- that uses net messages with a string identifier
	flow:setSynchronizer(dataflow.globalIdSynchronizer("test"))
	
	-- Subscribe all newly spawned players to our Flow
	-- You could also pass a function that accepts a player parameter and returns whether they should be subscribed
	flow:addAutoSubscriberHook(true)
	
	-- Set key in table and update to all subscribers
	myGlobalData.hello = "world"
	flow:commit()
end

if CLIENT then
	-- Create a Flow using synchronizer with same key as serverside Flow
	local flow = dataflow.fromSync(dataflow.globalIdSynchronizer("test"))
	
	-- Every time a change happens, print the new table
	flow:onChange(function(e)
		print("flow change!")
		PrintTable(flow:getTable())
	end)
end
```

### Problems in nettable solved by dataflow
- Insufficient control of who is receiving updates
	- For example you could not unsubscribe from a nettable
	- ✓ Solved by having explicit control of subscriptions
- Being closely tied to nettable's networking system caused problems
	- For example creating entity- specific nettable was hard
	- ✓ Solved by making networking pluggable
- Nettable created the networked table, which makes networking existing tables hard
	- ✓ Solved by making wrapping existing tables the default
- Nettable has no way to modify the table before sending
	- This might force you to create two tables: one for actual usage and one for nettable
	- ✓ Solved by adding `map` function support