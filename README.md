# 📦 PvpMatchmakingModule

A modular, plug-and-play **PvP Duel Matchmaking & Queue Engine** for Roblox.

---

## ✨ Features
- **Physical Display Board**: Live `SurfaceGui` with Roblox avatar thumbnails, player names, "VS" indicator, and prize info.
- **Proximity & Snap**: Smooth `ProximityPrompt` interaction that snaps players to pad centers facing the arena with automatic movement lock.
- **Queue Controls**: Instant **Invite**, **VS AI**, and **Leave** lobby actions.
- **CollectionService Support**: Tag any pad model with `"PvpMatchmakingPad"` to auto-register multiple independent duel stations across your world.
- **Graceful Lifecycle**: Full disconnection, forfeit, and match cleanup handling.

---

## 🚀 Quick Start

### 1. Server Setup
```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PvpMatchmaking = require(ReplicatedStorage.Submodules.PvpMatchmakingModule)

-- Initialize the service (auto-scans tagged pads)
PvpMatchmaking.Init()

-- Or manually register a specific pad
local padSession = PvpMatchmaking.RegisterPad(workspace.MatchmakingPad)

-- Listen for Match Ready (2 players or Player + Bot)
PvpMatchmaking.OnMatchReady(function(session)
    local p1 = session.slot1
    local p2 = session.slot2
    print(string.format("Duel starting: %s vs %s!", p1.name, p2.name))

    -- Start your game-specific combat/draft here...
    session.state = "InMatch"

    -- When game ends:
    -- session:FinishMatch(winnerSlot)
end)
```

### 2. Client Setup
Drop `StarterGui.MatchLobbyGui` and `StarterPlayerScripts.PvpLobbyController` into your game.
