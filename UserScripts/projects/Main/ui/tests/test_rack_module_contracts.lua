package.path = "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/tests/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?/init.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?/init.lua;"
  .. package.path

local Test = require("rack_module_testlib")

local DYNAMIC_MODULES = {
  "adsr",
  "arp",
  "transpose",
  "velocity_mapper",
  "scale_quantizer",
  "note_filter",
  "attenuverter_bias",
  "lfo",
  "slew",
  "sample_hold",
  "compare",
  "cv_mix",
  "range_mapper",
  "eq",
  "fx",
  "filter",
  "rack_oscillator",
  "rack_sample",
}

local tests = {}
for i = 1, #DYNAMIC_MODULES do
  local specId = DYNAMIC_MODULES[i]
  tests[#tests + 1] = function()
    Test.assertDynamicModuleContract(specId, { voiceCount = 8 })
  end
end

Test.runTests("rack_module_contracts", tests)
