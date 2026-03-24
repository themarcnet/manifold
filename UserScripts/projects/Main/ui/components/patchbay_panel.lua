-- patchbay_panel.lua
-- Generates a dense three-column Eurorack-style patchbay widget tree from a node spec.
--
-- Two broad signal categories:
--   1. AUDIO - warm family (copper/gold/orange tones), larger ports, wave indicator
--   2. CV/MOD - cool family (silver/cyan/blue tones), standard ports, trigger/step indicator
--
-- Port design:
--   - Looks like actual 3.5mm sockets with depth
--   - Dark center hole (where cable plugs in)
--   - Metallic 3D bezel with gradient
--   - Input ports: bezel style + label on right
--   - Output ports: different bezel style + label on left
--   - Signal type encoded in color temperature + subtle iconography
--
-- Pagination:
--   - 1x1 nodes: max 6 params per page
--   - 1x2 nodes: max 12 params per page
--   - Overflow params go to additional pages
--   - Square pagination dots sit under the PARAMS label without pushing content down

local COLORS = {
  -- Audio signal family (warm)
  audioHole   = 0xff1a0f0a,   -- very dark brown (socket interior)
  audioBezel  = 0xffb87333,   -- copper/bronze metallic
  audioHighlight = 0xffe8a87c, -- light copper shine
  audioShadow = 0xff8b4513,   -- dark copper shadow
  
  -- CV/Mod signal family (cool)  
  cvHole      = 0xff0a141a,   -- very dark blue-gray (socket interior)
  cvBezel     = 0xff64748b,   -- silver/steel metallic
  cvHighlight = 0xff94a3b8,   -- light silver shine
  cvShadow    = 0xff475569,   -- dark steel shadow
  
  -- MIDI (distinct purple family)
  midiHole    = 0xff140a1a,   -- very dark purple
  midiBezel   = 0xff9333ea,   -- purple metallic
  
  -- Bus port (distinct yellow/gold for page aggregation)
  busHole     = 0xff1a1505,   -- very dark gold
  busBezel    = 0xffd4af37,   -- gold metallic
  busHighlight = 0xfff0e68c,  -- light gold
  busShadow   = 0xffb8860b,   -- dark gold
  
  -- UI
  label       = 0xffffffff,   -- white
  dimLabel    = 0xff94a3b8,   -- muted gray
  sectionLabel = 0xff64748b,  -- darker gray for headers
  dotActive   = 0xffffffff,   -- white for active page dot
  dotInactive = 0xff475569,   -- slate-600 for inactive
  bg          = 0x00000000,   -- transparent
}

-- Shared slider colors (unchanged - already dark)
local SLIDER_COLORS = {
  adsr = { bg = 0xff280505, fill = 0xffb91c1c },
  oscillator = { bg = 0xff051524, fill = 0xff0284c7 },
  filter = { bg = 0xff1a0842, fill = 0xff7c3aed },
  fx = { bg = 0xff0f172a, fill = 0xff2563eb },
  eq = { bg = 0xff011811, fill = 0xff059669 },
}

local ROW_H = 22
local PORT_SIZE = 14
local PORT_HOLE_SIZE = 8
local SECTION_H = 14
local HEADER_LABEL_Y = -2
local HEADER_LABEL_H = 8
local COL_GAP = 8
local MAX_SLIDER_W = 100
local ROW_GAP = 3
local DOT_SIZE = 5
local DOT_HIT_SIZE = 8
local DOT_GAP = 4
local DOT_ROW_Y = 9
local DOT_ROW_X = 2

-- Max params per page based on node size
local PARAMS_PER_PAGE_1X1 = 6
local PARAMS_PER_PAGE_1X2 = 12

