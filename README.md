# LuauX VM

**The lightweight, high-performance Luau virtual machine.**

LuauX is a compact Luau VM built with one primary goal: **maximum performance with minimal overhead.**

Despite its small size, LuauX supports all modern Luau syntax, providing a lightweight alternative for executing Luau code through its own virtual machine.

## ✨ Features

- ⚡ **Blazing Fast** — Designed with execution speed as a priority.
- 📦 **Extremely Lightweight** — A small implementation without unnecessary overhead.
- 🧩 **Modern Luau Support** — Supports all modern Luau syntax.
- 🔧 **Flexible API** — Compile, tokenize, load, and execute Luau code.
- 🌍 **Custom Environments** — Execute programs with custom global environments.
- 🔌 **VM Hooks** — Access the VM's exposed hooks and opcode definitions.

## 📥 Installation

Clone the repository:

```bash
git clone https://github.com/Its-Kawi/LuauX-VM.git
```

Require the LuauX module in your project:

```lua
local LuauX = require(path.to.LuauX)
```

## 🚀 Quick Start

The simplest way to execute Luau code is with `LuauX.run`:

```lua
local LuauX = require(path.to.LuauX)

LuauX.run([[
    local message = "Hello from LuauX!"
    print(message)
]])
```

You can also compile and load code separately:

```lua
local compiled = LuauX.compile([[
    local function add(a, b)
        return a + b
    end

    return add(10, 20)
]])

local program = LuauX.load(compiled)

print(program()) -- 30
```

## 📚 API Reference

### `LuauX.tokenize(source, internStrings)`

Tokenizes Luau source code.

| Parameter | Type | Description |
|---|---|---|
| `source` | `string` | Source code to tokenize. |
| `internStrings` | `boolean` | Whether to intern strings during tokenization. |

**Returns:** The compiler's tokenized representation.

```lua
local tokens = LuauX.tokenize([[
    local x = 10
    print(x)
]])
```

### `LuauX.compile(source, options)`

Compiles Luau source code into a LuauX program.

| Parameter | Type | Description |
|---|---|---|
| `source` | `string` | Source code to compile. |
| `options` | `table?` | Compiler options. |

**Returns:** A compiled program.

```lua
local compiled = LuauX.compile([[
    return 100 + 200
]])
```

### `LuauX.load(code, options)`

Loads source code or an already compiled program and returns an executable function.

| Parameter | Type | Description |
|---|---|---|
| `code` | `string \| table` | Source code or compiled program. |
| `options` | `table?` | Loading and environment options. |

Supported options:

| Option | Type | Description |
|---|---|---|
| `Environment` | `table` | Environment used by the VM. |
| `Globals` | `table` | Alternative environment option. |

`Environment` takes precedence over `Globals`.

```lua
local program = LuauX.load([[
    return "Hello, LuauX!"
]])

print(program())
```

You can also load an already compiled program:

```lua
local compiled = LuauX.compile("return 42")
local program = LuauX.load(compiled)

print(program()) -- 42
```

### `LuauX.loadstring(source, chunkName, env)`

Compiles source code and returns an executable function.

Unlike `load`, this function returns `false, error` if compilation fails.

| Parameter | Type | Description |
|---|---|---|
| `source` | `string \| number` | Source code. |
| `chunkName` | `string \| number?` | Optional chunk name. |
| `env` | `table?` | Optional execution environment. |

**Returns:** An executable function on success, or `false, error` on compilation failure.

```lua
local program, err = LuauX.loadstring([[
    return 10 * 10
]], "Example")

if program then
    print(program()) -- 100
else
    warn(err)
end
```

### `LuauX.run(code, options, ...)`

Compiles, loads, and executes code in one call.

| Parameter | Type | Description |
|---|---|---|
| `code` | `string \| table` | Source code or compiled program. |
| `options` | `table \| string?` | Execution options or chunk name. |
| `...` | `any` | Arguments passed to the executed program. |

```lua
local result = LuauX.run([[
    local function multiply(a, b)
        return a * b
    end

    return multiply(...)
]], nil, 5, 10)

print(result) -- 50
```

You can also provide a custom environment:

```lua
local env = {
    print = print,
    answer = 42
}

LuauX.run([[
    print(answer)
]], env)
```

## 🔌 Additional Exports

### `LuauX.Hooks`

Exposes the hooks provided by the internal VM module.

```lua
local hooks = LuauX.Hooks
```

### `LuauX.OPs`

Exposes the VM's opcode definitions.

```lua
local opcodes = LuauX.OPs
```

These exports allow advanced users to inspect and interact with the VM's exposed internals.

## 📖 Examples

### Reusing Compiled Programs

Compile once and execute the resulting program multiple times:

```lua
local compiled = LuauX.compile([[
    local function factorial(n)
        if n <= 1 then
            return 1
        end

        return n * factorial(n - 1)
    end

    return factorial(...)
]])

local factorial = LuauX.load(compiled)

print(factorial(5)) -- 120
print(factorial(10)) -- 3628800
```

### Custom Execution Environment

```lua
local environment = {
    print = print,
    greeting = "Hello"
}

local program = LuauX.load([[
    print(greeting .. " from LuauX!")
]], {
    Environment = environment
})

program()
```

### Using LuauX as a Callable

LuauX can also be called directly. Its metatable forwards calls to `LuauX.loadstring`:

```lua
local program, err = LuauX([[
    return "Executed through LuauX!"
]])

if program then
    print(program())
else
    warn(err)
end
```

## ⚡ Performance

Performance is a central focus of LuauX.

The project aims to combine a minimal implementation with fast execution, while retaining support for modern Luau syntax.

## 📄 License

LuauX VM is licensed under the MIT License. See [LICENSE](LICENSE) for details.

## ⭐ Support

If you find LuauX useful, consider giving the repository a star!

[GitHub Repository](https://github.com/Its-Kawi/LuauX-VM)
