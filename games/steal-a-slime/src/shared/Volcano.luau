--!strict
-- Legacy alias: the volcano became the slime fountain (RANCH_RENAME.md).
-- Same table as Fountain; new code requires Fountain directly.
return if script then require(script.Parent.Fountain) else require("./Fountain")
