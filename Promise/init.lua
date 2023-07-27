local Types = require( script:WaitForChild("Types") )

local UNKNOWN_ELEMENT = "Unknown entry in list of Promises passed to %s at index %d"
local PROMISE_EXCEPTION = "An exception has been caught while executing Promise:\n\n%s\n\n%s"
local BAD_ARGUMENT = "Bad argument #%d to %q: expected %s, got %s"

local PromiseStatus = {
	Pending = "pending",
	Fulfilled = "fulfilled",
	Rejected = "rejected"
}

local function assert(value: any, errorMessage: string, ...)
	if value then
		return value
	end
	
	error( string.format(errorMessage, ...) )
end

local function assertType(value: any, argNum: number, funcName: string, expectedType: string): boolean
	local valueType = typeof(value)
	if valueType ~= expectedType then
		error( string.format(BAD_ARGUMENT, argNum, funcName, expectedType, valueType), 2 )
	end

	return true
end

local function isPromise(promise: any)
	return type(promise) == "table" and getmetatable(promise) == "Promise"
end

local function checkPromiseList(promises: {Types.promise}, funcName: string)
	for index, promise in promises do
		assert(isPromise(promise), UNKNOWN_ELEMENT, funcName, index)
	end
end

local function doErrorHandling(errorMessage: string)
	return string.format( PROMISE_EXCEPTION, errorMessage, debug.traceback(nil, 3) )
end

local function runPromise(promise: Types._promise)
	return {xpcall(promise._callback, doErrorHandling, promise)}
end

local Promise = {}
Promise.__metatable = "Promise"
Promise.__type = "Promise"
Promise.__index = {}

-- // PUBLIC API
function Promise.new(callback: Types.callback): Types.promise
	assertType(callback, 1, "Promise.new", "function")

	local promiseObj = Promise._new(callback)
	promiseObj._thread = task.spawn(runPromise, promiseObj)

	return promiseObj
end

function Promise.all(promises: {Types.promise}): Types.promise
	assertType(promises, 1, "Promise.all", "table")
	checkPromiseList(promises, "Promise.all")

	local promiseCount = #promises
	if promiseCount == 0 then
		return Promise.resolved
	end

	return Promise.new(function(mainPromise)
		local resolves, resolveCount = {}, 0

		for index, promise in promises do
			promise:andThen(function(value: any)
				resolves[index] = value
				resolveCount += 1
				if resolveCount < promiseCount then
					return
				end

				mainPromise:resolve(resolves)
			end, function(reason: any)
				mainPromise:reject(reason)
			end)
		end
	end):onCancel(function()
		for _, promise in promises do
			promise:cancel()
		end
	end)
end

function Promise.allSettled(promises: {Types.promise}): Types.promise
	assertType(promises, 1, "Promise.allSettled", "table")
	checkPromiseList(promises, "Promise.allSettled")

	local promiseCount = #promises
	if promiseCount == 0 then
		return Promise.resolved
	end

	return Promise.new(function(mainPromise)
		local settled, settleCount = {}, 0

		for index, promise in promises do
			promise:finally(function(value: any)
				local settleObject = {status = promise.status}
				local propName = if settleObject.status == PromiseStatus.Rejected then "reason" else "value"
				settleObject[propName] = value

				settled[index] = settleObject
				settleCount += 1

				if settleCount < promiseCount then
					return
				end

				mainPromise:resolve(settled)
			end)
		end
	end):onCancel(function()
		for _, promise in promises do
			promise:cancel()
		end
	end)
end

function Promise.race(promises: {Types.promise}): Types.promise
	assertType(promises, 1, "Promise.race", "table")
	checkPromiseList(promises, "Promise.race")

	local promiseCount = #promises
	if promiseCount == 0 then
		return Promise.resolved
	end

	return Promise.new(function(mainPromise)
		for index, promise in promises do
			promise:andThen(function(value: any)
				mainPromise:resolve(value)
			end, function(reason: any)
				mainPromise:reject(reason)
			end)
		end
	end):onCancel(function()
		for _, promise in promises do
			promise:cancel()
		end
	end)
end

function Promise.any(promises: {Types.promise}): Types.promise
	assertType(promises, 1, "Promise.any", "table")
	checkPromiseList(promises, "Promise.any")

	local promiseCount = #promises
	if promiseCount == 0 then
		return Promise.rejected
	end

	return Promise.new(function(mainPromise)
		local rejected, rejectCount = {}, 0

		for index, promise in promises do
			promise:andThen(function(value: any)
				mainPromise:resolve(value)
			end, function(reason: any)
				rejected[index] = reason
				rejectCount += 1
				if rejectCount < promiseCount then
					return
				end

				mainPromise:reject(rejected)
			end)
		end
	end):onCancel(function()
		for _, promise in promises do
			promise:cancel()
		end
	end)
