extends Control

## A deliberately asset-free jumpscare portrait. Drawing it as vectors keeps the
## face sharp at every resolution and lets the death screen tear, offset and
## recolour it every frame instead of showing a static "you died" image.

var killer_variant: StringName = &"statue"
var scare_progress: float = 0.0
var elapsed: float = 0.0

## The outline the death screen ghosts in red behind the portrait: the ring the
## crown of spines sits on, with the beak running off the bottom of the frame.
## Packed arrays cannot be `const` in GDScript, so this is a plain member built
## once at load.
var hunter_skull := PackedVector2Array([
	Vector2(-0.30, -0.26), Vector2(-0.12, -0.38),
	Vector2(0.13, -0.37), Vector2(0.31, -0.21),
	Vector2(0.30, 0.03), Vector2(0.12, 0.17),
	Vector2(0.06, 0.52), Vector2(-0.06, 0.52),
	Vector2(-0.13, 0.16), Vector2(-0.31, 0.01),
])


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func configure(variant: StringName) -> void:
	killer_variant = variant
	elapsed = 0.0
	scare_progress = 0.0
	queue_redraw()


func set_scare_progress(value: float) -> void:
	scare_progress = clampf(value, 0.0, 1.0)
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	elapsed += delta
	queue_redraw()


func _draw() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return

	var unit := minf(size.x, size.y)
	var rush := ease(clampf((scare_progress - 0.025) / 0.82, 0.0, 1.0), -2.35)
	var face_scale := lerpf(0.34, 1.46, rush)
	face_scale *= 1.0 + sin(elapsed * 31.0) * lerpf(0.008, 0.035, scare_progress)

	var shake_strength := lerpf(2.0, 28.0, scare_progress)
	var shake := Vector2(sin(elapsed * 173.0), cos(elapsed * 131.0)) * shake_strength
	# Every few frames the face snaps sideways like a damaged tape rather than
	# merely wobbling smoothly.
	if int(elapsed * 30.0) % 7 == 0:
		shake.x += sin(elapsed * 811.0) * 42.0 * scare_progress
	var center := size * 0.5 + Vector2(0.0, unit * 0.035) + shake
	var face_rotation := sin(elapsed * 47.0) * deg_to_rad(2.2 + scare_progress * 3.8)
	var chromatic_offset := lerpf(2.0, 17.0, scare_progress)

	# Offset silhouettes create a violent red/cyan split before the detailed
	# central face is drawn over them.
	draw_set_transform(
		center + Vector2(-chromatic_offset, 0.0),
		face_rotation,
		Vector2.ONE * face_scale
	)
	_draw_head_silhouette(unit, Color(0.05, 0.75, 0.88, 0.18))
	draw_set_transform(
		center + Vector2(chromatic_offset, 0.0),
		face_rotation,
		Vector2.ONE * face_scale
	)
	_draw_head_silhouette(unit, Color(0.95, 0.015, 0.025, 0.24))

	draw_set_transform(center, face_rotation, Vector2.ONE * face_scale)
	match killer_variant:
		&"crawler":
			_draw_crawler(unit)
		&"hunter":
			_draw_hunter(unit)
		_:
			_draw_statue(unit)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_interference()


func _draw_head_silhouette(unit: float, color: Color) -> void:
	if killer_variant == &"hunter":
		draw_colored_polygon(_scaled(hunter_skull, unit), color)
		return
	if killer_variant == &"crawler":
		draw_colored_polygon(_scaled(PackedVector2Array([
			Vector2(-0.31, -0.19), Vector2(-0.22, -0.34),
			Vector2(0.04, -0.4), Vector2(0.29, -0.27),
			Vector2(0.34, -0.03), Vector2(0.22, 0.31),
			Vector2(-0.08, 0.39), Vector2(-0.31, 0.22),
		]), unit), color)
	else:
		draw_colored_polygon(_scaled(PackedVector2Array([
			Vector2(-0.28, -0.34), Vector2(-0.08, -0.43),
			Vector2(0.22, -0.35), Vector2(0.31, -0.08),
			Vector2(0.22, 0.32), Vector2(0.0, 0.42),
			Vector2(-0.24, 0.3), Vector2(-0.33, -0.04),
		]), unit), color)


