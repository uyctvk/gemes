extends RefCounted
## Local authority. All economic commands are serialized and committed together.
## No external client or LLM may write state. Network authentication is a later milestone.
const Catalog = preload("res://game/core/catalog.gd")
const INITIAL_ACCOUNTS = {"player": 24, "vault": 0, "market": 500, "council": 300, "smith": 150, "healer": 100, "escrow": 0, "lost": 0}
var state: Dictionary = {}
var save_path := ""
var mutex := Mutex.new()
var last_io_error := ""
var recovered_from_backup := false

func _init(path: String = "") -> void:
	save_path = path

func new_world(world_seed: int = 20261021) -> void:
	state = {
		"schema": 1, "rules": Catalog.RULES_VERSION, "seed": world_seed, "clock": 480.0,
		"sequence": 0, "version": 0, "events": [], "requests": {}, "items": {},
		"accounts": {"player": 24, "vault": 0, "market": 500, "council": 300, "smith": 150, "healer": 100, "escrow": 0, "lost": 0},
		"ledger": [], "initial_money": 1074, "crafts": {}, "quests": {},
		"resources": {"ore": 12, "wood": 12, "herb": 12}, "npcs": [],
		"player": {"job": "無垢", "level": 1, "xp": 0, "hp": 100.0, "stamina": 100.0, "position": [0, 0, 16], "yaw": 0.0, "pitch": 0.0, "training": 0, "crafted": 0, "helped": 0, "next_gather": 0.0, "next_attack": 0.0, "dead": false},
		"enemy": {"hp": 65.0, "position": [0, 0, -43], "next_attack": 0.0, "respawn_at": 0.0},
		"vault_open": true, "wall_hp": 40, "repaired": false, "death": {}, "price_history": []
	}
	_event("INITIAL_WORLD_SEED", "world", "村の資産と住民を初期配置", "", {"seed": world_seed})
	for kind in ["ore", "wood", "herb"]:
		for i in range(8): _mint(kind, "market", "market", "initial_world_seed", "world")
	# Seed manufactured stock through actual recipes, including inputs and provenance.
	for kind in ["sword", "medicine"]:
		var inputs: Array = []
		for material in Catalog.RECIPES[kind].inputs:
			for i in range(Catalog.RECIPES[kind].inputs[material]):
				inputs.append(_mint(material, "smith", "workshop", "initial_world_seed", "world"))
		for id in inputs: _consume(id, "INITIAL_CRAFT_INPUT")
		_mint(kind, "market", "market", "craft_completed", "smith", inputs)
	for i in range(30):
		var angle = float(i) * TAU / 30.0
		state.npcs.append({"id": "npc_%02d" % i, "name": Catalog.NAMES[i], "role": Catalog.ROLES[i % 10], "action": "仕事", "trust": 0, "memories": [], "home": [cos(angle)*14, 0, sin(angle)*13], "phase": float(i) * 0.71})
	_offer("supply", "工房に鉄鉱石を", "鍛冶師エッダ", "smith", "ore", 3, 20, "鍛冶場の鉄鉱石が不足している。西の露頭から3個を届けてほしい。", "INITIAL_WORLD_SEED")
	_offer("repair", "北門をふたたび", "村の評議会", "council", "wood", 4, 28, "嵐で北門が損傷した。木材4個を納め、修復を手伝ってほしい。", "INITIAL_WORLD_SEED")

func _id(prefix: String) -> String:
	state.sequence += 1
	return "%s_%08d" % [prefix, state.sequence]

func _event(kind: String, actor: String, message: String, cause: String = "", payload: Dictionary = {}) -> String:
	var id = _id("ev")
	state.events.append({"id": id, "type": kind, "actor": actor, "message": message, "time": state.clock, "version": state.version, "cause": cause, "payload": payload})
	return id

func _mint(kind: String, owner: String, location: String, origin: String, creator: String, inputs: Array = []) -> String:
	assert(Catalog.ITEM_TYPES[kind].natural or origin in ["craft_completed", "initial_world_seed"])
	var id = _id("item")
	var event = _event(origin.to_upper(), creator, Catalog.item_name(kind) + "が世界に加わった", "", {"item": id, "inputs": inputs})
	state.items[id] = {"id": id, "kind": kind, "owner": owner, "custodian": owner, "location": location, "origin": origin, "origin_event": event, "creator": creator, "inputs": inputs.duplicate(), "durability": 100, "quality": 1, "version": 0, "active": true}
	return id

func _move(id: String, owner: String, location: String, reason: String) -> void:
	var item: Dictionary = state.items[id]
	var source: String = item.location
	item.owner = owner
	item.custodian = owner
	item.location = location
	item.version += 1
	_event("ITEM_TRANSFERRED", owner, Catalog.item_name(item.kind) + "を移動", "", {"item": id, "from": source, "to": location, "reason": reason})

