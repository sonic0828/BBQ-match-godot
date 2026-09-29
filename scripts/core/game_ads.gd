class_name GameAds
extends Node

signal event_received(event: Dictionary)
signal layout_changed

var bridge: JavaScriptObject
var callback: JavaScriptObject
var initialized = false
var window_width = 0.0
var window_height = 0.0
var safe_bottom = 0.0
var banner_size = Vector2(300, 105) # User-selected 20:7 card; native resize is authoritative.
var request_serial = 0

func initialize() -> void:
	if initialized: return
	initialized = true
	if OS.has_feature("wechat"):
		bridge = JavaScriptBridge.get_interface("bbqAds")
		if bridge != null:
			callback = JavaScriptBridge.create_callback(_receive)
			bridge.initialize(callback)

func _receive(args: Array) -> void:
	if args.is_empty(): return
	var value = JSON.parse_string(str(args[0]))
	if value is Dictionary: _deliver.call_deferred(value)

func _deliver(event: Dictionary) -> void:
	if event.get("type") == "layout":
		window_width = float(event.windowWidth)
		window_height = float(event.windowHeight)
		safe_bottom = float(event.safeBottom)
		banner_size = Vector2(event.bannerWidth, event.bannerHeight)
		layout_changed.emit()
	else:
		event_received.emit(event)

func prepare_reward() -> void:
	if bridge != null: bridge.prepareReward()

func request(kind: String) -> int:
	request_serial += 1
	if bridge == null:
		_deliver.call_deferred({"type": "result", "kind": kind, "id": request_serial, "status": "unavailable"})
	elif kind == "interstitial": bridge.showInterstitial(request_serial)
	else: bridge.showRewarded(request_serial)
	return request_serial

func acknowledge(receipt: String) -> void:
	if bridge != null: bridge.acknowledgeReward(receipt)

func set_banner(rect: Rect2, visible: bool, context: int) -> void:
	if bridge != null:
		bridge.setBanner(JSON.stringify({"left": rect.position.x, "top": rect.position.y,
			"width": rect.size.x, "height": rect.size.y, "visible": visible, "context": context}))

func _exit_tree() -> void:
	if bridge != null: bridge.dispose()
	callback = null