func _draw_statue(unit: float) -> void:
	var stone := Color(0.24, 0.25, 0.235, 1.0)
	var pale := Color(0.39, 0.38, 0.35, 1.0)
	var void_color := Color(0.002, 0.001, 0.002, 1.0)
	var blood := Color(0.82, 0.018, 0.012, 1.0)
	var outline := Color(0.055, 0.045, 0.043, 1.0)

	var skull := _scaled(PackedVector2Array([
		Vector2(-0.28, -0.34), Vector2(-0.08, -0.43),
		Vector2(0.22, -0.35), Vector2(0.31, -0.08),
		Vector2(0.22, 0.32), Vector2(0.0, 0.42),
		Vector2(-0.24, 0.3), Vector2(-0.33, -0.04),
	]), unit)
	draw_colored_polygon(skull, stone)
	draw_polyline(_scaled(PackedVector2Array([
		Vector2(-0.28, -0.34), Vector2(-0.08, -0.43),
		Vector2(0.22, -0.35), Vector2(0.31, -0.08),
		Vector2(0.22, 0.32), Vector2(0.0, 0.42),
		Vector2(-0.24, 0.3), Vector2(-0.33, -0.04),
		Vector2(-0.28, -0.34),
	]), unit), outline, maxf(unit * 0.012, 3.0), true)

	# Jagged forehead plates make the stone face read as cracked rather than a
	# smooth cartoon mask.
	draw_colored_polygon(_scaled(PackedVector2Array([
		Vector2(-0.25, -0.31), Vector2(-0.07, -0.39),
		Vector2(-0.02, -0.13), Vector2(-0.19, -0.09),
	]), unit), pale)
	draw_colored_polygon(_scaled(PackedVector2Array([
		Vector2(-0.015, -0.4), Vector2(0.19, -0.32),
		Vector2(0.23, -0.08), Vector2(0.035, -0.13),
	]), unit), Color(0.31, 0.31, 0.29, 1.0))

	var left_socket := _scaled(PackedVector2Array([
		Vector2(-0.255, -0.11), Vector2(-0.065, -0.16),
		Vector2(-0.045, 0.025), Vector2(-0.23, 0.045),
	]), unit)
	var right_socket := _scaled(PackedVector2Array([
		Vector2(0.055, -0.16), Vector2(0.245, -0.105),
		Vector2(0.225, 0.045), Vector2(0.04, 0.02),
	]), unit)
	draw_colored_polygon(left_socket, void_color)
	draw_colored_polygon(right_socket, void_color)
	_draw_burning_eye(Vector2(-0.145, -0.045) * unit, unit, blood)
	_draw_burning_eye(Vector2(0.14, -0.045) * unit, unit, blood)

	draw_colored_polygon(_scaled(PackedVector2Array([
		Vector2(-0.045, 0.015), Vector2(0.045, 0.01),
		Vector2(0.075, 0.13), Vector2(0.0, 0.165),
		Vector2(-0.065, 0.125),
	]), unit), Color(0.035, 0.025, 0.022, 1.0))

	var mouth := _scaled(PackedVector2Array([
		Vector2(-0.22, 0.16), Vector2(-0.105, 0.115),
		Vector2(0.115, 0.12), Vector2(0.225, 0.175),
		Vector2(0.155, 0.36), Vector2(0.0, 0.405),
		Vector2(-0.17, 0.34),
	]), unit)
	draw_colored_polygon(mouth, void_color)
	_draw_teeth(unit, -0.19, 0.19, 0.145, true)
	_draw_teeth(unit, -0.15, 0.16, 0.345, false)

	var crack_color := Color(0.055, 0.018, 0.014, 0.95)
	_draw_crack(_scaled(PackedVector2Array([
		Vector2(-0.015, -0.4), Vector2(-0.055, -0.23),
		Vector2(0.015, -0.12), Vector2(-0.04, 0.01),
	]), unit), crack_color, unit)
	_draw_crack(_scaled(PackedVector2Array([
		Vector2(0.235, -0.08), Vector2(0.14, 0.02),
		Vector2(0.18, 0.12), Vector2(0.1, 0.18),
	]), unit), crack_color, unit)
	_draw_crack(_scaled(PackedVector2Array([
		Vector2(-0.27, 0.04), Vector2(-0.17, 0.1),
		Vector2(-0.2, 0.2), Vector2(-0.12, 0.25),
	]), unit), crack_color, unit)


