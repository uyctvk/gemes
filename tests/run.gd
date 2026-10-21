extends SceneTree
const World = preload("res://game/core/world.gd")
const Catalog = preload("res://game/core/catalog.gd")
var passed := 0
var failed := 0
var sequence := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, name: String) -> void:
	if condition: passed += 1; print("PASS ", name)
	else: failed += 1; push_error("FAIL " + name)

func fresh() -> RefCounted:
	var world = World.new()
	world.new_world()
	return world

func act(world: RefCounted, action: String, args: Dictionary = {}) -> Dictionary:
	sequence += 1
	return world.command("test_%d" % sequence, action, args)

func at(world: RefCounted, position: Vector3) -> void:
	world.state.player.position = Catalog.array_vec(position)

func gather(world: RefCounted, kind: String, count: int) -> void:
	at(world, Catalog.RESOURCES[kind])
	for i in range(count):
		world.advance(2)
		var result = act(world, "gather", {"kind": kind})
		check(result.ok, "gather " + kind)

func run() -> void:
	var start = Time.get_ticks_msec()
	test_seed_and_capacity()
	test_craft_and_trade()
	test_concurrency()
	test_quests_and_jobs()
	test_death_and_recovery()
	test_persistence()
	test_simulation()
	print("RESULT: %d passed; %d failed; %.2fs" % [passed, failed, (Time.get_ticks_msec()-start)/1000.0])
	quit(0 if failed == 0 else 1)

func test_seed_and_capacity() -> void:
	var world = fresh()
	check(world.state.player.job == "無垢" and world.state.npcs.size() == 30, "FR-02 / NPC-03 initial world")
	check(world.audit().is_empty(), "ECO-01 initial asset reconciliation")
	check(not act(world, "gather", {"kind": "ore"}).ok, "remote gathering rejected")
	check(not act(world, "gather", {"kind": "sword"}).ok, "manufactured resources rejected")
	for ratio in [0.5, 0.75, 1.0, 1.25]:
		check(Catalog.load_tier(ratio).speed > 0, "AC6-011/012 inclusive load boundary %.2f" % ratio)
	check(Catalog.load_tier(1.2501).speed == 0, "AC6-013 above carrying limit")
	# Volume reaches the 125% limit before weight: nine logs fit, the tenth does not.
	gather(world, "wood", 9)
	at(world, Catalog.RESOURCES.wood)
	world.advance(2)
	var resource_before = world.state.resources.wood
	check(not act(world, "gather", {"kind": "wood"}).ok, "volume overflow rejected")
	check(world.state.resources.wood == resource_before, "failed harvest preserves resource node")
	at(world, Catalog.STATIONS.vault)
	check(not act(world, "deposit_coins", {"amount": -10}).ok, "negative money transfer rejected")
	check(not act(world, "deposit_coins", {"amount": 0.5}).ok, "fractional money transfer rejected")
	check(not act(world, "deposit_coins", {"amount": "10"}).ok, "string money transfer rejected")
	check(world.audit().is_empty(), "failed commands have no partial asset mutation")
	world.state.accounts.player += 1
	world.state.accounts.market -= 1
	check(not world.audit().is_empty(), "audit detects unrecorded transfers even if total money matches")

func test_craft_and_trade() -> void:
	var world = fresh()
	at(world, Catalog.STATIONS.forge)
	check(not act(world, "craft", {"recipe": "sword"}).ok, "AC6-039 missing ingredients")
	gather(world, "ore", 3)
	gather(world, "wood", 1)
	at(world, Catalog.STATIONS.forge)
	var crafted = world.command("craft-once", "craft", {"recipe": "sword"})
	check(crafted.ok and world.items_at("inventory", "ore").is_empty(), "craft reserves real inputs")
	check(world.command("craft-once", "craft", {"recipe": "sword"}) == crafted, "QA-INV-003 identical craft replay")
	check(not act(world, "craft", {"recipe": "sword"}).ok, "reserved materials cannot be reused")
	world.advance(5)
	var sword = world.items_at("inventory", "sword")[0]
	check(sword.inputs.size() == 4 and sword.creator == "player", "AC-09-03 creator and input provenance")
	world.advance(5)
	check(world.items_at("inventory", "sword").size() == 1, "craft completion runs exactly once")
	at(world, Catalog.STATIONS.market)
	var quote: int = world.price("sword", true)
	var money_before = world.state.accounts.player
	var result = world.command("sell-once", "sell", {"item": sword.id, "quote": quote})
	check(result.ok and world.state.accounts.player == money_before + quote, "market atomically exchanges item and currency")
	for i in range(10): check(world.command("sell-once", "sell", {"item": sword.id, "quote": quote}) == result, "QA-INV-004 retry %d" % i)
	check(world.state.accounts.player == money_before + quote, "no duplicate sale proceeds")
	check(not world.command("sell-once", "sell", {"item": sword.id, "quote": quote + 1}).ok, "request ID cannot be reused with changed payload")
	var item = world.items_at("market", "herb")[0]
	check(not act(world, "buy", {"item": item.id, "quote": 0}).ok, "stale or forged price rejected")
	check(act(world, "buy", {"item": item.id, "quote": world.price("herb")}).ok, "buy real inventory")
	check(world.audit().is_empty(), "QA-INV-007 trade conserves money")

