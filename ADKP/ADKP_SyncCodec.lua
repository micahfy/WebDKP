-- Deterministic, bounded data codec for WoW 1.12 / Lua 5.0.
-- No executable Lua is read from files or the network. Repeated strings and
-- the per-reset player dictionary are represented by numeric references.
ADKP_SyncCodec = {}
local C = ADKP_SyncCodec
C.MAX_BYTES = 4194304
C.MAX_NODES = 250000
C.MAX_DEPTH = 24

local function finite(n)
    return type(n) == "number" and n == n and math.abs(n) < 1e308
end

function C.Keys(value)
    local keys = {}
    for key in pairs(value) do
        if type(key) ~= "string" and type(key) ~= "number" then error("invalid key") end
        table.insert(keys, key)
    end
    table.sort(keys, function(a, b)
        if type(a) ~= type(b) then return type(a) == "number" end
        return a < b
    end)
    return keys
end

function C.Pack(value, names)
    local parts, strings, active = {}, {}, {}
    local nodes, bytes, nextString = 0, 0, 0
    local function put(s)
        bytes = bytes + string.len(s)
        if bytes > C.MAX_BYTES then error("data too large") end
        table.insert(parts, s)
    end
    local function encode(v, depth)
        nodes = nodes + 1
        if nodes > C.MAX_NODES or depth > C.MAX_DEPTH then error("data too complex") end
        local kind = type(v)
        if kind == "nil" then put("z")
        elseif kind == "boolean" then put(v and "y" or "f")
        elseif kind == "number" then
            if not finite(v) then error("invalid number") end
            local s = string.format("%.17g", v)
            put("n" .. string.len(s) .. ":" .. s)
        elseif kind == "string" then
            if names and names[v] then put("p" .. names[v] .. ":")
            elseif strings[v] then put("r" .. strings[v] .. ":")
            else
                nextString = nextString + 1
                strings[v] = nextString
                put("s" .. string.len(v) .. ":" .. v)
            end
        elseif kind == "table" then
            if active[v] then error("cyclic data") end
            active[v] = true
            local keys = C.Keys(v)
            put("t" .. table.getn(keys) .. ":")
            for i = 1, table.getn(keys) do
                encode(keys[i], depth + 1)
                encode(v[keys[i]], depth + 1)
            end
            active[v] = nil
        else error("unsupported data") end
    end
    encode(value, 0)
    return table.concat(parts)
end

function C.Unpack(text, names)
    if type(text) ~= "string" or string.len(text) > C.MAX_BYTES then error("invalid data size") end
    local position, nodes = 1, 0
    local strings = {}
    local function integer()
        local ending = string.find(text, ":", position, true)
        if not ending or ending - position > 9 then error("invalid length") end
        local token = string.sub(text, position, ending - 1)
        if not string.find(token, "^%d+$") then error("invalid length") end
        position = ending + 1
        return tonumber(token)
    end
    local function decode(depth)
        nodes = nodes + 1
        if nodes > C.MAX_NODES or depth > C.MAX_DEPTH then error("data too complex") end
        local tag = string.sub(text, position, position)
        position = position + 1
        if tag == "z" then return nil end
        if tag == "y" then return true end
        if tag == "f" then return false end
        if tag == "p" or tag == "r" then
            local index = integer()
            local value = (tag == "p" and names or strings)
            value = value and value[index]
            if type(value) ~= "string" then error("missing string dictionary") end
            return value
        end
        if tag == "s" or tag == "n" then
            local length = integer()
            if position + length - 1 > string.len(text) then error("truncated data") end
            local value = string.sub(text, position, position + length - 1)
            position = position + length
            if tag == "s" then table.insert(strings, value); return value end
            value = tonumber(value)
            if not finite(value) then error("invalid number") end
            return value
        end
        if tag == "t" then
            local count = integer()
            if count > C.MAX_NODES then error("invalid table size") end
            local result = {}
            for i = 1, count do
                local key = decode(depth + 1)
                if type(key) ~= "string" and (type(key) ~= "number" or not finite(key)) then error("invalid key") end
                if result[key] ~= nil then error("duplicate key") end
                local value = decode(depth + 1)
                if value == nil then error("nil table entry") end
                result[key] = value
            end
            return result
        end
        error("invalid data tag")
    end
    local value = decode(0)
    if position ~= string.len(text) + 1 then error("extra data") end
    return value
