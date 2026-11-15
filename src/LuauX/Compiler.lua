local OP = require(script.Parent.OPs)

local callMultiOpcodes = {
	[OP.CALL] = OP.CALL_MULTI,
	[OP.CALL_EXPAND] = OP.CALL_MULTI_EXPAND,
	[OP.CALL_NAME] = OP.CALL_NAME_MULTI,
	[OP.CALL_NAME_EXPAND] = OP.CALL_NAME_MULTI_EXPAND,
}

local callSingleOpcodes = {
	[OP.CALL_MULTI] = OP.CALL,
	[OP.CALL_MULTI_EXPAND] = OP.CALL_EXPAND,
	[OP.CALL_NAME_MULTI] = OP.CALL_NAME,
	[OP.CALL_NAME_MULTI_EXPAND] = OP.CALL_NAME_EXPAND,
}

local callOpcodes = {
	[OP.CALL] = true,
	[OP.CALL_EXPAND] = true,
	[OP.CALL_NAME] = true,
	[OP.CALL_NAME_EXPAND] = true,
	[OP.CALL_MULTI] = true,
	[OP.CALL_MULTI_EXPAND] = true,
	[OP.CALL_NAME_MULTI] = true,
	[OP.CALL_NAME_MULTI_EXPAND] = true,
}

local Compiler = {}
Compiler.__index = Compiler

local Lexer = {}
Lexer.__index = Lexer

local simpleStringEscapes = {
	[97] = "\a",
	[98] = "\b",
	[102] = "\f",
	[110] = "\n",
	[114] = "\r",
	[116] = "\t",
	[118] = "\v",
	[92] = "\\",
	[39] = "'",
	[34] = '"',
}

local stringChar = string.char
local stringByte = string.byte
local stringSub = string.sub
local stringFind = string.find
local stringGsub = string.gsub
local utf8Char = utf8.char
local tableCreate = table.create

local function raiseSyntaxError(line, column, message, chunkname)
	local detail = tostring(line or 1) .. ": " .. message
	error(if chunkname then chunkname .. ":" .. detail else detail, 0)
end

local keywords = {
	["local"]=true, ["function"]=true, ["end"]=true,
	["if"]=true, ["then"]=true, ["else"]=true, ["elseif"]=true,
	["while"]=true, ["do"]=true, ["return"]=true, ["true"]=true,
	["false"]=true, ["nil"]=true, ["and"]=true, ["or"]=true,
	["not"]=true,
	["for"]=true, ["in"]=true, ["repeat"]=true, ["until"]=true,
	["break"]=true,
}

local operators = {
	"...", "//=", "..=", "+=", "-=", "*=", "/=", "%=", "^=",
	"==", "~=", "<=", ">=", "//", "..", "::", "->",
	"&", "@",
	"+", "-", "*", "/", "%", "^", "#", "=", "<", ">", "?", "|",
	"(", ")", "{", "}", "[", "]", ".", ",", ";", ":",
}

local operatorsByFirstByte = {}
for _, operator in ipairs(operators) do
	local firstByte = stringByte(operator, 1)
	local candidates = operatorsByFirstByte[firstByte]
	if candidates == nil then
		candidates = {}
		operatorsByFirstByte[firstByte] = candidates
	end
	candidates[#candidates + 1] = {
		value = operator,
		length = #operator,
		secondByte = stringByte(operator, 2),
		thirdByte = stringByte(operator, 3),
	}
end

