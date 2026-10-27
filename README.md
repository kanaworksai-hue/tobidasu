<div align="center">

<img src="docs/assets/banner.jpg" alt="Tobidasu: pop 2D pixel tile maps out into 3D dioramas, a Godot 4 plugin" width="820">

<p>
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-6b4dff?style=flat-square"></a>
  <img alt="Godot 4.7+" src="https://img.shields.io/badge/Godot-4.7%2B-478cbf?style=flat-square&logo=godotengine&logoColor=white">
  <img alt="Forward+ and Compatibility (Web)" src="https://img.shields.io/badge/renderer-Forward%2B_·_Compatibility_(Web)-555?style=flat-square">
  <img alt="Pure GDScript" src="https://img.shields.io/badge/GDScript-no_native_code-355570?style=flat-square">
  <a href="https://github.com/kanaworksai-hue/tobidasu/stargazers"><img alt="GitHub stars" src="https://img.shields.io/github/stars/kanaworksai-hue/tobidasu?style=flat-square&logo=github&label=stars&color=f5c518"></a>
</p>

<p><a href="https://github.com/kanaworksai-hue"><img src="docs/brand/kanaworks-mark.png" height="22" alt="" align="absmiddle"></a>&nbsp;<a href="https://github.com/kanaworksai-hue"><b>A KanaWorks_AI project</b></a></p>

[日本語](README.ja.md) | **English** | [简体中文](README.zh-CN.md) | [한국어](README.ko.md)