func _consume(id: String, reason: String) -> void:
	state.items[id].active = false
	state.items[id].location = "consumed"
	state.items[id].version += 1
	_event("ITEM_CONSUMED", state.items[id].owner, Catalog.item_name(state.items[id].kind) + "を使用", "", {"item": id, "reason": reason})

func _pay(source: String, target: String, amount: int, reason: String) -> void:
	assert(amount >= 0 and state.accounts[source] >= amount)
	var tx = _id("tx")
	state.accounts[source] -= amount
	state.accounts[target] += amount
	state.ledger.append({"tx": tx, "account": source, "delta": -amount, "reason": reason})
	state.ledger.append({"tx": tx, "account": target, "delta": amount, "reason": reason})

func items_at(location: String, kind: String = "") -> Array:
	var result: Array = []
	for item in state.items.values():
		if item.active and item.location == location and (kind == "" or item.kind == kind): result.append(item)
	return result

func load_for(location: String = "inventory", extra_kind: String = "", extra_coins: int = 0) -> Dictionary:
	var weight := 0
	var volume := 0
	for item in items_at(location):
		weight += Catalog.ITEM_TYPES[item.kind].weight
		volume += Catalog.ITEM_TYPES[item.kind].volume
	if extra_kind != "":
		weight += Catalog.ITEM_TYPES[extra_kind].weight
		volume += Catalog.ITEM_TYPES[extra_kind].volume
	var coins: int = state.accounts.player if location == "inventory" else state.accounts.vault if location == "vault" else 0
	weight += (coins + extra_coins) * Catalog.COIN_WEIGHT
	volume += coins + extra_coins
	var mass_cap = Catalog.WEIGHT_CAP if location == "inventory" else Catalog.VAULT_WEIGHT_CAP
	var volume_cap = Catalog.VOLUME_CAP if location == "inventory" else Catalog.VAULT_VOLUME_CAP
	var ratio = maxf(float(weight) / mass_cap, float(volume) / volume_cap)
	return {"weight": weight, "volume": volume, "ratio": ratio, "tier": Catalog.load_tier(ratio)}

func _fits(kind: String = "", coins: int = 0, location: String = "inventory") -> bool:
	return load_for(location, kind, coins).ratio <= (1.25 if location == "inventory" else 1.0)

func price(kind: String, selling: bool = false) -> int:
	var stock = items_at("market", kind).size()
	var target := 8.0 if Catalog.ITEM_TYPES[kind].natural else 3.0
	var scarcity = clampf(1.0 + (target - stock) * 0.07, 0.6, 2.0)
	if kind == "wood" and state.wall_hp < 100: scarcity += 0.2
	var ask = maxi(1, int(ceil(Catalog.ITEM_TYPES[kind].base * scarcity)))
	return maxi(1, int(floor(ask * 0.65))) if selling else ask

func _near(point: Vector3, distance: float = 4.0) -> bool:
	var pos = Catalog.vec(state.player.position)
	return Vector2(pos.x, pos.z).distance_to(Vector2(point.x, point.z)) <= distance

func _ok(message: String, extra: Dictionary = {}) -> Dictionary:
	var result = {"ok": true, "message": message}
	result.merge(extra)
	return result

func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}

func command(request_id: String, action: String, args: Dictionary = {}) -> Dictionary:
	mutex.lock()
	var result = _command_locked(request_id, action, args)
	mutex.unlock()
	return result

func _command_locked(request_id: String, action: String, args: Dictionary) -> Dictionary:
	if request_id.is_empty(): return _fail("REQUEST_REQUIRED", "操作IDがありません。")
	var fingerprint = JSON.stringify({"action": action, "args": args}).sha256_text()
	if state.requests.has(request_id):
		var prior: Dictionary = state.requests[request_id]
		if prior.fingerprint != fingerprint: return _fail("REQUEST_CONFLICT", "同じ操作IDで内容が変更されています。")
		return prior.result.duplicate(true)
	var before = state.duplicate(true)
	var result = _apply(action, args)
	if not result.ok:
		state = before
	else:
		state.version += 1
		var cause = _event("COMMAND_COMMITTED", "player", result.message, request_id, {"action": action})
		result["event_id"] = cause
	result["version"] = state.version
	state.requests[request_id] = {"fingerprint": fingerprint, "result": result.duplicate(true)}
	if not save_path.is_empty() and not save():
		state = before
		return _fail("SAVE_FAILED", "保存できませんでした。操作を取り消しました。")
	return result