-- Get color family for a signal type
local function getPortColors(portType)
  if portType == "audio" then
    return {
      hole = COLORS.audioHole,
      bezel = COLORS.audioBezel,
      highlight = COLORS.audioHighlight,
      shadow = COLORS.audioShadow,
    }
  elseif portType == "midi" then
    return {
      hole = COLORS.midiHole,
      bezel = COLORS.midiBezel,
      highlight = 0xffc084fc,
      shadow = 0xff7c3aed,
    }
  elseif portType == "bus" then
    return {
      hole = COLORS.busHole,
      bezel = COLORS.busBezel,
      highlight = COLORS.busHighlight,
      shadow = COLORS.busShadow,
    }
  else
    return {
      hole = COLORS.cvHole,
      bezel = COLORS.cvBezel,
      highlight = COLORS.cvHighlight,
      shadow = COLORS.cvShadow,
    }
  end
end

-- Get two-tone slider colors for a node
local function getSliderColors(specId)
  if specId == "fx1" or specId == "fx2" then
    return SLIDER_COLORS.fx
  end
  return SLIDER_COLORS[specId] or { bg = 0xff1e293b, fill = 0xff64748b }
end

-- Build a proper 3D port socket widget
local function portWidget(id, portType, isInput)
  local colors = getPortColors(portType)
  
  return {
    id = id,
    type = "Panel",
    x = 0, y = 0, w = PORT_SIZE, h = PORT_SIZE,
    layoutChild = { grow = 0, shrink = 0, basisW = PORT_SIZE, alignSelf = "center" },
    style = { 
      bg = colors.bezel,
      radius = PORT_SIZE / 2,
      border = colors.shadow,
      borderWidth = isInput and 2 or 3,
    },
    props = { interceptsMouse = false },
    children = {
      {
        id = id .. "_hole",
        type = "Panel",
        x = math.floor((PORT_SIZE - PORT_HOLE_SIZE) / 2),
        y = math.floor((PORT_SIZE - PORT_HOLE_SIZE) / 2),
        w = PORT_HOLE_SIZE,
        h = PORT_HOLE_SIZE,
        style = {
          bg = colors.hole,
          radius = PORT_HOLE_SIZE / 2,
          border = isInput and 0x00000000 or colors.highlight,
          borderWidth = isInput and 0 or 1,
        },
        props = { interceptsMouse = false },
      },
    },
  }
end

-- Build horizontal pagination dots
local function paginationDots(id, numPages, currentPage, x, y)
  local dots = {}
  for i = 1, numPages do
    local isActive = (i - 1) == currentPage
    dots[#dots + 1] = {
      id = id .. "_dot" .. i,
      type = "Panel",
      x = 0, y = 0,
      w = DOT_HIT_SIZE, h = DOT_HIT_SIZE,
      layoutChild = { grow = 0, shrink = 0, basisW = DOT_HIT_SIZE, basisH = DOT_HIT_SIZE },
      style = { bg = 0x00000000, radius = 0 },
      props = { interceptsMouse = true },
      children = {
        {
          id = id .. "_dot" .. i .. "_visual",
          type = "Panel",
          x = math.floor((DOT_HIT_SIZE - DOT_SIZE) / 2),
          y = math.floor((DOT_HIT_SIZE - DOT_SIZE) / 2),
          w = DOT_SIZE, h = DOT_SIZE,
          style = {
            bg = isActive and COLORS.dotActive or COLORS.dotInactive,
            radius = 1,
          },
          props = { interceptsMouse = false },
        },
      },
    }
  end

  return {
    id = id,
    type = "Panel",
    x = x, y = y,
    w = numPages * DOT_HIT_SIZE + (numPages - 1) * DOT_GAP,
    h = DOT_HIT_SIZE,
    style = { bg = 0x00000000 },
    props = { interceptsMouse = false },
    layout = { mode = "stack-x", gap = DOT_GAP, align = "center" },
    children = dots,
  }
end

-- Build a bus port with label
local function busPortWidget(id, pageNum, colW)
  return {
    id = id,
    type = "Panel",
    x = 0, y = 0, w = colW, h = ROW_H,
    layoutChild = { grow = 0, shrink = 0, basisH = ROW_H },
    style = { bg = 0x00000000, radius = 0 },
    props = { interceptsMouse = false },
    layout = { mode = "stack-x", gap = 6, align = "center", padding = { 4, 2, 4, 2 } },
    children = {
      portWidget(id .. "_port", "bus", true),
      {
        id = id .. "_label",
        type = "Label",
        x = 0, y = 0, w = math.max(40, colW - PORT_SIZE - 12), h = ROW_H,
        layoutChild = { grow = 1, shrink = 1, basisW = 40 },
        props = { text = "BUS " .. pageNum },
        style = { colour = COLORS.busBezel, fontSize = 9, bg = 0x00000000 },
      },
    },
  }