func _draw_crawler(unit: float) -> void:
	var flesh := Color(0.31, 0.19, 0.18, 1.0)
	var pale := Color(0.48, 0.34, 0.3, 1.0)
	var bruise := Color(0.16, 0.035, 0.06, 1.0)
	var void_color := Color(0.003, 0.001, 0.003, 1.0)

	# Long jointed fingers arrive a fraction before the face, framing it like it
	# has grabbed both sides of the screen.
	for side: float in [-1.0, 1.0]:
		var hand := _scaled(PackedVector2Array([
			Vector2(side * 0.48, 0.37), Vector2(side * 0.38, 0.08),
			Vector2(side * 0.31, -0.26), Vector2(side * 0.255, -0.24),
			Vector2(side * 0.29, 0.13), Vector2(side * 0.39, 0.43),
		]), unit)
		draw_colored_polygon(hand, Color(0.12, 0.055, 0.06, 1.0))

	var head := _scaled(PackedVector2Array([
		Vector2(-0.31, -0.19), Vector2(-0.22, -0.34),
		Vector2(0.04, -0.4), Vector2(0.29, -0.27),
		Vector2(0.34, -0.03), Vector2(0.22, 0.31),
		Vector2(-0.08, 0.39), Vector2(-0.31, 0.22),
	]), unit)
	draw_colored_polygon(head, flesh)
	draw_polyline(_scaled(PackedVector2Array([
		Vector2(-0.31, -0.19), Vector2(-0.22, -0.34),
		Vector2(0.04, -0.4), Vector2(0.29, -0.27),
		Vector2(0.34, -0.03), Vector2(0.22, 0.31),
		Vector2(-0.08, 0.39), Vector2(-0.31, 0.22),
		Vector2(-0.31, -0.19),
	]), unit), bruise, maxf(unit * 0.014, 3.0), true)
	draw_colored_polygon(_scaled(PackedVector2Array([
		Vector2(-0.24, -0.2), Vector2(0.02, -0.34),
		Vector2(0.25, -0.2), Vector2(0.16, -0.06),
		Vector2(-0.19, -0.03),
	]), unit), pale)

	# The crawler is blind: stitched eye seams are more unsettling and match its
	# sound-hunting behaviour.
	for side: float in [-1.0, 1.0]:
		var seam_center := Vector2(side * 0.14, -0.075) * unit
		draw_line(
			seam_center + Vector2(-0.09, -0.016) * unit,
			seam_center + Vector2(0.075, 0.012) * unit,
			void_color,
			maxf(unit * 0.015, 3.0),
			true
		)
		for stitch_index: int in 4:
			var stitch_x := lerpf(-0.065, 0.055, float(stitch_index) / 3.0)
			draw_line(
				seam_center + Vector2(stitch_x, -0.035) * unit,
				seam_center + Vector2(stitch_x + 0.012, 0.034) * unit,
				Color(0.06, 0.018, 0.02, 1.0),
				maxf(unit * 0.006, 2.0),
				true
			)

	draw_colored_polygon(_scaled(PackedVector2Array([
		Vector2(-0.04, -0.02), Vector2(0.055, -0.025),
		Vector2(0.085, 0.09), Vector2(-0.025, 0.115),
	]), unit), bruise)
	var mouth := _scaled(PackedVector2Array([
		Vector2(-0.24, 0.105), Vector2(-0.08, 0.065),
		Vector2(0.19, 0.095), Vector2(0.25, 0.18),
		Vector2(0.13, 0.345), Vector2(-0.095, 0.37),
		Vector2(-0.255, 0.255),
	]), unit)
	draw_colored_polygon(mouth, void_color)
	_draw_teeth(unit, -0.21, 0.21, 0.11, true)
	_draw_teeth(unit, -0.19, 0.14, 0.335, false)

	for vein_index: int in 5:
		var start := Vector2(-0.27 + vein_index * 0.13, -0.27 + absf(2.0 - vein_index) * 0.025)
		var points := _scaled(PackedVector2Array([
			start,
			start + Vector2(0.035, 0.08),
			start + Vector2(0.005, 0.16),
		]), unit)
		draw_polyline(points, Color(0.35, 0.025, 0.045, 0.85), maxf(unit * 0.004, 1.5), true)


