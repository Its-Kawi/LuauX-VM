local Compiler = require(script.Compiler)
local OP = require(script.OPs)
local VM = require(script.VM)

local LuauX = {
	Hooks = VM.Hooks,
	OPs = OP
}

function LuauX.tokenize(source, internStrings)
	return Compiler.tokenize(source, internStrings)
end

function LuauX.compile(source, options)
	return Compiler.compile(source, options or { })
end

local function getEnv()
	return getfenv()
end

local function VMF(compiled, env)
	return function(...)
		return VM.run(compiled, env, ...)
	end
end

function LuauX.load(code, options)
	options = options or { }

	local compiled
	if type(code) == "string" then
		compiled = LuauX.compile(code, options)
	elseif type(code) == "table" and type(code.code) == "table" then
		compiled = code
	else
		error("LuauX.load expects source text or a compiled LuauX program", 2)
	end

	return VMF(compiled, options.Environment or options.Globals or getEnv())
end

function LuauX.loadstring(source, chunkName, env)
	local t = type(source)
	if t ~= "string" and t ~= "number" then error(t ~= nil and ("invalid argument #1 to 'loadstring' (string expected, got %s)"):format(t) or "missing argument #1 to 'loadstring' (string expected)", 0) end
	source = tostring(source)

	t = type(chunkName)
	if t ~= "string" and t ~= "number" and t ~= "nil" then error(("invalid argument #2 to 'loadstring' (string expected, got %s)"):format(t), 0) end
	chunkName = chunkName and tostring(chunkName) or nil

	local options = { ChunkName = chunkName, Environment = env or getEnv() }
	local s, e = pcall(LuauX.compile, source, { ChunkName = chunkName })
	if not s then
		return false, e
	end

	return VMF(e, options.Environment)
end

function LuauX.run(code, options, ...)
	return LuauX.load(code, type(options) == "string" and { ChunkName = options, Environment = getEnv() } or (type(options) == "table" or type(options) == "userdata") and { Environment = options } or options)(...)
end

return setmetatable(LuauX, {
	__call = function(_, ...)
		return LuauX.loadstring(...)
	end,
	__metatable = "LuauX",
	__index = LuauX
})
