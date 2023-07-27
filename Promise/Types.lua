export type callback = (promise: promise) -> any
export type statusCallback = (value: any) -> any
export type promise = {
	andThen: (self: promise, onFulfilled: statusCallback, onRejected: statusCallback?) -> promise,
	catch: (self: promise, onRejected: statusCallback) -> promise,
	finally: (self: promise, onSettled: statusCallback) -> promise,
	await: (self: promise) -> any,
	onCancel: (self: promise, onCancelled: callback) -> promise,

	reject: (self: promise, reason: any) -> promise,
	resolve: (self: promise, value: any) -> promise,
	cancel: (self: promise) -> nil,

	status: string,
	value: any
}

export type listener = {
	callback: statusCallback,
	status: string?
}

export type _promise = promise & {
	_listeners: {listener},
	_callback: callback,
	_thread: thread,
	_cancelled: boolean?,
	_onCancel: callback?,
	_addListener: (self: _promise, status: string?, callback: statusCallback | thread) -> boolean,
	_callListeners: (self: _promise) -> nil,
	_destroy: (self: _promise) -> nil
}

return nil