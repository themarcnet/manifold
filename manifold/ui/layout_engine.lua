local M = {}

local function lowerString(value)
  return string.lower(tostring(value or ""))
end

local function numberOrNil(value)
  if value == nil then
    return nil
  end
  return tonumber(value)
end

local function clamp(value, minValue, maxValue)
  local n = tonumber(value) or 0
  if minValue ~= nil and n < minValue then
    n = minValue
  end
  if maxValue ~= nil and n > maxValue then
    n = maxValue
  end
  return n
end

local function floorInt(value)
  return math.floor((tonumber(value) or 0) + 0.5)
end

local function deepCopy(value)
  if type(value) ~= "table" then
    return value
  end
  local out = {}
  for k, v in pairs(value) do
    out[deepCopy(k)] = deepCopy(v)
  end
  return out
end

local function mergeInto(dst, src)
  if type(src) ~= "table" then
    return dst
  end
  for k, v in pairs(src) do
    dst[k] = deepCopy(v)
  end
  return dst
end

local function parseEdgeInsets(value, defaultValue)
  local fallback = tonumber(defaultValue) or 0
  if type(value) == "number" then
    local n = tonumber(value) or fallback
    return n, n, n, n
  end
  if type(value) ~= "table" then
    return fallback, fallback, fallback, fallback
  end

  local top = tonumber(value.top)
  local right = tonumber(value.right)
  local bottom = tonumber(value.bottom)
  local left = tonumber(value.left)

  if #value == 2 then
    local vertical = tonumber(value[1]) or fallback
    local horizontal = tonumber(value[2]) or fallback
    return vertical, horizontal, vertical, horizontal
  end

  if #value >= 4 then
    top = tonumber(value[1]) or top or fallback
    right = tonumber(value[2]) or right or fallback
    bottom = tonumber(value[3]) or bottom or fallback
    left = tonumber(value[4]) or left or fallback
    return top, right, bottom, left
  end

  if #value == 1 then
    local n = tonumber(value[1]) or fallback
    return n, n, n, n
  end

  top = top or fallback
  right = right or fallback
  bottom = bottom or fallback
  left = left or fallback
  return top, right, bottom, left
end

local function getLayoutMode(spec)
  local layout = type(spec) == "table" and spec.layout or nil
  if type(layout) ~= "table" then
    return ""
  end
  return lowerString(layout.mode or layout.sizing or layout.kind or "")
end

function M.isManagedContainerLayoutMode(mode)
  local normalized = lowerString(mode)
  return normalized == "stack-x"
    or normalized == "stack-y"
    or normalized == "grid"
    or normalized == "overlay"
end

function M.isManagedContainerSpec(spec)
  return M.isManagedContainerLayoutMode(getLayoutMode(spec))
end

local function isRecordVisible(record)
  local widget = record and record.widget or nil
  if widget and type(widget.isVisible) == "function" then
    return widget:isVisible() == true
  end
  if widget and widget.node and widget.node.isVisible then
    return widget.node:isVisible() == true
  end
  return true
end

local function getChildLayout(record)
  local spec = record and record.spec or nil
  return type(spec) == "table" and type(spec.layoutChild) == "table" and spec.layoutChild or {}
end

local function childOrderValue(record, fallback)
  local childLayout = getChildLayout(record)
  local order = tonumber(childLayout.order)
  if order ~= nil then
    return order
  end
  return fallback or 0
end

local function sortChildren(children)
  local entries = {}
  for i = 1, #(children or {}) do
    entries[i] = {
      record = children[i],
      index = i,
    }
  end
  table.sort(entries, function(a, b)
    local ai = childOrderValue(a.record, a.index)
    local bi = childOrderValue(b.record, b.index)
    if ai ~= bi then
      return ai < bi
    end
    return a.index < b.index
  end)

  local out = {}
  for i = 1, #entries do
    out[i] = entries[i].record
  end
  return out
end

local function childParticipationMode(record)
  local childLayout = getChildLayout(record)
  local position = lowerString(childLayout.position or childLayout.mode or "")
  if position == "absolute" then
    return "absolute"
  end
  if position == "overlay" then
    return "overlay"
  end
  if childLayout.participate == false then
    return "excluded"
  end
  return "flow"
end

