<div align="center">

<img src="docs/assets/banner.jpg" alt="Tobidasu：把 2D 像素瓦片地图变成 3D 立体模型的 Godot 4 插件" width="820">

<p>
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-6b4dff?style=flat-square"></a>
  <img alt="Godot 4.7+" src="https://img.shields.io/badge/Godot-4.7%2B-478cbf?style=flat-square&logo=godotengine&logoColor=white">
  <img alt="Forward+ and Compatibility (Web)" src="https://img.shields.io/badge/renderer-Forward%2B_·_Compatibility_(Web)-555?style=flat-square">
  <img alt="Pure GDScript" src="https://img.shields.io/badge/GDScript-no_native_code-355570?style=flat-square">
  <a href="https://github.com/kanaworksai-hue/tobidasu/stargazers"><img alt="GitHub stars" src="https://img.shields.io/github/stars/kanaworksai-hue/tobidasu?style=flat-square&logo=github&label=stars&color=f5c518"></a>
</p>

<p><a href="https://github.com/kanaworksai-hue"><img src="docs/brand/kanaworks-mark.png" height="22" alt="" align="absmiddle"></a>&nbsp;<a href="https://github.com/kanaworksai-hue"><b>A KanaWorks_AI project</b></a></p>

[日本語](README.ja.md) | [English](README.md) | **简体中文** | [한국어](README.ko.md)

