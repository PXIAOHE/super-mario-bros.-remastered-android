extends SceneTree
## 字体探针：在 CI 里验证字体资源是否导入成功、是否含所需字形。
## 用法：godot --headless --path . --script res://tools/font_probe.gd


func _init() -> void:
	print("=== FONT PROBE START ===")
	_probe("res://Resources/ThemedResources/FontMain.tres", "FontMain")
	_probe("res://Resources/ThemedResources/ScoreFont.tres", "ScoreFont")
	_probe("res://Assets/Sprites/UI/Font.fnt", "Font.fnt(bitmap)")
	_probe("res://Scripts/Classes/Singletons/PixelFont.ttf", "PixelFont.ttf")
	_probe("res://Scripts/Classes/Singletons/CheatFont.otf", "CheatFont.otf")
	print("=== FONT PROBE END ===")
	quit()


func _probe(path: String, label: String) -> void:
	print("--- ", label, " @ ", path)
	if not ResourceLoader.exists(path):
		print("    MISSING (ResourceLoader.exists = false)")
		return
	var res = load(path)
	if res == null:
		print("    LOAD FAILED (null)")
		return
	print("    type = ", res.get_class())
	if not (res is Font):
		print("    NOT A FONT")
		return
	var f: Font = res
	print("    has A = ", f.has_char(65), " | has 0 = ", f.has_char(48), " | has 金 = ", f.has_char(0x91D1), " | has 世 = ", f.has_char(0x4E16))
	print("    height@16 = ", f.get_height(16), " | ascent@16 = ", f.get_ascent(16))
	if f is FontVariation:
		print("    base_font = ", f.base_font)
	if f is FontFile:
		print("    fixed_size = ", f.fixed_size, " | fallbacks = ", f.fallbacks.size())
# touch to trigger probe
