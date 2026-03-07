local Shared = require("behaviors.donut_shared_state")

local M = {}

function M.init(ctx)
  local widgets = ctx.widgets or {}

  if widgets.rec then
    widgets.rec._onPress = function()
      local state = ctx._state or {}
      if state.isRecording then
        Shared.commandTrigger("/core/behavior/stoprec")
      else
        Shared.commandTrigger("/core/behavior/rec")
      end
    end
  end

  if widgets.play then
    widgets.play._onClick = function()
      Shared.commandTrigger("/core/behavior/play")
    end
  end

  if widgets.pause then
    widgets.pause._onClick = function()
      Shared.commandTrigger("/core/behavior/pause")
    end
  end

  if widgets.stop then
    widgets.stop._onClick = function()
      Shared.commandTrigger("/core/behavior/stop")
    end
  end

  if widgets.clear then
    widgets.clear._onClick = function()
      Shared.commandTrigger("/core/behavior/clear")
    end
  end

  if widgets.overdub then
    widgets.overdub._onChange = function(on)
      Shared.commandSet("/core/behavior/overdub", on and 1 or 0)
    end
  end

  if widgets.tempo then
    widgets.tempo._onChange = function(v)
      Shared.commandSet("/core/behavior/tempo", v)
    end
  end

  if widgets.target then
    widgets.target._onChange = function(v)
      Shared.commandSet("/core/behavior/targetbpm", v)
    end
  end
end

function M.resized(ctx, w, h)
  local widgets = ctx.widgets or {}
  local designW, designH = Shared.getDesignSize(ctx, w, h)
  local ids = { "title", "rec", "play", "pause", "stop", "clear", "overdub", "tempo", "target" }
  for _, id in ipairs(ids) do
    Shared.applySpecRect(widgets[id], Shared.getChildSpec(ctx, id), w, h, designW, designH)
  end
end

function M.update(ctx, rawState)
  local widgets = ctx.widgets or {}
  local state = Shared.normalizeState(rawState)
  ctx._state = state

  if widgets.tempo then widgets.tempo:setValue(state.tempo or 120) end
  if widgets.target then widgets.target:setValue(state.targetBPM or 120) end
  if widgets.overdub then widgets.overdub:setValue(state.overdubEnabled or false) end

  if widgets.rec then
    if state.isRecording then
      widgets.rec:setLabel("● REC*")
      widgets.rec:setBg(0xffdc2626)
    else
      widgets.rec:setLabel("● REC")
      widgets.rec:setBg(0xff7f1d1d)
    end
  end
end

function M.cleanup(ctx)
end

return M
