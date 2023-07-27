export type Callback = (...any) -> ...any
export type Signal = {
	Connect: (self: Signal, Callback: Callback) -> Connection,
	Once: (self: Signal, Callback: Callback) -> Connection,
	Wait: (self: Signal) -> ...any,
	Fire: (self: Signal, ...any) -> nil,
	Destroy: (self: Signal) -> nil
}

export type _Signal = Signal & {
	Connections: {_Connection},
	Destroyed: boolean?
}

export type Connection = {
	Disconnect: (self: Connection) -> nil
}

export type _Connection = Connection & {
	Callback: Callback | thread,
	Signal: _Signal,
	Once: boolean?,
	Connected: boolean?
}

return nil