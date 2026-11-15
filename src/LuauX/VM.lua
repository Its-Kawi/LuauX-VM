local OP = require(script.Parent.OPs)

local NIL = { }
local SCOPE_PARENT = { }
local PACK_TAG = { }
local EMPTY_VALUES = table.freeze({ n = 0, tag = PACK_TAG })
local LOOP_BREAK = { }
local VM_RETURN = { }
local RUN_END = { }
local hooks = { }
local rawGet = rawget
local rawSet = rawset
local pack = table.pack
local unpack = unpack or table.unpack
local selectFunction = select
local typeOf = type
local toString = tostring
local tableCreate = table.create
local tableConcat = table.concat

local run

local function invoke(callback, arguments, count, multi)
	while callback ~= nil do
		local hooked = hooks[callback]
		if not hooked then break end
		callback = hooked
	end
	local returned = multi and pack(callback(unpack(arguments, 1, count)))
		or callback(unpack(arguments, 1, count))
	for i = 1, count do arguments[i] = nil end
	return returned
end

local function localAccess(c, name, value, action)
	if action == 1 then
		rawSet(c.scope, name, value == nil and NIL or value)
		return
	end
	local target = c.scope
	while target do
		local current = rawGet(target, name)
		if current ~= nil then
			if action == 0 then
				if current == NIL then return nil end
				return current
			end
			rawSet(target, name, value == nil and NIL or value)
			return
		end
		target = rawGet(target, SCOPE_PARENT)
	end
	if action == 0 then return c.env[name] end
	c.env[name] = value
end

local tbl, tg = "table", "tag"
local function collectExpressions(c, count, expandLast)
	local values, stack, sp = c.expressionValues, c.stack, c.sp
	local previous = values.n
	if count == 0 then
		for i = 1, previous do values[i] = nil end
		values.n, c.sp = 0, sp
		return values
	end
	local last = stack[sp]
	stack[sp] = nil
	sp -= 1
	local packed = expandLast and typeOf(last) == tbl and rawGet(last, tg) == PACK_TAG and last
	local expanded = packed and packed.n or 1
	local total = count - 1 + expanded
	for i = total + 1, previous do values[i] = nil end
	values.n = total
	if packed then
		for i = 1, expanded do values[count - 1 + i] = packed[i] end
	else
		values[count] = last
	end
	for i = count - 1, 1, -1 do
		values[i] = stack[sp]
		stack[sp] = nil
		sp -= 1
	end
	c.sp = sp
	return values
end

local function declareLocals(c, a, action)
	local values = collectExpressions(c, a.count, a.expandLast)
	for i = 1, #a.names do localAccess(c, a.names[i], values[i], action) end
end

local function assignTargets(c, a)
	local values = collectExpressions(c, a.count, a.expandLast)
	local targets, refs, stack = a.targets, c.assignReferences, c.stack
	local count = #targets
	for i = count, 1, -1 do
		if targets[i].kind == tbl then
			local key, object = stack[c.sp], stack[c.sp - 1]
			stack[c.sp], stack[c.sp - 1] = nil, nil
			c.sp -= 2
			local ref = i * 2
			refs[ref - 1], refs[ref] = object, key
		end
	end
	for i = 1, count do
		local target, value = targets[i], values[i]
		if target.kind == tbl then
			local ref = i * 2
			refs[ref - 1][refs[ref]] = value
			refs[ref - 1], refs[ref] = nil, nil
		else
			localAccess(c, target.name, value, 2)
		end
	end
end

local function tableSet(c, expand)
	local stack, sp = c.stack, c.sp
	local value, key, target = stack[sp], stack[sp - 1], stack[sp - 2]
	if expand and typeOf(value) == tbl and rawGet(value, tg) == PACK_TAG then
		for i = 1, value.n do target[key + i - 1] = value[i] end
	else
		target[key] = value
	end
	stack[sp], stack[sp - 1], stack[sp - 2] = nil, nil, nil
	c.sp = sp - 3
end


local function jump(c, targetIp, unwindCount, condition)
	local shouldJump = true
	if condition ~= nil then
		local value = c.stack[c.sp]
		c.stack[c.sp] = nil
		c.sp -= 1
		local truthy = value ~= false and value ~= nil
		shouldJump = condition and truthy or not condition and not truthy
	end
	if shouldJump then
		for _ = 1, unwindCount or 0 do
			c.scope = rawGet(c.scope, SCOPE_PARENT)
		end
		c.ip = targetIp
	end