func _apply(action: String, args: Dictionary) -> Dictionary:
	if state.player.dead and action != "respawn": return _fail("PLAYER_DEAD", "村へ戻ってから操作してください。")
	match action:
		"gather": return _gather(str(args.get("kind", "")))
		"craft": return _craft(str(args.get("recipe", "")))
		"claim_craft":
			var id = str(args.get("item", ""))
			if not state.items.has(id) or state.items[id].location != "workshop_pickup" or state.items[id].owner != "player": return _fail("ITEM_MISSING", "受取待ちの品がありません。")
			var kind: String = state.items[id].kind
			if not _near(Catalog.STATIONS[Catalog.RECIPES[kind].station]): return _fail("OUT_OF_RANGE", "製造した工房へ近づいてください。")
			if not _fits(kind): return _fail("CAPACITY_EXCEEDED", "品物を持ちきれません。")
			_move(id, "player", "inventory", "CRAFT_PICKUP")
			return _ok(Catalog.item_name(kind) + "を受け取った。")
		"buy", "sell": return _trade(action, str(args.get("item", "")), args.get("quote", -1))
		"deposit", "withdraw": return _vault_item(action, str(args.get("item", "")))
		"deposit_coins", "withdraw_coins": return _vault_coins(action, args.get("amount", 0))
		"accept", "deliver", "abandon": return _quest(action, str(args.get("quest", "")))
		"train":
			if not _near(Catalog.STATIONS.trainer): return _fail("OUT_OF_RANGE", "訓練場へ近づいてください。")
			if state.player.training >= 3: return _fail("TRAINING_DONE", "基礎訓練は修了しています。")
			if state.clock < state.player.next_attack: return _fail("COOLDOWN", "一呼吸おいてください。")
			state.player.training += 1
			state.player.next_attack = state.clock + 1.0
			_gain_xp(3)
			return _ok("剣術の基礎訓練 %d / 3" % state.player.training)
		"job": return _change_job(str(args.get("job", "")))
		"attack": return _attack()
		"heal":
			var medicines = items_at("inventory", "medicine")
			if medicines.is_empty(): return _fail("NO_MEDICINE", "傷薬を携行していません。")
			if state.player.hp >= 100: return _fail("FULL_HEALTH", "体力は十分です。")
			_consume(medicines[0].id, "HEAL")
			state.player.hp = minf(100, state.player.hp + 45)
			return _ok("傷薬を使い、体力が回復した。")
		"loot": return _loot()
		"respawn":
			if not state.player.dead: return _fail("NOT_DEAD", "まだ倒れていません。")
			state.player.dead = false
			state.player.hp = 100.0
			state.player.stamina = 100.0
			state.player.position = [0, 0, 16]
			return _ok("村の広場で目を覚ました。銀行の保管品は無事だ。")
		"talk":
			var index = int(args.get("npc", -1))
			if index < 0 or index >= state.npcs.size(): return _fail("NPC_MISSING", "相手が見つかりません。")
			if not _near(npc_position(index), 4.5): return _fail("OUT_OF_RANGE", "住民へ近づいてください。")
			var npc: Dictionary = state.npcs[index]
			var day = int(state.clock / 1440)
			if npc.get("last_talk_day", -1) != day:
				npc.trust += 1
				npc.last_talk_day = day
				npc.memories.append({"type": "MET_PLAYER", "day": day})
			return _ok(dialogue(index))
	return _fail("UNKNOWN_COMMAND", "この操作は利用できません。")

func _gather(kind: String) -> Dictionary:
	if not Catalog.RESOURCES.has(kind): return _fail("INVALID_RESOURCE", "この資源は採集できません。")
	if not _near(Catalog.RESOURCES[kind]): return _fail("OUT_OF_RANGE", "資源へ近づいてください。")
	if state.clock < state.player.next_gather: return _fail("COOLDOWN", "採集の手を休めています。")
	if state.resources[kind] <= 0: return _fail("RESOURCE_EMPTY", "資源が枯渇しています。時間をおいてください。")
	if not _fits(kind): return _fail("CAPACITY_EXCEEDED", "重量または体積が搬送限界を超えます。銀行へ預けてください。")
	state.resources[kind] -= 1
	var id = _mint(kind, "player", "inventory", "resource_harvested", "player")
	state.player.next_gather = state.clock + 1.5
	_gain_xp(2)
	return _ok(Catalog.item_name(kind) + "を採集した。", {"item": id})