function Lexer.new(source, internStrings, chunkname)
	return setmetatable({
		source = source,
		chunkname = chunkname,
		pos = 1,
		line = 1,
		column = 1,
		tokens = tableCreate(math.min(math.floor(#source / 3), 4096)),
		stringPool = if internStrings == true then {} else nil,
		sourceLength = #source,
		typeMode = "nonstrict",
	}, Lexer)
end

function Lexer:peekByte(offset)
	return stringByte(self.source, self.pos + (offset or 0))
end

function Lexer:advanceByte()
	local byte = stringByte(self.source, self.pos)
	if byte == nil then
		return nil
	end

	self.pos += 1
	if byte == 10 then
		self.line += 1
		self.column = 1
	else
		self.column += 1
	end
	return byte
end

function Lexer:advanceTo(position)
	local source = self.source
	local start = self.pos
	if position <= start then
		return
	end

	local scan = start
	local lastNewline = nil
	while true do
		local newline = stringFind(source, "\n", scan, true)
		if newline == nil or newline >= position then
			break
		end
		self.line += 1
		lastNewline = newline
		scan = newline + 1
	end

	self.pos = position
	if lastNewline then
		self.column = position - lastNewline
	else
		self.column += position - start
	end
end

function Lexer:emit(kind, value, line, column, raw)
	local stringPool = self.stringPool
	if stringPool and (kind == "name" or kind == "string" or kind == "interp_text") then
		local cached = stringPool[value]
		if cached ~= nil then
			value = cached
		else
			stringPool[value] = value
		end
	end

	local token = {
		kind = kind,
		value = value,
		raw = raw,
		line = line,
	}
	if self.chunkname then token.sourceName = self.chunkname end
	self.tokens[#self.tokens + 1] = token
end

function Lexer:longBracketLevel()
	if self:peekByte() ~= 91 then
		return nil
	end

	local cursor = self.pos + 1
	while stringByte(self.source, cursor) == 61 do
		cursor += 1
	end
	if stringByte(self.source, cursor) ~= 91 then
		return nil
	end

	return stringSub(self.source, self.pos + 1, cursor - 1), cursor
end

function Lexer:readLongString()
	local line, column = self.line, self.column
	local equals, openingEnd = self:longBracketLevel()
	if equals == nil then
		raiseSyntaxError(line, column, "Invalid long string delimiter", self.chunkname)
	end

	self:advanceTo(openingEnd + 1)

	if self:peekByte() == 13 then
		self:advanceByte()
		if self:peekByte() == 10 then
			self:advanceByte()
		end
	elseif self:peekByte() == 10 then
		self:advanceByte()
	end

	local contentStart = self.pos
	local closing = "]" .. equals .. "]"
	local closingStart = stringFind(self.source, closing, contentStart, true)
	if closingStart then
		local value = stringSub(self.source, contentStart, closingStart - 1)
		self:advanceTo(closingStart + #closing)
		self:emit("string", value, line, column)
		return
	end

	self:advanceTo(self.sourceLength + 1)
	raiseSyntaxError(line, column, "Malformed string; did you forget to finish it?", self.chunkname)
end

function Lexer:skipLongComment()
	local equals, openingEnd = self:longBracketLevel()
	if equals == nil then
		return false
	end

	self:advanceTo(openingEnd + 1)

	local closing = "]" .. equals .. "]"
	local closingStart = stringFind(self.source, closing, self.pos, true)
	if closingStart then
		self:advanceTo(closingStart + #closing)
		return true
	end

	self:advanceTo(self.sourceLength + 1)
	raiseSyntaxError(self.line, self.column, "Malformed comment; did you forget to finish it?", self.chunkname)
end

function Lexer:skipSpace()
	local source = self.source
	local sourceLength = self.sourceLength

	while true do
		local start = self.pos
		local cursor = stringFind(source, "%S", start) or (sourceLength + 1)
		if cursor > start then
			self:advanceTo(cursor)
		end

		if self:peekByte() == 45 and self:peekByte(1) == 45 then
			if #self.tokens == 0 then
				local commentStart = self.pos + 2
				local commentEnd = stringFind(source, "\n", commentStart, true) or (sourceLength + 1)
				local commentText = stringSub(source, commentStart, commentEnd - 1)
				local directive = commentText:match("^%s*!([%a]+)%s*$")
				if directive == "strict" or directive == "nonstrict" or directive == "nocheck" then
					self.typeMode = directive
				end
			end
			self:advanceByte()
			self:advanceByte()
			if not self:skipLongComment() then
				local newline = stringFind(source, "\n", self.pos, true)
				self:advanceTo(newline or (sourceLength + 1))
			end
		else
			return
		end
	end
end

local function hexDigitValue(byte)
	if byte == nil then
		return nil
	elseif byte >= 48 and byte <= 57 then
		return byte - 48
	elseif byte >= 65 and byte <= 70 then
		return byte - 55
	elseif byte >= 97 and byte <= 102 then
		return byte - 87
	end
	return nil
end

function Lexer:readEscapeSequence(interpolated)
	local escapedByte = self:advanceByte()
	if escapedByte == nil then
		raiseSyntaxError(self.line, self.column, "Malformed string escape sequence", self.chunkname)
	end

	if escapedByte == 10 then
		return "\n"
	elseif escapedByte == 13 then
		if self:peekByte() == 10 then
			self:advanceByte()
		end
		return "\n"
	end

	if interpolated and (escapedByte == 96 or escapedByte == 123) then
		return stringChar(escapedByte)
	end

	local simple = simpleStringEscapes[escapedByte]
	if simple ~= nil then
		return simple
	elseif escapedByte == 122 then
		while true do
			local byte = self:peekByte()
			if byte == 32 or byte == 9 or byte == 10 or byte == 11 or byte == 12 or byte == 13 then
				self:advanceByte()
			else
				break
			end
		end
		return ""
	elseif escapedByte == 120 then
		local first = hexDigitValue(self:peekByte())
		local second = hexDigitValue(self:peekByte(1))
		if first == nil or second == nil then
			raiseSyntaxError(self.line, self.column, "Expected two hexadecimal digits after \\x", self.chunkname)
		end
		self:advanceByte()
		self:advanceByte()
		return stringChar(first * 16 + second)
	elseif escapedByte == 117 and self:peekByte() == 123 then
		self:advanceByte()
		local codepoint = 0
		local digitCount = 0
		while true do
			local digit = hexDigitValue(self:peekByte())
			if digit == nil then
				break
			end
			digitCount += 1
			if digitCount > 8 then
				raiseSyntaxError(self.line, self.column, "Invalid Unicode escape", self.chunkname)
			end
			codepoint = codepoint * 16 + digit
			self:advanceByte()
		end
		if digitCount == 0 or self:peekByte() ~= 125 then
			raiseSyntaxError(self.line, self.column, "Invalid Unicode escape", self.chunkname)
		end
		self:advanceByte()
		if codepoint > 0x10FFFF or (codepoint >= 0xD800 and codepoint <= 0xDFFF) then
			raiseSyntaxError(self.line, self.column, "Invalid Unicode code point", self.chunkname)
		end
		return utf8Char(codepoint)
	elseif escapedByte == 117 then
		raiseSyntaxError(self.line, self.column, "Invalid Unicode escape", self.chunkname)
	elseif escapedByte >= 48 and escapedByte <= 57 then
		local value = escapedByte - 48
		for _ = 1, 2 do
			local byte = self:peekByte()
			if byte ~= nil and byte >= 48 and byte <= 57 then
				value = value * 10 + byte - 48
				self:advanceByte()
			else
				break
			end
		end
		if value > 255 then
			raiseSyntaxError(self.line, self.column, "Decimal escape is out of range", self.chunkname)
		end
		return stringChar(value)
	end

	if interpolated then
		return stringChar(escapedByte)
	end

	raiseSyntaxError(self.line, self.column, "Invalid escape sequence \\" .. stringChar(escapedByte), self.chunkname)
end

function Lexer:readString(quote)
	local line, column = self.line, self.column
	local quoteByte = stringByte(quote, 1)
	local source = self.source
	self:advanceByte()

	local rawStart = self.pos
	local cursor = rawStart
	local chunkStart = rawStart
	local output = nil

	while true do
		local byte = stringByte(source, cursor)
		if byte == nil or byte == 10 or byte == 13 then
			raiseSyntaxError(line, column, "Malformed string; did you forget to finish it?", self.chunkname)
		elseif byte == quoteByte then
			local raw = stringSub(source, rawStart, cursor - 1)
			local value
			if output == nil then
				value = raw
			else
				if cursor > chunkStart then
					output[#output + 1] = stringSub(source, chunkStart, cursor - 1)
				end
				value = table.concat(output)
			end
			self:advanceTo(cursor + 1)
			self:emit("string", value, line, column, raw)
			return
		elseif byte == 92 then
			output = output or {}
			if cursor > chunkStart then
				output[#output + 1] = stringSub(source, chunkStart, cursor - 1)
			end
			self:advanceTo(cursor + 1)
			output[#output + 1] = self:readEscapeSequence(false)
			cursor = self.pos
			chunkStart = cursor
		else
			cursor += 1
		end
	end
end

function Lexer:readInterpolationExpression(line, column)
	local braceDepth = 0

	while true do
		self:skipSpace()
		local byte = self:peekByte()
		if byte == nil then
			raiseSyntaxError(line, column, "Malformed interpolated string; did you forget to add a '}'?", self.chunkname)
		elseif byte == 125 and braceDepth == 0 then
			self:advanceByte()
			self:emit("interp_expr_end", nil, self.line, self.column)
			return
		end

		local before = #self.tokens
		self:readToken()
		local emitted = self.tokens[#self.tokens]
		if #self.tokens > before then
			if emitted.kind == "{" then
				braceDepth += 1
			elseif emitted.kind == "}" then
				braceDepth -= 1
			end
		end
	end
end

function Lexer:readInterpolatedString()
	local line, column = self.line, self.column
	local source = self.source
	self:advanceByte()
	self:emit("interp_begin", nil, line, column)

	local textParts = nil
	local textValue = nil
	local textLine, textColumn = self.line, self.column

	local function flushText()
		if textParts then
			if #textParts > 0 then
				self:emit("interp_text", table.concat(textParts), textLine, textColumn)
			end
		elseif textValue ~= nil then
			self:emit("interp_text", textValue, textLine, textColumn)
		end
		textParts = nil
		textValue = nil
	end

	while true do
		local chunkStart = self.pos
		local cursor = chunkStart
		while true do
			local byte = stringByte(source, cursor)
			if byte == nil or byte == 96 or byte == 123 or byte == 92 or byte == 10 or byte == 13 then
				break
			end
			cursor += 1
		end

		if cursor > chunkStart then
			local chunk = stringSub(source, chunkStart, cursor - 1)
			if textParts then
				textParts[#textParts + 1] = chunk
			else
				textValue = (textValue or "") .. chunk
			end
			self.pos = cursor
			self.column += cursor - chunkStart
		end

		local byte = self:peekByte()
		if byte == nil then
			raiseSyntaxError(line, column, "Malformed interpolated string; did you forget to add a '`'?", self.chunkname)
		elseif byte == 96 then
			flushText()
			self:advanceByte()
			self:emit("interp_end", nil, self.line, self.column)
			return
		elseif byte == 123 then
			if self:peekByte(1) == 123 then
				raiseSyntaxError(self.line, self.column, "Double braces are not permitted within interpolated strings; did you mean '\\{'?", self.chunkname)
			end
			flushText()
			local expressionLine, expressionColumn = self.line, self.column
			self:emit("interp_expr_begin", nil, expressionLine, expressionColumn)
			self:advanceByte()
			self:readInterpolationExpression(expressionLine, expressionColumn)
			textLine, textColumn = self.line, self.column
		elseif byte == 92 then
			if textParts == nil then
				textParts = {}
				if textValue ~= nil then
					textParts[1] = textValue
					textValue = nil
				end
			end
			self:advanceByte()
			textParts[#textParts + 1] = self:readEscapeSequence(true)
		else
			raiseSyntaxError(self.line, self.column, "Unescaped newline in interpolated string", self.chunkname)
		end
	end
end

local function consumeNumberDigits(lexer, digitBase, allowLeadingSeparator)
	local source = lexer.source
	local cursor = lexer.pos
	local count = 0

	while true do
		local byte = stringByte(source, cursor)
		local valid
		if digitBase == 16 then
			valid = byte ~= nil and (
				(byte >= 48 and byte <= 57)
					or (byte >= 65 and byte <= 70)
					or (byte >= 97 and byte <= 102)
			)
		elseif digitBase == 2 then
			valid = byte == 48 or byte == 49
		else
			valid = byte ~= nil and byte >= 48 and byte <= 57
		end

		if valid then
			count += 1
			cursor += 1
		elseif byte == 95 then
			local nextByte = stringByte(source, cursor + 1)
			local nextValid
			if digitBase == 16 then
				nextValid = nextByte ~= nil and ((nextByte >= 48 and nextByte <= 57)
					or (nextByte >= 65 and nextByte <= 70) or (nextByte >= 97 and nextByte <= 102))
			elseif digitBase == 2 then
				nextValid = nextByte == 48 or nextByte == 49
			else
				nextValid = nextByte ~= nil and nextByte >= 48 and nextByte <= 57
			end
			if nextValid and (count > 0 or allowLeadingSeparator and cursor == lexer.pos) then
				cursor += 1
			else
				break
			end
		else
			break
		end
	end

	local consumed = cursor - lexer.pos
	lexer.pos = cursor
	lexer.column += consumed
	return count
end

function Lexer:readNumber()
	local line, column = self.line, self.column
	local start = self.pos
	local source = self.source
	local first = self:peekByte()
	local base


	if first == 48 and (self:peekByte(1) == 120 or self:peekByte(1) == 88) then
		base = 16
		self:advanceByte()
		self:advanceByte()
		if consumeNumberDigits(self, 16, true) == 0 then
			raiseSyntaxError(line, column, "Malformed number", self.chunkname)
		end
	elseif first == 48 and (self:peekByte(1) == 98 or self:peekByte(1) == 66) then
		base = 2
		self:advanceByte()
		self:advanceByte()
		if consumeNumberDigits(self, 2, true) == 0 then
			raiseSyntaxError(line, column, "Malformed number", self.chunkname)
		end
	else
		if first == 46 then
			self:advanceByte()
			if consumeNumberDigits(self, 10) == 0 then
				raiseSyntaxError(line, column, "Malformed number", self.chunkname)
			end
		else
			consumeNumberDigits(self, 10)
			if self:peekByte() == 46 and self:peekByte(1) ~= 46 then
				self:advanceByte()
				consumeNumberDigits(self, 10)
			end
		end

		local exponent = self:peekByte()
		if exponent == 101 or exponent == 69 then
			self:advanceByte()
			local sign = self:peekByte()
			if sign == 43 or sign == 45 then
				self:advanceByte()
			end
			if consumeNumberDigits(self, 10) == 0 then
				raiseSyntaxError(line, column, "Malformed number", self.chunkname)
			end
		end
	end

	local raw = stringSub(source, start, self.pos - 1)
	local cleaned = if stringFind(raw, "_", 1, true) then stringGsub(raw, "_", "") else raw
	local value
	if base then
		value = tonumber(stringSub(cleaned, 3), base)
	else
		value = tonumber(cleaned)
	end

	if value == nil then
		raiseSyntaxError(line, column, "Malformed number " .. string.format("%q", raw), self.chunkname)
	end

	local nextByte = self:peekByte()
	if nextByte ~= nil and (
		(nextByte >= 48 and nextByte <= 57)
			or (nextByte >= 65 and nextByte <= 90)
			or (nextByte >= 97 and nextByte <= 122)
			or nextByte == 95
		) then
		raiseSyntaxError(self.line, self.column, "Malformed number", self.chunkname)
	end

	self:emit("number", value, line, column, raw)
end

function Lexer:readName()
	local line, column = self.line, self.column
	local source = self.source
	local start = self.pos
	local cursor = start

	while true do
		local byte = stringByte(source, cursor)
		if byte ~= nil and (
			(byte >= 48 and byte <= 57)
				or (byte >= 65 and byte <= 90)
				or (byte >= 97 and byte <= 122)
				or byte == 95
			) then
			cursor += 1
		else
			break
		end
	end

	local name = stringSub(source, start, cursor - 1)
	self.column += cursor - start
	self.pos = cursor
	self:emit(keywords[name] and name or "name", name, line, column)
end

function Lexer:readToken()
	self:skipSpace()
	local byte = self:peekByte()
	if byte == nil then
		return false
	end

	local line, column = self.line, self.column
	if (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) or byte == 95 then
		self:readName()
	elseif (byte >= 48 and byte <= 57) or (byte == 46 and (self:peekByte(1) or 0) >= 48 and (self:peekByte(1) or 0) <= 57) then
		self:readNumber()
	elseif byte == 39 then
		self:readString("'")
	elseif byte == 34 then
		self:readString('"')
	elseif byte == 96 then
		self:readInterpolatedString()
	elseif byte == 91 and self:longBracketLevel() ~= nil then
		self:readLongString()
	else
		local matched
		local candidates = operatorsByFirstByte[byte]
		if candidates then
			local secondByte = self:peekByte(1)
			local thirdByte = self:peekByte(2)
			for candidateIndex = 1, #candidates do
				local candidate = candidates[candidateIndex]
				local operatorLength = candidate.length
				if (operatorLength == 1 or candidate.secondByte == secondByte)
					and (operatorLength < 3 or candidate.thirdByte == thirdByte) then
					self.pos += operatorLength
					self.column += operatorLength
					self:emit(candidate.value, candidate.value, line, column)
					matched = true
					break
				end
			end
		end

		if not matched then
			local character = stringSub(self.source, self.pos, self.pos)
			raiseSyntaxError(line, column, "Unexpected symbol " .. string.format("%q", character), self.chunkname)
		end
	end

	return true
end

function Lexer:tokenize()
	while self:readToken() do
	end

	self:emit("eof", nil, self.line, self.column)
	self.tokens.typeMode = self.typeMode
	return self.tokens
end

local precedence = {
	["or"] = 1,
	["and"] = 2,
	["=="] = 3,
	["~="] = 3,
	["<"] = 3,
	["<="] = 3,
	[">"] = 3,
	[">="] = 3,
	[".."] = 8,
	["+"] = 9,
	["-"] = 9,
	["*"] = 10,
	["/"] = 10,
	["//"] = 10,
	["%"] = 10,
	["^"] = 12,
}


local function displayToken(token)
	local kind = token.kind
	if kind == "eof" then
		return "<eof>"
	elseif kind == "name" then
		return "'" .. tostring(token.value) .. "'"
	elseif kind == "number" then
		return "'" .. tostring(token.raw or token.value) .. "'"
	elseif kind == "string" then
		return "<string>"
	elseif kind == "interp_begin" then
		return "the beginning of an interpolated string"
	elseif kind == "interp_text" then
		return "the middle of an interpolated string"
	elseif kind == "interp_end" then
		return "the end of an interpolated string"
	elseif kind == "interp_expr_begin" then
		return "'{'"
	elseif kind == "interp_expr_end" then
		return "'}'"
	elseif keywords[kind] or #kind == 1 or kind == "..." or kind == "//" or kind == "//="
		or kind == ".." or kind == "..=" or kind == "::" or kind == "->"
		or kind == "==" or kind == "~=" or kind == "<=" or kind == ">="
		or kind == "+=" or kind == "-=" or kind == "*=" or kind == "/="
		or kind == "%=" or kind == "^=" then
		return "'" .. kind .. "'"
	end
	return tostring(kind)
end

local function displayExpected(kind)
	if kind == "name" then
		return "identifier"
	elseif kind == "eof" then
		return "<eof>"
	elseif kind == "number" or kind == "string" then
		return kind
	end
	return "'" .. kind .. "'"
end

local function raiseDiagnostic(token, category, message)
	local line = token and token.line or 1
	local sourceName = token and token.sourceName
	local prefix = if category == "TypeError" then "TypeError: " else ""
	local detail = tostring(line) .. ": " .. prefix .. message
	error(if sourceName then sourceName .. ":" .. detail else detail, 0)
end

local assignmentOperators = {
	["="] = true,
	["+="] = true,
	["-="] = true,
	["*="] = true,
	["/="] = true,
	["//="] = true,
	["%="] = true,
	["^="] = true,
	["..="] = true,
}

local compoundOperators = {
	["+="] = "+",
	["-="] = "-",
	["*="] = "*",
	["/="] = "/",
	["//="] = "//",
	["%="] = "%",
	["^="] = "^",
	["..="] = "..",
}

local binaryOpcodes = {
	["+"] = OP.ADD,
	["-"] = OP.SUBTRACT,
	["*"] = OP.MULTIPLY,
	["/"] = OP.DIVIDE,
	["//"] = OP.FLOOR_DIVIDE,
	["%"] = OP.MODULO,
	["^"] = OP.POWER,
	[".."] = OP.CONCAT,
	["=="] = OP.EQUAL,
	["~="] = OP.NOT_EQUAL,
	["<"] = OP.LESS_THAN,
	["<="] = OP.LESS_EQUAL,
	[">"] = OP.GREATER_THAN,
	[">="] = OP.GREATER_EQUAL,
}

local function emitBinary(compiler, operator)
	local opcode = binaryOpcodes[operator]
	if not opcode then
		error("Compiler: unsupported binary operator " .. tostring(operator), 0)
	end
	compiler:emit(opcode)
end


local builtinGlobalNames = {
	assert = true, error = true, ipairs = true, pairs = true, next = true,
	pcall = true, xpcall = true, select = true, tonumber = true, tostring = true,
	type = true, typeof = true, rawequal = true, rawget = true, rawset = true,
	rawlen = true, setmetatable = true, getmetatable = true, print = true,
	warn = true, require = true,
	math = true, string = true, table = true, coroutine = true, bit32 = true,
	os = true, utf8 = true, task = true, buffer = true,
	game = true, workspace = true, script = true, plugin = true,
	Instance = true, Enum = true, Vector2 = true, Vector3 = true,
	Vector2int16 = true, Vector3int16 = true, CFrame = true, UDim = true,
	UDim2 = true, Color3 = true, BrickColor = true, Ray = true,
	Region3 = true, TweenInfo = true, PhysicalProperties = true,
	NumberRange = true, NumberSequence = true, ColorSequence = true,
	Random = true, DateTime = true, Font = true, Faces = true, Axes = true,
	SharedTable = true, typeof = true,
}

function Compiler.new(tokens, isVararg, inheritedBindings, inheritedTypes, typeMode, inheritedAliases, globalTypes, sharedConstants, sharedConstantIndexes)
	local rootBindings = {}
	if inheritedBindings then
		for name, isConst in pairs(inheritedBindings) do
			rootBindings[name] = isConst
		end
	end

	local rootTypes = {}
	for name in pairs(builtinGlobalNames) do
		rootTypes[name] = "any"
	end
	if inheritedTypes then
		for name, inferredType in pairs(inheritedTypes) do
			rootTypes[name] = inferredType
		end
	end

	if globalTypes then
		for name, inferredType in pairs(globalTypes) do
			rootTypes[name] = inferredType
		end
	end

	local aliases = {}
	if inheritedAliases then
		for name, aliasType in pairs(inheritedAliases) do
			aliases[name] = aliasType
		end
	end

	return setmetatable({
		tokens = tokens,
		at = 1,
		code = tableCreate(math.min(#tokens, 4096)),
		constants = sharedConstants or {},
		constantIndexes = sharedConstantIndexes or {},
		loopStack = {},
		scopeDepth = 1,
		scopes = { { bindings = rootBindings, types = rootTypes } },
		typeAliases = aliases,
		typePacks = {},
		typeDefaults = {},
		exportedTypes = nil,
		typeMode = typeMode or tokens.typeMode or "nonstrict",
		expectedReturnType = nil,
		isVararg = isVararg ~= false,
	}, Compiler)
end

function Compiler:declareBinding(name, isConst, inferredType)
	self.scopes[#self.scopes].bindings[name] = isConst == true
	if inferredType ~= nil then
		self.scopes[#self.scopes].types[name] = inferredType
	end
end

function Compiler:lookupBinding(name)
	for index = #self.scopes, 1, -1 do
		local value = self.scopes[index].bindings[name]
		if value ~= nil then
			return value
		end
	end
	return nil
end

function Compiler:lookupType(name)
	for index = #self.scopes, 1, -1 do
		local value = self.scopes[index].types[name]
		if value ~= nil then
			return value
		end
	end
	return nil
end

function Compiler:setBindingType(name, inferredType)
	if inferredType ~= nil then
		self.scopes[#self.scopes].types[name] = inferredType
	end
end

function Compiler:visibleTypes()
	local visible = {}
	for index = 1, #self.scopes do
		for name, inferredType in pairs(self.scopes[index].types) do
			visible[name] = inferredType
		end
	end
	return visible
end

local function simpleTypeName(inferredType)
	if type(inferredType) == "table" then
		local kind = inferredType.kind
		if kind == "union" or kind == "intersection" then
			local separator = if kind == "union" then "|" else "&"
			local members = {}
			for index, memberType in ipairs(inferredType.types or {}) do
				members[index] = simpleTypeName(memberType)
			end
			return table.concat(members, separator)
		end
		if kind == "table" then return "table" end
		if kind == "typePack" then return "typePack" end
		return kind or "function"
	end
	return inferredType or "any"
end

local function unionMembers(typeName)
	local members = {}
	if type(typeName) ~= "string" then
		return members
	end
	for member in string.gmatch(typeName, "[^|]+") do
		members[member] = true
	end
	return members
end

function Compiler:assertWritable(name, token)
	if self:lookupBinding(name) == true then
		token = token or self.tokens[math.max(self.at - 1, 1)]
		raiseDiagnostic(token, "CompileError", "Assigned expression must be a variable or a field")
	end
end

function Compiler:visibleBindings()
	local visible = {}
	for index = 1, #self.scopes do
		for name, isConst in pairs(self.scopes[index].bindings) do
			visible[name] = isConst
		end
	end
	return visible
end

function Compiler:peek(offset)
	return self.tokens[self.at + (offset or 0)]
end

function Compiler:check(kind)
	return self.tokens[self.at].kind == kind
end

function Compiler:checkName(value, offset)
	local token = self.tokens[self.at + (offset or 0)]
	return token.kind == "name" and token.value == value
end

function Compiler:take()
	local token = self.tokens[self.at]
	self.at += 1
	return token
end

function Compiler:match(kind)
	local token = self.tokens[self.at]
	if token.kind == kind then
		self.at += 1
		return true
	end
	return false
end

function Compiler:expect(kind, context)
	local token = self:take()
	if token.kind ~= kind then
		local message = "Expected " .. displayExpected(kind)
		if context then
			message ..= " when parsing " .. context
		end
		message ..= ", got " .. displayToken(token)
		raiseDiagnostic(token, "SyntaxError", message)
	end
	return token
end

function Compiler:addConstant(value)
	if value == nil then
		return 0
	end

	local indexes = self.constantIndexes
	local index = indexes[value]
	if index ~= nil then
		return index
	end

	local constants = self.constants
	index = #constants + 1
	constants[index] = value
	indexes[value] = index
	return index
end

function Compiler:emit(opcode, a, b)
	if opcode == OP.PUSH_CONSTANT then
		a = self:addConstant(a)
	end

	local code = self.code
	local index = #code + 1
	code[index] = { opcode, a, b }
	return index
end

function Compiler:emitCall(argumentCount, expandLast, nameCall)
	local opcode
	if nameCall then
		opcode = if expandLast then OP.CALL_NAME_EXPAND else OP.CALL_NAME
	else
		opcode = if expandLast then OP.CALL_EXPAND else OP.CALL
	end
	return self:emit(opcode, argumentCount)
end

function Compiler:markLastExpressionSingle()
	local instruction = self.code[#self.code]
	if not instruction then return end
	local singleOpcode = callSingleOpcodes[instruction[1]]
	if singleOpcode then
		instruction[1] = singleOpcode
	elseif instruction[1] == OP.PUSH_VARARGS then
		instruction[1] = OP.PUSH_VARARG
	end
end

function Compiler:patch(instructionIndex, target)
	local instruction = self.code[instructionIndex]
	if instruction[1] == OP.NUMERIC_FOR_PREP then
		instruction[3] = target
	else
		instruction[2] = target
	end
end

function Compiler:pushLoop(loopInfo)
	self.loopStack[#self.loopStack + 1] = loopInfo
end

function Compiler:popLoop()
	self.loopStack[#self.loopStack] = nil
end

function Compiler:enterScope()
	self:emit(OP.ENTER_SCOPE)
	self.scopeDepth += 1
	self.scopes[#self.scopes + 1] = { bindings = {}, types = {} }
end

function Compiler:exitScope()
	if self.scopeDepth <= 1 then
		error("Compiler: cannot exit the root scope")
	end
	self:emit(OP.EXIT_SCOPE)
	self.scopeDepth -= 1
	self.scopes[#self.scopes] = nil
end

function Compiler:emitScopeCleanupJump(targetDepth)
	local count = self.scopeDepth - targetDepth
	return self:emit(OP.JUMP, 0, math.max(count, 0))
end

function Compiler:emitNativeLoopControl(opcode, targetDepth)
	local count = self.scopeDepth - targetDepth
	self:emit(opcode, math.max(count, 0))
end

function Compiler:compileBlock(stops)
	self:enterScope()
	while not self:check("eof") and not stops[self:peek().kind] do
		self:statement()
	end
	self:exitScope()
end

function Compiler:parseGenericParameterList(withDefaults)
	self:expect("<")
	local parameters = {}
	if not self:check(">") then
		while true do
			local name = self:expect("name").value
			parameters[#parameters + 1] = name
			if self:match("...") then
				self.typePacks[name] = true
			end
			if withDefaults and self:match("=") then
				self.typeDefaults[name] = self:parseType()
			end

			if not self:match(",") then
				break
			end
		end
	end
	self:expect(">")
	return parameters
end

function Compiler:genericParameterMetadata(parameters)
	local packs, defaults = {}, {}
	for _, name in ipairs(parameters) do
		if self.typePacks[name] then
			packs[name] = true
		end
		if self.typeDefaults[name] ~= nil then
			defaults[name] = self.typeDefaults[name]
		end
	end
	return packs, defaults
end

function Compiler:parseTypeofExpression()
	self:expect("(")
	local inferredType = "any"
	if self:check("name") and self:peek(1).kind == ")" then
		inferredType = self:lookupType(self:take().value) or "any"
		self:take()
		return inferredType
	end
	local depth = 1
	while depth > 0 and not self:check("eof") do
		local kind = self:take().kind
		if kind == "(" then
			depth += 1
		elseif kind == ")" then
			depth -= 1
		end
	end
	if depth ~= 0 then
		local token = self:peek()
		raiseDiagnostic(token, "SyntaxError", "Expected ')', got " .. displayToken(token))
	end
	return inferredType
end

function Compiler:parseTypeArguments()
	self:expect("<")
	local arguments = {}
	if not self:check(">") then
		repeat
			arguments[#arguments + 1] = self:parseType()
		until not self:match(",")
	end
	self:expect(">")
	return arguments
end

function Compiler:parseExplicitTypeInstantiation()
	self:expect("<")
	self:expect("<")
	if self:check(">") then
		raiseDiagnostic(self:peek(), "SyntaxError", "Expected a type argument, got " .. displayToken(self:peek()))
	end

	local arguments = {}
	repeat
		arguments[#arguments + 1] = self:parseType()
	until not self:match(",")

	self:expect(">")
	self:expect(">")
	return arguments
end

function Compiler:parseTypePackOrFunction()
	self:expect("(")
	local parameterTypes = {}
	local varargType
	if not self:check(")") then
		while true do
			if self:check("name") and self:peek(1).kind == ":" then
				self:take()
				self:take()
				parameterTypes[#parameterTypes + 1] = self:parseType()
			elseif self:match("...") then
				varargType = self:parseType()
			else
				parameterTypes[#parameterTypes + 1] = self:parseType()
			end

			if not self:match(",") then
				break
			end
		end
	end
	self:expect(")")
	return {
		parameters = parameterTypes,
		varargType = varargType,
	}
end

function Compiler:parseTableType()
	self:expect("{")
	local properties = {}
	if self:match("}") then
		return { kind = "table", properties = properties }
	end

	local function parseProperty(compiler)
		local modifier
		if compiler:check("name") then
			local current = compiler:peek().value
			local nextKind = compiler:peek(1).kind
			if (current == "read" or current == "write")
				and (nextKind == "name" or nextKind == "[") then
				modifier = compiler:take().value
			end
		end

		if compiler:match("[") then
			local keyType = compiler:parseType()
			compiler:expect("]")
			compiler:expect(":")
			local valueType = compiler:parseType()
			local indexers = properties.__indexers
			if not indexers then
				indexers = {}
				properties.__indexers = indexers
			end
			indexers[#indexers + 1] = {
				keyType = keyType,
				valueType = valueType,
				modifier = modifier,
			}
			return true
		end

		if compiler:check("name")
			and (compiler:peek(1).kind == ":" or compiler:peek(1).kind == "?") then
			local propertyName = compiler:take().value
			local optional = compiler:match("?")
			compiler:expect(":")
			properties[propertyName] = {
				type = compiler:parseType(),
				optional = optional,
				modifier = modifier,
			}
			return true
		end

		properties.__array = compiler:parseType()
		compiler:expect("}")
		return false
	end

	if self:match("...") then
		self:expect("}")
		return { kind = "table", properties = properties, open = true }
	end

	if not parseProperty(self) then
		return { kind = "table", properties = properties }
	end

	while self:match(",") or self:match(";") do
		if self:check("}") then
			break
		end
		if self:match("...") then
			self:expect("}")
			return { kind = "table", properties = properties, open = true }
		end
		if not parseProperty(self) then
			return { kind = "table", properties = properties }
		end
	end
	self:expect("}")
	return { kind = "table", properties = properties }
end

local function substituteAliasType(typeValue, substitutions)
	if type(typeValue) == "string" then
		return substitutions[typeValue] or typeValue
	end
	if type(typeValue) ~= "table" then
		return typeValue
	end

	local copy = {
		kind = typeValue.kind,
		open = typeValue.open,
		variadic = typeValue.variadic,
		varargType = substituteAliasType(typeValue.varargType, substitutions),
		returnType = substituteAliasType(typeValue.returnType, substitutions),
		genericParameters = typeValue.genericParameters,
		packs = typeValue.packs,
		defaults = typeValue.defaults,
	}
	if typeValue.types then
		copy.types = {}
		for index, memberType in ipairs(typeValue.types) do
			copy.types[index] = substituteAliasType(memberType, substitutions)
		end
	end
	if typeValue.parameters then
		copy.parameters = {}
		for index, parameterType in ipairs(typeValue.parameters) do
			copy.parameters[index] = substituteAliasType(parameterType, substitutions)
		end
	end
	if typeValue.properties then
		copy.properties = {}
		for name, property in pairs(typeValue.properties) do
			if name == "__array" then
				copy.properties[name] = substituteAliasType(property, substitutions)
			elseif name == "__indexers" then
				local indexers = {}
				for index, entry in ipairs(property) do
					indexers[index] = {
						keyType = substituteAliasType(entry.keyType, substitutions),
						valueType = substituteAliasType(entry.valueType, substitutions),
						modifier = entry.modifier,
					}
				end
				copy.properties[name] = indexers
			else
				copy.properties[name] = {
					type = substituteAliasType(property.type, substitutions),
					optional = property.optional,
					modifier = property.modifier,
				}
			end
		end
	end
	return copy
end

function Compiler:parseSimpleType()
	if self:match("...") then
		local packType = self:parseType()
		return { kind = "typePack", types = { packType }, variadic = true }
	end

	if self:check("<") then
		local genericParameters = self:parseGenericParameterList(false)
		local signature = self:parseTypePackOrFunction()
		if not self:match("->") then
			local token = self:peek()
			raiseDiagnostic(token, "SyntaxError", "Expected '->' when parsing a generic function type, got " .. displayToken(token))
		end
		local returnType = self:parseType()
		return {
			kind = "function",
			parameters = signature.parameters,
			varargType = signature.varargType,
			genericParameters = genericParameters,
			returnType = returnType,
		}
	end

	if self:check("(") then
		local signature = self:parseTypePackOrFunction()
		if self:match("->") then
			local returnType = self:parseType()
			return {
				kind = "function",
				parameters = signature.parameters,
				varargType = signature.varargType,
				genericParameters = {},
				returnType = returnType,
			}
		end
		if #signature.parameters == 1 and signature.varargType == nil then
			return signature.parameters[1]
		end
		return {
			kind = "typePack",
			types = signature.parameters,
			varargType = signature.varargType,
		}
	end

	if self:check("{") then
		return self:parseTableType()
	end

	local token = self:peek()
	if token.kind == "string" or token.kind == "true" or token.kind == "false"
		or token.kind == "nil" then
		self:take()
		if token.kind == "string" then return "string" end
		if token.kind == "nil" then return "nil" end
		return "boolean"
	end

	if token.kind ~= "name" then
		raiseDiagnostic(token, "SyntaxError", "Expected a type, got " .. displayToken(token))
	end

	self:take()
	if token.value == "typeof" and self:check("(") then
		return self:parseTypeofExpression()
	end

	local typeName = token.value
	while self:match(".") do
		typeName ..= "." .. self:expect("name").value
	end

	local typeArguments
	if self:check("<") then
		typeArguments = self:parseTypeArguments()
	end

	local isTypePack = self:match("...")
	local alias = self.typeAliases[typeName]
	if type(alias) == "table" and alias.kind == "genericAlias" then
		local substitutions = {}
		local parameters = alias.parameters
		if typeArguments then
			local requiredCount = 0
			for index, parameter in ipairs(parameters) do
				if alias.defaults == nil or alias.defaults[parameter] == nil then
					requiredCount = index
				end
			end
			if #typeArguments < requiredCount or #typeArguments > #parameters then
				raiseDiagnostic(token, "TypeError", "Expected " .. tostring(requiredCount)
					.. " to " .. tostring(#parameters) .. " type arguments for '" .. typeName
					.. "', got " .. tostring(#typeArguments))
			end
		end
		for index, parameter in ipairs(parameters) do
			local defaultType = alias.defaults and alias.defaults[parameter]
			substitutions[parameter] = typeArguments and typeArguments[index] or defaultType or "any"
		end
		alias = substituteAliasType(alias.definition, substitutions)
	else
		alias = alias or typeName
	end
	if isTypePack then
		return { kind = "typePack", types = { alias }, variadic = true }
	end
	return alias
end

function Compiler:parsePostfixType()
	local typeName = self:parseSimpleType()
	while self:match("?") do
		local baseType = typeName
		if type(baseType) == "string" then
			if not string.find("|" .. baseType .. "|", "|nil|", 1, true) then
				typeName = baseType .. "|nil"
			end
		else
			typeName = { kind = "union", types = { baseType, "nil" } }
		end
	end
	return typeName
end

function Compiler:parseIntersectionType()
	local typeName = self:parsePostfixType()
	while self:match("&") do
		local rightType = self:parsePostfixType()
		if typeName == "any" then
			typeName = rightType
		elseif rightType ~= "any" then
			if type(typeName) == "table" and typeName.kind == "intersection" then
				typeName.types[#typeName.types + 1] = rightType
			else
				typeName = { kind = "intersection", types = { typeName, rightType } }
			end
		end
	end
	return typeName
end

function Compiler:parseType()
	local typeName = self:parseIntersectionType()
	while self:match("|") do
		local rightType = self:parseIntersectionType()
		if type(typeName) == "string" and type(rightType) == "string" then
			local leftName = typeName
			local rightName = rightType
			if leftName ~= rightName and leftName ~= "any" and rightName ~= "any"
				and not string.find("|" .. leftName .. "|", "|" .. rightName .. "|", 1, true) then
				typeName = leftName .. "|" .. rightName
			else
				typeName = leftName
			end
		elseif type(typeName) == "table" and typeName.kind == "union" then
			typeName.types[#typeName.types + 1] = rightType
		else
			typeName = { kind = "union", types = { typeName, rightType } }
		end
	end
	return typeName
end

function Compiler:parseAttributeLiteral()
	if self:match("{") then
		while not self:check("}") do
			if self:check("name") and self:peek(1).kind == "=" then
				self:take()
				self:take()
				self:parseAttributeLiteral()
			elseif self:match("[") then
				self:parseAttributeLiteral()
				self:expect("]", "table constructor index")
				self:expect("=")
				self:parseAttributeLiteral()
			else
				self:parseAttributeLiteral()
			end
			if not self:match(",") and not self:match(";") then break end
		end
		self:expect("}", "attribute parameter table")
		return
	end

	local token = self:take()
	if token.kind ~= "nil" and token.kind ~= "true" and token.kind ~= "false"
		and token.kind ~= "number" and token.kind ~= "string" then
		raiseDiagnostic(token, "SyntaxError", "Expected a literal attribute parameter, got " .. displayToken(token))
	end
end

function Compiler:parseAttributeParameters()
	if self:match("(") then
		if not self:check(")") then
			repeat self:parseAttributeLiteral() until not self:match(",")
		end
		self:expect(")")
	elseif self:check("{") or self:check("string") then
		self:parseAttributeLiteral()
	end
end

function Compiler:parseAttributes()
	while self:match("@") do
		if self:match("[") then
			if self:check("]") then
				local token = self:peek()
				raiseDiagnostic(token, "SyntaxError", "Expected an attribute, got " .. displayToken(token))
			end
			repeat
				self:expect("name")
				self:parseAttributeParameters()
			until not self:match(",")
			self:expect("]")
		else
			self:expect("name")
			self:parseAttributeParameters()
		end
	end
end

function Compiler:markLastExpressionMulti()
	local instruction = self.code[#self.code]
	if not instruction then
		return false
	end

	local multiOpcode = callMultiOpcodes[instruction[1]]
	if multiOpcode then
		instruction[1] = multiOpcode
		return true
	elseif instruction[1] == OP.PUSH_VARARG then
		instruction[1] = OP.PUSH_VARARGS
		return true
	end

	return false
end

function Compiler:parseExpressionList()
	local count = 0
	local expandLast = false
	local expressionTypes = {}

	repeat
		expressionTypes[count + 1] = self:expression(1)
		count += 1
		if not self:check(",") then
			expandLast = self:markLastExpressionMulti()
		end
	until not self:match(",")

	return count, expandLast, expressionTypes
end

function Compiler:compileFunctionPrototype(prependSelf)
	local genericParameters = {}
	if self:check("<") then
		genericParameters = self:parseGenericParameterList(false)
	end

	self:expect("(", "function parameters")
	local parameters = {}
	local parameterTypes = {}
	if prependSelf then
		parameters[1] = "self"
		parameterTypes[1] = "any"
	end
	local isVararg = false

	if not self:check(")") then
		while true do
			if self:match("...") then
				isVararg = true
				if self:match(":") then
					self:parseType()
				end
				if self:check(",") then
					local token = self:peek()
					raiseDiagnostic(token, "SyntaxError", "Expected ')' after varargs, got " .. displayToken(token))
				end
				break
			end

			local parameterName = self:expect("name").value
			parameters[#parameters + 1] = parameterName
			parameterTypes[#parameters] = "any"
			if self:match(":") then
				parameterTypes[#parameters] = self:parseType()
			end
			if not self:match(",") then
				break
			end
			if self:check(")") then
				break
			end
		end
	end
	self:expect(")", "function parameters")

	local returnType
	if self:match(":") or self:match("->") then
		returnType = self:parseType()
	end

	local child = Compiler.new(
		self.tokens,
		isVararg,
		self:visibleBindings(),
		self:visibleTypes(),
		self.typeMode,
		self.typeAliases,
		nil,
		self.constants,
		self.constantIndexes
	)
	for name, isPack in pairs(self.typePacks) do
		child.typePacks[name] = isPack
	end
	for name, defaultType in pairs(self.typeDefaults) do
		child.typeDefaults[name] = defaultType
	end
	for _, genericName in ipairs(genericParameters) do
		child.typeAliases[genericName] = "any"
		child.typePacks[genericName] = self.typePacks[genericName] or nil
		child.typeDefaults[genericName] = self.typeDefaults[genericName]
	end
	for index, parameterName in ipairs(parameters) do
		child:declareBinding(parameterName, false, parameterTypes[index] or "any")
	end
	child.at = self.at
	child.expectedReturnType = returnType
	while not child:check("end") and not child:check("eof") do
		child:statement()
	end
	child:expect("end")
	child:emit(OP.RETURN, 0)
	self.at = child.at

	local functionType = {
		kind = "function",
		parameters = parameterTypes,
		genericParameters = genericParameters,
		returnType = returnType,
	}
	return {
		code = child.code,
		parameters = parameters,
		vararg = isVararg,
	}, functionType
end

function Compiler:parseArguments()
	self:expect("(", "function arguments")
	local count = 0
	local expandLast = false
	local argumentTypes = {}

	if not self:check(")") then
		while true do
			argumentTypes[count + 1] = self:expression(1)
			count += 1

			if not self:match(",") then
				expandLast = self:markLastExpressionMulti()
				break
			end
		end
	end

	self:expect(")", "function arguments")
	return count, expandLast, argumentTypes
end

function Compiler:compileNameCall()
	self:emit(OP.DUP)
	self:emit(OP.PUSH_CONSTANT, self:expect("name").value)
	self:emit(OP.TABLE_GET)

	if self:check("<") and self:peek(1).kind == "<" then
		self:parseExplicitTypeInstantiation()
	end

	if self:check("(") then
		local argumentCount, expandLast = self:parseArguments()
		self:emitCall(argumentCount, expandLast, true)
	elseif self:check("string") then
		local argument = self:take()
		self:emit(OP.PUSH_CONSTANT, argument.value)
		self:emitCall(1, false, true)
	elseif self:check("{") then
		self:expression(13)
		self:emitCall(1, false, true)
	else
		local token = self:peek()
		raiseDiagnostic(token, "SyntaxError", "Expected '(', '{' or <string> when parsing function call, got " .. displayToken(token))
	end
end

function Compiler:compileInterpolatedString()
	self:expect("interp_begin")
	local partCount = 0

	while not self:check("interp_end") do
		if self:match("interp_text") then
			local text = self.tokens[self.at - 1].value
			self:emit(OP.PUSH_CONSTANT, text)
			partCount += 1
		elseif self:match("interp_expr_begin") then
			self:expression(1)
			self:expect("interp_expr_end")
			partCount += 1
		else
			local token = self:peek()
			raiseDiagnostic(token, "SyntaxError", "Expected interpolated string text or expression, got " .. displayToken(token))
		end
	end

	self:expect("interp_end")
	if partCount == 0 then
		self:emit(OP.PUSH_CONSTANT, "")
	else
		self:emit(if partCount == 1 then OP.INTERP_VALUE else OP.INTERP_CONCAT, partCount)
	end
end

local function joinTypes(leftType, rightType)
	leftType = simpleTypeName(leftType)
	rightType = simpleTypeName(rightType)
	if leftType == rightType then
		return leftType
	end
	if leftType == "any" or rightType == "any" then
		return "any"
	end

	local members = unionMembers(leftType)
	for member in pairs(unionMembers(rightType)) do
		members[member] = true
	end
	local joined = {}
	for member in pairs(members) do
		joined[#joined + 1] = member
	end
	table.sort(joined)
	return table.concat(joined, "|")
end

function Compiler:compileIfExpressionBranch()
	local hasBinding = self:check("local") or (self:checkName("const") and self:peek(1).kind == "name")
	local falseJump

	if hasBinding then
		local keyword = self:take()
		local isConst = keyword.value == "const"
		local nameToken = self:expect("name")
		local name = nameToken.value

		local declaredType
		if self:match(":") then
			declaredType = self:parseType()
		end
		if self:check(",") then
			raiseDiagnostic(self:peek(), "SyntaxError", "'" .. keyword.value .. "' in an if condition requires exactly one binding")
		end

		self:expect("=")
		local initializerType = self:expression(1)
		if self:check(",") then
			raiseDiagnostic(self:peek(), "SyntaxError", "'" .. keyword.value .. "' in an if condition requires exactly one initializer expression")
		end
		self:expect("then")

		self:emit(OP.DUP)
		falseJump = self:emit(OP.JUMP_IF_FALSE, 0)
		self:enterScope()
		self:declareBinding(name, isConst, declaredType or initializerType)
		self:emit(OP.DECLARE_LOCAL, name)
		local branchType = self:expression(1)
		self:exitScope()
		return falseJump, hasBinding, branchType
	else
		self:expression(1)
		self:expect("then")
		falseJump = self:emit(OP.JUMP_IF_FALSE, 0)
		local branchType = self:expression(1)
		return falseJump, hasBinding, branchType
	end
end

function Compiler:compileIfExpression()
	local endJumps = {}
	local resultType

	while true do
		local falseJump, hasBinding, branchType = self:compileIfExpressionBranch()
		resultType = resultType and joinTypes(resultType, branchType) or branchType
		endJumps[#endJumps + 1] = self:emit(OP.JUMP, 0)
		self:patch(falseJump, #self.code + 1)
		if hasBinding then
			self:emit(OP.POP)
		end

		if self:match("elseif") then
			continue
		end

		self:expect("else")
		local elseType = self:expression(1)
		resultType = joinTypes(resultType, elseType)
		break
	end

	local endTarget = #self.code + 1
	for index = 1, #endJumps do
		self:patch(endJumps[index], endTarget)
	end
	local lastInstruction = self.code[#self.code]
	if lastInstruction then
		self:markLastExpressionSingle()
	end
	return resultType or "any"
end


local function substituteGenericType(typeValue, genericMap)
	return substituteAliasType(typeValue, genericMap)
end

function Compiler:checkFunctionCall(functionType, argumentTypes, token, explicitTypeArguments)
	if self.typeMode == "nocheck" or type(functionType) ~= "table" or functionType.kind ~= "function" then
		return "any"
	end

	local genericMap = {}
	local genericParameters = functionType.genericParameters or {}
	if explicitTypeArguments then
		if #explicitTypeArguments ~= #genericParameters then
			raiseDiagnostic(token, "TypeError", "Expected " .. tostring(#genericParameters)
				.. " type arguments, got " .. tostring(#explicitTypeArguments))
		end
		for index, genericName in ipairs(genericParameters) do
			genericMap[genericName] = explicitTypeArguments[index]
		end
	end

	local parameterTypes = functionType.parameters or {}
	for index, expectedType in ipairs(parameterTypes) do
		local actualType = argumentTypes[index] or "nil"
		if expectedType ~= nil then
			expectedType = substituteGenericType(expectedType, genericMap)
			if genericMap[expectedType] == nil and table.find(genericParameters, expectedType) then
				genericMap[expectedType] = actualType
				expectedType = genericMap[expectedType]
			end
		end
	end

	return substituteGenericType(functionType.returnType, genericMap) or "any"
end


local function tablePropertyType(typeInfo, propertyName)
	if type(typeInfo) ~= "table" or typeInfo.kind ~= "table" then
		return "any"
	end
	local property = typeInfo.properties and typeInfo.properties[propertyName]
	if property then
		local propertyType = property.type or "any"
		if property.optional then
			return { kind = "union", types = { propertyType, "nil" } }
		end
		return propertyType
	end
	if type(propertyName) == "number" and typeInfo.properties.__array then
		return typeInfo.properties.__array
	end
	local indexers = typeInfo.properties and typeInfo.properties.__indexers
	if indexers then
		for _, indexer in ipairs(indexers) do
			local keyTypes = unionMembers(simpleTypeName(indexer.keyType))
			if keyTypes.string or keyTypes.number or keyTypes.any then
				return indexer.valueType
			end
		end
	end
	return "any"
end

function Compiler:expression(minPrecedence)
	minPrecedence = minPrecedence or 1
	local token = self:take()
	local directInterpolation = token.kind == "interp_begin"
	local inferredType = "any"
	local explicitTypeArguments

	if token.kind == "number" then
		self:emit(OP.PUSH_CONSTANT, token.value)
		inferredType = "number"
	elseif token.kind == "string" then
		self:emit(OP.PUSH_CONSTANT, token.value)
		inferredType = "string"
	elseif token.kind == "interp_begin" then
		self.at -= 1
		self:compileInterpolatedString()
		inferredType = "string"
	elseif token.kind == "true" or token.kind == "false" then
		self:emit(OP.PUSH_CONSTANT, token.kind == "true")
		inferredType = "boolean"
	elseif token.kind == "nil" then
		self:emit(OP.PUSH_CONSTANT, nil)
		inferredType = "nil"
	elseif token.kind == "..." then
		self:emit(OP.PUSH_VARARG)
	elseif token.kind == "function" then
		local prototype, functionType = self:compileFunctionPrototype()
		self:emit(OP.CLOSURE, prototype)
		inferredType = functionType
	elseif token.kind == "@" then
		self.at -= 1
		self:parseAttributes()
		self:expect("function")
		local prototype, functionType = self:compileFunctionPrototype(false)
		self:emit(OP.CLOSURE, prototype)
		inferredType = functionType
	elseif token.kind == "if" then
		inferredType = self:compileIfExpression()
	elseif token.kind == "name" then
		self:emit(OP.PUSH_NAME, token.value)
		inferredType = self:lookupType(token.value)
		if inferredType == nil and self.typeMode == "strict" then
			raiseDiagnostic(token, "TypeError", "Unknown global '" .. token.value .. "'")
		end
		inferredType = inferredType or "any"
	elseif token.kind == "(" then
		inferredType = self:expression(1)
		self:expect(")", "parenthesized expression")
		local lastInstruction = self.code[#self.code]
		if lastInstruction then
			self:markLastExpressionSingle()
		end
	elseif token.kind == "-" then
		local operandType = self:expression(11)
		self:emit(OP.UNARY, "-")
		inferredType = "number"
	elseif token.kind == "not" then
		self:expression(3)
		self:emit(OP.UNARY, "not")
		inferredType = "boolean"
	elseif token.kind == "#" then
		self:expression(11)
		self:emit(OP.UNARY, "#")
		inferredType = "number"
	elseif token.kind == "{" then
		self:emit(OP.TABLE_NEW)
		local arrayIndex = 1
		local tableProperties = {}

		while not self:check("}") do
			self:emit(OP.DUP)
			local emittedAssignment = false

			if self:check("name") and self:peek(1).kind == "=" then
				local key = self:take().value
				self:take()
				self:emit(OP.PUSH_CONSTANT, key)
				tableProperties[key] = { type = self:expression(1) }
			elseif self:match("[") then
				local keyToken = self:peek()
				local staticKey
				if keyToken.kind == "string" then
					staticKey = keyToken.value
				elseif keyToken.kind == "number" then
					staticKey = keyToken.value
				end
				self:expression(1)
				self:expect("]", "table constructor index")
				self:expect("=")
				local valueType = self:expression(1)
				if staticKey ~= nil then
					tableProperties[staticKey] = { type = valueType }
				end
			else
				self:emit(OP.PUSH_CONSTANT, arrayIndex)
				tableProperties[arrayIndex] = { type = self:expression(1) }
				local nextKind = self:peek().kind
				local isFinalField = nextKind == "}"
					or ((nextKind == "," or nextKind == ";") and self:peek(1).kind == "}")
				local expands = isFinalField and self:markLastExpressionMulti()
				self:emit(if expands then OP.TABLE_SET_EXPAND else OP.TABLE_SET)
				emittedAssignment = true
				arrayIndex += 1
			end

			if not emittedAssignment then
				self:emit(OP.TABLE_SET)
			end
			if not self:match(",") and not self:match(";") then
				break
			end
		end

		self:expect("}", "table constructor")
		inferredType = { kind = "table", properties = tableProperties }
	else
		raiseDiagnostic(token, "SyntaxError", "Expected expression, got " .. displayToken(token))
	end

	while true do
		if directInterpolation and (self:check("(") or self:check(":")) then
			local nextToken = self:peek()
			raiseDiagnostic(nextToken, "SyntaxError", "Interpolated strings must be parenthesized before calls")
		end

		if self:match(".") then
			local propertyName = self:expect("name").value
			local propertyType = tablePropertyType(inferredType, propertyName)
			self:emit(OP.PUSH_CONSTANT, propertyName)
			self:emit(OP.TABLE_GET)
			inferredType = propertyType
		elseif self:match(":") then
			self:compileNameCall()
			inferredType = "any"
		elseif self:match("[") then
			local keyToken = self:peek()
			local staticKey = if keyToken.kind == "string" or keyToken.kind == "number" then keyToken.value else nil
			self:expression(1)
			self:expect("]")
			self:emit(OP.TABLE_GET)
			inferredType = if staticKey ~= nil then tablePropertyType(inferredType, staticKey) else "any"
		elseif self:check("(") then
			local callToken = self:peek()
			local argumentCount, expandLast, argumentTypes = self:parseArguments()
			self:emitCall(argumentCount, expandLast, false)
			if expandLast then
				inferredType = self:checkFunctionCall(inferredType, argumentTypes, callToken, explicitTypeArguments)
			else
				inferredType = self:checkFunctionCall(inferredType, argumentTypes, callToken, explicitTypeArguments)
			end
			explicitTypeArguments = nil
		elseif self:check("string") then
			self:take()
			self:emit(OP.PUSH_CONSTANT, self.tokens[self.at - 1].value)
			self:emitCall(1, false, false)
			inferredType = "any"
		elseif self:check("{") then
			self:expression(13)
			self:emitCall(1, false, false)
			inferredType = "any"
		elseif self:check("<") and self:peek(1).kind == "<" then
			explicitTypeArguments = self:parseExplicitTypeInstantiation()
			if not self:check("(") then
				raiseDiagnostic(self:peek(), "SyntaxError", "Expected '(' after explicit type arguments, got " .. displayToken(self:peek()))
			end
		elseif self:match("::") then
			inferredType = self:parseType()
		else
			local operator = self:peek().kind
			local opPrecedence = precedence[operator]
			if not opPrecedence or opPrecedence < minPrecedence then
				break
			end

			local operatorToken = self:take()
			local leftType = inferredType
			local rightPrecedence = opPrecedence + ((operator == "^" or operator == "..") and 0 or 1)

			if operator == "and" then
				self:emit(OP.DUP)
				local shortCircuit = self:emit(OP.JUMP_IF_FALSE, 0)
				self:emit(OP.POP)
				local rightType = self:expression(rightPrecedence)
				self:patch(shortCircuit, #self.code + 1)
				inferredType = joinTypes(leftType, rightType)
			elseif operator == "or" then
				self:emit(OP.DUP)
				local shortCircuit = self:emit(OP.JUMP_IF_TRUE, 0)
				self:emit(OP.POP)
				local rightType = self:expression(rightPrecedence)
				self:patch(shortCircuit, #self.code + 1)
				inferredType = joinTypes(leftType, rightType)
			else
				local rightType = self:expression(rightPrecedence)
				if operator == "+" or operator == "-" or operator == "*"
					or operator == "/" or operator == "//" or operator == "%" or operator == "^" then
					inferredType = "number"
				elseif operator == ".." then
					inferredType = "string"
				else
					inferredType = "boolean"
				end
				emitBinary(self, operator)
			end
		end
	end

	return inferredType
end

function Compiler:compileIfLocalBranch()
	local keyword = self:take()
	local isConst = keyword.value == "const"
	local nameToken = self:expect("name")
	local name = nameToken.value

	local declaredType
	if self:match(":") then
		declaredType = self:parseType()
	end

	if self:check(",") then
		local token = self:peek()
		raiseDiagnostic(token, "SyntaxError", "'" .. keyword.value .. "' in an if condition requires exactly one binding")
	end

	self:expect("=")
	local initializerType = self:expression(1)

	if self:check(",") then
		local token = self:peek()
		raiseDiagnostic(token, "SyntaxError", "'" .. keyword.value .. "' in an if condition requires exactly one initializer expression")
	end
	self:expect("then")

	self:emit(OP.DUP)
	local falseJump = self:emit(OP.JUMP_IF_FALSE, 0)

	self:enterScope()
	self:declareBinding(name, isConst, declaredType or initializerType)
	self:emit(OP.DECLARE_LOCAL, name)
	while not self:check("eof") and not self:check("elseif")
		and not self:check("else") and not self:check("end") do
		self:statement()
	end
	self:exitScope()

	if self:match("elseif") then
		local endJump = self:emit(OP.JUMP, 0)
		self:patch(falseJump, #self.code + 1)
		self:emit(OP.POP)
		self:compileIfBranch()
		self:patch(endJump, #self.code + 1)
	elseif self:match("else") then
		local endJump = self:emit(OP.JUMP, 0)
		self:patch(falseJump, #self.code + 1)
		self:emit(OP.POP)
		self:compileBlock({ ["end"] = true })
		self:expect("end")
		self:patch(endJump, #self.code + 1)
	else
		local endJump = self:emit(OP.JUMP, 0)
		self:patch(falseJump, #self.code + 1)
		self:emit(OP.POP)
		self:expect("end")
		self:patch(endJump, #self.code + 1)
	end
end

function Compiler:compileIfBranch()
	if self:check("local") or (self:checkName("const") and self:peek(1).kind == "name") then
		return self:compileIfLocalBranch()
	end

	self:expression(1)
	self:expect("then")

	local falseJump = self:emit(OP.JUMP_IF_FALSE, 0)
	self:compileBlock({
		["elseif"] = true,
		["else"] = true,
		["end"] = true,
	})

	if self:match("elseif") then
		local endJump = self:emit(OP.JUMP, 0)
		self:patch(falseJump, #self.code + 1)
		self:compileIfBranch()
		self:patch(endJump, #self.code + 1)
	elseif self:match("else") then
		local endJump = self:emit(OP.JUMP, 0)
		self:patch(falseJump, #self.code + 1)
		self:compileBlock({ ["end"] = true })
		self:expect("end")
		self:patch(endJump, #self.code + 1)
	else
		self:patch(falseJump, #self.code + 1)
		self:expect("end")
	end
end

function Compiler:compileIf()
	self:compileIfBranch()
end

function Compiler:compileWhile()
	local conditionStart = #self.code + 1
	local outerDepth = self.scopeDepth
	local hasBinding = self:check("local") or (self:checkName("const") and self:peek(1).kind == "name")
	local bindingName
	local isConst = false
	local bindingType

	if hasBinding then
		local keyword = self:take()
		isConst = keyword.value == "const"
		local bindingToken = self:expect("name")
		bindingName = bindingToken.value
		if self:match(":") then
			bindingType = self:parseType()
		end
		self:expect("=")
		local initializerType = self:expression(1)
		bindingType = bindingType or initializerType
		self:expect("do")
		self:emit(OP.DUP)
	else
		self:expression(1)
		self:expect("do")
	end

	local exitJump = self:emit(OP.JUMP_IF_FALSE, 0)
	self:enterScope()
	if hasBinding then
		self:declareBinding(bindingName, isConst, bindingType)
		self:emit(OP.DECLARE_LOCAL, bindingName)
	end

	local loopInfo = {
		breaks = {},
		continues = {},
		breakScopeDepth = outerDepth,
		continueScopeDepth = outerDepth,
	}
	self:pushLoop(loopInfo)

	while not self:check("end") and not self:check("eof") do
		self:statement()
	end
	self:expect("end")

	self:exitScope()
	for _, jump in ipairs(loopInfo.continues) do
		self:patch(jump, conditionStart)
	end
	self:emit(OP.JUMP, conditionStart)

	local falseTarget = #self.code + 1
	if hasBinding then
		self:emit(OP.POP)
	end
	local exitTarget = #self.code + 1
	self:patch(exitJump, falseTarget)
	for _, jump in ipairs(loopInfo.breaks) do
		self:patch(jump, exitTarget)
	end

	self:popLoop()
end

function Compiler:compileRepeat()
	local outerDepth = self.scopeDepth
	local repeatStart = #self.code + 1
	self:enterScope()
	local conditionStart = nil
	local loopInfo = {
		breaks = {},
		continues = {},
		breakScopeDepth = outerDepth,
		continueScopeDepth = outerDepth + 1,
	}
	self:pushLoop(loopInfo)

	while not self:check("until") and not self:check("eof") do
		self:statement()
	end
	self:expect("until")
	conditionStart = #self.code + 1
	for _, jump in ipairs(loopInfo.continues) do
		self:patch(jump, conditionStart)
	end

	self:expression(1)
	local repeatJump = self:emit(OP.JUMP_IF_FALSE, 0)
	self:exitScope()
	local exitJump = self:emit(OP.JUMP, 0)
	local repeatAgain = #self.code + 1
	self:emit(OP.EXIT_SCOPE)
	self:emit(OP.JUMP, repeatStart)
	local exitTarget = #self.code + 1

	self:patch(repeatJump, repeatAgain)
	self:patch(exitJump, exitTarget)
	for _, jump in ipairs(loopInfo.breaks) do
		self:patch(jump, exitTarget)
	end
	self:popLoop()
end

function Compiler:compileDo()
	self:compileBlock({ ["end"] = true })
	self:expect("end")
end

function Compiler:isTableAssignmentAhead()
	local cursor = self.at
	local hasAccess = false

	while true do
		local kind = self.tokens[cursor].kind
		if kind == "." then
			hasAccess = true
			cursor += 2
		elseif kind == "[" then
			hasAccess = true
			cursor += 1
			local depth = 1
			while depth > 0 and self.tokens[cursor].kind ~= "eof" do
				if self.tokens[cursor].kind == "[" then
					depth += 1
				elseif self.tokens[cursor].kind == "]" then
					depth -= 1
				end
				cursor += 1
			end
		else
			break
		end
	end

	return hasAccess and assignmentOperators[self.tokens[cursor].kind] == true
end

function Compiler:compileTableAssignment(rootName)
	self:emit(OP.PUSH_NAME, rootName)
	local targetType = self:lookupType(rootName)

	while true do
		if self:match(".") then
			local propertyName = self:expect("name").value
			targetType = tablePropertyType(targetType, propertyName)
			self:emit(OP.PUSH_CONSTANT, propertyName)
		elseif self:match("[") then
			local keyToken = self:peek()
			local staticKey
			if keyToken.kind == "string" then
				staticKey = keyToken.value
			elseif keyToken.kind == "number" then
				staticKey = keyToken.value
			end
			self:expression(1)
			self:expect("]")
			if staticKey ~= nil then
				targetType = tablePropertyType(targetType, staticKey)
			else
				targetType = "any"
			end
		else
			raiseDiagnostic(self:peek(), "SyntaxError", "Invalid table assignment target")
		end

		if self:check(".") or self:check("[") then
			self:emit(OP.TABLE_GET)
		else
			break
		end
	end

	local operator = self:take().kind
	if not assignmentOperators[operator] then
		local token = self.tokens[self.at - 1]
		raiseDiagnostic(token, "SyntaxError", "Expected an assignment operator, got " .. displayToken(token))
	end

	if operator == "=" then
		local assignedType = self:expression(1)
	else
		self:emit(OP.DUP_PAIR)
		self:emit(OP.TABLE_GET)
		local rightType = self:expression(1)
		local expectedType = if operator == "..=" then "string|number" else "number"
		emitBinary(self, compoundOperators[operator])
	end
	self:emit(OP.TABLE_SET)
end

local matchingDelimiters = {
	["("] = ")",
	["["] = "]",
	["{"] = "}",
}

function Compiler:skipDelimitedTokens(cursor)
	local first = self.tokens[cursor]
	local expected = matchingDelimiters[first.kind]
	if not expected then
		return cursor
	end

	local stack = { expected }
	cursor += 1

	while #stack > 0 and self.tokens[cursor].kind ~= "eof" do
		local kind = self.tokens[cursor].kind
		local closing = matchingDelimiters[kind]

		if closing then
			stack[#stack + 1] = closing
		elseif kind == stack[#stack] then
			stack[#stack] = nil
		end

		cursor += 1
	end

	return cursor
end

function Compiler:scanAssignmentTarget(cursor)
	local firstKind = self.tokens[cursor].kind
	local rootIsName = firstKind == "name"
	if rootIsName then
		cursor += 1
	elseif firstKind == "(" then
		cursor = self:skipDelimitedTokens(cursor)
	else
		return nil
	end

	local hasField = false
	local hasCall = false

	while true do
		local kind = self.tokens[cursor].kind
		if kind == "." then
			if self.tokens[cursor + 1].kind ~= "name" then
				return nil
			end
			cursor += 2
			hasField = true
		elseif kind == "[" then
			cursor = self:skipDelimitedTokens(cursor)
			hasField = true
		elseif kind == "(" then
			cursor = self:skipDelimitedTokens(cursor)
			hasCall = true
			hasField = false
		elseif kind == ":" then
			if self.tokens[cursor + 1].kind ~= "name" then
				return nil
			end
			cursor += 2
			local argumentKind = self.tokens[cursor].kind
			if argumentKind == "(" or argumentKind == "{" then
				cursor = self:skipDelimitedTokens(cursor)
			elseif argumentKind == "string" then
				cursor += 1
			else
				return nil
			end
			hasCall = true
			hasField = false
		elseif kind == "string" then
			cursor += 1
			hasCall = true
			hasField = false
		elseif kind == "{" then
			cursor = self:skipDelimitedTokens(cursor)
			hasCall = true
			hasField = false
		else
			break
		end
	end

	if hasField then
		return cursor, "table"
	elseif rootIsName and not hasCall then
		return cursor, "variable"
	end

	return nil
end

function Compiler:isMultiAssignmentAhead()
	local cursor = self.at
	local targetCount = 0
	local hasTableTarget = false

	while true do
		local nextCursor, targetKind = self:scanAssignmentTarget(cursor)
		if not nextCursor then
			return false
		end

		targetCount += 1
		hasTableTarget = hasTableTarget or targetKind == "table"
		cursor = nextCursor

		if self.tokens[cursor].kind == "," then
			cursor += 1
		elseif self.tokens[cursor].kind == "=" then
			return targetCount > 1 and hasTableTarget
		else
			return false
		end
	end
end

function Compiler:compileAssignmentTarget()
	local rootKind = self:peek().kind
	local variableName
	if rootKind == "name" then
		variableName = self:take().value
		local nextKind = self:peek().kind
		if nextKind == "." or nextKind == "[" or nextKind == "(" or nextKind == ":"
			or nextKind == "string" or nextKind == "{" then
			self:emit(OP.PUSH_NAME, variableName)
			variableName = nil
		end
	elseif rootKind == "(" then
		self:take()
		self:expression(1)
		self:expect(")")
	else
		local token = self:peek()
		raiseDiagnostic(token, "SyntaxError", "Invalid assignment target")
	end

	while true do
		if self:match(".") then
			self:emit(OP.PUSH_CONSTANT, self:expect("name").value)
			local nextKind = self:peek().kind
			if nextKind == "." or nextKind == "[" or nextKind == "(" or nextKind == ":"
				or nextKind == "string" or nextKind == "{" then
				self:emit(OP.TABLE_GET)
			else
				return { kind = "table" }
			end
		elseif self:match("[") then
			self:expression(1)
			self:expect("]")
			local nextKind = self:peek().kind
			if nextKind == "." or nextKind == "[" or nextKind == "(" or nextKind == ":"
				or nextKind == "string" or nextKind == "{" then
				self:emit(OP.TABLE_GET)
			else
				return { kind = "table" }
			end
		elseif self:check("(") then
			local argumentCount, expandLast = self:parseArguments()
			self:emitCall(argumentCount, expandLast, false)
		elseif self:match(":") then
			self:compileNameCall()
		elseif self:check("string") then
			local argument = self:take()
			self:emit(OP.PUSH_CONSTANT, argument.value)
			self:emitCall(1, false, false)
		elseif self:check("{") then
			self:expression(13)
			self:emitCall(1, false, false)
		else
			break
		end
	end

	if variableName then
		return { kind = "variable", name = variableName }
	end

	local token = self:peek()
	raiseDiagnostic(token, "SyntaxError", "Invalid assignment target")
end

function Compiler:compileMultiAssignment()
	local targets = {}
	repeat
		local target = self:compileAssignmentTarget()
		if target.kind == "variable" then
			self:assertWritable(target.name)
		end
		targets[#targets + 1] = target
	until not self:match(",")

	self:expect("=")
	local expressionCount, expandLast, expressionTypes = self:parseExpressionList()
	for index, target in ipairs(targets) do
		if target.kind == "variable" then
			local assignedType = expressionTypes[index]
			if assignedType == nil then
				assignedType = if expandLast then "any" else "nil"
			end
		end
	end
	self:emit(OP.ASSIGN_TARGETS, {
		targets = targets,
		count = expressionCount,
		expandLast = expandLast,
	})
end

function Compiler:isPrefixAssignmentAhead()
	local cursor, targetKind = self:scanAssignmentTarget(self.at)
	return cursor ~= nil
		and targetKind ~= nil
		and assignmentOperators[self.tokens[cursor].kind] == true
end

function Compiler:compileLocalCompoundAssignment(name, operator)
	self:emit(OP.PUSH_NAME, name)
	local rightType = self:expression(1)
	emitBinary(self, compoundOperators[operator])
	self:emit(OP.SET_LOCAL, name)
	return rightType
end

function Compiler:compilePrefixAssignment()
	local target = self:compileAssignmentTarget()
	local operator = self:take().kind
	if not assignmentOperators[operator] then
		local token = self.tokens[self.at - 1]
		raiseDiagnostic(token, "SyntaxError", "Expected an assignment operator, got " .. displayToken(token))
	end

	if target.kind == "variable" then
		self:assertWritable(target.name)
		if operator == "=" then
			self:expression(1)
			self:emit(OP.SET_LOCAL, target.name)
		else
			self:compileLocalCompoundAssignment(target.name, operator)
		end
		return
	end

	if operator ~= "=" then
		self:emit(OP.DUP_PAIR)
		self:emit(OP.TABLE_GET)
		self:expression(1)
		emitBinary(self, compoundOperators[operator])
	else
		self:expression(1)
	end
	self:emit(OP.TABLE_SET)
end

function Compiler:parseForNames()
	local names = {}
	repeat
		names[#names + 1] = self:expect("name").value
		if self:match(":") then
			self:parseType()
		end
	until not self:match(",")

	return names
end

function Compiler:compileNumericFor(name)
	self:expression(1)
	self:expect(",")
	self:expression(1)

	if self:match(",") then
		self:expression(1)
	else
		self:emit(OP.PUSH_CONSTANT, 1)
	end

	self:expect("do")
	local outerDepth = self.scopeDepth
	self:enterScope()
	self:declareBinding(name, false, "number")
	local prep = self:emit(OP.NUMERIC_FOR_PREP, name, 0)
	local bodyStart = #self.code + 1
	self:emit(OP.ENTER_SCOPE)
	self.scopeDepth += 1
	self.scopes[#self.scopes + 1] = { bindings = {}, types = {} }
	local loopInfo = {
		breaks = {},
		continues = {},
		breakScopeDepth = outerDepth,
		continueScopeDepth = outerDepth,
	}
	self:pushLoop(loopInfo)

	while not self:check("end") and not self:check("eof") do
		self:statement()
	end
	self:expect("end")

	self:emit(OP.EXIT_SCOPE)
	self.scopeDepth -= 1
	self.scopes[#self.scopes] = nil

	local incrementInstruction = self:emit(OP.NUMERIC_FOR_NEXT, bodyStart)
	for _, jump in ipairs(loopInfo.continues) do
		self:patch(jump, incrementInstruction)
	end

	local exhaustedJump = self:emit(OP.JUMP, 0)
	local breakCleanup = #self.code + 1
	self:emit(OP.NUMERIC_FOR_CLEANUP)
	local scopeExitInstruction = #self.code + 1
	self:exitScope()

	self.code[prep][3] = scopeExitInstruction
	self:patch(exhaustedJump, scopeExitInstruction)
	for _, jump in ipairs(loopInfo.breaks) do
		self:patch(jump, breakCleanup)
	end

	self:popLoop()
end

function Compiler:compileGenericFor(names)
	if #names > 32 then
		raiseDiagnostic(self:peek(), "SyntaxError", "Generic for loops support at most 32 variables")
	end
	self:expect("in")

	local expressionCount = 0
	repeat
		self:expression(1)
		expressionCount += 1

		if not self:check(",") then
			self:markLastExpressionMulti()
		end
	until not self:match(",")

	self:expect("do")
	local outerDepth = self.scopeDepth
	self:enterScope()
	for _, loopName in ipairs(names) do
		self:declareBinding(loopName, false)
	end

	local bodyStart = #self.code + 1
	self:enterScope()
	local loopInfo = {
		nativeGeneric = true,
		breakScopeDepth = outerDepth + 1,
		continueScopeDepth = outerDepth + 1,
	}
	self:pushLoop(loopInfo)

	while not self:check("end") and not self:check("eof") do
		self:statement()
	end
	self:expect("end")

	self:exitScope()
	self:popLoop()

	local bodyEnd = #self.code
	local bodyCode = table.create(bodyEnd - bodyStart + 1)
	local offset = bodyStart - 1
	for sourceIndex = bodyStart, bodyEnd do
		local instruction = self.code[sourceIndex]
		local opcode = instruction[1]
		if (opcode == OP.JUMP or opcode == OP.JUMP_IF_FALSE or opcode == OP.JUMP_IF_TRUE
			or opcode == OP.NUMERIC_FOR_NEXT) and type(instruction[2]) == "number" then
			instruction[2] -= offset
		elseif opcode == OP.NUMERIC_FOR_PREP and type(instruction[3]) == "number" then
			instruction[3] -= offset
		end
		bodyCode[sourceIndex - offset] = instruction
		self.code[sourceIndex] = nil
	end

	self:emit(OP.GENERIC_FOR, {
		expressionCount = expressionCount,
		names = names,
		body = bodyCode,
	})
	self:exitScope()
end

function Compiler:compileFor()
	local names = self:parseForNames()

	if self:match("=") then
		if #names ~= 1 then
			raiseDiagnostic(self:peek(-1), "SyntaxError", "Expected one loop variable in numeric for loop, got " .. tostring(#names))
		end
		self:compileNumericFor(names[1])
	else
		self:compileGenericFor(names)
	end
end

function Compiler:statement()
	local terminalStatement

	if self:check("@") then
		self:parseAttributes()
		local localFunction = self:check("local") and self:peek(1).kind == "function"
		local constFunction = self:checkName("const") and self:peek(1).kind == "function"
		if not localFunction and not constFunction and not self:check("function") then
			local token = self:peek()
			raiseDiagnostic(token, "SyntaxError", "Expected a function declaration after attributes, got " .. displayToken(token))
		end
	end

	local isLocalDeclaration = self:match("local")
	local isConstDeclaration = false
	if not isLocalDeclaration and self:checkName("const") then
		local nextKind = self:peek(1).kind
		if nextKind == "function" or nextKind == "name" then
			self:take()
			isLocalDeclaration = true
			isConstDeclaration = true
		end
	end

	if isLocalDeclaration then
		local isConst = isConstDeclaration

		if self:match("function") then
			local functionNameToken = self:expect("name")
			local functionName = functionNameToken.value
			self:declareBinding(functionName, isConst)
			self:emit(OP.PUSH_CONSTANT, nil)
			self:emit(OP.DECLARE_LOCAL, functionName)
			local prototype, functionType = self:compileFunctionPrototype(false)
			self:emit(OP.CLOSURE, prototype)
			self:emit(OP.DECLARE_LOCAL, functionName)
			self:setBindingType(functionName, functionType)
		else
			local names = {}
			local annotations = {}
			local nameTokens = {}
			repeat
				local nameToken = self:expect("name")
				names[#names + 1] = nameToken.value
				nameTokens[#nameTokens + 1] = nameToken
				if self:match(":") then
					annotations[#names] = self:parseType()
				end
			until not self:match(",")

			local expressionCount = 1
			local expandLast = false
			local expressionTypes = {}
			if self:match("=") then
				expressionCount, expandLast, expressionTypes = self:parseExpressionList()
			elseif isConst then
				local token = self:peek()
				raiseDiagnostic(token, "CompileError", "Missing initializer in const declaration")
			else
				self:emit(OP.PUSH_CONSTANT, nil)
				expressionTypes[1] = "nil"
			end

			if #names == 1 and not expandLast then
				self:emit(OP.DECLARE_LOCAL, names[1])
			else
				self:emit(OP.DECLARE_LOCALS, {
					names = names,
					count = expressionCount,
					expandLast = expandLast,
				})
			end
			for index, localName in ipairs(names) do
				local declaredType = annotations[index]
				local actualType = expressionTypes[index]
				if declaredType ~= nil then
					if actualType == nil then
						actualType = if expandLast then "any" else "nil"
					end
				end
				if declaredType == nil and actualType == "nil" then
					actualType = "any"
				end
				self:declareBinding(localName, isConst, declaredType or actualType)
			end
		end

	elseif self:checkName("type") and (self:peek(1).kind == "function" or self:peek(1).kind == "name") then
		self:take()
		if self:match("function") then
			self:expect("name")
			self:compileFunctionPrototype()
		else
			local aliasName = self:expect("name").value
			local genericParameters = {}
			if self:check("<") then
				genericParameters = self:parseGenericParameterList(true)
			end
			self:expect("=")
			local aliasDefinition = self:parseType()
			local packs, defaults = self:genericParameterMetadata(genericParameters)
			self.typeAliases[aliasName] = if #genericParameters > 0 then {
				kind = "genericAlias",
				parameters = genericParameters,
				packs = packs,
				defaults = defaults,
				definition = aliasDefinition,
			} else aliasDefinition
		end

	elseif self:checkName("export") and self:checkName("type", 1) then
		self:take()
		self:take()
		if self:match("function") then
			self:expect("name")
			self:compileFunctionPrototype()
		else
			local aliasName = self:expect("name").value
			local genericParameters = {}
			if self:check("<") then
				genericParameters = self:parseGenericParameterList(true)
			end
			self:expect("=")
			local aliasDefinition = self:parseType()
			local packs, defaults = self:genericParameterMetadata(genericParameters)
			self.typeAliases[aliasName] = if #genericParameters > 0 then {
				kind = "genericAlias",
				parameters = genericParameters,
				packs = packs,
				defaults = defaults,
				definition = aliasDefinition,
			} else aliasDefinition
			self.exportedTypes = self.exportedTypes or {}
			self.exportedTypes[aliasName] = self.typeAliases[aliasName]
		end

	elseif self:match("function") then
		local functionNameToken = self:expect("name")
		local functionName = functionNameToken.value
		local isMember = self:check(".") or self:check(":")
		if not isMember then
			self:assertWritable(functionName, functionNameToken)
		end
		local isMethod = false

		if isMember then
			self:emit(OP.PUSH_NAME, functionName)
			while true do
				if self:match(".") then
					local key = self:expect("name").value
					self:emit(OP.PUSH_CONSTANT, key)
					if self:check(".") or self:check(":") then
						self:emit(OP.TABLE_GET)
					else
						break
					end
				elseif self:match(":") then
					local key = self:expect("name").value
					self:emit(OP.PUSH_CONSTANT, key)
					isMethod = true
					break
				else
					raiseDiagnostic(self:peek(), "SyntaxError", "Invalid function declaration target")
				end
			end
			local prototype = self:compileFunctionPrototype(isMethod)
			self:emit(OP.CLOSURE, prototype)
			self:emit(OP.TABLE_SET)
		else
			local prototype, functionType = self:compileFunctionPrototype(false)
			self:emit(OP.CLOSURE, prototype)
			self:emit(OP.SET_LOCAL, functionName)
			self:setBindingType(functionName, functionType)
		end

	elseif self:match("if") then
		self:compileIf()

	elseif self:match("while") then
		self:compileWhile()

	elseif self:match("for") then
		self:compileFor()

	elseif self:match("do") then
		self:compileDo()

	elseif self:match("repeat") then
		self:compileRepeat()

	elseif self:match("break") then
		terminalStatement = "break"
		local loopInfo = self.loopStack[#self.loopStack]
		if not loopInfo then
			raiseDiagnostic(self:peek(-1), "SyntaxError", "break statement must be inside a loop")
		end
		if loopInfo.nativeGeneric then
			self:emitNativeLoopControl(OP.BREAK, loopInfo.breakScopeDepth or self.scopeDepth)
		else
			loopInfo.breaks[#loopInfo.breaks + 1] = self:emitScopeCleanupJump(
				loopInfo.breakScopeDepth or loopInfo.scopeDepth or self.scopeDepth
			)
		end

	elseif self:check("name") and self:peek().value == "continue"
		and (self:peek(1).line > self:peek().line
			or self:peek(1).kind == "eof"
			or self:peek(1).kind == "end"
			or self:peek(1).kind == "else"
			or self:peek(1).kind == "elseif"
			or self:peek(1).kind == "until"
			or self:peek(1).kind == ";") then
		self:take()
		terminalStatement = "continue"
		local loopInfo = self.loopStack[#self.loopStack]
		if not loopInfo then
			raiseDiagnostic(self:peek(-1), "SyntaxError", "continue statement must be inside a loop")
		end
		if loopInfo.nativeGeneric then
			self:emitNativeLoopControl(OP.CONTINUE, loopInfo.continueScopeDepth or self.scopeDepth)
		else
			loopInfo.continues[#loopInfo.continues + 1] = self:emitScopeCleanupJump(
				loopInfo.continueScopeDepth or loopInfo.scopeDepth or self.scopeDepth
			)
		end

	elseif self:match("return") then
		terminalStatement = "return"
		if self:check("eof") or self:check("end") or self:check(";")
			or self:check("until") or self:check("elseif") or self:check("else") then
			if self.expectedReturnType ~= nil then
			end
			self:emit(OP.RETURN, 0)
		else
			local expressionCount, expandLast, expressionTypes = self:parseExpressionList()
			if self.expectedReturnType ~= nil then
			end
			if expressionCount == 1 and not expandLast then
				self:emit(OP.RETURN, 1)
			else
				self:emit(if expandLast then OP.RETURN_EXPAND else OP.RETURN, expressionCount)
			end
		end

	elseif self:isMultiAssignmentAhead() then
		self:compileMultiAssignment()

	elseif self:isPrefixAssignmentAhead() then
		self:compilePrefixAssignment()

	elseif self:check("name") then
		local name = self:take().value
		local nextKind = self:peek().kind

		if nextKind == "," then
			local names = { name }
			self:assertWritable(name, self.tokens[self.at - 1])
			repeat
				self:expect(",")
				local nameToken = self:expect("name")
				self:assertWritable(nameToken.value, nameToken)
				names[#names + 1] = nameToken.value
			until not self:check(",")
			self:expect("=")
			local expressionCount, expandLast, expressionTypes = self:parseExpressionList()
			for index, targetName in ipairs(names) do
				local assignedType = expressionTypes[index]
				if assignedType == nil then
					assignedType = if expandLast then "any" else "nil"
				end
			end
			self:emit(OP.SET_LOCALS, {
				names = names,
				count = expressionCount,
				expandLast = expandLast,
			})
		elseif self:isTableAssignmentAhead() then
			self:compileTableAssignment(name)
		elseif assignmentOperators[nextKind] then
			self:assertWritable(name, self.tokens[self.at - 1])
			local operator = self:take().kind
			if operator == "=" then
				local assignedType = self:expression(1)
				self:emit(OP.SET_LOCAL, name)
			else
				local rightType = self:compileLocalCompoundAssignment(name, operator)
				local expectedType = if operator == "..=" then "string|number" else "number"
			end
		else
			self.at -= 1
			self:expression(1)
			local instruction = self.code[#self.code]
			if not instruction or not callOpcodes[instruction[1]] then
				local token = self:peek()
				raiseDiagnostic(token, "SyntaxError", "Expected a function call statement, got " .. displayToken(token))
			end
			self:emit(OP.POP)
		end
	elseif self:check("(") or self:check("...") then
		self:expression(1)
		local instruction = self.code[#self.code]
		local opcode = instruction and instruction[1]
		if not callOpcodes[opcode] then
			local token = self:peek()
			raiseDiagnostic(token, "SyntaxError", "Expected a function call statement, got " .. displayToken(token))
		end
		self:emit(OP.POP)
	else
		local token = self:peek()
		raiseDiagnostic(token, "SyntaxError", "Expected a statement, got " .. displayToken(token))
	end

	self:match(";")
	if terminalStatement then
		local nextToken = self:peek()
		local blockEnd = nextToken.kind == "eof" or nextToken.kind == "end"
			or nextToken.kind == "else" or nextToken.kind == "elseif"
			or nextToken.kind == "until"
		if not blockEnd then
			raiseDiagnostic(nextToken, "SyntaxError",
				"Expected end of block after '" .. terminalStatement .. "', got " .. displayToken(nextToken))
		end
	end
end

function Compiler:compile()
	while not self:check("eof") do
		self:statement()
	end

	return {
		code = self.code,
		constants = self.constants,
		exportedTypes = self.exportedTypes,
	}
end

local function tokenize(source, internStrings)
	assert(type(source) == "string", "LuauX.tokenize expects source text")
	return Lexer.new(source, internStrings):tokenize()
end

local function compile(source, options)
	assert(type(source) == "string", "LuauX.compile expects source text")
	options = options or { }

	local sourceName = options.chunkname or options.ChunkName or options.sourceName or options.SourceName
	local tokens = Lexer.new(source, false, sourceName):tokenize()

	local mode = options and options.typeMode or tokens.typeMode
	if mode ~= "strict" and mode ~= "nonstrict" and mode ~= "nocheck" then
		error("LuauX.compile typeMode must be 'strict', 'nonstrict', or 'nocheck'", 0)
	end

	tokens.typeMode = mode
	local succeeded, result = pcall(function()
		return Compiler.new(tokens, nil, nil, nil, mode, options.typeAliases, options.globalTypes):compile()
	end)

	if succeeded then
		return result
	end

	local message = tostring(result)
	local line, column, detail = message:match("Compiler:(%d+):(%d+) (.*)")
	if line then
		local lowered = string.lower(detail)
		local category = if string.find(lowered, "expected", 1, true)
			or string.find(lowered, "invalid assignment target", 1, true)
			or string.find(lowered, "unsupported", 1, true)
			then "SyntaxError" else "CompileError"

		local first = string.sub(detail, 1, 1)

		if first == "e" then
			detail = "E" .. string.sub(detail, 2)
		end

		raiseDiagnostic({ line = tonumber(line), column = tonumber(column) }, category, detail)
	end

	local generic = message:match("Compiler: (.*)")
	if generic then
		error(generic, 0)
	end

	error(result, 0)
end

return {
	new = Compiler.new,
	tokenize = tokenize,
	compile = compile,
}