end

function Promise.__index.andThen(self: Types._promise, onFulfilled: Types.statusCallback, onRejected: Types.statusCallback?)
	assertType(onFulfilled, 1, "Promise:andThen", "function")
	if onRejected ~= nil then
		assertType(onRejected, 2, "Promise:andThen", "function")
	end

	if self.status ~= PromiseStatus.Pending then
		if self.status == PromiseStatus.Fulfilled then
			task.spawn(onFulfilled, self.value)
		elseif self.status == PromiseStatus.Rejected and onRejected then
			task.spawn(onRejected, self.value)
		end

		return self
	end

	self:_addListener(PromiseStatus.Fulfilled, onFulfilled)
	if onRejected then
		self:_addListener(PromiseStatus.Rejected, onRejected)
	end
	
	return self
end

function Promise.__index.catch(self: Types._promise, onRejected: Types.statusCallback)
	assertType(onRejected, 1, "Promise:catch", "function")

	if self.status ~= PromiseStatus.Pending then
		if self.status == PromiseStatus.Rejected then
			task.spawn(onRejected, self.value)
		end

		return self
	end

	self:_addListener(PromiseStatus.Rejected, onRejected)
	return self
end

function Promise.__index.finally(self: Types._promise, onSettled: Types.statusCallback)
	assertType(onSettled, 1, "Promise:finally", "function")

	if self.status ~= PromiseStatus.Pending then
		task.spawn(onSettled, self.value)
		return self
	end

	self:_addListener(nil, onSettled)
	return self
end

function Promise.__index.await(self: Types._promise)
	local thread = coroutine.running()
	if not self:_addListener(nil, thread) then
		if self.status == PromiseStatus.Rejected then
			error("Awaited promise has been rejected:\n" .. self.value, 2)
		end
		
		return self.value
	end
	
	local value = coroutine.yield()
	if self.status == PromiseStatus.Rejected then
		error("Awaited promise has been rejected:\n" .. value, 2)
	end
	
	return value
end

function Promise.__index.onCancel(self: Types._promise, callback: Types.callback)
	assertType(callback, 1, "Promise:onCancel", "function")
	self._onCancel = callback
	
	return self
end

function Promise.__index.resolve(self: Types._promise, value: any)
	if self.status ~= PromiseStatus.Pending then
		return self
	end

	self.value = value
	self.status = PromiseStatus.Fulfilled
	self:_callListeners()
	
	return self
end

function Promise.__index.reject(self: Types._promise, reason: any)
	if self.status ~= PromiseStatus.Pending then
		return self
	end

	self.value = reason
	self.status = PromiseStatus.Rejected
	self:_callListeners()
	
	return self
end

function Promise.__index.cancel(self: Types._promise)
	if self._onCancel then
		task.spawn(self._onCancel, self)
	end
	
	self:_destroy()
	
	return self
end

-- // INTERNAL
function Promise._new(callback: Types.callback?): Types.promise
	local promiseObj = setmetatable({
		status = PromiseStatus.Pending,
		_listeners = {},
		_callback = callback
	}, Promise)

	return promiseObj
end

function Promise.__index._callListeners(self: Types._promise)
	local promiseStatus = self.status
	
	-- execute the andThen/catch pending callbacks
	for _, listener in self._listeners do
		if not listener.status or listener.status ~= promiseStatus then
			continue
		end
		
		if typeof(listener.callback) == "thread" and coroutine.status(listener.callback) ~= "suspended" then
			continue
		end

		task.spawn(listener.callback, self.value)
	end
	
	-- execute the finally callbacks lastly since that's the intended behavior
	for _, listener in self._listeners do
		if listener.status then
			continue
		end

		if typeof(listener.callback) == "thread" and coroutine.status(listener.callback) ~= "suspended" then
			continue
		end

		task.spawn(listener.callback, self.value)
	end
	
	table.clear(self._listeners)
	self:cancel()
end

function Promise.__index._addListener(self: Types._promise, status: string?, callback: Types.statusCallback | thread): boolean
	if self.status ~= PromiseStatus.Pending then
		return false
	end
	
	for _, listener in self._listeners do
		if listener.callback == callback then
			return false
		end
	end

	table.insert(self._listeners, {
		status = status,
		callback = callback
	})
	
	return true
end

function Promise.__index._destroy(self: Types._promise)
	if self._cancelled then
		return
	end

	self._cancelled = true
	if self.status == PromiseStatus.Pending then
		self.status = PromiseStatus.Rejected
		self.value = "Promise cancelled mid execution"
		self:_callListeners()
	end
	
	if self._thread and coroutine.status(self._thread) == "suspended" then
		task.cancel(self._thread)
	end
end

-- // STATIC PROMISES
Promise.resolved = Promise._new():resolve()
Promise.rejected = Promise._new():reject()

return Promise