func _craft(kind: String) -> Dictionary:
	if not Catalog.RECIPES.has(kind): return _fail("INVALID_RECIPE", "レシピがありません。")
	var recipe: Dictionary = Catalog.RECIPES[kind]
	if not _near(Catalog.STATIONS[recipe.station]): return _fail("OUT_OF_RANGE", "対応する工房へ近づいてください。")
	for job in state.crafts.values():
		if job.status == "working": return _fail("WORKSTATION_BUSY", "進行中の製造が終わるまでお待ちください。")
	var inputs: Array = []
	for material in recipe.inputs:
		var found = items_at("inventory", material)
		if found.size() < recipe.inputs[material]: return _fail("MATERIALS_MISSING", "必要な材料が足りません。")
		for i in range(recipe.inputs[material]): inputs.append(found[i].id)
	var job_id = _id("craft")
	for id in inputs: _move(id, "player", "craft:" + job_id, "CRAFT_RESERVED")
	state.crafts[job_id] = {"id": job_id, "recipe": kind, "inputs": inputs, "due": state.clock + recipe.duration, "status": "working"}
	_event("CRAFT_STARTED", "player", Catalog.item_name(kind) + "の製造を開始", "", {"job": job_id})
	return _ok("材料を確保し、%sの製造を始めた。" % Catalog.item_name(kind), {"craft": job_id})

func _trade(action: String, id: String, quote: Variant) -> Dictionary:
	if not _near(Catalog.STATIONS.market): return _fail("OUT_OF_RANGE", "市場へ近づいてください。")
	if not state.items.has(id) or not state.items[id].active: return _fail("ITEM_MISSING", "この品はもうありません。")
	var item: Dictionary = state.items[id]
	var buying = action == "buy"
	var source = "market" if buying else "inventory"
	if item.location != source or item.owner != ("market" if buying else "player"): return _fail("ITEM_NOT_OWNED", "品物の所在が変わりました。")
	var amount = price(item.kind, not buying)
	if typeof(quote) not in [TYPE_INT, TYPE_FLOAT] or quote != amount: return _fail("PRICE_CHANGED", "価格が変わりました。最新の見積りを確認してください。")
	var payer = "player" if buying else "market"
	var receiver = "market" if buying else "player"
	if state.accounts[payer] < amount: return _fail("INSUFFICIENT_FUNDS", "支払う側の所持金が足りません。")
	if buying and not _fits(item.kind, -amount): return _fail("CAPACITY_EXCEEDED", "持ち物の重量または体積が限界です。")
	if not buying:
		# Capacity is evaluated after removing the sold item and adding coins.
		_move(id, "market", "market", "SALE")
		if not _fits("", amount): return _fail("CAPACITY_EXCEEDED", "代金の硬貨を持ちきれません。")
	else:
		_move(id, "player", "inventory", "PURCHASE")
	_pay(payer, receiver, amount, "MARKET_TRADE")
	_event("TRADE_MATCHED", "player", "%sを%d銅貨で%s" % [Catalog.item_name(item.kind), amount, "購入" if buying else "売却"], "", {"item": id, "price": amount})
	return _ok("%sを%d銅貨で%sした。" % [Catalog.item_name(item.kind), amount, "購入" if buying else "売却"])

func _vault_item(action: String, id: String) -> Dictionary:
	if not _near(Catalog.STATIONS.vault): return _fail("OUT_OF_RANGE", "銀行窓口へ近づいてください。")
	if not state.vault_open: return _fail("VAULT_CLOSED", "窓口は休止中です。保管資産は守られています。")
	if not state.items.has(id): return _fail("ITEM_MISSING", "品物がありません。")
	var item: Dictionary = state.items[id]
	var source = "inventory" if action == "deposit" else "vault"
	var target = "vault" if action == "deposit" else "inventory"
	if not item.active or item.owner != "player" or item.location != source: return _fail("ITEM_NOT_OWNED", "移動できる所有品ではありません。")
	if not _fits(item.kind, 0, target): return _fail("CAPACITY_EXCEEDED", "移動先の重量または体積が限界です。")
	_move(id, "player", target, action.to_upper())
	return _ok(Catalog.item_name(item.kind) + ("を安全に預けた。" if action == "deposit" else "を引き出した。"))

func _vault_coins(action: String, value: Variant) -> Dictionary:
	if not _near(Catalog.STATIONS.vault): return _fail("OUT_OF_RANGE", "銀行窓口へ近づいてください。")
	if not state.vault_open: return _fail("VAULT_CLOSED", "窓口は休止中です。保管資産は守られています。")
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or value != int(value) or value <= 0: return _fail("INVALID_AMOUNT", "正の整数で指定してください。")
	var amount = int(value)
	var depositing = action == "deposit_coins"
	var source = "player" if depositing else "vault"
	var target = "vault" if depositing else "player"
	if state.accounts[source] < amount: return _fail("INSUFFICIENT_FUNDS", "銅貨が足りません。")
	if not _fits("", amount, "vault" if depositing else "inventory"): return _fail("CAPACITY_EXCEEDED", "硬貨を保管・携行する容量が不足しています。")
	_pay(source, target, amount, "VAULT_COINS")
	return _ok("%d銅貨を%s。" % [amount, "預けた" if depositing else "引き出した"])