[效果展示](#-效果展示) · [快速上手](#-快速上手) · [原理](#-原理) · [规则](#-规则) · [限制](#-限制) · [⭐ Star](#-喜欢就点个-star)

</div>

**Tobidasu（飛び出す，意为「弹出来」）** 能把你已有的 2D 像素 `TileMapLayer` 变成 3D 立体小模型（diorama），并且可以用动画在 2D 和 3D 之间来回切换。

- 房子从正面的墙折起来，盖上屋顶。
- 树从地面立起来。
- 池塘里有了水。
- 角色变成立起来的卡片。

不用手工建模，也不用 AI 生成，所有形状都直接来自瓦片的像素。

点一下 **Build 3D**，再把 `pop` 从 0 动画到 1 就行。

<p align="center">
  <a href="https://github.com/kanaworksai-hue/tobidasu/releases/download/v0.1.0/tobidasu-showa-snow-town.mp4"><img src="docs/assets/showcase.gif" alt="短片片段：昭和雪国像素小镇从平面 2D 地图弹出成 3D 模型" width="720"></a>
  <br><sub>▶ <a href="https://github.com/kanaworksai-hue/tobidasu/releases/download/v0.1.0/tobidasu-showa-snow-town.mp4"><b>观看完整短片</b></a>：用 Tobidasu 做的昭和雪国小镇（2 分 24 秒，有声音）</sub>
</p>

## 🎉 Tobidasu 开源了

<img src="docs/brand/kanaworks-logo.png" align="right" width="150" alt="KanaWorks_AI">

采用 MIT 许可，任何人都可以免费使用。欢迎拿你自己的瓦片地图试试看。

- **喜欢的话：** 请点一个 **⭐ Star**。每一颗星都让我知道有人在用，这是我继续开发下去的动力。
- **有问题、发现 bug 或有想法：** 欢迎[提 Issue](https://github.com/kanaworksai-hue/tobidasu/issues)，或者在 X 上给 [@KanaWorks_AI](https://x.com/KanaWorks_AI) 留言。我会根据大家的建议继续开发。

## ✨ 特点

- **2D 画面一个像素都不变。** 2D 地图和 3D 模型是同一个网格。`pop = 0` 时画出来的和原来的 `TileMapLayer` 逐像素一致，所以切换没有跳变，游戏中途也能用。
- **两种风格：** 整块挤出，或逐像素体素。
- **看懂画面再决定形状：**
  - **地面：** 道路、池塘按画出来的形状下沉，台地有岩石悬崖。
  - **水面：** 有水底和会动的水面。
  - **建筑：** 正面的墙绕底边折起来，屋顶和山墙跟着动；支持深出檐、一楼退进去的雁木走廊；窗户自动识别，夜里会亮。
  - **立着的东西：** 树按画法立起来，尖树变圆锥、圆树变球；鸟居、塔、石灯笼也一样。
  - **花和草：** 画在地上的花连着茎浮起来，草长成一根根，都会随风摆。
- **精灵变卡片。** `Sprite2D` / `AnimatedSprite2D` 立起来朝向镜头，动画帧直接复用。
- **会动的大件。** 列车、缆车、推车各用一个小瓦片层做成，和地图一起弹起来、沿路线走，还能进隧道。
- **只在 3D 里出现的氛围效果（回到 2D 时完全消失）：**
  - **光和天气：** 风、接触阴影（AO）、云影、按栋开关的夜灯、落雪、烟。
  - **小生物：** 蝴蝶、萤火虫、蜜蜂。
  - **线缆：** 钢索和电线。
- **像素防闪烁。** 镜头移动时像素画不会闪。
- **编辑器集成。** 在 Godot 自带的 TileSet 编辑器里就能给瓦片标「怎么立起来、多高」，可以撤销，不用写代码。
- **网页也能跑。** 效果在 Forward+ 和 Compatibility 渲染器里看起来一样。

## 🎬 效果展示

下面是用 Tobidasu 做的三个 demo 场景，每个都是从一张平面 2D 瓦片地图开始的。场景本身不包含在这个仓库里。

| | |
|:-:|:-:|
| <img src="docs/assets/showa_2d.jpg" alt="昭和雪国小镇，2D 瓦片地图" width="400"><br><sub>昭和雪国小镇：2D 瓦片地图</sub> | <img src="docs/assets/showa_day.jpg" alt="同一张地图变成 3D" width="400"><br><sub>……弹出成 3D</sub> |
| <img src="docs/assets/showa_night.jpg" alt="雪国的夜晚" width="400"><br><sub>夜晚：窗灯、路灯、落雪</sub> | <img src="docs/assets/kyoto_day.jpg" alt="京都神社" width="400"><br><sub>京都：千本鸟居、五重塔、社殿</sub> |
| <img src="docs/assets/kyoto_night.jpg" alt="京都的夜晚" width="400"><br><sub>京都的夜晚：灯笼亮起</sub> | <img src="docs/assets/town_day.jpg" alt="Kenney Tiny Town 地图" width="400"><br><sub><a href="https://kenney.nl/assets/tiny-town">Kenney Tiny Town</a> 地图</sub> |

▶ [昭和雪国小镇完整短片](https://github.com/kanaworksai-hue/tobidasu/releases/download/v0.1.0/tobidasu-showa-snow-town.mp4)。更多短片发布在 X：[@KanaWorks_AI](https://x.com/KanaWorks_AI)

## 🚀 快速上手

1. 把 `addons/tobidasu` 复制到你项目的 `addons/` 文件夹，在「项目设置 → 插件」里启用 **Tobidasu**。需要 Godot 4.7 或更新版本。
2. 在 3D 场景里添加一个 **`Tobidasu3D`** 节点，把 **`layers`** 设成你的 `TileMapLayer`（地面层放第一个）。想让角色立成卡片，就把它们放进 **`sprites`**。
3. 在检查器里点 **Build 3D**，或保持 `build_on_ready` 打开。然后动画 `pop`：

```gdscript
@onready var diorama: Tobidasu3D = $Tobidasu3D

func pop_out() -> void:
	var t := create_tween().set_trans(Tween.TRANS_SINE)
	t.tween_property(diorama, "pop", 1.0, 1.2).from(0.0)
```

没有规则集时，第 0 层保持平面，上面的层按整块立起来。房子、树、水等需要一个 **`TobidasuRuleSet`**（见[规则](#-规则)），或者在 TileSet 编辑器的 **Tobidasu** 面板里给瓦片做标注。

想要无缝切换：`pop` 为 0 时用正上方的正交相机，然后换成同构图的透视相机，随着 `pop` 增大慢慢倾斜。

常用成员：

| | |
|---|---|
| `pop`, `shade`, `stable_pixels` | 2D ⇄ 3D 进度、光照强度、像素滤波 |
| `wind_strength`, `ambient_occlusion`, `cloud_shadows`, `night_lights`, `edge_highlight` | 只在 3D 出现的效果 |
| `ground_height_at_map()`, `map_to_local()`, `tiles_to_local()` | 把游戏物体放到 3D 地面上 |
| `get_buildings()`, `get_trees()`, `set_lights(cells, amount)` | 门灯、按栋开关灯 |
| `follow`, `visible_rect`, `elevation` | 移动部件（跟着主地图跑的车辆） |
| `TobidasuCritters`, `TobidasuWires` | 蝴蝶、萤火虫、雪、烟；钢索和电线 |

## 🧩 原理

每个顶点都带两个位置：在平面地图上的位置和在 3D 里的位置。shader 按 `pop` 在两者之间移动，并且在地图上像波浪一样有先后。每个可见面在 2D 里的位置，就是这个像素在瓦片里画着的位置，所以 `pop = 0` 时的网格就是瓦片地图的逐像素复制。

<p align="center">
  <img src="docs/assets/pop.gif" alt="一个下雪的像素小镇从平面 2D 地图立成 3D 模型，再收回去" width="640">
</p>

高度来自像素本身：
- 地面是逐像素的高度场。
- 建筑按「上面几行是屋顶、下面几行是墙」来读。
- 树和其它立着的东西按常见的斜 45° 俯视（3/4 视角）画法逐行立起来：离地面线几行就是多高，这一行有多宽就是多深。

## 📐 规则

`TobidasuRuleSet` 是一张有顺序的 `TobidasuRule` 表，按图集坐标匹配，先匹配的生效（TileSet 标注优先）。模式：

| 模式 | 用途 |
|---|---|
| `FLAT` | 草地、道路、雪地（道路和池塘可以按颜色下沉） |
| `BLOCK` / `DOME` | 墙、树篱、土堆（固定高度 / 越往中间越高） |
| `LUMA` | 按亮度决定高度 |
| `ROOF` / `WALL` | 建筑：屋顶行和墙行、山墙、出檐、雁木、发光的窗户 |
| `WATER` | 池塘、温泉 |
| `TREE` | 所有按 3/4 视角画的立着的东西：树、鸟居、塔、灯笼、山、车辆 |
| `PROP` | 模板道具（水井、隧道口） |

让画面立得好看的画法：
- 形状之间用 1 像素的深色描边隔开。
- 形状内部的颜色比描边亮。
- 窗户用窗框围住，玻璃不要碰到瓦片边。
- 两栋房子之间空一格。

## ⚠️ 限制

- **建筑：** 只支持矩形，按「屋顶行 + 墙行」来读；还不支持 L 形、歇山顶、不对称屋顶。
- **立着的东西：** 截面只有圆形和方形。
- **角色：** 是卡片，不是体素人偶，也不和场景碰撞。
- **生成时间：** 生成器是 GDScript 写的，大地图生成要等一会儿。
- **图集：** 16px 瓦片、按 2 的幂对齐的图集最稳定。

## 🗺️ 路线图

- [ ] 导入瓦片集时的规则推荐和检查工具，以及 3D 调试叠加显示
- [ ] 常见瓦片素材包的现成规则
- [ ] 更快的生成：分块、后台线程、只重建改动的部分
- [ ] 更多建筑形状：歇山顶、不对称屋顶（流造）、L 形、退台、翘起的檐角
- [ ] 用数据描述的道具模板
- [ ] 可选的体素角色和简单碰撞
- [ ] 横躺的圆柱（锅炉、水管）

欢迎提 Issue 和 Pull Request。

## ⭐ 喜欢就点个 Star

如果 Tobidasu 让你的瓦片地图「弹」了出来，请在[仓库页面](https://github.com/kanaworksai-hue/tobidasu)顶部点一下 **⭐ Star**。免费，能让更多 Godot 开发者发现它，也是我继续更新的动力。

也欢迎[提 Issue](https://github.com/kanaworksai-hue/tobidasu/issues)，或者在 X 上分享你做的东西并 @[KanaWorks_AI](https://x.com/KanaWorks_AI)。

## 📄 许可与鸣谢

- **本项目：** [MIT](LICENSE)。
- **品牌：** KanaWorks_AI 名称、logo 和 Kana 形象版权归东京AI映像合同会社（Tokyo AI Visuals LLC）所有，**不在** MIT 授权范围内。详见 [docs/brand](docs/brand/README.md)。
- **展示图：** 小镇场景使用 [Kenney](https://kenney.nl) 的 Tiny Town / Tiny Battle / Tiny Dungeon（CC0）；京都和昭和场景是原创美术。demo 场景不包含在本仓库中。
- **基于：** [Godot Engine](https://godotengine.org)。

本项目是独立项目，与 Godot Foundation 没有关联，也未获其背书。

<br>

<div align="center">

<a href="https://x.com/KanaWorks_AI"><img src="docs/brand/kana-wave.png" width="150" alt="KanaWorks_AI 的吉祥物 Kana 在挥手"></a>

<p><b>Made with ♥ by <a href="https://x.com/KanaWorks_AI">KanaWorks_AI</a></b></p>

<p><sub>如果 Tobidasu 帮到了你，点个 ⭐ 能让更多人发现它。更多项目：<a href="https://github.com/kanaworksai-hue">github.com/kanaworksai-hue</a></sub></p>

</div>