end

-- Build a compact slider spec
local function paramSlider(rowId, param, sliderW, rowH, specId)
  local colors = getSliderColors(specId)
  
  local props = {
    min = param.min or 0, max = param.max or 1,
    step = param.step or 0.01, value = param.default or 0.5,
    label = param.label or param.id,
    showValue = true,
    compact = true,
  }
  if param.options and #param.options > 0 then
    props.options = param.options
  end
  return {
    id = rowId .. "_slider",
    type = "Slider",
    x = 0, y = 0, w = math.max(30, sliderW), h = math.max(10, rowH - 6),
    layoutChild = { grow = 0, shrink = 0, basisW = math.max(30, sliderW), alignSelf = "center" },
    props = props,
    style = { 
      colour = colors.fill,
      bg = colors.bg,
      fontSize = 9 
    },
  }
end

-- Build a single param row: [in port?] [slider] [out port?]
local function paramRow(rowId, param, rowW, rowH, specId)
  local hasIn = param.input ~= false
  local hasOut = param.output ~= false
  local availableW = rowW - (hasIn and PORT_SIZE + 6 or 0) - (hasOut and PORT_SIZE + 6 or 0) - 12
  local sliderW = math.min(availableW, MAX_SLIDER_W)

  local children = {}
  if hasIn then
    children[#children + 1] = portWidget(rowId .. "_in", "cv", true)
  end
  children[#children + 1] = paramSlider(rowId, param, sliderW, rowH, specId)
  if hasOut then
    children[#children + 1] = portWidget(rowId .. "_out", "cv", false)
  end

  return {
    id = rowId,
    type = "Panel",
    x = 0, y = 0, w = rowW, h = rowH,
    layoutChild = { grow = 0, shrink = 0, basisH = rowH },
    style = { bg = 0x00000000, radius = 0 },
    props = { interceptsMouse = false },
    layout = { mode = "stack-x", gap = 6, align = "center", padding = { 0, 2, 0, 2 } },
    children = children,
  }
end

-- Build an input row: [port] [label with gap]
local function inputRow(rowId, inp, colW, rowIdx)
  local portType = inp.type or "control"
  
  return {
    id = rowId,
    type = "Panel",
    x = 0, y = 0, w = colW, h = ROW_H,
    layoutChild = { grow = 0, shrink = 0, basisH = ROW_H },
    style = { bg = 0x00000000, radius = 0 },
    props = { interceptsMouse = false },
    layout = { mode = "stack-x", gap = 10, align = "center", padding = { 4, 2, 4, 2 } },
    children = {
      portWidget(rowId .. "_port", portType, true),
      {
        id = rowId .. "_label",
        type = "Label",
        x = 0, y = 0, w = math.max(20, colW - PORT_SIZE - 18), h = ROW_H,
        layoutChild = { grow = 1, shrink = 1, basisW = 20 },
        props = { text = inp.label or inp.id },
        style = { colour = COLORS.label, fontSize = 9, bg = 0x00000000 },
      },
    },
  }
end

-- Build an output row: [label with gap] [port]
local function outputRow(rowId, out, colW, rowIdx)
  local portType = out.type or "audio"
  
  return {
    id = rowId,
    type = "Panel",
    x = 0, y = 0, w = colW, h = ROW_H,
    layoutChild = { grow = 0, shrink = 0, basisH = ROW_H },
    style = { bg = 0x00000000, radius = 0 },
    props = { interceptsMouse = false },
    layout = { mode = "stack-x", gap = 10, align = "center", padding = { 4, 2, 4, 2 } },
    children = {
      {
        id = rowId .. "_label",
        type = "Label",
        x = 0, y = 0, w = math.max(20, colW - PORT_SIZE - 18), h = ROW_H,
        layoutChild = { grow = 1, shrink = 1, basisW = 20 },
        props = { text = out.label or out.id },
        style = { colour = COLORS.label, fontSize = 9, bg = 0x00000000, align = "right" },
      },
      portWidget(rowId .. "_port", portType, false),
    },
  }
end

-- Split params into pages based on node size
local function paginateParams(params, nodeSize)
  local perPage = (nodeSize == "1x2") and PARAMS_PER_PAGE_1X2 or PARAMS_PER_PAGE_1X1
  local pages = {}
  local currentPage = {}
  
  for i, param in ipairs(params) do
    table.insert(currentPage, param)
    if #currentPage >= perPage then
      table.insert(pages, currentPage)
      currentPage = {}
    end
  end
  
  if #currentPage > 0 then
    table.insert(pages, currentPage)
  end
  
  -- If no pagination needed, return single page with all params
  if #pages == 0 then
    pages = { params }
  end
  
  return pages, perPage
end

-- Generate a patchbay panel for a given node spec and dimensions.
local function generatePatchbay(spec, w, h, nodeSize, currentPage)
  if not spec then return nil end
  
  nodeSize = nodeSize or "1x1"
  currentPage = currentPage or 0

  local ports = spec.ports or {}
  local rawInputs = ports.inputs or {}
  local rawOutputs = ports.outputs or {}
  local params = ports.params or {}
  local specId = spec.id or "unknown"

  local inputs = {}
  for i = 1, #rawInputs do
    local port = rawInputs[i]
    if type(port) == "table" and port.edge == nil then
      inputs[#inputs + 1] = port
    end
  end

  local outputs = {}
  for i = 1, #rawOutputs do
    local port = rawOutputs[i]
    if type(port) == "table" and port.edge == nil then
      outputs[#outputs + 1] = port
    end
  end

  local hasInputs = #inputs > 0
  local hasOutputs = #outputs > 0
  local hasParams = #params > 0

  -- Paginate params if needed
  local paramPages = {}
  local numParamPages = 1
  local needsPagination = false
  
  if hasParams then
    paramPages, _ = paginateParams(params, nodeSize)
    numParamPages = #paramPages
    needsPagination = numParamPages > 1
    
    -- Clamp current page
    if currentPage >= numParamPages then
      currentPage = numParamPages - 1
    end
    if currentPage < 0 then
      currentPage = 0
    end
  end

  -- Column width calculation
  local inputColW = 0
  local paramColW = 0
  local outputColW = 0

  if hasInputs and hasOutputs and hasParams then
    inputColW = math.max(60, math.floor(w * 0.20))
    outputColW = math.max(60, math.floor(w * 0.20))
    paramColW = w - inputColW - outputColW - COL_GAP * 2
  elseif hasParams and (hasInputs or hasOutputs) then
    local ioW = math.max(60, math.floor(w * 0.22))
    if hasInputs then inputColW = ioW end
    if hasOutputs then outputColW = ioW end
    paramColW = w - inputColW - outputColW - COL_GAP * (hasInputs and hasOutputs and 2 or 1)
  elseif hasParams then
    paramColW = w
  elseif hasInputs and hasOutputs then
    inputColW = math.floor(w * 0.5) - COL_GAP
    outputColW = w - inputColW - COL_GAP
  elseif hasInputs then
    inputColW = w
  elseif hasOutputs then
    outputColW = w
  end

  local children = {}

  -- ═══════════════════ COLUMN 1: INPUTS ═══════════════════
  if hasInputs and inputColW > 0 then
    local inputChildren = {
      {
        id = "inputsHeader",
        type = "Panel",
        x = 0, y = 0, w = inputColW, h = SECTION_H,
        layoutChild = { grow = 0, shrink = 0, basisH = SECTION_H },
        style = { bg = 0x00000000 },
        props = { interceptsMouse = false },
        children = {
          {
            id = "inputsHeaderLabel",
            type = "Label",
            x = 0, y = HEADER_LABEL_Y, w = inputColW, h = HEADER_LABEL_H,
            props = { text = "IN" },
            style = { colour = COLORS.sectionLabel, fontSize = 9, bg = 0x00000000 },
          },
        },
      },
    }
    
    for i, inp in ipairs(inputs) do
      inputChildren[#inputChildren + 1] = inputRow("input_" .. (inp.id or tostring(i)), inp, inputColW, i)
    end
    
    children[#children + 1] = {
      id = "inputsColumn", type = "Panel",
      x = 0, y = 0, w = inputColW, h = h,
      layoutChild = { grow = 0, shrink = 0, basisW = inputColW },
      style = { bg = COLORS.bg },
      props = { interceptsMouse = false },
      layout = { mode = "stack-y", gap = ROW_GAP, padding = { 1, 4, 6, 4 } },
      children = inputChildren,
    }
  end

  -- ═══════════════════ COLUMN 2: PARAMETERS ═══════════════════
  if hasParams and paramColW > 0 then
    local paramChildren = {}
    
    -- Header with pagination dots if needed
    if needsPagination then
      local dotsWidth = numParamPages * DOT_HIT_SIZE + (numParamPages - 1) * DOT_GAP

      paramChildren[#paramChildren + 1] = {
        id = "paramsHeaderRow",
        type = "Panel",
        x = 0, y = 0, w = paramColW, h = SECTION_H,
        layoutChild = { grow = 0, shrink = 0, basisH = SECTION_H },
        style = { bg = 0x00000000 },
        props = { interceptsMouse = false },
        children = {
          {
            id = "paramsHeaderLabel",
            type = "Label",
            x = 0, y = HEADER_LABEL_Y, w = paramColW, h = HEADER_LABEL_H,
            props = { text = "PARAMS" },
            style = { colour = COLORS.sectionLabel, fontSize = 9, bg = 0x00000000 },
          },
          paginationDots("pageDots", numParamPages, currentPage, DOT_ROW_X, DOT_ROW_Y),
        },
      }
    else
      paramChildren[#paramChildren + 1] = {
        id = "paramsHeader",
        type = "Panel", x = 0, y = 0, w = paramColW, h = SECTION_H,
        layoutChild = { grow = 0, shrink = 0, basisH = SECTION_H },
        style = { bg = 0x00000000 },
        props = { interceptsMouse = false },
        children = {
          {
            id = "paramsHeaderLabel",
            type = "Label",
            x = 0, y = HEADER_LABEL_Y, w = paramColW, h = HEADER_LABEL_H,
            props = { text = "PARAMS" },
            style = { colour = COLORS.sectionLabel, fontSize = 9, bg = 0x00000000 },
          },
        },
      }
    end

    -- Current page params
    local availH = h - SECTION_H - 4
    local currentParams = paramPages[currentPage + 1] or {}
    local totalParamRows = #currentParams

    -- Keep layout mode stable across pages so later pages don't jump around.
    local paramCols = (nodeSize == "1x2" and #params > 6 and paramColW >= 260) and 2 or 1

    -- Stretch to fill, but reserve some breathing room at the bottom.
    -- Also size against page capacity rather than current-page count so shorter later
    -- pages don't get weirdly re-spaced.
    local bottomReserve = (nodeSize == "1x1") and 14 or 10
    local rowsForSizing
    if nodeSize == "1x1" then
      rowsForSizing = PARAMS_PER_PAGE_1X1
    elseif paramCols == 2 then
      rowsForSizing = math.ceil(PARAMS_PER_PAGE_1X2 / 2)
    else
      rowsForSizing = math.min(8, math.max(1, #params))
    end
    local sizingAvailH = math.max(1, availH - bottomReserve)
    local paramRowH = math.max(18, math.min(24, math.floor(sizingAvailH / math.max(1, rowsForSizing))))

    if paramCols == 2 then
      local halfW = math.floor((paramColW - COL_GAP) / 2)
      local leftChildren = {}
      local rightChildren = {}
      local splitAt = math.ceil(totalParamRows / 2)

      for i, param in ipairs(currentParams) do
        local target = (i <= splitAt) and leftChildren or rightChildren
        local rowId = "param_" .. (param.id or tostring(i)) .. "_p" .. currentPage
        target[#target + 1] = paramRow(rowId, param, halfW, paramRowH, specId)
      end

      paramChildren[#paramChildren + 1] = {
        id = "paramColumns", type = "Panel",
        x = 0, y = 0, w = paramColW, h = availH,
        layoutChild = { grow = 1, shrink = 1, basisH = availH },
        style = { bg = COLORS.bg }, props = { interceptsMouse = false },
        layout = { mode = "stack-x", gap = COL_GAP },
        children = {
          { id = "paramColLeft", type = "Panel", x = 0, y = 0, w = halfW, h = availH,
            layoutChild = { grow = 1, shrink = 1, basisW = halfW },
            style = { bg = COLORS.bg },
            props = { interceptsMouse = false },
            layout = { mode = "stack-y", gap = ROW_GAP }, children = leftChildren },
          { id = "paramColRight", type = "Panel", x = 0, y = 0, w = halfW, h = availH,
            layoutChild = { grow = 1, shrink = 1, basisW = halfW },
            style = { bg = COLORS.bg },
            props = { interceptsMouse = false },
            layout = { mode = "stack-y", gap = ROW_GAP }, children = rightChildren },
        },
      }
    else
      for i, param in ipairs(currentParams) do
        local rowId = "param_" .. (param.id or tostring(i)) .. "_p" .. currentPage
        paramChildren[#paramChildren + 1] = paramRow(rowId, param, paramColW, paramRowH, specId)
      end
    end

    children[#children + 1] = {
      id = "paramsColumn", type = "Panel",
      x = 0, y = 0, w = paramColW, h = h,
      layoutChild = { grow = 1, shrink = 1, basisW = paramColW },
      style = { bg = COLORS.bg },
      props = { interceptsMouse = false },
      layout = { mode = "stack-y", gap = ROW_GAP, padding = { 1, 4, 6, 4 } },
      children = paramChildren,
    }
  end

  -- ═══════════════════ COLUMN 3: OUTPUTS ═══════════════════
  if hasOutputs and outputColW > 0 then
    local outputChildren = {
      {
        id = "outputsHeader",
        type = "Panel",
        x = 0, y = 0, w = outputColW, h = SECTION_H,
        layoutChild = { grow = 0, shrink = 0, basisH = SECTION_H },
        style = { bg = 0x00000000 },
        props = { interceptsMouse = false },
        children = {
          {
            id = "outputsHeaderLabel",
            type = "Label",
            x = 0, y = HEADER_LABEL_Y, w = outputColW, h = HEADER_LABEL_H,
            props = { text = "OUT" },
            style = { colour = COLORS.sectionLabel, fontSize = 9, bg = 0x00000000 },
          },
        },
      },
    }
    
    for i, out in ipairs(outputs) do
      outputChildren[#outputChildren + 1] = outputRow("output_" .. (out.id or tostring(i)), out, outputColW, i)
    end
    
    children[#children + 1] = {
      id = "outputsColumn", type = "Panel",
      x = 0, y = 0, w = outputColW, h = h,
      layoutChild = { grow = 0, shrink = 0, basisW = outputColW },
      style = { bg = COLORS.bg },
      props = { interceptsMouse = false },
      layout = { mode = "stack-y", gap = ROW_GAP, padding = { 1, 4, 6, 4 } },
      children = outputChildren,
    }
  end

  return {
    id = "patchbayContent", type = "Panel",
    x = 0, y = 0, w = w, h = h,
    style = { bg = COLORS.bg }, 
    props = { 
      interceptsMouse = false,
      _numPages = numParamPages,
      _currentPage = currentPage,
    },
    layout = { mode = "stack-x", gap = COL_GAP, padding = { 6, 4, 6, 4 } },
    children = children,
  }
end

return {
  generate = generatePatchbay,
  COLORS = COLORS,
  ROW_H = ROW_H,
  PORT_SIZE = PORT_SIZE,
  PARAMS_PER_PAGE_1X1 = PARAMS_PER_PAGE_1X1,
  PARAMS_PER_PAGE_1X2 = PARAMS_PER_PAGE_1X2,
}
