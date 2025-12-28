local json = {}

local function escape_str(s)
  return s:gsub('\\', '\\\\')
          :gsub('"', '\\"')
          :gsub('\b', '\\b')
          :gsub('\f', '\\f')
          :gsub('\n', '\\n')
          :gsub('\r', '\\r')
          :gsub('\t', '\\t')
end

local function is_array(tbl)
  local max = 0
  local count = 0
  for k, _ in pairs(tbl) do
    if type(k) ~= 'number' then
      return false
    end
    if k > max then
      max = k
    end
    count = count + 1
  end
  if max ~= count then
    return false
  end
  return true
end

local function encode_value(value)
  local t = type(value)
  if t == 'nil' then
    return 'null'
  elseif t == 'number' then
    return tostring(value)
  elseif t == 'boolean' then
    return value and 'true' or 'false'
  elseif t == 'string' then
    return '"' .. escape_str(value) .. '"'
  elseif t == 'table' then
    if is_array(value) then
      local items = {}
      for i = 1, #value do
        items[#items + 1] = encode_value(value[i])
      end
      return '[' .. table.concat(items, ',') .. ']'
    else
      local items = {}
      for k, v in pairs(value) do
        if type(k) ~= 'string' then
          -- Skip non-string keys in objects
        else
          items[#items + 1] = '"' .. escape_str(k) .. '":' .. encode_value(v)
        end
      end
      return '{' .. table.concat(items, ',') .. '}'
    end
  end
  return 'null'
end

function json.encode(value)
  return encode_value(value)
end

return json