[Showcase](#-showcase) · [Quick start](#-quick-start) · [How it works](#-how-it-works) · [Rules](#-rules) · [Limitations](#-limitations) · [⭐ Star](#-like-it-star-it)

</div>

**Tobidasu** (飛び出す, "to pop out") turns the 2D pixel-art `TileMapLayer`s you already have into a 3D diorama, with an animated switch between the two. Houses fold up from their front wall and get their roofs, trees stand up out of the ground, water fills the ponds, and your sprites stand up as cards. Nothing is modelled by hand and no AI generates anything. The geometry is built from the pixels of your tiles.

Press **Build 3D**, then animate `pop` from 0 to 1.

<p align="center">
  <a href="https://github.com/kanaworksai-hue/tobidasu/releases/download/v0.1.0/tobidasu-showa-snow-town.mp4"><img src="docs/assets/showcase.gif" alt="From the film: a snowy Showa-era pixel-art town pops up from its flat 2D map into a 3D diorama" width="720"></a>
  <br><sub>▶ <a href="https://github.com/kanaworksai-hue/tobidasu/releases/download/v0.1.0/tobidasu-showa-snow-town.mp4"><b>Watch the full film</b></a>: a Showa-era snow town, made with Tobidasu (2 min 24 s, sound on)</sub>
</p>

## 🎉 Tobidasu is now open source

<img src="docs/brand/kanaworks-logo.png" align="right" width="150" alt="KanaWorks_AI">

It's free to use under the MIT license, so try it on your own tile maps.

- **Like it?** Please give it a **⭐ Star**. Every star tells me people want more, and it's what lets me keep developing it.
- **Questions, bugs or ideas?** [Open an issue](https://github.com/kanaworksai-hue/tobidasu/issues), or send me a message on X: [@KanaWorks_AI](https://x.com/KanaWorks_AI). Suggestions shape what comes next.

## ✨ Highlights

- **The 2D look is preserved exactly.** The 2D map and the 3D model are the same mesh. At `pop = 0` it renders the same pixels as your `TileMapLayer`s, so the switch has no jump and you can use it in the middle of a game.
- **Two looks:** solid blocks, or per-pixel voxels.
- **It knows what it's looking at:**
  - **Ground:** roads and ponds sink only where they are painted, and plateaus get rock cliffs.
  - **Water:** a bed and an animated surface.
  - **Buildings:** fronts fold up on a hinge, roofs and gables follow, and deep eaves and arcades (an inset ground floor) are supported. Windows are found in the art and glow at night.
  - **Trees and other upright things:** they stand up from their drawing, so pointed trees become cones and round ones become spheres. Torii, towers and stone lanterns work the same way.
  - **Flowers and grass:** painted flowers float up on stems and grass blades grow, both swaying in the wind.
- **Sprites become cards.** `Sprite2D` and `AnimatedSprite2D` stand up and face the camera, reusing your animation frames.
- **Moving parts.** Trains, cable cars and carts are small tile layers of their own that pop up and drive along with the map, into tunnels too.
- **3D-only juice that disappears in 2D:**
  - **Light and weather:** wind, contact shadows (AO), cloud shadows, night lights per building, falling snow and smoke.
  - **Critters:** butterflies, fireflies and bees.
  - **Wires:** cables and power lines.
- **Stable pixels.** A filter keeps pixel art from shimmering when the camera moves.
- **Editor integration.** Tag tiles in Godot's own TileSet editor with how they rise and how high, with undo. No code needed.
- **Runs on the Web.** The effects are made to look the same on Forward+ and on the Compatibility renderer.

## 🎬 Showcase

Three demo scenes built with Tobidasu. Each started as a flat 2D tile map. The scenes themselves are not part of this repository.

| | |
|:-:|:-:|
| <img src="docs/assets/showa_2d.jpg" alt="Showa snow town, the 2D tile map" width="400"><br><sub>Showa snow town: the 2D tile map</sub> | <img src="docs/assets/showa_day.jpg" alt="The same map popped out in 3D" width="400"><br><sub>…popped out in 3D</sub> |
| <img src="docs/assets/showa_night.jpg" alt="Showa snow town at night" width="400"><br><sub>Night: windows, lamps, snow</sub> | <img src="docs/assets/kyoto_day.jpg" alt="Kyoto shrine scene" width="400"><br><sub>Kyoto: torii tunnel, pagoda, shrine</sub> |
| <img src="docs/assets/kyoto_night.jpg" alt="Kyoto shrine at night" width="400"><br><sub>Kyoto at night: lanterns light up</sub> | <img src="docs/assets/town_day.jpg" alt="A Kenney Tiny Town map" width="400"><br><sub>A <a href="https://kenney.nl/assets/tiny-town">Kenney Tiny Town</a> map</sub> |

▶ [The full Showa snow town film](https://github.com/kanaworksai-hue/tobidasu/releases/download/v0.1.0/tobidasu-showa-snow-town.mp4). More films made with these scenes are on X: [@KanaWorks_AI](https://x.com/KanaWorks_AI).

## 🚀 Quick start

1. Copy `addons/tobidasu` into your project's `addons/` folder and enable **Tobidasu** in *Project Settings → Plugins*. Godot 4.7 or later.
2. In a 3D scene, add a **`Tobidasu3D`** node. Set **`layers`** to your `TileMapLayer`s, ground first. Optionally set **`sprites`** to the characters that should stand up as cards.
3. Click **Build 3D** in the inspector, or leave `build_on_ready` on. Then animate `pop`:

```gdscript
@onready var diorama: Tobidasu3D = $Tobidasu3D

func pop_out() -> void:
	var t := create_tween().set_trans(Tween.TRANS_SINE)
	t.tween_property(diorama, "pop", 1.0, 1.2).from(0.0)
```

Without a rule set, layer 0 stays flat and the layers above it rise as blocks. For houses, trees, water and the rest, give it a **`TobidasuRuleSet`** (see [Rules](#-rules)), or tag tiles in the TileSet editor with the **Tobidasu** panel.

For the seamless switch, use an orthographic top-down camera while `pop` is 0, then a perspective camera with the same framing that you tilt as `pop` rises.

Useful members:

| | |
|---|---|
| `pop`, `shade`, `stable_pixels` | 2D ⇄ 3D progress, lighting amount, pixel filter |
| `wind_strength`, `ambient_occlusion`, `cloud_shadows`, `night_lights`, `edge_highlight` | 3D-only effects |
| `ground_height_at_map()`, `map_to_local()`, `tiles_to_local()` | put game objects on the 3D ground |
| `get_buildings()`, `get_trees()`, `set_lights(cells, amount)` | lamps by doors, lights on and off per building |
| `follow`, `visible_rect`, `elevation` | moving parts (a vehicle that follows a main map) |
| `TobidasuCritters`, `TobidasuWires` | butterflies, fireflies, snow and smoke; cables and power lines |

## 🧩 How it works

Every vertex carries two positions: where it sits on the flat map, and where it belongs in 3D. A shader moves between them as `pop` changes, with a delay that ripples across the map. The 2D position of every visible face is where that pixel is drawn in your tile, so at `pop = 0` the mesh is a pixel-exact copy of the tile map.

<p align="center">
  <img src="docs/assets/pop.gif" alt="A snowy pixel-art town folds up from the flat 2D map into a 3D diorama and back" width="640">
</p>

Heights come from the pixels themselves:
- ground is a per-pixel height field;
- buildings are read as roof rows over wall rows;
- trees and other upright shapes are drawings in the usual three-quarter view, stood up row by row, so the row above the ground line becomes height and the row's width becomes depth.

## 📐 Rules

A `TobidasuRuleSet` is an ordered list of `TobidasuRule`s matched by atlas coordinates. The first match wins, and TileSet tags override it. Modes:

| Mode | For |
|---|---|
| `FLAT` | grass, paths, snow (roads and ponds can sink by colour) |
| `BLOCK` / `DOME` | walls, hedges, mounds; constant height or rising toward the middle |
| `LUMA` | height from brightness |
| `ROOF` / `WALL` | buildings: roof rows over wall rows, gables, eaves, arcades, glowing windows |
| `WATER` | ponds and springs |
| `TREE` | anything upright drawn in three-quarter view: trees, torii, towers, lanterns, mountains, vehicles |
| `PROP` | template objects (a well, a tunnel portal) |

Drawing tips that make art rise well:
- Separate shapes with a 1-pixel dark outline.
- Keep colours inside a shape brighter than the outline.
- Frame windows so that the glass doesn't touch the tile edge.
- Leave one empty tile between two buildings.

## ⚠️ Limitations

- **Buildings** are rectangles, read as roof rows over wall rows. L-shapes, hip roofs and asymmetric roofs are not supported yet.
- **Upright shapes** have round or square cross-sections.
- **Characters** are cards, not voxel figures, and they don't collide with the scene.
- **Build time:** the builder is GDScript, so building large maps takes a moment.
- **Atlases:** 16 px tiles in a power-of-two-aligned atlas work best.

## 🗺️ Roadmap

- [ ] Rule suggestions and a checker for imported tilesets, plus a 3D debug overlay
- [ ] Ready-made rules for popular tile packs
- [ ] Faster builds: chunks, background threads, rebuilding only what changed
- [ ] More building shapes: hip roofs, asymmetric roofs, L-shapes, setbacks, upturned eaves
- [ ] Data-driven prop templates
- [ ] Optional voxel characters and simple collision
- [ ] Lying cylinders (boilers, pipes)

Issues and pull requests are welcome.

## ⭐ Like it? Star it

If Tobidasu made your tile map pop, please click **⭐ Star** at the top of the [repository page](https://github.com/kanaworksai-hue/tobidasu). It's free, it helps other Godot developers find it, and it tells me to keep going.

Other ways to help: [open an issue](https://github.com/kanaworksai-hue/tobidasu/issues), or share what you made on X and tag [@KanaWorks_AI](https://x.com/KanaWorks_AI).

## 📄 License and credits

- **This project:** [MIT](LICENSE).
- **Brand:** the KanaWorks_AI name, logo and the Kana character are © 東京AI映像合同会社 (Tokyo AI Visuals LLC) and are **not** covered by the MIT license. See [docs/brand](docs/brand/README.md).
- **Showcase images:** the town scene uses [Kenney](https://kenney.nl)'s Tiny Town, Tiny Battle and Tiny Dungeon (CC0). The Kyoto and Showa scenes are original art. The demo scenes are not included here.
- **Built with:** [Godot Engine](https://godotengine.org).

This is an independent project. It is not affiliated with or endorsed by the Godot Foundation.

<br>

<div align="center">

<a href="https://x.com/KanaWorks_AI"><img src="docs/brand/kana-wave.png" width="150" alt="Kana, the KanaWorks_AI mascot, waving"></a>

<p><b>Made with ♥ by <a href="https://x.com/KanaWorks_AI">KanaWorks_AI</a></b></p>

<p><sub>If Tobidasu saves you time, a ⭐ helps others find it. More projects: <a href="https://github.com/kanaworksai-hue">github.com/kanaworksai-hue</a></sub></p>

</div>
