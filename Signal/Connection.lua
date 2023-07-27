local Types = require( script.Parent:WaitForChild("Types") )

local Connection = {}
Connection.__index = Connection

function Connection.new(Signal: Types.Signal, Callback: Types.Callback | thread, Once: boolean?): Types.Connection
	local ConnectionObject = setmetatable({
		Callback = Callback,
		Once = Once,
		Signal = Signal,
		Connected = true
	}, Connection)
	
	return ConnectionObject
end

function Connection:Disconnect()
	local self: Types._Connection = self
	if not self.Connected then
		return
	end
	
	local Index = table.find(self.Signal.Connections, self)
	if Index then
		table.remove(self.Signal.Connections, Index)
	end
	
	table.clear(self)
	self.Connected = false
end

return Connection