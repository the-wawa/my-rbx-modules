local Types = require( script:WaitForChild("Types") )
local Connection = require( script:WaitForChild("Connection") )

local Signal = {}
Signal.__index = Signal

function Signal.new(): Types.Signal
	local SignalObject = setmetatable({
		Connections = {}
	}, Signal)
	
	return SignalObject
end

function Signal:Connect(Callback: Types.Callback)
	local self: Types._Signal = self
	if self.Destroyed then
		return
	end
	
	local ConnectionObject = Connection.new(self, Callback)
	table.insert(self.Connections, ConnectionObject)
	
	return ConnectionObject
end

function Signal:Once(Callback: Types.Callback)
	local self: Types._Signal = self
	if self.Destroyed then
		return
	end
	
	local ConnectionObject = Connection.new(self, Callback, true)
	table.insert(self.Connections, ConnectionObject)

	return ConnectionObject
end

function Signal:Wait()
	local self: Types._Signal = self
	if self.Destroyed then
		return
	end
	
	local Thread = coroutine.running()
	
	local ConnectionObject = Connection.new(self, Thread, true)
	table.insert(self.Connections, ConnectionObject)
	
	return coroutine.yield()
end

function Signal:Fire(...)
	local self: Types._Signal = self
	if self.Destroyed then
		return
	end
	
	for _, Connection in self.Connections do
		local Callback = Connection.Callback
		task.spawn(Callback, ...)

		if typeof(Callback) == "thread" or Connection.Once then
			Connection:Disconnect()
		end
	end
end

function Signal:Destroy()
	local self: Types._Signal = self
	if self.Destroyed then
		return
	end
	
	for _, Connection in self.Connections do
		Connection:Disconnect()
	end
	
	table.clear(self.Connections)
	table.clear(self)
	self.Destroyed = true
end

return Signal