func test_concurrency() -> void:
	var world = fresh()
	at(world, Catalog.STATIONS.market)
	var item = world.items_at("market", "herb")[0]
	var quote: int = world.price("herb")
	var threads: Array = []
	for i in range(100):
		var thread := Thread.new()
		thread.start(world.command.bind("race_%d" % i, "buy", {"item": item.id, "quote": quote}))
		threads.append(thread)
	var successes := 0
	for thread in threads:
		if thread.wait_to_finish().ok: successes += 1
	check(successes == 1, "QA-INV-001 100 concurrent item claims: exactly one success")
	check(world.audit().is_empty(), "concurrent claims preserve ledger")
	world = fresh()
	at(world, Catalog.STATIONS.board)
	threads.clear()
	for i in range(100):
		var thread := Thread.new()
		thread.start(world.command.bind("quest_race_%d" % i, "accept", {"quest": "supply"}))
		threads.append(thread)
	successes = 0
	for thread in threads:
		if thread.wait_to_finish().ok: successes += 1
	check(successes == 1, "QA-QUEST-001 100 concurrent slot claims: exactly one success")

func test_quests_and_jobs() -> void:
	var world = fresh()
	at(world, Catalog.STATIONS.board)
	check(act(world, "accept", {"quest": "supply"}).ok, "quest slot accepted")
	check(not act(world, "deliver", {"quest": "supply"}).ok, "claimed delivery without evidence rejected")
	gather(world, "ore", 3)
	at(world, Catalog.STATIONS.board)
	check(act(world, "deliver", {"quest": "supply"}).ok, "real materials settle escrow")
	var money = world.state.accounts.player
	check(not act(world, "deliver", {"quest": "supply"}).ok and money == world.state.accounts.player, "quest cannot pay twice")
	at(world, Catalog.STATIONS.trainer)
	for i in range(3):
		world.advance(2)
		check(act(world, "train").ok, "verified training %d" % i)
	check(act(world, "job", {"job": "剣士"}).ok, "QA-JOB-001 innocent to swordsman")
	check(not act(world, "job", {"job": "職人"}).ok, "craft evidence required for artisan")
	gather(world, "wood", 4)
	at(world, Catalog.STATIONS.board)
	act(world, "accept", {"quest": "repair"})
	var wood_price: int = world.price("wood")
	check(act(world, "deliver", {"quest": "repair"}).ok, "WORLD-03 funded repair delivery")
	check(world.state.wall_hp == 100 and world.state.repaired, "repair changes physical world")
	check(world.price("wood") < wood_price, "repair lowers material demand")
	check(world.items_at("workshop", "wood").is_empty(), "repair consumes actual materials")
	check(world.audit().is_empty(), "repair and profession E2E preserves assets")
	world = fresh()
	world.state.accounts.smith = 0
	check(not world._offer("unfunded", "x", "x", "smith", "ore", 1, 20, "x", "x"), "QA-QUEST-002 no unfunded reward")
	world = fresh()
	world.advance(2881)
	check(world.state.quests.supply.status == "expired" and world.state.accounts.escrow == 0, "QA-QUEST-003 expiry refunds escrow")
	check(world.audit().is_empty(), "expired quests preserve funds")

func death_task(world: RefCounted) -> Dictionary:
	world.mutex.lock()
	world._die()
	world.mutex.unlock()
	return {"ok": true}