func _offer(id: String, title: String, issuer: String, account: String, kind: String, count: int, reward: int, description: String, cause: String) -> bool:
	if state.quests.has(id) or state.accounts[account] < reward: return false
	_pay(account, "escrow", reward, "QUEST_FUNDED")
	state.quests[id] = {"id": id, "title": title, "issuer": issuer, "account": account, "kind": kind, "count": count, "reward": reward, "description": description, "status": "available", "deadline": state.clock + 2880.0, "actor": "", "version": 0}
	_event("QUEST_OFFERED", account, title + "の報酬を確保", cause, {"quest": id})
	return true

func _quest(action: String, id: String) -> Dictionary:
	if not _near(Catalog.STATIONS.board): return _fail("OUT_OF_RANGE", "依頼掲示板へ近づいてください。")
	if not state.quests.has(id): return _fail("QUEST_MISSING", "依頼が見つかりません。")
	var quest: Dictionary = state.quests[id]
	if state.clock >= quest.deadline: return _fail("EXPIRED", "依頼の期限が過ぎています。")
	if action == "accept":
		if quest.status != "available": return _fail("SLOT_TAKEN", "この依頼はすでに受注されています。")
		quest.status = "active"
		quest.actor = "player"
		quest.version += 1
		return _ok("「%s」を受注した。" % quest.title)
	if quest.status != "active" or quest.actor != "player": return _fail("NOT_ACCEPTED", "受注中の依頼ではありません。")
	if action == "abandon":
		quest.status = "available"
		quest.actor = ""
		quest.version += 1
		return _ok("依頼を返却した。報酬は次の受注者のために保全される。")
	var found = items_at("inventory", quest.kind)
	if found.size() < quest.count: return _fail("DELIVERY_MISSING", "納品する材料が足りません。")
	var ids: Array = []
	for i in range(quest.count):
		ids.append(found[i].id)
		_move(found[i].id, quest.account, "workshop", "QUEST_DELIVERY")
	if not _fits("", quest.reward): return _fail("CAPACITY_EXCEEDED", "報酬の硬貨を持ちきれません。")
	_pay("escrow", "player", quest.reward, "QUEST_SETTLED")
	quest.status = "completed"
	quest.version += 1
	state.player.helped += 1
	_gain_xp(15)
	var event = _event("QUEST_SETTLED", "player", quest.title + "を完了", "", {"quest": id, "proof_items": ids})
	if id == "repair":
		for item_id in ids: _consume(item_id, "WALL_REPAIR")
		state.wall_hp = 100
		state.repaired = true
		_event("WALL_REPAIRED", "council", "北門が修復され、木材需要が落ち着いた", event)
	else:
		for item_id in ids: _move(item_id, "market", "market", "SMITH_SUPPLY")
	state.npcs[0].trust += 3
	state.npcs[0].memories.append({"type": "HELPED_VILLAGE", "event": event})
	return _ok("「%s」を完了。%d銅貨を受け取った。" % [quest.title, quest.reward])

func _gain_xp(amount: int) -> void:
	state.player.xp += amount
	while state.player.xp >= 20:
		state.player.xp -= 20
		state.player.level += 1

func _change_job(job: String) -> Dictionary:
	if not _near(Catalog.STATIONS.trainer): return _fail("OUT_OF_RANGE", "訓練場で師匠に相談してください。")
	if job not in ["剣士", "職人"]: return _fail("INVALID_JOB", "この職業はまだ選べません。")
	if state.player.job == job: return _fail("SAME_JOB", "すでにその職業です。")
	if state.player.helped < 1: return _fail("EVIDENCE_MISSING", "まず村の依頼をひとつ完了させてください。")
	if job == "剣士" and state.player.training < 3: return _fail("TRAINING_MISSING", "基礎訓練を3回受けてください。")
	if job == "職人" and state.player.crafted < 1: return _fail("CRAFT_MISSING", "工房で製品をひとつ作ってください。")
	state.player.job = job
	_event("JOB_CHANGED", "player", job + "への道を歩み始めた")
	return _ok(job + "に転職した。")

