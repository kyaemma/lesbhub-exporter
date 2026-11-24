local waits = 0
task = {wait = function() waits = waits + 1 end}
local Budget = require("../src/work_budget")
local control = {}
local budget = Budget.new({frameBudgetMs = 4, yieldEvery = 2}, control)
assert(budget:checkpoint("test"))
assert(budget:checkpoint("test"))
assert(waits == 1 and budget:summary().yields == 1)
budget:native("compile", 0.008)
local summary = budget:summary()
assert(summary.nativeOverruns == 1 and summary.nativeByStage.compile.calls == 1)
control.cancelled = true
assert(not budget:checkpoint("cancel") and waits == 1)
print("Work budget OK")
