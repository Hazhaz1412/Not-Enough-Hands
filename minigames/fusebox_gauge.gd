class_name FuseboxGauge
extends Control

## Pure presentation: the minigame script writes these each frame and calls
## queue_redraw(). No game state lives here.
var needle_angle_deg: float = 0.0
var band_lo_deg: float = -10.0
var band_hi_deg: float = 10.0
var span_deg: float = 88.0


func _draw() -> void:
	var center := Vector2(size.x * 0.5, size.y * 0.96)
	var radius := minf(size.x * 0.5, size.y * 0.92)
	if radius <= 1.0:
		return

	_draw_face(center, radius)
	_draw_ticks(center, radius)
	_draw_band(center, radius)
	_draw_needle(center, radius)


func _draw_face(center: Vector2, radius: float) -> void:
	draw_arc(
		center, radius,
		deg_to_rad(-90.0 - span_deg), deg_to_rad(-90.0 + span_deg),
		48, Color(0.86, 0.83, 0.75, 0.16), 3.0, true
	)


func _draw_ticks(center: Vector2, radius: float) -> void:
	var degrees := -int(span_deg)
	while degrees <= int(span_deg):
		var major := degrees % 30 == 0
		var inner := radius * (0.8 if major else 0.87)
		var outer := radius * 0.94
		var angle := deg_to_rad(float(degrees) - 90.0)
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(
			center + direction * inner,
			center + direction * outer,
			Color(0.78, 0.73, 0.62, 0.55),
			2.2 if major else 1.3,
			true
		)
		degrees += 10


func _draw_band(center: Vector2, radius: float) -> void:
	draw_arc(
		center, radius * 0.86,
		deg_to_rad(band_lo_deg - 90.0), deg_to_rad(band_hi_deg - 90.0),
		24, Color(0.42, 0.7, 0.4, 0.95), 11.0, true
	)


func _draw_needle(center: Vector2, radius: float) -> void:
	var angle := deg_to_rad(needle_angle_deg - 90.0)
	var tip := center + Vector2(cos(angle), sin(angle)) * radius * 0.78
	draw_line(center, tip, Color(0.82, 0.26, 0.2, 0.98), 4.0, true)
	draw_circle(center, 9.0, Color(0.14, 0.12, 0.1, 1.0))
	draw_circle(center, 3.5, Color(0.72, 0.57, 0.32, 1.0))