## The huntsman is the only one of the three that is not a face at all: it is a
## hole, a ring of bone spines around it, and an eye on the end of every spine.
## The light is not a lantern any more - it is the creature's own gaze coming
## out of the hole, which is cold, does not flicker like a flame, and is already
## pointed at you. The last thing that happens is the beak coming down the
## middle of the frame.
func _draw_hunter(unit: float) -> void:
	var bone := Color(0.255, 0.210, 0.158, 1.0)
	var bone_lit := Color(0.44, 0.365, 0.272, 1.0)
	var void_color := Color(0.002, 0.001, 0.001, 1.0)
	var iris := Color(0.95, 0.55, 0.20, 1.0)
	var flesh := Color(0.055, 0.045, 0.038, 1.0)
	var gaze := Color(0.62, 0.70, 0.82)

	# The gaze washing out of the hole. It pulses on the creature's own rhythm
	# rather than guttering, which is the difference between a light something
	# is carrying and a light something *is*.
	var pulse := 1.0 + sin(elapsed * 6.0) * 0.10
	draw_circle(Vector2.ZERO, unit * 0.70 * pulse, Color(gaze.r, gaze.g, gaze.b, 0.045))
	draw_circle(Vector2.ZERO, unit * 0.38 * pulse, Color(gaze.r, gaze.g, gaze.b, 0.075))

	# Shoulders and ribcage, close enough now to fill everything the crown does
	# not - and carrying eyes of their own.
	draw_colored_polygon(_scaled(PackedVector2Array([
		Vector2(-0.66, 0.62), Vector2(-0.44, 0.20),
		Vector2(-0.16, 0.06), Vector2(0.18, 0.06),
		Vector2(0.46, 0.22), Vector2(0.68, 0.64),
	]), unit), flesh)

	# The crown. Ten spines, each a polyline rather than a filled shape so they
	# stay spindly and wrong at any scale, and each one twitching on its own.
	var spines := 10
	for index: int in spines:
		var seed := float(index)
		var angle := TAU * seed / float(spines) - PI * 0.5 \
			+ sin(elapsed * (0.8 + seed * 0.11) + seed) * 0.045
		var reach := 0.58 + sin(elapsed * (2.1 + seed * 0.23) + seed * 1.7) * 0.035
		var out := Vector2(cos(angle), sin(angle))
		var across := Vector2(-out.y, out.x)
		var root := out * 0.20
		var elbow := out * (reach * 0.62) + across * 0.035
		var tip := out * reach
		draw_polyline(
			PackedVector2Array([root * unit, elbow * unit, tip * unit]),
			bone,
			maxf(unit * 0.012, 2.5),
			true
		)
		# A barb off each shaft, so the ring is spiked and not just spoked.
		draw_line(
			(elbow + across * 0.005) * unit,
			(elbow + across * 0.048 - out * 0.015) * unit,
			bone,
			maxf(unit * 0.005, 1.5),
			true
		)
		_draw_stalker_eye(tip * unit, unit, 0.030, iris, seed * 1.31)

	# The hole. Drawn last of the head so nothing bleeds into it.
	draw_circle(Vector2.ZERO, unit * 0.215, void_color)
	draw_arc(Vector2.ZERO, unit * 0.225, 0.0, TAU, 28, bone, maxf(unit * 0.008, 2.0), true)

	# Skull and beak, straight down the middle and out of the bottom of frame.
	draw_colored_polygon(_scaled(PackedVector2Array([
		Vector2(-0.082, 0.02), Vector2(0.082, 0.02),
		Vector2(0.038, 0.30), Vector2(0.020, 0.62),
		Vector2(-0.020, 0.62), Vector2(-0.038, 0.30),
	]), unit), bone)
	# One lit edge, raked by its own gaze from above.
	draw_colored_polygon(_scaled(PackedVector2Array([
		Vector2(-0.082, 0.02), Vector2(-0.024, 0.02),
		Vector2(-0.010, 0.62), Vector2(-0.020, 0.62),
	]), unit), bone_lit)
	draw_polyline(_scaled(PackedVector2Array([
		Vector2(-0.082, 0.02), Vector2(-0.038, 0.30), Vector2(-0.020, 0.62),
		Vector2(0.020, 0.62), Vector2(0.038, 0.30), Vector2(0.082, 0.02),
	]), unit), Color(0.07, 0.055, 0.045, 1.0), maxf(unit * 0.009, 2.0), true)
	# The mandible splitting away from it, wider the closer this gets.
	var gape := 0.03 + sin(elapsed * 11.0) * 0.012
	draw_polyline(_scaled(PackedVector2Array([
		Vector2(-0.06, 0.12), Vector2(-0.05 - gape, 0.38), Vector2(-0.03 - gape, 0.66),
	]), unit), bone, maxf(unit * 0.008, 2.0), true)
	# Serrations cut into the beak's own edge rather than a row of teeth stuck
	# onto it: this jaw is one piece of bone, and it is not a mouth.
	for notch: int in 5:
		var along := 0.14 + float(notch) * 0.095
		var half := lerpf(0.062, 0.024, float(notch) / 4.0)
		draw_line(
			Vector2(-half, along) * unit,
			Vector2(-half * 0.45, along + 0.028) * unit,
			Color(0.06, 0.05, 0.04, 1.0),
			maxf(unit * 0.006, 1.5),
			true
		)
		draw_line(
			Vector2(half, along) * unit,
			Vector2(half * 0.45, along + 0.028) * unit,
			Color(0.06, 0.05, 0.04, 1.0),
			maxf(unit * 0.006, 1.5),
			true
		)

	# The pair in roughly the place a face would put them, and then the ones
	# that are not.
	for side: float in [-1.0, 1.0]:
		_draw_stalker_eye(Vector2(side * 0.155, 0.075) * unit, unit, 0.042, iris, side * 0.6)
		_draw_stalker_eye(Vector2(side * 0.375, 0.335) * unit, unit, 0.034, iris, side * 2.2)
		_draw_stalker_eye(Vector2(side * 0.545, 0.545) * unit, unit, 0.026, iris, side * 3.9)

	# It is soaking, and it is close enough now that the run-off is in frame.
	for index: int in 5:
		var drift := fposmod(elapsed * (0.5 + index * 0.11) + index * 0.29, 1.0)
		var origin := Vector2((index - 2) * 0.155, 0.10) * unit
		var bead := origin + Vector2(0.0, drift * 0.55 * unit)
		draw_line(origin, bead, Color(0.03, 0.026, 0.022, 0.5), maxf(unit * 0.004, 1.0), true)
		draw_circle(bead, unit * 0.012 * (1.0 - drift * 0.6), Color(0.06, 0.055, 0.05, 0.8))