local function getWidgetMeasuredSize(record)
  local widget = record and record.widget or nil
  if widget == nil then
    return 0, 0
  end

  local width = nil
  local height = nil

  if type(widget.getPreferredWidth) == "function" then
    width = tonumber(widget:getPreferredWidth())
  end
  if type(widget.getPreferredHeight) == "function" then
    height = tonumber(widget:getPreferredHeight())
  end

  if (width == nil or height == nil) and widget.node then
    if width == nil and widget.node.getWidth then
      width = tonumber(widget.node:getWidth())
    end
    if height == nil and widget.node.getHeight then
      height = tonumber(widget.node:getHeight())
    end
    if (width == nil or height == nil) and widget.node.getBounds then
      local _, _, bw, bh = widget.node:getBounds()
      if width == nil then width = tonumber(bw) end
      if height == nil then height = tonumber(bh) end
    end
  end

  local spec = record.spec or {}
  if width == nil then width = tonumber(spec.w) or 0 end
  if height == nil then height = tonumber(spec.h) or 0 end
  return math.max(0, width or 0), math.max(0, height or 0)
end

local function getChildPreferredSize(record)
  local childLayout = getChildLayout(record)
  local measuredW, measuredH = getWidgetMeasuredSize(record)
  local preferredW = tonumber(childLayout.prefW or childLayout.preferredWidth or childLayout.basisW) or measuredW
  local preferredH = tonumber(childLayout.prefH or childLayout.preferredHeight or childLayout.basisH) or measuredH
  preferredW = math.max(0, preferredW or 0)
  preferredH = math.max(0, preferredH or 0)
  return preferredW, preferredH
end

local function getChildMainSize(record, orientation)
  local childLayout = getChildLayout(record)
  local preferredW, preferredH = getChildPreferredSize(record)
  local basis = tonumber(childLayout.basis)
  local minSize = tonumber(childLayout.minSize)
  local maxSize = tonumber(childLayout.maxSize)

  local size = basis
  if orientation == "x" then
    size = size or tonumber(childLayout.basisW or childLayout.width) or preferredW
    minSize = tonumber(childLayout.minW or childLayout.minWidth) or minSize
    maxSize = tonumber(childLayout.maxW or childLayout.maxWidth) or maxSize
  else
    size = size or tonumber(childLayout.basisH or childLayout.height) or preferredH
    minSize = tonumber(childLayout.minH or childLayout.minHeight) or minSize
    maxSize = tonumber(childLayout.maxH or childLayout.maxHeight) or maxSize
  end

  size = clamp(size or 0, minSize, maxSize)
  return math.max(0, size), minSize, maxSize
end

local function getChildCrossSize(record, orientation)
  local childLayout = getChildLayout(record)
  local preferredW, preferredH = getChildPreferredSize(record)
  if orientation == "x" then
    return clamp(
      tonumber(childLayout.crossSize or childLayout.basisH or childLayout.height) or preferredH,
      tonumber(childLayout.minH or childLayout.minHeight),
      tonumber(childLayout.maxH or childLayout.maxHeight)
    )
  end
  return clamp(
    tonumber(childLayout.crossSize or childLayout.basisW or childLayout.width) or preferredW,
    tonumber(childLayout.minW or childLayout.minWidth),
    tonumber(childLayout.maxW or childLayout.maxWidth)
  )
end

local function buildContentRect(layout, containerW, containerH)
  local top, right, bottom, left = parseEdgeInsets(layout and (layout.padding or layout.pad), 0)
  local x = left
  local y = top
  local w = math.max(0, (tonumber(containerW) or 0) - left - right)
  local h = math.max(0, (tonumber(containerH) or 0) - top - bottom)
  return {
    x = x,
    y = y,
    w = w,
    h = h,
    paddingTop = top,
    paddingRight = right,
    paddingBottom = bottom,
    paddingLeft = left,
  }
end

local childLayoutSpecSkip = {
  participate = true,
  position = true,
  order = true,
  grow = true,
  shrink = true,
  basis = true,
  basisW = true,
  basisH = true,
  prefW = true,
  prefH = true,
  preferredWidth = true,
  preferredHeight = true,
  minSize = true,
  maxSize = true,
  crossSize = true,
  col = true,
  row = true,
  colSpan = true,
  rowSpan = true,
  anchor = true,
  margin = true,
  alignSelf = true,
}

local function buildAbsoluteChildSpec(record)
  local spec = deepCopy(record.spec or {})
  local childLayout = getChildLayout(record)

  spec.layout = deepCopy(spec.layout or {})
  for k, v in pairs(childLayout) do
    if not childLayoutSpecSkip[k] then
      if k == "x" or k == "y" or k == "w" or k == "h" or k == "width" or k == "height" then
        if k == "width" then
          spec.w = v
        elseif k == "height" then
          spec.h = v
        else
          spec[k] = v
        end
      else
        spec.layout[k] = deepCopy(v)
      end
    end
  end

  if next(spec.layout) == nil then
    spec.layout = nil
  end
  return spec
end