func _attack() -> Dictionary:
	if state.clock < state.player.next_attack: return _fail("COOLDOWN", "武器を構え直しています。")
	if state.player.stamina < 15: return _fail("STAMINA_LOW", "スタミナが足りません。")
	state.player.next_attack = state.clock + 0.65
	state.player.stamina -= 15
	var enemy_pos = Catalog.vec(state.enemy.position)
	var direction = enemy_pos - Catalog.vec(state.player.position)
	var forward = Vector3(-sin(state.player.yaw), 0, -cos(state.player.yaw))
	if state.enemy.hp <= 0 or direction.length() > 3.4 or forward.dot(direction.normalized()) < 0.55:
		return _ok("攻撃は空を切った。")
	var damage := 8
	for item in items_at("inventory", "sword"):
		if item.durability > 0:
			damage = 22
			item.durability -= 1
			break
	if state.player.job == "剣士": damage += 6
	state.enemy.hp = maxf(0, state.enemy.hp - damage)
	_event("ATTACK_RESOLVED", "player", "遺跡の守り手に%dダメージ" % damage)
	if state.enemy.hp == 0:
		state.enemy.respawn_at = state.clock + 180
		for item in items_at("enemy"): _move(item.id, "lost", "chest", "MONSTER_DROPPED")
		_gain_xp(12)
		return _ok("守り手を倒した。回収箱の遺品を確かめよう。")
	return _ok("守り手に%dダメージ。" % damage)

func _die() -> void:
	if state.player.dead: return
	var lost: Array = []
	for item in items_at("inventory"):
		lost.append(item.id)
		_move(item.id, "lost", "chest", "PLAYER_DIED")
	var before_level = state.player.level
	state.player.level = maxi(1, int(before_level) - 2)
	var coins = int(floor(state.accounts.player * 0.25))
	_pay("player", "lost", coins, "DEATH_PENALTY")
	state.player.dead = true
	state.player.hp = 0
	state.death = {"lost": lost, "coins": coins, "level_before": before_level, "level_after": state.player.level, "protected": items_at("vault").size(), "vault_coins": state.accounts.vault}
	var event = _event("PLAYER_DIED", "player", "携行品を失った。銀行保管品は保護された。", "", state.death.duplicate(true))
	# The guardian equips one real lost sword. Never create a second sword.
	if state.enemy.hp > 0:
		for item in items_at("chest", "sword"):
			_move(item.id, "enemy", "enemy", "MONSTER_EQUIPPED")
			_event("MONSTER_EQUIPPED", "enemy", "守り手が遺品の剣を拾った", event, {"item": item.id})
			break

func _loot() -> Dictionary:
	if not _near(Catalog.STATIONS.chest): return _fail("OUT_OF_RANGE", "遺跡の回収箱へ近づいてください。")
	if state.enemy.hp > 0: return _fail("AREA_UNSAFE", "守り手が回収箱を守っています。")
	var contents = items_at("chest")
	if contents.is_empty(): return _fail("POOL_EMPTY", "遺品はありません。空の箱から装備は生まれません。")
	var item: Dictionary = contents[0]
	if not _fits(item.kind): return _fail("CAPACITY_EXCEEDED", "持ち物を整理してから戻ってください。")
	_move(item.id, "player", "inventory", "DUNGEON_ASSET_OUT")
	return _ok(Catalog.item_name(item.kind) + "を回収した。", {"item": item.id})

func advance(minutes: float) -> void:
	if minutes <= 0 or not is_finite(minutes): return
	mutex.lock()
	var remaining = minutes
	while remaining > 0:
		var step = minf(remaining, 1.0)
		var old_slot = int(state.clock / 30)
		state.clock += step
		remaining -= step
		state.player.stamina = minf(100, state.player.stamina + step * 7)
		for job in state.crafts.values():
			if job.status != "working" or state.clock < job.due: continue
			for id in job.inputs: _consume(id, "CRAFT_COMPLETED")
			var destination = "inventory" if _fits(job.recipe) and not state.player.dead else "workshop_pickup"
			job.output = _mint(job.recipe, "player", destination, "craft_completed", "player", job.inputs)
			job.status = "completed"
			state.player.crafted += 1
			_gain_xp(8)
			_event("CRAFT_COMPLETED", "player", Catalog.item_name(job.recipe) + ("が完成した" if destination == "inventory" else "が完成。工房で受取待ち"), "", {"job": job.id})
		for quest in state.quests.values():
			if quest.status in ["available", "active"] and state.clock >= quest.deadline:
				_pay("escrow", quest.account, quest.reward, "QUEST_REFUNDED")
				quest.status = "expired"
				_event("QUEST_EXPIRED", quest.account, quest.title + "が期限切れ。報酬を返却")
		if old_slot != int(state.clock / 30): _village_tick()
		_update_enemy(step)
	mutex.unlock()

func claim_craft(request_id: String, id: String) -> Dictionary:
	# Kept on the same command path for atomicity and idempotency.
	return command(request_id, "claim_craft", {"item": id})

