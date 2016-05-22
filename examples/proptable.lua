-- Proptable adds each created prop_physics a data flow table which can be freely edited
-- on serverside and propagates updates to all players

local synchronizer = {
	write = function(flow, flowNetWriter, targets)
		net.Start("dataflow_ex_proptbl")
		
		-- Note: the entity is crudely stored in Flow object
		net.WriteEntity(flow.myProp)
		
		flowNetWriter()
		net.Send(targets)
	end
}

if SERVER then
	util.AddNetworkString("dataflow_ex_proptbl")
	
	hook.Add("OnEntityCreated", "Dataflow_ex_propTable", function(ent)
		if ent:GetClass() == "prop_physics" then
			-- Prop was just spawned so it might not be visible on clients, so wait a bit
			-- This also does not account for props spawned outside player's PVS
			-- As you can see, this usecase is not the recommended or the usual usecase for dataflow
			timer.Simple(1, function()
				local flow = dataflow.from({}, synchronizer)
				
				ent.propFlow = flow -- store flow in the prop so it does not get garbage collected
				flow.myProp = ent -- store prop in flow so that it can be accessed in the synchronizer
				
				-- Subscribe everyone automatically
				flow:addAutoSubscriberHook(true)
				
				-- an example key stored in the flow table
				flow:getTable().spawnTime = CurTime()
				flow:commit()
			end)
		end
	end)
	hook.Add("EntityRemoved", "Dataflow_ex_propTable", function(ent)
		if ent:GetClass() == "prop_physics" and ent.propFlow then
			ent.propFlow:unsubscribeAll()
		end
	end)
end

if CLIENT then
	net.Receive("dataflow_ex_proptbl", function()
		local e = net.ReadEntity()
		
		if not e.propFlow then
			e.propFlow = dataflow.fromSync(synchronizer)
			e.propFlow:onChange(function()
				print(e, " prop flow changed: ", table.ToString(e.propFlow:getTable()))
			end)
		end
		
		e.propFlow:readNet()
	end)
end