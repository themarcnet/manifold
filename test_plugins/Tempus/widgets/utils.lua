-- utils.lua
-- Shared utility functions for widgets

local Utils = {}

function Utils.colour(c, default)
    return c or default or 0xff333333
end

function Utils.clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

function Utils.lerp(a, b, t)
    return a + (b - a) * t
end

function Utils.brighten(c, amount)
    local a = (c >> 24) & 0xff
    local r = math.min(255, ((c >> 16) & 0xff) + amount)
    local g = math.min(255, ((c >> 8) & 0xff) + amount)
    local b = math.min(255, (c & 0xff) + amount)
    return (a << 24) | (r << 16) | (g << 8) | b
end

function Utils.darken(c, amount)
    local a = (c >> 24) & 0xff
    local r = math.max(0, ((c >> 16) & 0xff) - amount)
    local g = math.max(0, ((c >> 8) & 0xff) - amount)
    local b = math.max(0, (c & 0xff) - amount)
    return (a << 24) | (r << 16) | (g << 8) | b
end

function Utils.snapToStep(value, step)
    if step and step > 0 then
        return math.floor(value / step + 0.5) * step
    end
    return value
end

function Utils.cloneArrayOfTables(items)
    local out = {}
    for i = 1, #(items or {}) do
        local src = items[i]
        local dst = {}
        for k, v in pairs(src) do
            if type(v) == "table" then
                local t = {}
                for kk, vv in pairs(v) do
                    t[kk] = vv
                end
                dst[k] = t
            else
                dst[k] = v
            end
        end
        out[#out + 1] = dst
    end
    return out
end

function Utils.makeFontStyleOptions()
    local fs = FontStyle or {}
    return {
        { label = "plain", value = fs.plain or 0 },
        { label = "bold", value = fs.bold or 1 },
        { label = "italic", value = fs.italic or 2 },
        { label = "boldItalic", value = fs.boldItalic or 3 },
    }
end

function Utils.makeJustifyOptions()
    local j = Justify or {}
    return {
        { label = "centred", value = j.centred or 36 },
        { label = "centredLeft", value = j.centredLeft or 33 },
        { label = "centredRight", value = j.centredRight or 34 },
        { label = "topLeft", value = j.topLeft or 9 },
        { label = "topRight", value = j.topRight or 10 },
        { label = "bottomLeft", value = j.bottomLeft or 17 },
        { label = "bottomRight", value = j.bottomRight or 18 },
    }
end

return Utils
