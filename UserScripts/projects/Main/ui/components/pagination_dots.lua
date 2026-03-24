-- PaginationDots widget
-- A reusable vertical/horizontal dot indicator for pagination
-- Replaces hardcoded dock dots with a componentized version

return function(props)
  local count = props.count or 3
  local orientation = props.orientation or "y"
  local gap = props.gap or 5
  local idPrefix = props.idPrefix or "dot"
  local containerId = props.id or "paginationDots"
  
  -- Build children (the dots)
  -- Support explicit IDs via props.dotIds, or default to idPrefix .. index
  local children = {}
  local dotIds = props.dotIds or {}
  for i = 1, count do
    local dotId = dotIds[i] or (idPrefix .. i)
    children[i] = {
      id = dotId,
      type = "Label",
      x = 0, y = 0, w = 12, h = 12,
      layoutChild = { basisW = 12, basisH = 12, shrink = 0, alignSelf = "center" },
      props = { text = "•", interceptsMouse = true },
      style = { colour = 0xff475569, fontSize = 16 },
    }
  end
  
  return {
    id = containerId,
    type = "Panel",
    x = props.x or 0, y = props.y or 0,
    w = props.w or 10, h = props.h or (count * 20),
    layoutChild = props.layoutChild or {},
    style = { bg = 0x00000000 },
    props = { interceptsMouse = false },
    layout = {
      mode = orientation == "x" and "stack-x" or "stack-y",
      gap = gap,
      align = "center",
    },
    children = children,
  }
end
