extends Control
class_name UIRoot
## Screen-filling, themed root for a UI CanvasLayer that UIKit.setup() has scaled
## down by UIKit.UI_SCALE. Keeps its size equal to the window in the layer's
## (scaled-up) units, so anchors and containers behave as if it were normal UI.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UIKit.theme()
	get_viewport().size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	size = get_viewport().get_visible_rect().size / UIKit.UI_SCALE
