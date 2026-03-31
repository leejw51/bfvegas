
# Generate images (requires GROK_API_KEY env var)
python generate_image.py
```

## Agent Team

Three specialized agents collaborate on this project:

- **designer** (`.claude/agents/designer.md`) - Generates game assets using `generate_image.py`
- **code** (`.claude/agents/code.md`) - Lua/LOVE2D developer for game implementation
- **plan** (`.claude/agents/plan.md`) - Game logic planner and architect

## Code Conventions

- Lua with LOVE2D 11.4 APIs
- One file per entity/system
- OOP via `class.lua`
- Global state in `variables.lua`
- MIT License