local function applyAbsoluteChild(record, contentRect, options)
  local spec = buildAbsoluteChildSpec(record)
  local x, y, w, h = options.resolveLayoutBounds(spec, contentRect.w, contentRect.h)
  options.applyRecordBounds(record,
    contentRect.x + (tonumber(x) or 0),
    contentRect.y + (tonumber(y) or 0),
    tonumber(w) or 0,
    tonumber(h) or 0)
end

local function applyOverlayAnchor(record, contentRect, options)
  local childLayout = getChildLayout(record)
  local anchor = lowerString(childLayout.anchor or "")
  if anchor == "" then
    applyAbsoluteChild(record, contentRect, options)
    return
  end

  local marginTop, marginRight, marginBottom, marginLeft = parseEdgeInsets(childLayout.margin, 0)
  local preferredW, preferredH = getChildPreferredSize(record)
  local width = tonumber(childLayout.w or childLayout.width) or preferredW
  local height = tonumber(childLayout.h or childLayout.height) or preferredH
  width = clamp(width, tonumber(childLayout.minW or childLayout.minWidth), tonumber(childLayout.maxW or childLayout.maxWidth))
  height = clamp(height, tonumber(childLayout.minH or childLayout.minHeight), tonumber(childLayout.maxH or childLayout.maxHeight))

  local x = contentRect.x + marginLeft
  local y = contentRect.y + marginTop
  local maxW = math.max(0, contentRect.w - marginLeft - marginRight)
  local maxH = math.max(0, contentRect.h - marginTop - marginBottom)

  if anchor == "fill" then
    width = maxW
    height = maxH
  elseif anchor == "top-right" then
    x = contentRect.x + contentRect.w - marginRight - width
  elseif anchor == "bottom-left" then
    y = contentRect.y + contentRect.h - marginBottom - height
  elseif anchor == "bottom-right" then
    x = contentRect.x + contentRect.w - marginRight - width
    y = contentRect.y + contentRect.h - marginBottom - height
  elseif anchor == "center" then
    x = contentRect.x + (contentRect.w - width) * 0.5
    y = contentRect.y + (contentRect.h - height) * 0.5
  elseif anchor == "top-center" then
    x = contentRect.x + (contentRect.w - width) * 0.5
  elseif anchor == "bottom-center" then
    x = contentRect.x + (contentRect.w - width) * 0.5
    y = contentRect.y + contentRect.h - marginBottom - height
  elseif anchor == "center-left" then
    y = contentRect.y + (contentRect.h - height) * 0.5
  elseif anchor == "center-right" then
    x = contentRect.x + contentRect.w - marginRight - width
    y = contentRect.y + (contentRect.h - height) * 0.5
  end

  options.applyRecordBounds(record, x, y, math.max(0, width), math.max(0, height))
end