func _village_tick() -> void:
	var hour = int(state.clock / 60) % 24
	for npc in state.npcs:
		npc.action = "休息" if hour < 6 or hour >= 21 else "食事" if hour == 12 or hour == 19 else "仕事"
	for kind in state.resources:
		var old = state.resources[kind]
		state.resources[kind] = mini(12, int(old) + 2)
		if old < 12: _event("RESOURCE_REGENERATED", "world", Catalog.item_name(kind) + "の資源が回復")
	if hour >= 6 and hour < 19:
		for kind in ["ore", "wood", "herb"]:
			if items_at("market", kind).size() < 12 and state.resources[kind] > 0:
				state.resources[kind] -= 1
				_mint(kind, "market", "market", "resource_harvested", "npc_gatherer")
		for kind in Catalog.RECIPES:
			if items_at("market", kind).size() >= 3: continue
			var inputs: Array = []
			var enough := true
			for material in Catalog.RECIPES[kind].inputs:
				var found = items_at("market", material)
				if found.size() < Catalog.RECIPES[kind].inputs[material]: enough = false; break
				for i in range(Catalog.RECIPES[kind].inputs[material]): inputs.append(found[i].id)
			if enough:
				for id in inputs: _consume(id, "NPC_CRAFT")
				_mint(kind, "market", "market", "craft_completed", "npc_smith" if kind == "sword" else "npc_healer", inputs)
	if hour in [12, 19]:
		var medicine = items_at("market", "medicine")
		if not medicine.is_empty() and state.accounts.healer >= price("medicine"):
			_pay("healer", "market", price("medicine"), "NPC_TREATMENT")
			_consume(medicine[0].id, "NPC_TREATMENT")
	state.price_history.append({"time": state.clock, "ore": price("ore"), "wood": price("wood"), "sword": price("sword")})
	if state.price_history.size() > 48: state.price_history.pop_front()
	_event("VILLAGE_UPDATED", "world", "%02d時：住民の生活・資源・生産を更新" % hour)

func _update_enemy(delta: float) -> void:
	if state.enemy.hp <= 0:
		if state.clock >= state.enemy.respawn_at:
			state.enemy.hp = 65.0
			state.enemy.position = [0, 0, -43]
		return
	if state.player.dead: return
	var enemy_pos = Catalog.vec(state.enemy.position)
	var player_pos = Catalog.vec(state.player.position)
	var distance = enemy_pos.distance_to(player_pos)
	if player_pos.z < -28 and distance < 13:
		if distance > 2.0:
			enemy_pos += (player_pos - enemy_pos).normalized() * minf(delta * 1.7, distance - 2.0)
			enemy_pos.y = 0
			state.enemy.position = Catalog.array_vec(enemy_pos)
		elif state.clock >= state.enemy.next_attack:
			state.enemy.next_attack = state.clock + 1.6
			var damage = 11 if items_at("enemy", "sword").is_empty() else 18
			state.player.hp = maxf(0, state.player.hp - damage)
			_event("PLAYER_HURT", "enemy", "守り手の攻撃：%dダメージ" % damage)
			if state.player.hp <= 0: _die()

func npc_position(index: int) -> Vector3:
	var npc: Dictionary = state.npcs[index]
	if index < 5:
		return [Vector3(-10, 0, 4), Vector3(10, 0, 4), Vector3(-9, 0, -9), Vector3(10, 0, -9), Vector3(-4, 0, 10)][index]
	var home = Catalog.vec(npc.home)
	if npc.action == "休息": return home
	var phase: float = state.clock * 0.018 + npc.phase
	return Vector3(sin(phase) * (6 + index % 4), 0, cos(phase * 0.7) * 12)

func dialogue(index: int) -> String:
	var npc: Dictionary = state.npcs[index]
	if index == 0:
		return "鉄を届けてくれたこと、覚えているよ。今度は自分の剣を打ってみないか。" if state.player.helped > 0 else "この村の剣は、誰かが鉱石を採り、火を焚いて作るんだ。掲示板に鉄の依頼を出しているよ。"
	if index == 3: return "ここに預けた品と銅貨は、命を落としても守られる。遠征の前に寄っておいで。"
	if index == 4: return "訓練を三度と、村の仕事をひとつ。剣士の道はそこからだ。北の遺跡に出るなら傷薬を忘れるな。"
	if npc.trust > 1: return "また会ったね。" + ("北門が直って、安心して働けるよ。" if state.repaired else "北門の木材が足りないらしい。掲示板を見てみて。")
	return "ようこそ、エルム村へ。私は%sの%s。今日は%sをしているところだよ。" % [npc.role, npc.name, npc.action]

