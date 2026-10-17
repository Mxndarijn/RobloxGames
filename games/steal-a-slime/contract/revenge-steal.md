# 16. Revenge steal (FEATURES.Revenge, default `true`)

- When a steal completes (`Carry.deposit(world, thiefId, now)` of a stolen slime), the victim gets a window of `Config.REVENGE_SECONDS` (60) on that thief. Robbing the same victim again refreshes it. Server state: `world.revenge[victimId][thiefId] = window end` (`server/Revenge`).
- **Lock cost:** while the thief is inside any victim's window their lock costs `Config.REVENGE_LOCK_COST_MULT` (2) x `Economy.lockCost`; several windows do not stack. It applies to the purchase (`Steal.buyLock` 5th arg), `State.lockCost` and the `Plot_<i>.LockCost` attribute. Lock length is unchanged.
- **Highlight:** Player attribute `RevengePlots` (`Constants.REVENGE_PLOTS_ATTRIBUTE`, string "3,5" via `Shared.RevengePlots`) is set on the **victim only**: plot indexes of thieves in their window who are still in the server; nil = none. `VisualsClient/RevengeFx` draws one local `Highlight` (`RevengeHighlight`) per plot on `Plot_<i>.Base`.
- A window ends at expiry (`StealService.step` prunes it), or when the thief or the victim leaves (`Sessions.leave` -> `Revenge.forget`). State is pushed to the thief so `lockCost` drops back. Nothing is saved.
- Flag off: no marks, no attribute, normal lock price.