## One of the creature's eyes: a wet dark ball, an iris that carries its own
## light, and a pupil that is a hole. `offset` desynchronises the blink, because
## a body covered in eyes that all blink together reads as decoration.
func _draw_stalker_eye(
	center: Vector2,
	unit: float,
	radius: float,
	iris: Color,
	offset: float
) -> void:
	# Open almost all the time: the blink is a tenth of the cycle, and `offset`
	# means no two eyes are inside that tenth together.
	var cycle := fposmod(elapsed * 0.7 + offset, 1.0)
	var blink := 0.0 if cycle > 0.09 else sin(cycle / 0.09 * PI)
	var open := 1.0 - blink * 0.92
	var scaled_radius := unit * radius
	draw_circle(center, scaled_radius, Color(0.045, 0.04, 0.035, 1.0))
	if open <= 0.05:
		return
	draw_circle(center, scaled_radius * 0.52 * open, Color(iris.r, iris.g, iris.b, 0.82))
	draw_circle(center, scaled_radius * 0.30 * open, Color(0.002, 0.002, 0.003, 1.0))
	draw_circle(
		center - Vector2(scaled_radius, scaled_radius) * 0.30,
		scaled_radius * 0.14,
		Color(0.85, 0.88, 0.95, 0.75)
	)


func _draw_burning_eye(center: Vector2, unit: float, color: Color) -> void:
	var pulse := 1.0 + sin(elapsed * 37.0) * 0.18
	draw_circle(center, unit * 0.047 * pulse, Color(color.r, color.g, color.b, 0.12))
	draw_circle(center, unit * 0.025 * pulse, Color(color.r, color.g, color.b, 0.52))
	draw_circle(center, unit * 0.011, Color(1.0, 0.48, 0.25, 1.0))
	draw_circle(center, unit * 0.004, Color.WHITE)


