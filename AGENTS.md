# Repository Guidelines

## Project Structure & Module Organization

This is a Godot 4.7 first-person multiplayer horror prototype. `project.godot`
defines autoloads and launches `network/multiplayer_menu.tscn`. Gameplay is
organized by feature: `player/`, `ghosts/`, `door/`, `power/`, `items/`,
`minigames/`, `ui/`, and `network/`. `house2/` is the hand-authored house;
`house3/` contains the procedural villa, whose layout source is
`house3/neh_map_spec_v2.json`. Reusable scenes, imported models, audio, and
textures live under `assets/` and `audio/`. Keep scripts and their `.tscn`
scenes together when practical.

## Build, Test, and Development Commands

There is no compile or package-build step. Open `project.godot` in Godot 4.7
and use F5 to run the project or F6 to run the current scene. Start a server
with `godot --headless --path . -- --server --port=7777`; a local client can
join with `godot --path . -- --join=127.0.0.1 --port=7777 --name=Player2`.

Run a focused smoke test with:

```sh
godot --headless --script tests/<feature>_smoke.gd
```

For example, use `tests/world_replication_pair_smoke.gd` after changes in
`network/`. Villa tests can take several minutes because they bake navigation
at runtime; do not mistake a short command timeout for a test failure.

## Coding Style & Naming Conventions

Write typed GDScript with tabs for indentation, `snake_case` for files,
variables, functions, and signals, and `PascalCase` for classes. Name scenes
after their primary script, e.g. `ghosts/crawler_ghost.tscn` and
`ghosts/crawler_ghost.gd`. Prefer explicit types and small feature-local
changes. No formatter or linter is configured; use the Godot editor's parser
and keep surrounding style intact. Retain `.uid` files generated for scripts.

## Testing Guidelines

Tests in `tests/` are standalone headless smoke scripts, not GdUnit. Add or
update the smallest relevant `*_smoke.gd` test, use descriptive assertions,
and run it before submitting. Network changes also require the appropriate
two-process pair smoke test. Screenshot/devshot scripts are for inspection,
not automated pass/fail coverage.

## Commit & Pull Request Guidelines

Recent history uses short Conventional Commit-style subjects such as
`feat: ghost_crawler model`, `fix: darkness ghost`, and `refactor: remove limit
from time bank`. Use `feat:`, `fix:`, or `refactor:` followed by an imperative,
focused summary. Keep commits scoped. Pull requests should explain the
gameplay or technical change, list tests run, link the issue when available,
and include screenshots or video for visual, UI, level, or animation changes.