end

local function genericFor(c, a)
	local values = collectExpressions(c, a.expressionCount, true)
	local names, bodyCode = a.names, a.body
	local loopValues = tableCreate(#names)
	local generator, iteratorState, control = values[1], values[2], values[3]

	while generator ~= nil do
		local hooked = hooks[generator]
		if not hooked then break end
		generator = hooked
	end

	local state, parentScope = c.state, c.scope
	if values.n == 1 then
		for v1, v2, v3, v4, v5, v6, v7, v8,
			v9, v10, v11, v12, v13, v14, v15, v16,
			v17, v18, v19, v20, v21, v22, v23, v24,
			v25, v26, v27, v28, v29, v30, v31, v32 in generator do
			loopValues[1], loopValues[2], loopValues[3], loopValues[4] = v1, v2, v3, v4
			loopValues[5], loopValues[6], loopValues[7], loopValues[8] = v5, v6, v7, v8
			loopValues[9], loopValues[10], loopValues[11], loopValues[12] = v9, v10, v11, v12
			loopValues[13], loopValues[14], loopValues[15], loopValues[16] = v13, v14, v15, v16
			loopValues[17], loopValues[18], loopValues[19], loopValues[20] = v17, v18, v19, v20
			loopValues[21], loopValues[22], loopValues[23], loopValues[24] = v21, v22, v23, v24
			loopValues[25], loopValues[26], loopValues[27], loopValues[28] = v25, v26, v27, v28
			loopValues[29], loopValues[30], loopValues[31], loopValues[32] = v29, v30, v31, v32

			local loopScope = { [SCOPE_PARENT] = parentScope }
			c.scope = loopScope
			for i = 1, #names do localAccess(c, names[i], loopValues[i], 1) end

			state.ip, state.sp, state.scope = 1, c.sp, loopScope
			local signal, result = run(state, bodyCode, 1, #bodyCode, true)
			c.sp, c.scope = state.sp, parentScope
			state.ip, state.sp, state.scope = c.ip, c.sp, parentScope
			if signal == VM_RETURN then return RUN_END, result end
			if signal == LOOP_BREAK then break end
		end
	else
		for v1, v2, v3, v4, v5, v6, v7, v8,
			v9, v10, v11, v12, v13, v14, v15, v16,
			v17, v18, v19, v20, v21, v22, v23, v24,
			v25, v26, v27, v28, v29, v30, v31, v32 in generator, iteratorState, control do
			loopValues[1], loopValues[2], loopValues[3], loopValues[4] = v1, v2, v3, v4
			loopValues[5], loopValues[6], loopValues[7], loopValues[8] = v5, v6, v7, v8
			loopValues[9], loopValues[10], loopValues[11], loopValues[12] = v9, v10, v11, v12
			loopValues[13], loopValues[14], loopValues[15], loopValues[16] = v13, v14, v15, v16
			loopValues[17], loopValues[18], loopValues[19], loopValues[20] = v17, v18, v19, v20
			loopValues[21], loopValues[22], loopValues[23], loopValues[24] = v21, v22, v23, v24
			loopValues[25], loopValues[26], loopValues[27], loopValues[28] = v25, v26, v27, v28
			loopValues[29], loopValues[30], loopValues[31], loopValues[32] = v29, v30, v31, v32

			local loopScope = { [SCOPE_PARENT] = parentScope }
			c.scope = loopScope
			for i = 1, #names do localAccess(c, names[i], loopValues[i], 1) end

			state.ip, state.sp, state.scope = 1, c.sp, loopScope
			local signal, result = run(state, bodyCode, 1, #bodyCode, true)
			c.sp, c.scope = state.sp, parentScope
			state.ip, state.sp, state.scope = c.ip, c.sp, parentScope
			if signal == VM_RETURN then return RUN_END, result end
			if signal == LOOP_BREAK then break end
		end
	end
end

local function genericForControl(c, a, isBreak)
	for _ = 1, a or 0 do
		c.scope = rawGet(c.scope, SCOPE_PARENT)
	end
	c.state.ip, c.state.sp, c.state.scope = c.ip, c.sp, c.scope
	if c.embedded and isBreak then return RUN_END, LOOP_BREAK end
	if c.embedded then return RUN_END end
end

local nmc = "numeric"
local function numericForPrep(c, name, exitIp)
	local stack, sp = c.stack, c.sp
	local step = stack[sp]; stack[sp] = nil; sp -= 1
	local limit = stack[sp]; stack[sp] = nil; sp -= 1
	local initial = stack[sp]; stack[sp] = nil; sp -= 1
	c.sp = sp
	local positive = step > 0
	if positive and initial <= limit or not positive and initial >= limit then
		local loopScope = c.scope
		c.scope = { [SCOPE_PARENT] = loopScope }
		rawSet(c.scope, name, initial)
		c.loopContexts[#c.loopContexts + 1] = {
			kind = nmc, name = name, loopScope = loopScope,
			value = initial, limit = limit, step = step, positive = positive,
		}
	else
		c.ip = exitIp
	end
end

local function numericForNext(c, targetIp)
	local contexts = c.loopContexts
	local context = contexts[#contexts]
	local value = context.value + context.step
	if context.positive and value <= context.limit or not context.positive and value >= context.limit then
		context.value = value
		c.scope = { [SCOPE_PARENT] = context.loopScope }
		rawSet(c.scope, context.name, value)
		c.ip = targetIp
	else
		c.scope = context.loopScope
		contexts[#contexts] = nil
	end
end

local function numericForCleanup(c)
	local contexts = c.loopContexts
	local context = contexts[#contexts]
	c.scope = context.loopScope
	contexts[#contexts] = nil
end

local function callInstruction(c, count, expandLast, nameCall, multi)
	local stack, args = c.stack, c.callArguments
	local callbackIndex = c.sp - count
	local callback, offset = stack[callbackIndex], nameCall and 1 or 0
	if nameCall then args[1] = stack[callbackIndex - 1] end
	for i = 1, count do
		args[i + offset] = stack[callbackIndex + i]
		stack[callbackIndex + i] = nil
	end
	stack[callbackIndex] = nil
	if nameCall then stack[callbackIndex - 1] = nil end
	c.sp = callbackIndex - 1 - offset
	local argumentCount = count + offset
	if count > 0 and expandLast then
		local value = args[argumentCount]
		if typeOf(value) == tbl and rawGet(value, tg) == PACK_TAG then
			args[argumentCount] = nil
			for i = 1, value.n do args[argumentCount + i - 1] = value[i] end
			argumentCount = count - 1 + value.n + offset
		end
	end
	local returned = invoke(callback, args, argumentCount, multi)
	if multi then returned.tag = PACK_TAG end
	c.sp += 1
	stack[c.sp] = returned
end

local function returnInstruction(c, count, expandLast)
	local returned
	if count == 0 then
		for i = 1, c.sp do c.stack[i] = nil end
		c.sp, returned = 0, EMPTY_VALUES
	elseif count == 1 and not expandLast then
		local value = c.stack[c.sp]
		c.stack[c.sp] = nil
		c.sp -= 1
		returned = { n = 1, value }
	else
		returned = collectExpressions(c, count, expandLast)
	end
	c.state.ip, c.state.sp, c.state.scope = c.ip, c.sp, c.scope
	return RUN_END, returned
end

local hs = "#"
local function makeClosure(c, prototype)
	local capturedScope, capturedEnvironment = c.scope, c.env
	local parameters, parameterCount = prototype.parameters, #prototype.parameters
	local prototypeCode, hasVararg, constants = prototype.code, prototype.vararg, c.state.constants
	local closure = function(...)
		local argumentCount = selectFunction(hs, ...)
		local extraCount = hasVararg and math.max(argumentCount - parameterCount, 0) or 0
		local functionVarargs = EMPTY_VALUES
		if extraCount > 0 then
			functionVarargs = tableCreate(extraCount)
			functionVarargs.n, functionVarargs.tag = extraCount, PACK_TAG
			for i = 1, extraCount do functionVarargs[i] = selectFunction(parameterCount + i, ...) end
		end
		local functionScope = { [SCOPE_PARENT] = capturedScope }
		local childState = {
			env = capturedEnvironment, code = prototypeCode, constants = constants,
			scope = functionScope,
			stack = { }, sp = 0, ip = 1, loopContexts = { },
			scratch = { callArguments = { }, expressionValues = { n = 0 }, assignReferences = { } },
			varargs = functionVarargs,
		}
		for i = 1, parameterCount do
			local value = selectFunction(i, ...)
			rawSet(functionScope, parameters[i], value == nil and NIL or value)
		end
		return run(childState)
	end
	c.sp += 1
	c.stack[c.sp] = closure
end

local str = "string"
local function interpolateValue(c)
	local value = c.stack[c.sp]
	c.stack[c.sp] = typeOf(value) == str and value or toString(value)
end

local null = ""
local function interpolateConcat(c, count)
	local stack, first = c.stack, c.sp - count + 1
	for i = first, c.sp do
		local value = stack[i]
		stack[i] = typeOf(value) == str and value or toString(value)
	end
	local result = tableConcat(stack, null, first, c.sp)
	for i = first, c.sp do stack[i] = nil end
	c.sp = first
	stack[first] = result
end

local function localHandler(action)
	return function(c, name)
		local value = c.stack[c.sp]
		c.stack[c.sp] = nil
		c.sp -= 1
		localAccess(c, name, value, action)
	end
end

local function localsHandler(action)
	return function(c, a) declareLocals(c, a, action) end
end

local function jumpHandler(condition)
	return function(c, a, b) jump(c, a, b, condition) end
end

local function callHandler(expandLast, nameCall, multi)
	return function(c, count) callInstruction(c, count, expandLast, nameCall, multi) end
end

local function returnHandler(expandLast)
	return function(c, count) return returnInstruction(c, count, expandLast) end
end

local function binaryHandler(operation)
	return function(c)
		local stack, sp = c.stack, c.sp
		stack[sp - 1] = operation(stack[sp - 1], stack[sp])
		stack[sp] = nil
		c.sp = sp - 1
	end
end

local function logicalHandler(isAnd)
	return function(c, targetIp)
		local stack, sp = c.stack, c.sp
		local value = stack[sp]
		local truthy = value ~= false and value ~= nil
		if truthy == isAnd then
			stack[sp] = nil
			c.sp = sp - 1
		else
			c.ip = targetIp
		end
	end
end

local minus = "-"
local nt = "not"

local instrs = {
	[OP.PUSH_CONSTANT] = function(c, a) c.sp += 1; c.stack[c.sp] = a end,
	[OP.PUSH_NAME] = function(c, a) c.sp += 1; c.stack[c.sp] = localAccess(c, a, nil, 0) end,
	[OP.PUSH_VARARG] = function(c) c.sp += 1; c.stack[c.sp] = c.varargs[1] end,
	[OP.PUSH_VARARGS] = function(c) c.sp += 1; c.stack[c.sp] = c.varargs end,
	[OP.DECLARE_LOCAL] = localHandler(1), [OP.SET_LOCAL] = localHandler(2),
	[OP.DECLARE_LOCALS] = localsHandler(1), [OP.SET_LOCALS] = localsHandler(2),
	[OP.ASSIGN_TARGETS] = assignTargets,
	[OP.POP] = function(c) c.stack[c.sp] = nil; c.sp -= 1 end,
	[OP.DUP] = function(c) c.sp += 1; c.stack[c.sp] = c.stack[c.sp - 1] end,
	[OP.DUP_PAIR] = function(c)
		local target, key = c.stack[c.sp - 1], c.stack[c.sp]
		c.sp += 1; c.stack[c.sp] = target
		c.sp += 1; c.stack[c.sp] = key
	end,
	[OP.UNARY] = function(c, op)
		local value = c.stack[c.sp]
		if op == minus then c.stack[c.sp] = -value
		elseif op == nt then c.stack[c.sp] = not value
		else c.stack[c.sp] = #value end
	end,
	[OP.ADD] = binaryHandler(function(left, right) return left + right end),
	[OP.SUBTRACT] = binaryHandler(function(left, right) return left - right end),
	[OP.MULTIPLY] = binaryHandler(function(left, right) return left * right end),
	[OP.DIVIDE] = binaryHandler(function(left, right) return left / right end),
	[OP.FLOOR_DIVIDE] = binaryHandler(function(left, right) return left // right end),
	[OP.MODULO] = binaryHandler(function(left, right) return left % right end),
	[OP.POWER] = binaryHandler(function(left, right) return left ^ right end),
	[OP.CONCAT] = binaryHandler(function(left, right) return left .. right end),
	[OP.EQUAL] = binaryHandler(function(left, right) return left == right end),
	[OP.NOT_EQUAL] = binaryHandler(function(left, right) return left ~= right end),
	[OP.LESS_THAN] = binaryHandler(function(left, right) return left < right end),
	[OP.LESS_EQUAL] = binaryHandler(function(left, right) return left <= right end),
	[OP.GREATER_THAN] = binaryHandler(function(left, right) return left > right end),
	[OP.GREATER_EQUAL] = binaryHandler(function(left, right) return left >= right end),
	[OP.AND] = logicalHandler(true),
	[OP.OR] = logicalHandler(false),
	[OP.TABLE_NEW] = function(c) c.sp += 1; c.stack[c.sp] = { } end,
	[OP.TABLE_GET] = function(c)
		local stack, sp = c.stack, c.sp
		local target, key = stack[sp - 1], stack[sp]
		stack[sp] = nil; stack[sp - 1] = target[key]
		c.sp = sp - 1
	end,
	[OP.TABLE_SET] = function(c) tableSet(c, false) end,
	[OP.TABLE_SET_EXPAND] = function(c) tableSet(c, true) end,
	[OP.JUMP] = jumpHandler(nil), [OP.JUMP_IF_FALSE] = jumpHandler(false), [OP.JUMP_IF_TRUE] = jumpHandler(true),
	[OP.GENERIC_FOR] = genericFor,
	[OP.BREAK] = function(c, a) return genericForControl(c, a, true) end,
	[OP.CONTINUE] = function(c, a) return genericForControl(c, a, false) end,
	[OP.NUMERIC_FOR_PREP] = numericForPrep,
	[OP.NUMERIC_FOR_NEXT] = numericForNext,
	[OP.NUMERIC_FOR_CLEANUP] = numericForCleanup,
	[OP.ENTER_SCOPE] = function(c) c.scope = { [SCOPE_PARENT] = c.scope } end,
	[OP.EXIT_SCOPE] = function(c)
		c.scope = rawGet(c.scope, SCOPE_PARENT)
	end,
	[OP.CALL] = callHandler(false, false, false),
	[OP.CALL_EXPAND] = callHandler(true, false, false),
	[OP.CALL_NAME] = callHandler(false, true, false),
	[OP.CALL_NAME_EXPAND] = callHandler(true, true, false),
	[OP.CALL_MULTI] = callHandler(false, false, true),
	[OP.CALL_MULTI_EXPAND] = callHandler(true, false, true),
	[OP.CALL_NAME_MULTI] = callHandler(false, true, true),
	[OP.CALL_NAME_MULTI_EXPAND] = callHandler(true, true, true),
	[OP.RETURN] = returnHandler(false), [OP.RETURN_EXPAND] = returnHandler(true),
	[OP.CLOSURE] = makeClosure,
	[OP.INTERP_VALUE] = interpolateValue,
	[OP.INTERP_CONCAT] = interpolateConcat,
}

local pc = OP.PUSH_CONSTANT
run = function(state, codeOverride, startIp, endIp, embedded)
	local scratch, code, constants = state.scratch, codeOverride or state.code, state.constants
	local codeLength = endIp or #code
	local c = {
		state = state, stack = state.stack, scope = state.scope,
		loopContexts = state.loopContexts, env = state.env, varargs = state.varargs,
		ip = startIp or state.ip, sp = state.sp, embedded = embedded,
		callArguments = scratch.callArguments, expressionValues = scratch.expressionValues,
		assignReferences = scratch.assignReferences,
	}
	while c.ip <= codeLength do
		local encoded = code[c.ip]
		c.ip += 1
		local opcode, a, b = encoded[1], encoded[2], encoded[3]
		if opcode == pc and constants then a = if a == 0 then nil else constants[a] end
		local instr = instrs[opcode]
		local outcome, payload = instr(c, a, b)
		if outcome == RUN_END then
			if payload == LOOP_BREAK then return LOOP_BREAK end
			if payload == nil then return end
			if embedded then return VM_RETURN, payload end
			return unpack(payload, 1, payload.n)
		end
	end
	state.ip, state.sp, state.scope = c.ip, c.sp, c.scope
	if embedded or c.sp == 0 then return end
	return c.stack[c.sp]
end

return {
	Hooks = hooks,
	run = function(program, globals, ...)
		local varargs = pack(...)
		varargs.tag = PACK_TAG
		local scope = { }
		return run({
			env = globals or { }, code = program.code, constants = program.constants, scope = scope,
			stack = { }, sp = 0, ip = 1, loopContexts = { },
			scratch = { callArguments = { }, expressionValues = { n = 0 }, assignReferences = { } },
			varargs = varargs,
		})
	end
}
