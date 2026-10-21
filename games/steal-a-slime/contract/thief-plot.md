# 16. Thief plot highlight

- While a thief carries one of your slimes, you see the thief's plot in red. The server sets Player attribute `ThiefPlots` (`Constants.THIEF_PLOTS_ATTRIBUTE`, string "3,5" via `Shared.ThiefPlots`) on the **victim only**: plot indexes of players carrying one of the victim's slimes right now (`StealService.thiefPlots`); nil = none. `VisualsClient/ThiefPlotFx` draws one local `Highlight` (`ThiefPlotHighlight`) per plot on `Plot_<i>.Base`.
- It clears the moment the carry ends: the slime is stolen (deposit), goes home (slap, drop, death) or either player leaves. Nothing lingers after the steal and nothing is saved.
- The thief's character is drawn red for the victim over the same span by `ui/StealAlertFx` (`StealHighlight`, §17).
- There is no revenge window and no lock price change: a thief pays the normal lock price right after a theft.
