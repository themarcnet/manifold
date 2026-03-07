local looper = loadDspModule("system:lib/looper_primitives.lua")

function buildPlugin(ctx)
  return looper.buildPlugin(ctx)
end
