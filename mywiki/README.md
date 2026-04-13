# MyWiki

A visual AI knowledge mindmap built with LÖVE2D (Lua) and a Rust native library. MyWiki lets you grow, explore, and export interactive mindmaps with AI-assisted node generation.

## Introduction

MyWiki is a desktop app for building knowledge graphs as visual mindmaps. Nodes can be created manually or expanded automatically with AI (via Grok), letting you brainstorm and explore topics interactively. The UI is rendered in LÖVE2D for smooth, zoomable canvases, while heavy lifting (AI requests, FFI-backed utilities) runs in a Rust cdylib loaded through LuaJIT FFI.

Features:
- Interactive mindmap editor with pan, zoom, and node editing
- AI-powered node expansion using Grok
- PDF export with embedded images
- "All Cards" overview with background generation
- Poker hand cheatsheet screen (bonus mode)

## How to use

Requirements:
- [LÖVE2D](https://love2d.org) (`love` in PATH)
- Rust toolchain (`rustc`, `cargo`)
- C compiler (`cc`)
- `GROK_API_KEY` environment variable (for AI features)

Build and run:

```sh
make build     # build the Rust cdylib (libmywiki_ai)
make run       # build then launch the app via LÖVE2D
make test      # run cargo tests + FFI smoke test
```

Package and distribute:

```sh
make package   # bundle mywiki.love + native lib into dist/
make fuse      # build a fused macOS MyWiki.app
make clean     # remove build artifacts
```

Run `make` (or `make help`) for the full menu.

## Demo

[![MyWiki Demo](https://img.youtube.com/vi/6XmPcPOZSl4/0.jpg)](https://youtu.be/6XmPcPOZSl4)
