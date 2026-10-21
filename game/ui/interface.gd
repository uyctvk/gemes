extends CanvasLayer
## Reusable native UI. All buttons dispatch commands through the local authority.
const Catalog = preload("res://game/core/catalog.gd")
const INK = Color("eff0d9")
const MUTED = Color("a8b9a8")
const GOLD = Color("d7b878")
const PANEL = Color(0.055, 0.105, 0.098, 0.96)
var game: Node
var root: Control
var overlay: Control
var hud: Control
var modal: PanelContainer
var body: VBoxContainer
var title: Label
var status: Label
var vitals: Label
var objective: Label
var prompt: Label
var toast_label: Label
var toast_time := 0.0
var page := ""
var context: Dictionary = {}
var current_focus: Button
var ui_font: Font
var back_button: Button

func setup(controller: Node, font: Font) -> void:
	game = controller
	ui_font = font
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 19
	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", GOLD)
	theme.set_stylebox("normal", "Button", _style(Color("243c32"), Color("53624c")))
	theme.set_stylebox("hover", "Button", _style(Color("354e3c"), GOLD))
	theme.set_stylebox("pressed", "Button", _style(Color("4c5d40"), GOLD))
	theme.set_stylebox("focus", "Button", _style(Color(0,0,0,0), GOLD))
	theme.set_stylebox("disabled", "Button", _style(Color("1f2e2a"), Color("34423a")))
	theme.set_color("font_disabled_color", "Button", Color("6c7c6f"))
	root.theme = theme
	_build_hud()
	_build_overlay()
	show_title()

func _style(color: Color, border: Color = Color("566249")) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style

func label(text: String, size: int = 19, color: Color = INK, parent: Node = null) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(parent if parent != null else body).add_child(node)
	return node

func button(text: String, callback: Callable, parent: Node = null, disabled: bool = false) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size.y = 44
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.disabled = disabled
	node.pressed.connect(callback)
	(parent if parent != null else body).add_child(node)
	if current_focus == null and not disabled: current_focus = node
	return node

func _panel(parent: Node, pos: Vector2, size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = pos
	panel.size = size
	panel.add_theme_stylebox_override("panel", _style(Color(0.06,0.12,0.1,0.88)))
	parent.add_child(panel)
	return panel

func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	var top = _panel(hud, Vector2(28, 26), Vector2(310, 102))
	var top_box := VBoxContainer.new()
	top.add_child(top_box)
	label("L I V I N G   W O R L D", 17, GOLD, top_box)
	status = label("エルム村", 22, INK, top_box)
	var guide = _panel(hud, Vector2(1030, 26), Vector2(382, 170))
	guide.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	guide.offset_left = -410
	guide.offset_right = -28
	guide.offset_top = 26
	guide.offset_bottom = 196
	var guide_box := VBoxContainer.new()
	guide.add_child(guide_box)
	label("旅の手帳", 16, GOLD, guide_box)
	objective = label("", 18, INK, guide_box)
	var bottom = _panel(hud, Vector2(28, -126), Vector2(540, 98))
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bottom.offset_left = 28
	bottom.offset_right = 568
	bottom.offset_top = -126
	bottom.offset_bottom = -28
	vitals = label("", 19, INK, bottom)
	var keys = label("WASD 移動   Shift 走る   E 調べる\nI 荷物   J 手帳   H 傷薬   Esc メニュー", 16, INK, hud)
	keys.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	keys.offset_left = -450
	keys.offset_right = -30
	keys.offset_top = -100
	keys.offset_bottom = -25
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var cross = label("·", 38, INK, hud)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.offset_left = -10
	cross.offset_right = 10
	cross.offset_top = -29
	cross.offset_bottom = 21
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt = label("", 22, INK, hud)
	prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.offset_left = -330
	prompt.offset_right = 330
	prompt.offset_top = -185
	prompt.offset_bottom = -137
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label = label("", 21, GOLD, hud)
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.offset_left = -370
	toast_label.offset_right = 370
	toast_label.offset_top = 150
	toast_label.offset_bottom = 240
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for node in hud.get_children():
		if node is Control: node.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _build_overlay() -> void:
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.015,0.035,0.03,0.58)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	modal = PanelContainer.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	modal.offset_left = -460
	modal.offset_right = 460
	modal.offset_top = -355
	modal.offset_bottom = 355
	modal.add_theme_stylebox_override("panel", _style(PANEL, Color("a18e5f")))
	overlay.add_child(modal)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	modal.add_child(column)
	title = label("", 30, GOLD, column)
	var line := HSeparator.new()
	column.add_child(line)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	back_button = button("戻る  [ Esc / B ]", close, column)

