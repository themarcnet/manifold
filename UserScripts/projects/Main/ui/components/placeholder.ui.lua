-- Placeholder component for empty rack nodes
-- Inherits dimensions from parent shell

return {
  id = "placeholderContent",
  type = "Panel",
  x = 0, y = 0, w = "100%", h = "100%",
  style = { bg = 0x00000000 },
  props = { interceptsMouse = false },
  layout = { mode = "hybrid", left = 0, top = 0, right = 0, bottom = 0 },
}