local super = loadDspModule("./super_extension.lua")

local function hostNode(ctx, path)
  if ctx.host and ctx.host.getGraphNodeByPath then
    return ctx.host.getGraphNodeByPath(path)
  end
  return nil
end

function buildPlugin(ctx)
  if type(super) ~= "table" or type(super.attach) ~= "function" then
    error("project super extension did not expose attach(ctx, layers)")
  end

  local layers = {}
  for i = 0, 3 do
    layers[i + 1] = {
      parts = {
        gain = hostNode(ctx, string.format("/core/behavior/layer/%d/output", i)),
        input = hostNode(ctx, string.format("/core/behavior/layer/%d/input", i)),
      },
    }
  end

  local extension = super.attach(ctx, layers)
  return {
    onParamChange = function(path, value)
      if extension and type(extension.applyParam) == "function" then
        extension.applyParam(path, value)
      end
    end,
  }
end