func audit() -> Array:
	var issues: Array = []
	var total := 0
	for balance in state.accounts.values():
		if balance < 0: issues.append("negative balance")
		total += int(balance)
	if total != int(state.initial_money): issues.append("money supply mismatch")
	var sums: Dictionary = {}
	var balances = INITIAL_ACCOUNTS.duplicate()
	for entry in state.ledger:
		sums[entry.tx] = sums.get(entry.tx, 0) + entry.delta
		if not balances.has(entry.account): issues.append("unknown ledger account")
		else: balances[entry.account] += int(entry.delta)
	for sum_value in sums.values():
		if sum_value != 0: issues.append("unbalanced transaction")
	for account in balances:
		if state.accounts.get(account) != balances[account]: issues.append("account does not match ledger")
	var events_by_id: Dictionary = {}
	for event in state.events: events_by_id[event.id] = event
	var crafted_inputs: Dictionary = {}
	for id in state.items:
		var item: Dictionary = state.items[id]
		if item.id != id or not events_by_id.has(item.origin_event): issues.append("invalid item identity/origin")
		if not Catalog.ITEM_TYPES.has(item.kind): issues.append("unknown item type"); continue
		if not Catalog.ITEM_TYPES[item.kind].natural and item.origin not in ["craft_completed", "initial_world_seed"]: issues.append("unfunded manufactured item")
		if item.active and item.location in ["", "consumed"]: issues.append("orphan active item")
		if item.location == "vault" and item.owner != "player": issues.append("invalid vault owner")
		if item.origin == "craft_completed":
			var counts: Dictionary = {}
			for input_id in item.inputs:
				if not state.items.has(input_id): issues.append("missing craft input"); continue
				var ingredient: Dictionary = state.items[input_id]
				if ingredient.active or crafted_inputs.has(input_id): issues.append("craft input reused")
				crafted_inputs[input_id] = true
				counts[ingredient.kind] = counts.get(ingredient.kind, 0) + 1
			if not Catalog.RECIPES.has(item.kind) or counts != Catalog.RECIPES[item.kind].inputs: issues.append("recipe does not reconcile")
	var escrow := 0
	for quest in state.quests.values():
		if quest.status in ["available", "active"]: escrow += int(quest.reward)
	if escrow != int(state.accounts.escrow): issues.append("escrow mismatch")
	for stock in state.resources.values():
		if stock < 0 or stock > 12: issues.append("resource bounds")
	return issues

func save() -> bool:
	if save_path.is_empty(): return true
	var directory = save_path.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		last_io_error = "directory unavailable"; return false
	# Variant bytes preserve integer money and full-precision positions across restart.
	# Object decoding is disabled; only plain data types are stored.
	var body = Marshalls.raw_to_base64(var_to_bytes(state))
	var envelope = JSON.stringify({"encoding": "godot-variant-v1", "sha256": body.sha256_text(), "body": body})
	var file = FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	if file == null: last_io_error = "cannot open temporary file"; return false
	file.store_string(envelope)
	file.flush()
	var write_error = file.get_error()
	file.close()
	if write_error != OK: last_io_error = "write failed"; return false
	if FileAccess.file_exists(save_path) and not recovered_from_backup:
		if DirAccess.copy_absolute(save_path, save_path + ".bak") != OK:
			last_io_error = "backup failed"; return false
	var err = DirAccess.rename_absolute(save_path + ".tmp", save_path)
	if err != OK: last_io_error = "atomic replacement failed"; return false
	recovered_from_backup = false
	return true

func load_world() -> Dictionary:
	var original = state.duplicate(true)
	for path in [save_path, save_path + ".bak"]:
		if not FileAccess.file_exists(path): continue
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(path)) != OK: continue
		var envelope = parser.data
		if not envelope is Dictionary or not envelope.get("body") is String: continue
		if envelope.get("encoding") != "godot-variant-v1": continue
		if envelope.get("sha256", "") != envelope.body.sha256_text(): continue
		var parsed = bytes_to_var(Marshalls.base64_to_raw(envelope.body))
		if not _valid_shape(parsed): continue
		state = parsed
		if audit().is_empty():
			recovered_from_backup = path.ends_with(".bak")
			return {"ok": true, "backup": path.ends_with(".bak")}
	state = original
	return _fail("SAVE_INVALID", "有効なセーブがありません。既存ファイルは上書きしていません。")

func _valid_shape(value: Variant) -> bool:
	if not value is Dictionary or value.get("schema") != 1 or value.get("rules") != Catalog.RULES_VERSION: return false
	for key in ["player", "enemy", "items", "accounts", "resources", "requests", "crafts", "quests"]:
		if not value.get(key) is Dictionary: return false
	for key in ["events", "ledger", "npcs", "price_history"]:
		if not value.get(key) is Array: return false
	for key in ["clock", "sequence", "version", "initial_money"]:
		if typeof(value.get(key)) not in [TYPE_INT, TYPE_FLOAT]: return false
	if not value.player.get("position") is Array or value.player.position.size() != 3: return false
	for item in value.items.values():
		if not item is Dictionary: return false
		for key in ["id", "kind", "owner", "location", "origin", "origin_event", "active"]:
			if not item.has(key): return false
	return true
