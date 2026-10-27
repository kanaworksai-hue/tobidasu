@tool
class_name TobidasuRule
extends Resource
## How one group of tiles pops out into 3D.
##
## Units: 1 tile = 1 world unit. Heights are in tiles.

enum Mode {
	FLAT,   ## Stays on the ground (grass, paths).
	BLOCK,  ## Opaque pixels extruded to a constant height.
	DOME,   ## Opaque pixels rise toward the middle of each shape (trees, bushes).
	LUMA,   ## Per-pixel height from brightness (bright pixels stand taller).
	ROOF,   ## Part of a building: gabled roof over the whole footprint.
	WALL,   ## Part of a building: front facade that stands up.
	SKIP,   ## Not converted.
	WATER,  ## Water pixels sink to a bed under a see-through surface; the rest is ground.
	TREE,   ## 3/4-view plants: each shape stands up and becomes a round voxel solid.
	PROP,   ## A procedural model from a template (`prop`), e.g. a well.
}

@export var name := ""
@export var mode: Mode = Mode.FLAT
## Atlas coordinates this rule applies to. Empty = every tile of the source.
@export var tiles: Array[Vector2i] = []
## TileSet source id this rule applies to. -1 = any source.
@export var source_id := -1
## BLOCK / DOME / LUMA: height of the shape. WALL: height of one wall row.
## ROOF: height of the ridge above the walls.
@export var height := 0.5
## Added below the shape (raises or sinks it; e.g. a plateau). TREE: lifts the
## solid off the ground in 3D (a chimney standing on a roof).
@export var base_offset := 0.0
## Stack on top of whatever the lower layers built at the same pixel.
@export var stack_on_below := true

@export_group("Dome")
## DOME: distance in pixels from the outline to where the shape reaches full height.
@export var dome_radius := 6.0
## DOME: profile exponent. < 1 gives round puffs, > 1 gives pointy cones.
@export var dome_exponent := 0.6

@export_group("Connections")
## Shapes of rules with the same group melt into one (e.g. a forest canopy);
## shapes of different groups stay apart. Empty = this rule is its own group.
@export var group := ""
## Dark outline pixels around a BLOCK / DOME shape stay low (a dark rim on the
## ground) so the coloured inside rises cleanly.
@export var lower_outline := true
@export var outline_height := 0.03
## Pixels darker than this count as outline.
@export var outline_luma := 0.3
## Pixels close to one of these colours sink by `sink_depth` (a road cut into
## the grass, the water of a pond). Only the drawn shape sinks, not the tile.
@export var sink_colors := PackedColorArray()
@export var sink_tolerance := 0.12
@export var sink_depth := -0.06
## Width in pixels of the stepped slope at the edge of a sunk area.
@export var sink_bevel := 1
## Pixels close to one of these colours (flowers drawn on a ground tile) lift
## off in 3D as little heads on a stem, `bloom_height` above the ground.
@export var bloom_colors := PackedColorArray()
@export var bloom_height := 0.19
## Grass tufts drawn in these colours grow up into pixel blades in 3D
## (`tuft_height` tall); `tuft_extra` more clumps sprout per tile of plain grass.
@export var tuft_colors := PackedColorArray()
@export var tuft_height := 0.28
@export var tuft_extra := 0.0

@export_group("Cliff & Water")
## Tall side faces (cliffs) get rock strata instead of the edge colour.
@export var cliff := false
## WATER: depth of the bed and level of the surface (relative to the ground).
@export var water_depth := -0.32
@export var water_level := -0.1

@export_group("Tree & Prop")
## TREE: pixel rows per canopy layer. 1 = smooth round solid, 3+ = stacked discs.
@export var tree_layers := 1
## TREE: depth of the solid relative to its width (1 = round).
@export var tree_depth := 1.0
## TREE: assumed trunk length (pixels) of a shape whose bottom is hidden behind another one.
@export var tree_hidden_trunk := 3
## TREE: sways in the wind (0 = stiff, e.g. mushrooms).
@export var tree_wind := 1.0
## TREE: vertical scale of the solid (3/4 drawings are taller than the real thing).
@export var tree_height_scale := 1.0
## TREE: 0..1, rows above the widest one get a rounded top (mushroom caps).
@export var tree_dome := 0.0
## PROP: template name. Built in: "well" (roof tile above, well tile below),
## "portal" (a stone tunnel mouth in the east face of the raised tile it sits
## on; west face if flipped).
@export var prop := "well"

@export_group("Building")
## ROOF: this column carries a cross gable ("^" tile) that faces the front.
@export var gable := false
## ROOF + gable: where the apex of the "^" sits inside the tile (0 = top, 1 = bottom).
@export var gable_apex := 0.56
## WALL / TREE: window panes (pixels of these colours enclosed by a frame)
## light up at night (Tobidasu3D.night_lights). Empty = no windows.
@export var glow_colors := PackedColorArray()

@export_group("Tree & Prop")
## TREE: square cross-section instead of round: every row becomes a square
## slab as deep as it is wide (x tree_depth) - pagoda storeys and eaves,
## stone lanterns, pedestals.
@export var tree_square := false

@export_group("Building")
## ROOF: how far the eaves reach out past the walls (tiles), front, back and
## sides. Deep eaves read as Japanese temple / shrine roofs. 3D only.
@export var roof_overhang := 0.08

@export_group("Tree & Prop")
## TREE: > 0 = every row is this deep (tiles), whatever its width: slab-like
## things drawn from the side (train cars, cable cars, walls). 0 = from the width.
@export var tree_thickness := 0.0
## TREE: every unbroken run of pixels in a row gets its own cross-section
## (a chimney and a cab on a locomotive's boiler stay narrow), instead of one
## for the whole row. With tree_thickness, a run is at most that deep.
@export var tree_runs := false
## TREE: hollow: only a 1 px slab at the front and at the back of the solid
## (lattice towers and frames: four legs, and you can see through them).
@export var tree_frame := false

@export_group("Building")
## WALL (ground-floor row): in 3D it stands this far back (tiles) under the
## floor above: a covered walkway (gangi, arcade, porch). 2D is unchanged.
@export var wall_recess := 0.0


func matches(src: int, atlas: Vector2i) -> bool:
	if source_id >= 0 and src != source_id:
		return false
	return tiles.is_empty() or tiles.has(atlas)


## Group key used for connections.
func group_key() -> String:
	return group if group != "" else "#%d" % get_instance_id()
