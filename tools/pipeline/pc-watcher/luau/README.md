Luau bodies the watcher sends through StudioMCP `execute_luau`.

Each file is a function body that ends in `return { ... }`. `mcp_client.wrap_luau`
wraps it in a pcall and returns the table as marked JSON. `%%NAME%%` placeholders
are filled by `watcher.py` (numbers only). Not part of any Rojo tree; not linted by CI.