end

function C.Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = C.Copy(item) end
    return result
end

function C.Hash(text)
    local a, b = 1, 0
    for i = 1, string.len(text) do
        a = math.mod(a + string.byte(text, i), 65521)
        b = math.mod(b + a, 65521)
    end
    return string.format("%08x", b * 65536 + a) .. ":" .. string.len(text)
end

function C.Escape(text)
    return string.gsub(text, "([%z\001-\031\127-\255%%|#])", function(c) return string.format("%%%02X", string.byte(c)) end)
end

function C.Unescape(text)
    if string.find(string.gsub(text, "%%%x%x", ""), "%%") then error("invalid escape") end
    return string.gsub(text, "%%(%x%x)", function(code) return string.char(tonumber(code, 16)) end)
end

-- Printable wire encoding; checkpoint Escape/Unescape remains unchanged.
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local base64Values = {}
for i = 1, 64 do base64Values[string.sub(alphabet, i, i)] = i - 1 end

function C.Base64Encode(text)
    local result = {}
    for i = 1, string.len(text), 3 do
        local a, b, c = string.byte(text, i), string.byte(text, i + 1), string.byte(text, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local x, y = math.floor(n / 262144), math.mod(math.floor(n / 4096), 64)
        local z, w = math.mod(math.floor(n / 64), 64), math.mod(n, 64)
        table.insert(result, string.sub(alphabet, x + 1, x + 1) .. string.sub(alphabet, y + 1, y + 1)
            .. (b and string.sub(alphabet, z + 1, z + 1) or "=")
            .. (c and string.sub(alphabet, w + 1, w + 1) or "="))
    end
    return table.concat(result)
end

function C.Base64Decode(text)
    local length = string.len(text)
    if math.mod(length, 4) ~= 0 or length > C.MAX_BYTES * 2 then error("invalid base64 size") end
    local result = {}
    for i = 1, length, 4 do
        local a, b, c, d = string.sub(text, i, i), string.sub(text, i + 1, i + 1),
            string.sub(text, i + 2, i + 2), string.sub(text, i + 3, i + 3)
        local x, y, z, w = base64Values[a], base64Values[b], base64Values[c], base64Values[d]
        if x == nil or y == nil or (c ~= "=" and z == nil) or (d ~= "=" and w == nil)
            or (c == "=" and d ~= "=") or ((c == "=" or d == "=") and i + 3 ~= length)
            or (c == "=" and math.mod(y, 16) ~= 0) or (d == "=" and c ~= "=" and math.mod(z, 4) ~= 0) then
            error("invalid base64 data")
        end
        local n = x * 262144 + y * 4096 + (z or 0) * 64 + (w or 0)
        table.insert(result, string.char(math.floor(n / 65536))
            .. (c ~= "=" and string.char(math.mod(math.floor(n / 256), 256)) or "")
            .. (d ~= "=" and string.char(math.mod(n, 256)) or ""))
    end
    return table.concat(result)
end

-- LZW with fixed 12-bit codes and a bounded 4096-entry dictionary. Clear code
-- zero resets the dictionary; no bit library or executable data is required.
function C.Compress(text)
    if string.len(text) > C.MAX_BYTES then error("compression input too large") end
    local dictionary, nextCode, output, pending = {}, 257, {}, nil
    local function reset()
        dictionary, nextCode = {}, 257
        for i = 0, 255 do dictionary[string.char(i)] = i + 1 end
    end
    local function emit(code)
        if pending then
            table.insert(output, string.char(math.floor(pending / 16), math.mod(pending, 16) * 16
                + math.floor(code / 256), math.mod(code, 256)))
            pending = nil
        else pending = code end
    end
    reset()
    local word = ""
    for i = 1, string.len(text) do
        local char = string.sub(text, i, i)
        local joined = word .. char
        if dictionary[joined] then word = joined
        else
            emit(dictionary[word])
            if nextCode <= 4095 then dictionary[joined] = nextCode; nextCode = nextCode + 1
            else emit(0); reset() end
            word = char
        end
    end
    if word ~= "" then emit(dictionary[word]) end
    if pending then table.insert(output, string.char(math.floor(pending / 16), math.mod(pending, 16) * 16)) end
    return table.concat(output)
end

function C.Decompress(text, limit)
    limit = math.min(limit or C.MAX_BYTES, C.MAX_BYTES)
    local length = string.len(text)
    if length > C.MAX_BYTES * 2 or math.mod(length, 3) == 1 then error("invalid compressed size") end
    local dictionary, nextCode, previous, output, bytes = {}, 257, nil, {}, 0
    local function reset()
        dictionary, nextCode, previous = {}, 257, nil
        for i = 0, 255 do dictionary[i + 1] = string.char(i) end
    end
    local function decode(code)
        if code == 0 then
            if nextCode <= 4095 then error("premature dictionary reset") end
            reset(); return
        end
        local word = dictionary[code]
        if not word and code == nextCode and previous then word = previous .. string.sub(previous, 1, 1) end
        if not word then error("invalid compression dictionary") end
        bytes = bytes + string.len(word)
        if bytes > limit then error("decompressed data too large") end
        table.insert(output, word)
        if previous and nextCode <= 4095 then
            dictionary[nextCode] = previous .. string.sub(word, 1, 1); nextCode = nextCode + 1
        end
        previous = word
    end
    reset()
    for i = 1, length, 3 do
        local a, b, c = string.byte(text, i), string.byte(text, i + 1), string.byte(text, i + 2)
        decode(a * 16 + math.floor(b / 16))
        if c then decode(math.mod(b, 16) * 256 + c)
        elseif math.mod(b, 16) ~= 0 then error("invalid compressed padding") end
    end
    return table.concat(output)
end

function C.WireEncode(text)
    local best = "E" .. C.Escape(text)
    local binary = "B" .. C.Base64Encode(text)
    if string.len(binary) < string.len(best) then best = binary end
    if string.len(text) >= 512 then
        local compressed = "Z" .. C.Base64Encode(C.Compress(text))
        if string.len(compressed) < string.len(best) then best = compressed end
    end
    return best
end

function C.WireDecode(text)
    if type(text) ~= "string" or string.len(text) > C.MAX_BYTES * 2 then error("invalid wire data") end
    local tag, body = string.sub(text, 1, 1), string.sub(text, 2)
    if tag == "E" then return C.Unescape(body) end
    if tag == "B" then return C.Base64Decode(body) end
    if tag == "Z" then return C.Decompress(C.Base64Decode(body)) end
    error("unknown wire encoding")
end

function C.Diff(before, after)
    local changes = {}
    local function visit(old, new, path)
        if type(old) == "table" and type(new) == "table" then
            local keys = {}
            for key in pairs(old) do keys[key] = true end
            for key in pairs(new) do keys[key] = true end
            local ordered = C.Keys(keys)
            for i = 1, table.getn(ordered) do
                local key = ordered[i]
                local nextPath = C.Copy(path)
                table.insert(nextPath, key)
                visit(old[key], new[key], nextPath)
            end
        elseif old ~= new then
            table.insert(changes, { path = path, remove = new == nil, value = C.Copy(new) })
        end
    end
    visit(before, after, {})
    return changes
end

function C.Patch(before, changes)
    local result = C.Copy(before)
    if type(changes) ~= "table" or table.getn(changes) > 20000 then error("invalid patch") end
    for _, change in ipairs(changes) do
        if type(change) ~= "table" or type(change.path) ~= "table" then error("invalid change") end
        local count = table.getn(change.path)
        if count == 0 or count > C.MAX_DEPTH then error("invalid path") end
        local parent = result
        for i = 1, count - 1 do
            parent = parent[change.path[i]]
            if type(parent) ~= "table" then error("missing patch parent") end
        end
        local key = change.path[count]
        if type(key) ~= "string" and type(key) ~= "number" then error("invalid patch key") end
        if change.remove then parent[key] = nil else parent[key] = C.Copy(change.value) end
    end
    return result
end