local function splitChildrenByParticipation(record)
  local flowChildren = {}
  local absoluteChildren = {}
  for _, child in ipairs(sortChildren(record.children or {})) do
    if isRecordVisible(child) then
      local participation = childParticipationMode(child)
      if participation == "flow" then
        flowChildren[#flowChildren + 1] = child
      elseif participation == "absolute" or participation == "overlay" then
        absoluteChildren[#absoluteChildren + 1] = child
      end
    end
  end
  return flowChildren, absoluteChildren
end

local function applyAbsoluteChildren(children, contentRect, options)
  for _, child in ipairs(children or {}) do
    applyAbsoluteChild(child, contentRect, options)
  end
end

local function resolveCrossPlacement(contentRect, crossSize, align)
  local normalized = lowerString(align or "stretch")
  if normalized == "stretch" then
    return contentRect.y, contentRect.h
  elseif normalized == "center" then
    return contentRect.y + (contentRect.h - crossSize) * 0.5, crossSize
  elseif normalized == "end" or normalized == "bottom" or normalized == "right" then
    return contentRect.y + contentRect.h - crossSize, crossSize
  end
  return contentRect.y, crossSize
end

local function applyStackLayout(record, containerW, containerH, options, orientation)
  local layout = type(record.spec) == "table" and type(record.spec.layout) == "table" and record.spec.layout or {}
  local contentRect = buildContentRect(layout, containerW, containerH)
  local flowChildren, absoluteChildren = splitChildrenByParticipation(record)
  local gap = tonumber(layout.gap or (orientation == "x" and layout.gapX or layout.gapY) or 0) or 0
  local justify = lowerString(
    layout.justify
      or layout.justifyContent
      or (orientation == "x" and layout.justifyX or layout.justifyY)
      or "start")
  local defaultAlign = lowerString(
    layout.align
      or layout.alignItems
      or (orientation == "x" and layout.alignY or layout.alignX)
      or "stretch")

  local infos = {}
  local totalBase = 0
  local totalGrow = 0
  local totalShrinkWeight = 0

  for _, child in ipairs(flowChildren) do
    local childLayout = getChildLayout(child)
    local mainSize, _, _ = getChildMainSize(child, orientation)
    local crossSize = getChildCrossSize(child, orientation)
    local grow = math.max(0, tonumber(childLayout.grow) or 0)
    local shrink = math.max(0, tonumber(childLayout.shrink) or 1)
    infos[#infos + 1] = {
      record = child,
      mainSize = mainSize,
      crossSize = crossSize,
      grow = grow,
      shrink = shrink,
      align = lowerString(childLayout.alignSelf or defaultAlign),
    }
    totalBase = totalBase + mainSize
    totalGrow = totalGrow + grow
    totalShrinkWeight = totalShrinkWeight + shrink * math.max(1, mainSize)
  end

  local availableMain = orientation == "x" and contentRect.w or contentRect.h
  local occupiedMain = totalBase + math.max(0, #infos - 1) * gap
  local extra = availableMain - occupiedMain

  if extra > 0 and totalGrow > 0 then
    for _, info in ipairs(infos) do
      if info.grow > 0 then
        info.mainSize = info.mainSize + (extra * (info.grow / totalGrow))
      end
    end
    occupiedMain = availableMain
    extra = 0
  elseif extra < 0 and totalShrinkWeight > 0 then
    local deficit = -extra
    for _, info in ipairs(infos) do
      local weight = info.shrink * math.max(1, info.mainSize)
      local reduction = deficit * (weight / totalShrinkWeight)
      info.mainSize = math.max(0, info.mainSize - reduction)
    end
    occupiedMain = availableMain
    extra = 0
  end

  local startMain = orientation == "x" and contentRect.x or contentRect.y
  local actualGap = gap
  if justify == "center" then
    startMain = startMain + math.max(0, extra) * 0.5
  elseif justify == "end" or justify == "right" or justify == "bottom" then
    startMain = startMain + math.max(0, extra)
  elseif justify == "space-between" and #infos > 1 then
    actualGap = gap + math.max(0, extra) / (#infos - 1)
  end

  local cursor = startMain
  for _, info in ipairs(infos) do
    local mainSize = math.max(0, info.mainSize)
    if orientation == "x" then
      local crossY, crossH = resolveCrossPlacement(contentRect, info.crossSize, info.align)
      options.applyRecordBounds(info.record, cursor, crossY, mainSize, crossH)
    else
      local crossX, crossW
      local normalized = lowerString(info.align or "stretch")
      if normalized == "stretch" then
        crossX = contentRect.x
        crossW = contentRect.w
      elseif normalized == "center" then
        crossX = contentRect.x + (contentRect.w - info.crossSize) * 0.5
        crossW = info.crossSize
      elseif normalized == "end" or normalized == "right" then
        crossX = contentRect.x + contentRect.w - info.crossSize
        crossW = info.crossSize
      else
        crossX = contentRect.x
        crossW = info.crossSize
      end
      options.applyRecordBounds(info.record, crossX, cursor, crossW, mainSize)
    end
    cursor = cursor + mainSize + actualGap
  end

  applyAbsoluteChildren(absoluteChildren, contentRect, options)
end

local function canPlaceInGrid(occupancy, row, col, rowSpan, colSpan, columnCount)
  if col < 1 or (col + colSpan - 1) > columnCount then
    return false
  end
  for r = row, row + rowSpan - 1 do
    occupancy[r] = occupancy[r] or {}
    for c = col, col + colSpan - 1 do
      if occupancy[r][c] == true then
        return false
      end
    end
  end
  return true
end

local function markGridPlacement(occupancy, row, col, rowSpan, colSpan)
  for r = row, row + rowSpan - 1 do
    occupancy[r] = occupancy[r] or {}
    for c = col, col + colSpan - 1 do
      occupancy[r][c] = true
    end
  end
end

local function applyGridLayout(record, containerW, containerH, options)
  local layout = type(record.spec) == "table" and type(record.spec.layout) == "table" and record.spec.layout or {}
  local contentRect = buildContentRect(layout, containerW, containerH)
  local flowChildren, absoluteChildren = splitChildrenByParticipation(record)
  local columns = math.max(1, floorInt(layout.columns or layout.cols or 1))
  local gapX = tonumber(layout.gapX or layout.gap or 0) or 0
  local gapY = tonumber(layout.gapY or layout.gap or 0) or 0
  local minRowHeight = tonumber(layout.minRowHeight or layout.rowHeight) or 0
  local uniformRowHeight = tonumber(layout.rowHeight)
  local occupancy = {}
  local placements = {}
  local rowHeights = {}

  for _, child in ipairs(flowChildren) do
    local childLayout = getChildLayout(child)
    local colSpan = math.max(1, floorInt(childLayout.colSpan or childLayout.columnSpan or 1))
    local rowSpan = math.max(1, floorInt(childLayout.rowSpan or 1))
    if colSpan > columns then
      colSpan = columns
    end

    local preferredW, preferredH = getChildPreferredSize(child)
    local desiredHeight = clamp(
      tonumber(childLayout.basisH or childLayout.height) or preferredH,
      tonumber(childLayout.minH or childLayout.minHeight),
      tonumber(childLayout.maxH or childLayout.maxHeight)
    )

    local explicitRow = tonumber(childLayout.row)
    local explicitCol = tonumber(childLayout.col or childLayout.column)
    local placedRow = nil
    local placedCol = nil

    if explicitRow ~= nil and explicitCol ~= nil then
      local row = math.max(1, floorInt(explicitRow))
      local col = math.max(1, floorInt(explicitCol))
      if canPlaceInGrid(occupancy, row, col, rowSpan, colSpan, columns) then
        placedRow = row
        placedCol = col
      end
    end

    if placedRow == nil then
      local row = 1
      local found = false
      while not found do
        for col = 1, columns - colSpan + 1 do
          if canPlaceInGrid(occupancy, row, col, rowSpan, colSpan, columns) then
            placedRow = row
            placedCol = col
            found = true
            break
          end
        end
        row = row + 1
      end
    end

    markGridPlacement(occupancy, placedRow, placedCol, rowSpan, colSpan)

    for r = placedRow, placedRow + rowSpan - 1 do
      local contribution = uniformRowHeight or math.max(minRowHeight, desiredHeight / rowSpan)
      rowHeights[r] = math.max(rowHeights[r] or 0, contribution)
    end

    placements[#placements + 1] = {
      record = child,
      row = placedRow,
      col = placedCol,
      rowSpan = rowSpan,
      colSpan = colSpan,
      preferredWidth = preferredW,
      preferredHeight = desiredHeight,
    }
  end

  local rowCount = #rowHeights
  for i = 1, rowCount do
    rowHeights[i] = math.max(minRowHeight, rowHeights[i] or 0)
  end

  if uniformRowHeight ~= nil then
    for i = 1, rowCount do
      rowHeights[i] = uniformRowHeight
    end
  end

  local columnWidth = 0
  if columns > 0 then
    columnWidth = math.max(0, (contentRect.w - math.max(0, columns - 1) * gapX) / columns)
  end

  local rowStarts = {}
  local cursorY = contentRect.y
  for i = 1, rowCount do
    rowStarts[i] = cursorY
    cursorY = cursorY + rowHeights[i] + gapY
  end

  for _, placement in ipairs(placements) do
    local x = contentRect.x + (placement.col - 1) * (columnWidth + gapX)
    local y = rowStarts[placement.row] or contentRect.y
    local width = placement.colSpan * columnWidth + math.max(0, placement.colSpan - 1) * gapX
    local height = 0
    for r = placement.row, placement.row + placement.rowSpan - 1 do
      height = height + (rowHeights[r] or minRowHeight)
    end
    height = height + math.max(0, placement.rowSpan - 1) * gapY
    options.applyRecordBounds(placement.record, x, y, width, height)
  end

  applyAbsoluteChildren(absoluteChildren, contentRect, options)
end

local function applyOverlayLayout(record, containerW, containerH, options)
  local layout = type(record.spec) == "table" and type(record.spec.layout) == "table" and record.spec.layout or {}
  local contentRect = buildContentRect(layout, containerW, containerH)
  for _, child in ipairs(sortChildren(record.children or {})) do
    if isRecordVisible(child) then
      applyOverlayAnchor(child, contentRect, options)
    end
  end
end

function M.applyContainerLayout(record, containerW, containerH, options)
  if type(record) ~= "table" or type(options) ~= "table" then
    return false
  end

  local mode = getLayoutMode(record.spec)
  if mode == "stack-x" then
    applyStackLayout(record, containerW, containerH, options, "x")
    return true
  elseif mode == "stack-y" then
    applyStackLayout(record, containerW, containerH, options, "y")
    return true
  elseif mode == "grid" then
    applyGridLayout(record, containerW, containerH, options)
    return true
  elseif mode == "overlay" then
    applyOverlayLayout(record, containerW, containerH, options)
    return true
  end

  return false
end

return M
