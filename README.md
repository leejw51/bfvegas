# Back to Future Vegas

A single-player Texas Hold'em poker game built with Love2D and Lua, featuring animated avatars, AI opponents with distinct personalities, and a hand-learning quiz mode.

[![Back to Future Vegas Gameplay](https://img.youtube.com/vi/_Pigmh6IWys/0.jpg)](https://youtu.be/_Pigmh6IWys?si=6DDWzW_HU0Vx0Btt)

## Features

- **Texas Hold'em Poker** - Full round structure: pre-flop, flop, turn, river, and showdown
- **3 AI Opponents** with distinct play styles:
  - **Alice** - Aggressive bluffer
  - **Bob** - Conservative and cautious
  - **Charlie** - Balanced all-rounder
- **Animated Avatars** - Sprite-based characters react to game actions (fold, think, raise)
- **Visual Effects** - Chip animations with bezier curves, card dealing sequences, particles, and screen shake
- **Learn Hands Mode** - Quiz mode that teaches all 10 poker hand rankings
- **Resizable Window** - Adaptive scaling with letterboxing

## How to Run

Install [Love2D](https://love2d.org/) (11.4+), then:

```bash
cd mygame/poker
love .
```

## Controls

| Input | Action |
|-------|--------|
| Mouse | Click Fold / Check / Call / Raise buttons, adjust bet with +/- |
| F / F11 | Toggle fullscreen |
| L | Open Learn Hands quiz (from menu) |
| ESC | Quit |

## Project Structure

```
mygame/poker/
  main.lua        Entry point & game loop
  conf.lua        Love2D configuration (1280x720, resizable)
  game.lua        Game state machine & core logic
  render.lua      All graphics rendering
  cards.lua       Card deck & utilities
  hand_eval.lua   Poker hand evaluation
  ai.lua          AI decision making
  quiz.lua        Hand learning quiz mode
  easing.lua      Animation & tween system
  assets/         Cards, avatars, chips, backgrounds
```

## License

MIT License
