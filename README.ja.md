<div align="center">

<img src="docs/assets/banner.jpg" alt="Tobidasu: 2D ドット絵のタイルマップを 3D ジオラマに飛び出させる Godot 4 プラグイン" width="820">

<p>
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-6b4dff?style=flat-square"></a>
  <img alt="Godot 4.7+" src="https://img.shields.io/badge/Godot-4.7%2B-478cbf?style=flat-square&logo=godotengine&logoColor=white">
  <img alt="Forward+ and Compatibility (Web)" src="https://img.shields.io/badge/renderer-Forward%2B_·_Compatibility_(Web)-555?style=flat-square">
  <img alt="Pure GDScript" src="https://img.shields.io/badge/GDScript-no_native_code-355570?style=flat-square">
  <a href="https://github.com/kanaworksai-hue/tobidasu/stargazers"><img alt="GitHub stars" src="https://img.shields.io/github/stars/kanaworksai-hue/tobidasu?style=flat-square&logo=github&label=stars&color=f5c518"></a>
</p>

<p><a href="https://github.com/kanaworksai-hue"><img src="docs/brand/kanaworks-mark.png" height="22" alt="" align="absmiddle"></a>&nbsp;<a href="https://github.com/kanaworksai-hue"><b>A KanaWorks_AI project</b></a></p>

**日本語** | [English](README.md) | [简体中文](README.zh-CN.md) | [한국어](README.ko.md)