func open(name: String, heading: String, data: Dictionary = {}) -> void:
	page = name
	back_button.visible = name != "title" and name != "death"
	context = data
	title.text = heading
	for node in body.get_children():
		body.remove_child(node)
		node.queue_free()
	current_focus = null
	overlay.show()
	game.set_control(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func focus_first() -> void:
	if is_instance_valid(current_focus): current_focus.grab_focus.call_deferred()

func close() -> void:
	if not game.started: return
	if game.world.state.player.dead: show_death(); return
	page = ""
	overlay.hide()
	game.set_control(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func toast(text: String) -> void:
	toast_label.text = text
	toast_time = 5.5

func show_title() -> void:
	hud.hide()
	open("title", "L I V I N G   W O R L D")
	label("生きる、働く、世界とともに。", 28)
	label("エルム村の朝", 42, GOLD)
	label("見知らぬ村で、あなたはまだ「無垢」。\n森の恵みを集め、職人に届け、最初の道を見つけよう。\n人々の仕事も、ものの価値も、あなたの行動で変わっていく。", 21)
	label("初期プレイアブル版  0.1  ·  1村 / 30人の住民", 17, MUTED)
	if FileAccess.file_exists(game.world.save_path) or FileAccess.file_exists(game.world.save_path + ".bak"):
		button("旅を続ける", func(): game.continue_game())
		button("新しい旅を始める", func(): confirm("新しい旅", "現在のセーブを新しい村で置き換えます。旧セーブは別ファイルに保管します。", func(): game.new_game()))
	else: button("旅を始める", func(): game.new_game())
	button("操作と設定", show_settings)
	button("終了", func(): game.get_tree().quit())
	focus_first()

func show_pause() -> void:
	open("pause", "旅のひと休み")
	label("村の時間はメニュー中も進みます。危険地帯では周囲に注意してください。", 19, MUTED)
	button("旅に戻る", close)
	button("持ち物を見る", show_inventory)
	button("旅の手帳", show_journal)
	button("操作と設定", show_settings)
	button("保存する", func(): toast("旅を保存した。" if game.world.save() else "保存に失敗しました。"))
	button("保存してタイトルへ", func(): game.return_to_title())
	focus_first()

func show_inventory() -> void:
	open("inventory", "持ち物")
	var load_info = game.world.load_for()
	label("%s  ·  %.1f / 24 kg  ·  %.1f / 30 L" % [load_info.tier.name, load_info.weight/1000.0, load_info.volume/1000.0], 21, GOLD)
	label("携行 %d 銅貨  /  銀行保管 %d 銅貨\n剣は携行中に自動装備。傷薬は H で使用。携行品は死亡時に遺品になります。" % [game.world.state.accounts.player, game.world.state.accounts.vault], 18, MUTED)
	var items = game.world.items_at("inventory")
	if items.is_empty(): label("まだ何も持っていません。村の外縁で資源を採集できます。")
	for item in items:
		label("%s    %.1f kg  /  %.1f L    耐久 %d\n製作者：%s  ·  %s" % [Catalog.item_name(item.kind), Catalog.ITEM_TYPES[item.kind].weight/1000.0, Catalog.ITEM_TYPES[item.kind].volume/1000.0, item.durability, item.creator, item.id], 18)
	button("傷薬を使う", func(): perform("heal", {}, show_inventory), null, game.world.items_at("inventory", "medicine").is_empty())
	focus_first()

func show_journal() -> void:
	open("journal", "旅の手帳")
	label("現在の道：%s  /  レベル %d" % [game.world.state.player.job, game.world.state.player.level], 24, GOLD)
	label("1. 掲示板で依頼を受ける → 2. 材料を集めて納品\n3. 訓練または製造 → 4. 師匠に転職を相談\n5. 銀行に大切な品を預け、北門の先へ", 19)
	label("村の案内", 23, GOLD)
	label("北：掲示板・北門・遺跡   西：市場・鍛冶場・鉄鉱石\n東：銀行・薬師・木材   南東：薬草   南西：訓練場", 19)
	for quest in game.world.state.quests.values():
		label("%s  —  %s\n%s %d個 / 報酬 %d銅貨" % [quest.title, _quest_status(quest.status), Catalog.item_name(quest.kind), quest.count, quest.reward], 18)
	label("村の近況", 23, GOLD)
	var events: Array = game.world.state.events
	var count := 0
	for i in range(events.size()-1, -1, -1):
		if events[i].type in ["INITIAL_WORLD_SEED", "VILLAGE_UPDATED", "QUEST_SETTLED", "WALL_REPAIRED", "JOB_CHANGED", "PLAYER_DIED", "CRAFT_COMPLETED", "TRADE_MATCHED"]:
			label("・" + events[i].message, 17, MUTED)
			count += 1
			if count >= 7: break
	focus_first()

func _quest_status(value: String) -> String:
	return {"available": "募集中", "active": "受注中", "completed": "完了", "expired": "期限切れ"}.get(value, value)

func show_quests() -> void:
	open("board", "村の依頼掲示板")
	label("仕事は村の困りごとから生まれます。報酬は依頼主が預託済みです。", 18, MUTED)
	for quest in game.world.state.quests.values():
		label(quest.title + "  ·  " + _quest_status(quest.status), 25, GOLD)
		label(quest.description, 19)
		var funding = "確保済み" if quest.status in ["available", "active"] else "支払済み" if quest.status == "completed" else "返却済み"
		label("依頼主：%s  /  納品：%s %d個\n報酬 %d銅貨（%s）  /  定員1人  /  残り %.1f時間" % [quest.issuer, Catalog.item_name(quest.kind), quest.count, quest.reward, funding, maxf(0, (quest.deadline-game.world.state.clock)/60)], 17, MUTED)
		var id: String = quest.id
		if quest.status == "available": button("この依頼を受ける", func(): confirm("受注の確認", quest.description + "\n報酬：%d銅貨。期限内に掲示板で材料を納品してください。" % quest.reward, func(): perform("accept", {"quest": id}, show_quests)))
		if quest.status == "active":
			button("材料を納品して報酬を受け取る", func(): confirm("納品の確認", "%sを%d個引き渡します。" % [Catalog.item_name(quest.kind), quest.count], func(): perform("deliver", {"quest": id}, show_quests)))
			button("依頼を返却する", func(): perform("abandon", {"quest": id}, show_quests))
	focus_first()

func show_market() -> void:
	open("market", "エルム村の市場")
	label("携行 %d銅貨  ·  商人の資金 %d銅貨" % [game.world.state.accounts.player, game.world.state.accounts.market], 21, GOLD)
	label("現地在庫に応じて価格が動きます。購入・売却はこの場で現物を引き渡します。税・手数料は試作では0。", 17, MUTED)
	label("買う", 24, GOLD)
	for kind in Catalog.ITEM_TYPES:
		var stock = game.world.items_at("market", kind)
		var amount: int = game.world.price(kind)
		if stock.is_empty(): label(Catalog.item_name(kind) + " — 品切れ", 18, MUTED); continue
		var id: String = stock[0].id
		button("%s    在庫%d    %d銅貨" % [Catalog.item_name(kind), stock.size(), amount], func(): confirm("購入の確認", "%sを%d銅貨で購入します。\n重さ %.1f kg / 体積 %.1f L" % [Catalog.item_name(kind), amount, Catalog.ITEM_TYPES[kind].weight/1000.0, Catalog.ITEM_TYPES[kind].volume/1000.0], func(): perform("buy", {"item": id, "quote": amount}, show_market)))
	label("売る", 24, GOLD)
	var carried = game.world.items_at("inventory")
	if carried.is_empty(): label("売れる携行品がありません。", 18, MUTED)
	for item in carried:
		var amount: int = game.world.price(item.kind, true)
		var id: String = item.id
		button("%sを売る    %d銅貨" % [Catalog.item_name(item.kind), amount], func(): confirm("売却の確認", "%sを%d銅貨で売却します。" % [Catalog.item_name(item.kind), amount], func(): perform("sell", {"item": id, "quote": amount}, show_market)))
	focus_first()

func show_vault() -> void:
	open("vault", "貸金庫  /  安全な保管")
	label("預入済みの品と銅貨は、死亡・襲撃から保護されます。", 21, GOLD)
	label("携行 %d銅貨  /  保管 %d銅貨  ·  手数料0\n容量 200 kg / 200 L。引出しはこの窓口で行います。" % [game.world.state.accounts.player, game.world.state.accounts.vault], 18, MUTED)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	button("10銅貨を預ける", func(): confirm("預入の確認", "携行金から10銅貨を安全保管へ移します。", func(): perform("deposit_coins", {"amount": 10}, show_vault)), row, game.world.state.accounts.player < 10)
	button("10銅貨を引き出す", func(): confirm("引出しの確認", "10銅貨を携行します。携行金は死亡時の損失対象です。", func(): perform("withdraw_coins", {"amount": 10}, show_vault)), row, game.world.state.accounts.vault < 10)
	label("預ける", 23, GOLD)
	if game.world.items_at("inventory").is_empty(): label("携行品はありません。", 18, MUTED)
	for item in game.world.items_at("inventory"):
		var id: String = item.id
		button(Catalog.item_name(item.kind) + "を預ける", func(): confirm("預入の確認", Catalog.item_name(item.kind) + "を安全保管へ移します。", func(): perform("deposit", {"item": id}, show_vault)))
	label("引き出す", 23, GOLD)
	if game.world.items_at("vault").is_empty(): label("貸金庫は空です。", 18, MUTED)
	for item in game.world.items_at("vault"):
		var id: String = item.id
		button(Catalog.item_name(item.kind) + "を引き出す", func(): confirm("引出しの確認", Catalog.item_name(item.kind) + "を携行します。死亡時は保護されません。", func(): perform("withdraw", {"item": id}, show_vault)))
	focus_first()

func show_craft(station: String) -> void:
	open(station, "鍛冶場" if station == "forge" else "薬師の工房")
	var recipe_id = "sword" if station == "forge" else "medicine"
	var recipe: Dictionary = Catalog.RECIPES[recipe_id]
	label("作る：" + recipe.name, 26, GOLD)
	label("材料を確保してから製造を始めます。製作者と材料の来歴は製品に残ります。", 18, MUTED)
	for kind in recipe.inputs:
		label("%s：%d / %d個" % [Catalog.item_name(kind), game.world.items_at("inventory", kind).size(), recipe.inputs[kind]], 21)
	label("作業時間：ゲーム内%d分（約%d秒）" % [recipe.duration, recipe.duration], 17, MUTED)
	button("製造を始める", func(): perform("craft", {"recipe": recipe_id}, func(): show_craft(station)))
	for job in game.world.state.crafts.values():
		if job.recipe != recipe_id: continue
		if job.status == "working": label("製造中。材料は工房で確保されています。", 18, GOLD)
		elif game.world.state.items[job.output].location == "workshop_pickup":
			var id: String = job.output
			button("完成品を受け取る", func(): perform("claim_craft", {"item": id}, func(): show_craft(station)))
	label("完成後は荷物へ入ります。持ちきれない場合は工房で保管します。", 17, MUTED)
	focus_first()

func show_trainer() -> void:
	open("trainer", "訓練場  /  最初の道")
	label("村に手を貸し、何者かになろう。", 26, GOLD)
	label("現在職：%s\n村の依頼：%d件完了   剣術訓練：%d / 3   製造：%d回" % [game.world.state.player.job, game.world.state.player.helped, game.world.state.player.training, game.world.state.player.crafted], 20)
	button("基礎訓練を受ける", func(): perform("train", {}, show_trainer), null, game.world.state.player.training >= 3)
	button("剣士になる  /  依頼1件 + 訓練3回", func(): confirm("剣士への道", "剣での攻撃が強くなります。試作では職業の変更が可能です。", func(): perform("job", {"job": "剣士"}, show_trainer)))
	button("職人になる  /  依頼1件 + 製造1回", func(): confirm("職人への道", "製造の実績を持つ職人として歩みます。上位技能は今後の実装範囲です。", func(): perform("job", {"job": "職人"}, show_trainer)))
	focus_first()

func show_npc(index: int, text: String) -> void:
	var npc: Dictionary = game.world.state.npcs[index]
	open("npc", "%s  /  %s" % [npc.name, npc.role])
	label("顔なじみ" if npc.trust > 1 else "出会ったばかり", 18, GOLD)
	label("「" + text + "」", 25)
	label("現在：" + npc.action, 18, MUTED)
	button("話を終える", close)
	focus_first()

func show_death() -> void:
	open("death", "旅は、ここで終わらない。")
	var summary: Dictionary = game.world.state.death
	label("レベル %d → %d  /  携行金 −%d銅貨" % [summary.level_before, summary.level_after, summary.coins], 25, GOLD)
	label("失った携行品：%d個。遺品は北の遺跡へ移りました。\n守り手が剣を拾っていることがあります。討伐して取り戻せます。" % summary.lost.size(), 20)
	for id in summary.lost: label("・" + Catalog.item_name(game.world.state.items[id].kind), 18, MUTED)
	label("守られたもの：銀行の%d個の品と%d銅貨。" % [summary.protected, summary.vault_coins], 22, GOLD)
	button("エルム村で再出発する", func():
		var result = game.act("respawn")
		if result.ok: game.player.restore_pose(); close()
	)
	focus_first()

func show_settings() -> void:
	open("settings", "操作と設定")
	label("WASD / 左スティック：移動\nマウス / 右スティック：視点\nE / A：調べる　左クリック / RT：攻撃\nShift / 左スティック押込：走る\nI / Y：荷物　J：手帳　H / X：傷薬\nEsc / B：戻る　F5：保存", 20)
	label("文字の大きさ", 21, GOLD)
	var row := HBoxContainer.new()
	body.add_child(row)
	for value in [0.9, 1.0, 1.15]:
		button("%d%%" % int(value * 100), func(): game.set_text_scale(value), row)
	label("視野角", 21, GOLD)
	var fov_slider := HSlider.new()
	fov_slider.min_value = 65
	fov_slider.max_value = 100
	fov_slider.step = 1
	fov_slider.value = game.player.camera.fov
	fov_slider.value_changed.connect(func(value): game.player.camera.fov = value; game.save_settings())
	body.add_child(fov_slider)
	label("マウス感度", 21, GOLD)
	var sensitivity := HSlider.new()
	sensitivity.min_value = 0.0008
	sensitivity.max_value = 0.005
	sensitivity.step = 0.0001
	sensitivity.value = game.player.sensitivity
	sensitivity.value_changed.connect(func(value): game.player.sensitivity = value; game.save_settings())
	body.add_child(sensitivity)
	button("戻る", show_pause if game.started else show_title)
	focus_first()

func confirm(heading: String, message: String, callback: Callable) -> void:
	var previous = page
	open("confirm", heading)
	label(message, 22)
	button("確定する", callback)
	button("キャンセル", func(): show_page(previous))
	focus_first()

func show_page(name: String) -> void:
	match name:
		"market": show_market()
		"vault": show_vault()
		"board": show_quests()
		"forge", "apothecary": show_craft(name)
		"trainer": show_trainer()
		"title": show_title()
		_: close()

func perform(action: String, args: Dictionary, refresh: Callable) -> void:
	var result = game.act(action, args)
	refresh.call()
	label(result.message, 19, GOLD if result.ok else Color("e6a08b"))

func update(delta: float, target: Dictionary) -> void:
	if not game.started: return
	hud.show()
	var state: Dictionary = game.world.state
	var day = int(state.clock / 1440) + 1
	var hour = int(state.clock / 60) % 24
	var minute = int(state.clock) % 60
	var area = "エルム村" if game.player.position.z > -27 else "北の遺跡  /  危険地帯"
	status.text = "%s\n第%d日  %02d:%02d" % [area, day, hour, minute]
	var load_info = game.world.load_for()
	vitals.text = "体力 %d   スタミナ %d   %s Lv.%d\n携行 %d銅貨   %.1f kg / %.1f L  ·  %s" % [state.player.hp, state.player.stamina, state.player.job, state.player.level, state.accounts.player, load_info.weight/1000.0, load_info.volume/1000.0, load_info.tier.name]
	if state.player.helped == 0: objective.text = "村の依頼をひとつ完了する\n北の掲示板で仕事を探そう。"
	elif state.player.job == "無垢": objective.text = "最初の職業を見つける\n訓練3回か製造1回を達成し、訓練場の師匠へ。"
	elif state.accounts.vault == 0 and game.world.items_at("vault").is_empty(): objective.text = "遠征の前に安全保管\n東の銀行へ品物か銅貨を預けよう。"
	else: objective.text = "北門の先を探索する\n剣と傷薬を用意して遺跡へ。帰還も大切な選択だ。"
	prompt.text = "[ E / A ]  " + target.name if not target.is_empty() and page == "" else ""
	toast_time = maxf(0, toast_time - delta)
	toast_label.visible = toast_time > 0