func test_death_and_recovery() -> void:
	var world = fresh()
	gather(world, "ore", 2)
	at(world, Catalog.STATIONS.vault)
	var safe_id: String = world.items_at("inventory")[0].id
	var lost_id: String = world.items_at("inventory")[1].id
	check(act(world, "deposit", {"item": safe_id}).ok, "deposit owned item")
	check(act(world, "deposit_coins", {"amount": 10}).ok, "deposit physical coins")
	world.state.player.level = 4
	death_task(world)
	check(world.state.items[safe_id].location == "vault" and world.state.accounts.vault == 10, "QA-DEATH-002 bank assets survive death")
	check(world.state.items[lost_id].location == "chest" and world.state.player.level == 2, "QA-DEATH-001 carried items moved and level -2")
	var once = world.state.duplicate(true)
	death_task(world)
	check(world.state == once, "duplicate death does not apply twice")
	check(act(world, "respawn").ok, "respawn preserves bank")
	world.state.enemy.hp = 0
	world.state.enemy.respawn_at = 99999
	at(world, Catalog.STATIONS.chest)
	check(act(world, "loot").item == lost_id, "AC6-048 recover identical item ID")
	check(not act(world, "loot").ok, "QA-INV-005 empty loot pool cannot mint weapons")
	check(world.audit().is_empty(), "death and recovery reconcile")
	world = fresh()
	gather(world, "wood", 1)
	at(world, Catalog.STATIONS.vault)
	var id: String = world.items_at("inventory")[0].id
	var deposit := Thread.new()
	var death := Thread.new()
	deposit.start(world.command.bind("deposit-race", "deposit", {"item": id}))
	death.start(death_task.bind(world))
	var result: Dictionary = deposit.wait_to_finish()
	death.wait_to_finish()
	check(world.state.items[id].location == ("vault" if result.ok else "chest"), "QA-INV-002 concurrent deposit and death are serialized")
	check(world.state.player.level == 1 and world.audit().is_empty(), "AC6-047 level floor and asset integrity")
	# Actual combat, not a direct kill: guardian gains only a real lost sword.
	world = fresh()
	gather(world, "ore", 3)
	gather(world, "wood", 1)
	at(world, Catalog.STATIONS.forge)
	act(world, "craft", {"recipe": "sword"})
	world.advance(5)
	var sword_id: String = world.items_at("inventory", "sword")[0].id
	at(world, Vector3(0, 0, -41))
	world.state.player.hp = 1
	world.advance(2)
	check(world.state.player.dead and world.state.items[sword_id].location == "enemy", "AC6-050 guardian equips actual death loot")
	act(world, "respawn")
	at(world, Vector3(0, 0, -41))
	world.state.enemy.hp = 5
	check(act(world, "attack").ok and world.state.enemy.hp == 0, "validated melee kills guardian")
	check(world.state.items[sword_id].location == "chest", "guardian drops same sword on defeat")
	check(world.audit().is_empty(), "combat asset conservation")

func test_persistence() -> void:
	var base = OS.get_environment("LIVING_WORLD_TEST_DIR")
	if base.is_empty(): base = "/tmp/living-world-tests-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(base)
	var path = base + "/world.json"
	var world = World.new(path)
	world.new_world()
	check(world.save(), "save complete initial snapshot")
	at(world, Catalog.RESOURCES.herb)
	var result = world.command("durable-harvest", "gather", {"kind": "herb"})
	check(result.ok, "persist confirmed command and request result")
	var loaded = World.new(path)
	check(loaded.load_world().ok, "load compatible save")
	check(loaded.state == world.state, "restored full state matches original")
	check(loaded.command("durable-harvest", "gather", {"kind": "herb"}) == result, "retry after restart is idempotent")
	var corrupt = FileAccess.open(path, FileAccess.WRITE)
	corrupt.store_string("truncated")
	corrupt.close()
	var restored = World.new(path)
	var restored_result = restored.load_world()
	check(restored_result.ok and restored_result.backup, "checksum failure recovers previous snapshot")
	check(restored.audit().is_empty(), "recovered snapshot reconciles")
	check(restored.save(), "save after backup recovery succeeds")
	var saved_backup = World.new(path + ".bak")
	check(saved_backup.load_world().ok, "recovery does not overwrite backup with corrupt primary")
	DirAccess.make_dir_recursive_absolute(base + "/blocked.tmp")
	var unavailable = World.new(base + "/blocked")
	unavailable.new_world()
	at(unavailable, Catalog.RESOURCES.herb)
	var before = unavailable.state.duplicate(true)
	check(not unavailable.command("blocked-save", "gather", {"kind": "herb"}).ok, "save failure is not reported as success")
	check(unavailable.state == before, "save failure rolls back in-memory transaction")

func test_simulation() -> void:
	var a = fresh()
	var b = fresh()
	a.advance(1440)
	for i in range(1440): b.advance(1)
	check(a.state == b.state, "WORLD-08 chunked time has deterministic results")
	a.advance(29 * 1440)
	check(a.state.clock == 480 + 30 * 1440, "30 game days actually simulated")
	check(a.audit().is_empty(), "NPC-03 30 day simulation has no asset or currency mismatch")
	check(a.state.price_history.size() == 48, "bounded price history")
	check(a.items_at("market", "sword").size() <= 3, "NPC production responds to finite stock")
	check(a.state.npcs.size() == 30, "NPC population conserved without LLM")