[ショーケース](#-ショーケース) · [クイックスタート](#-クイックスタート) · [しくみ](#-しくみ) · [ルール](#-ルール) · [制限](#-制限) · [⭐ Star](#-気に入ったら-star-を)

</div>

**Tobidasu（飛び出す）** は、手元にある 2D ドット絵の `TileMapLayer` を 3D のジオラマに変える Godot プラグインです。2D と 3D はアニメーションで行き来できます。

- 家は正面の壁が起き上がって屋根がのります。
- 木は地面から立ち上がります。
- 池には水が満ちます。
- キャラクターは立ち絵のカードになります。

手作業のモデリングも AI 生成も使わず、タイルのピクセルそのものから形を作ります。

**Build 3D** を押して、`pop` を 0 から 1 へアニメーションさせるだけです。

<p align="center">
  <a href="https://github.com/kanaworksai-hue/tobidasu/releases/download/v0.1.0/tobidasu-showa-snow-town.mp4"><img src="docs/assets/showcase.gif" alt="映像より：昭和の雪国のドット絵の町が、平らな 2D マップから 3D ジオラマに飛び出す" width="720"></a>
  <br><sub>▶ <a href="https://github.com/kanaworksai-hue/tobidasu/releases/download/v0.1.0/tobidasu-showa-snow-town.mp4"><b>映像を全編見る</b></a>：Tobidasu で作った昭和の雪国の町（2 分 24 秒・音声あり）</sub>
</p>

## 🎉 Tobidasu をオープンソースで公開しました

<img src="docs/brand/kanaworks-logo.png" align="right" width="150" alt="KanaWorks_AI">

MIT ライセンスで、どなたでも自由に使えます。ぜひ手持ちのタイルマップで試してみてください。

- **気に入ったら：** **⭐ Star** で応援してもらえるとうれしいです。Star が増えるほど「使ってくれる人がいる」とわかって、開発を続ける力になります。
- **質問・不具合・アイデア：** [Issue](https://github.com/kanaworksai-hue/tobidasu/issues) に書くか、X の [@KanaWorks_AI](https://x.com/KanaWorks_AI) に気軽にメッセージをください。いただいた提案をもとに開発を続けていきます。

## ✨ 特長

- **2D の見た目が 1 ピクセルも崩れない。** 2D マップと 3D モデルは同じメッシュです。`pop = 0` のときは元の `TileMapLayer` とピクセル単位で同じ絵になるので、切り替えに継ぎ目がなく、ゲームの途中でも使えます。
- **2 つの見た目：** ブロック押し出しか、ピクセルごとのボクセル。
- **絵を見て形を決める：**
  - **地面：** 道や池は描かれた形のまま凹み、台地には岩の崖ができます。
  - **水面：** 水底と、揺れる水面。
  - **建物：** 正面の壁がちょうつがいで起き上がり、屋根と妻壁がついてきます。深い軒、一階が奥まった雁木の通路にも対応。窓を絵から見つけて、夜は灯ります。
  - **立っているもの：** 木は描かれた絵から立ち上がり、とがった木は円錐、丸い木は球になります。鳥居、塔、石灯籠も同じしくみです。
  - **花と草：** 地面に描かれた花は茎ごと浮き上がり、草は一本ずつ伸びて、風に揺れます。
- **スプライトはカードに。** `Sprite2D` / `AnimatedSprite2D` がカメラの方を向いて立ち、アニメーションのコマもそのまま使えます。
- **動く部品。** 列車、ロープウェイ、屋台は専用の小さなタイルレイヤーで作り、マップと一緒に飛び出して走ります。トンネルにも入れます。
- **3D のときだけの演出（2D では消えます）：**
  - **光と天気：** 風、接地影（AO）、雲の影、建物ごとの夜の灯り、雪、煙。
  - **生き物：** 蝶、蛍、蜂。
  - **電線：** ケーブルや電線。
- **ピクセルのちらつき防止。** カメラが動いてもドット絵がちらつかないフィルター付き。
- **エディタ連携。** Godot 標準の TileSet エディタで、タイルごとに「どう立ち上がるか・高さ」を塗れます（取り消しもできます）。コードは不要。
- **Web でも動く。** 演出は Forward+ と Compatibility の両方で同じに見えるように作っています。

## 🎬 ショーケース

Tobidasu で作ったデモの 3 シーンです。どれも平らな 2D タイルマップから始まっています。シーン本体はこのリポジトリには含まれません。

| | |
|:-:|:-:|
| <img src="docs/assets/showa_2d.jpg" alt="昭和の雪国の町、2D タイルマップ" width="400"><br><sub>昭和の雪国の町：2D タイルマップ</sub> | <img src="docs/assets/showa_day.jpg" alt="同じマップを 3D に" width="400"><br><sub>…それが 3D に飛び出す</sub> |
| <img src="docs/assets/showa_night.jpg" alt="雪国の夜" width="400"><br><sub>夜：窓の灯り、街灯、雪</sub> | <img src="docs/assets/kyoto_day.jpg" alt="京都の神社" width="400"><br><sub>京都：千本鳥居、五重塔、社殿</sub> |
| <img src="docs/assets/kyoto_night.jpg" alt="京都の夜" width="400"><br><sub>京都の夜：灯籠がともる</sub> | <img src="docs/assets/town_day.jpg" alt="Kenney Tiny Town のマップ" width="400"><br><sub><a href="https://kenney.nl/assets/tiny-town">Kenney Tiny Town</a> のマップ</sub> |

▶ [昭和の雪国の町・全編](https://github.com/kanaworksai-hue/tobidasu/releases/download/v0.1.0/tobidasu-showa-snow-town.mp4)。ほかの映像も X で公開しています：[@KanaWorks_AI](https://x.com/KanaWorks_AI)

## 🚀 クイックスタート

1. `addons/tobidasu` をプロジェクトの `addons/` にコピーし、*プロジェクト設定 → プラグイン* で **Tobidasu** を有効にします。Godot 4.7 以降が必要です。
2. 3D シーンに **`Tobidasu3D`** ノードを追加し、**`layers`** に `TileMapLayer` を設定します（地面のレイヤーを最初に）。立ち絵カードにしたいキャラクターがいれば **`sprites`** に入れます。
3. インスペクタの **Build 3D** を押すか、`build_on_ready` をオンのままにします。あとは `pop` を動かすだけです。

```gdscript
@onready var diorama: Tobidasu3D = $Tobidasu3D

func pop_out() -> void:
	var t := create_tween().set_trans(Tween.TRANS_SINE)
	t.tween_property(diorama, "pop", 1.0, 1.2).from(0.0)
```

ルールセットがない場合、レイヤー 0 は平らなまま、その上のレイヤーはブロックとして立ち上がります。家や木、水などは **`TobidasuRuleSet`** で指定するか（[ルール](#-ルール)参照）、TileSet エディタの **Tobidasu** パネルでタイルに印をつけます。

継ぎ目なく切り替えるには、`pop` が 0 の間は真上からの正投影カメラを使い、同じ構図の透視カメラに替えてから、`pop` に合わせて傾けていきます。

よく使うもの：

| | |
|---|---|
| `pop`, `shade`, `stable_pixels` | 2D ⇄ 3D の進み具合、ライティング量、ピクセルフィルター |
| `wind_strength`, `ambient_occlusion`, `cloud_shadows`, `night_lights`, `edge_highlight` | 3D のときだけの演出 |
| `ground_height_at_map()`, `map_to_local()`, `tiles_to_local()` | ゲームのオブジェクトを 3D の地面に置く |
| `get_buildings()`, `get_trees()`, `set_lights(cells, amount)` | 玄関の灯り、建物ごとの点灯・消灯 |
| `follow`, `visible_rect`, `elevation` | 動く部品（メインマップについて走る乗り物） |
| `TobidasuCritters`, `TobidasuWires` | 蝶・蛍・雪・煙、ケーブルや電線 |

## 🧩 しくみ

すべての頂点が「平らなマップ上の位置」と「3D での位置」の 2 つを持ち、シェーダーが `pop` に合わせて両者の間を動かします。マップの上を波のように時間差がつきます。見えている面の 2D 上の位置は、そのピクセルがタイルに描かれている場所そのものなので、`pop = 0` のメッシュはタイルマップをピクセル単位で写したものになります。

<p align="center">
  <img src="docs/assets/pop.gif" alt="雪のドット絵の町が平らな 2D マップから 3D ジオラマに起き上がり、また戻る" width="640">
</p>

高さはピクセルから決まります。
- 地面はピクセルごとの高さマップ。
- 建物は「上の数行が屋根、下の数行が壁」として読みます。
- 木など立っているものは、よくある斜め見下ろし（3/4 ビュー）の絵を一行ずつ起こします。地面の線から何行上かが高さに、その行の幅が奥行きになります。

## 📐 ルール

`TobidasuRuleSet` は `TobidasuRule` の順番つきリストで、アトラス座標で照合し、最初に合ったものが使われます（TileSet の印が優先）。モード：

| モード | 用途 |
|---|---|
| `FLAT` | 草地、道、雪（道や池は色で凹ませられます） |
| `BLOCK` / `DOME` | 壁、生け垣、盛り土（一定の高さ／中央ほど高い） |
| `LUMA` | 明るさで高さを決める |
| `ROOF` / `WALL` | 建物：屋根の行と壁の行、妻壁、軒、雁木、光る窓 |
| `WATER` | 池、温泉 |
| `TREE` | 斜め見下ろしで描かれた立っているものすべて：木、鳥居、塔、灯籠、山、乗り物 |
| `PROP` | テンプレートの小物（井戸、トンネルの坑門） |

きれいに立ち上がる絵のコツ：
- 形と形の間は 1 ピクセルの暗い輪郭で分ける。
- 形の中の色は輪郭より明るくする。
- 窓は枠で囲んでガラスがタイルの端に触れないようにする。
- 建物と建物の間は 1 マス空ける。

## ⚠️ 制限

- **建物：** 長方形で、「屋根の行＋壁の行」として読みます。L 字、寄棟、左右非対称の屋根はまだ対応していません。
- **立っているものの断面：** 円か四角です。
- **キャラクター：** カードで、ボクセル人形ではありません。シーンとの当たり判定もありません。
- **生成時間：** ビルダーは GDScript なので、大きなマップの生成には少し時間がかかります。
- **アトラス：** 16px タイルで、2 のべき乗にそろったアトラスがいちばん安定します。

## 🗺️ ロードマップ

- [ ] 取り込んだタイルセットのルール提案とチェッカー、3D デバッグ表示
- [ ] 人気のタイル素材向けの既製ルール
- [ ] 生成の高速化：分割生成、バックグラウンドスレッド、変更部分だけの再生成
- [ ] 建物の形を増やす：寄棟、非対称の屋根（流造）、L 字、セットバック、反った軒
- [ ] データで書ける小物テンプレート
- [ ] ボクセルキャラクターと簡単な当たり判定（オプション）
- [ ] 横倒しの円柱（ボイラー、配管）

Issue や Pull Request を歓迎します。

## ⭐ 気に入ったら Star を

Tobidasu でタイルマップが飛び出したら、[リポジトリのページ](https://github.com/kanaworksai-hue/tobidasu)上部の **⭐ Star** を押してもらえるとうれしいです。無料で、ほかの Godot 開発者が見つけやすくなり、開発を続ける励みになります。

ほかにも、[Issue](https://github.com/kanaworksai-hue/tobidasu/issues) を書いたり、作ったものを X で [@KanaWorks_AI](https://x.com/KanaWorks_AI) をつけて見せてもらえると助かります。

## 📄 ライセンスとクレジット

- **このプロジェクト：** [MIT](LICENSE)。
- **ブランド：** KanaWorks_AI の名称、ロゴ、キャラクター Kana の権利は東京AI映像合同会社に帰属し、MIT ライセンスの対象**外**です。[docs/brand](docs/brand/README.md) を参照してください。
- **ショーケース画像：** 町のシーンは [Kenney](https://kenney.nl) の Tiny Town / Tiny Battle / Tiny Dungeon（CC0）を使っています。京都と昭和のシーンはオリジナルの絵です。デモのシーンはこのリポジトリには含まれません。
- **使用技術：** [Godot Engine](https://godotengine.org)。

本プロジェクトは個人の独立したプロジェクトであり、Godot Foundation とは関係ありません。

<br>

<div align="center">

<a href="https://x.com/KanaWorks_AI"><img src="docs/brand/kana-wave.png" width="150" alt="KanaWorks_AI のマスコット Kana が手を振っている"></a>

<p><b>Made with ♥ by <a href="https://x.com/KanaWorks_AI">KanaWorks_AI</a></b></p>

<p><sub>Tobidasu が役に立ったら ⭐ をお願いします。ほかのプロジェクト：<a href="https://github.com/kanaworksai-hue">github.com/kanaworksai-hue</a></sub></p>

</div>