func _draw_teeth(
	unit: float,
	left: float,
	right: float,
	y: float,
	points_down: bool
) -> void:
	var count := 7
	for index: int in count:
		var tooth_x := lerpf(left, right, (float(index) + 0.5) / float(count))
		var half_width := 0.018 if index % 2 == 0 else 0.014
		var tooth_height := (0.065 if index % 3 == 0 else 0.048) * (1.0 if points_down else -1.0)
		draw_colored_polygon(_scaled(PackedVector2Array([
			Vector2(tooth_x - half_width, y),
			Vector2(tooth_x + half_width, y),
			Vector2(tooth_x, y + tooth_height),
		]), unit), Color(0.72, 0.69, 0.58, 1.0))


func _scaled(points: PackedVector2Array, unit: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(points.size())
	for index: int in points.size():
		result[index] = points[index] * unit
	return result


func _draw_crack(points: PackedVector2Array, color: Color, unit: float) -> void:
	draw_polyline(points, color, maxf(unit * 0.006, 2.0), true)


func _draw_interference() -> void:
	# Moving scanlines and occasional displaced bars sell the feeling that the
	# camera itself is breaking during the attack.
	var scan_offset := fposmod(elapsed * 290.0, 20.0)
	var y := scan_offset
	while y < size.y:
		draw_line(Vector2(0.0, y), Vector2(size.x, y), Color(0.8, 0.86, 0.88, 0.045), 1.0)
		y += 20.0

	for index: int in 8:
		var noise := sin(elapsed * (41.0 + index * 3.7) + index * 9.1)
		if noise < 0.42:
			continue
		var bar_y := fposmod(index * 113.0 + elapsed * (190.0 + index * 17.0), size.y)
		var bar_height := 2.0 + float((index * 7) % 13)
		var bar_width := size.x * (0.18 + fposmod(index * 0.173, 0.56))
		var bar_x := fposmod(index * 239.0 + elapsed * 97.0, size.x + bar_width) - bar_width
		var bar_color := Color(0.86, 0.02, 0.025, 0.12 + scare_progress * 0.12)
		if index % 2 == 0:
			bar_color = Color(0.05, 0.72, 0.82, 0.09 + scare_progress * 0.1)
		draw_rect(Rect2(bar_x, bar_y, bar_width, bar_height), bar_color)
