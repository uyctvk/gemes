extends RefCounted
## Prototype tuning values. Integers use copper, grams and millilitres.

const RULES_VERSION = "prototype-1"
const WEIGHT_CAP = 24000
const VOLUME_CAP = 30000
const COIN_WEIGHT = 4
const VAULT_WEIGHT_CAP = 200000
const VAULT_VOLUME_CAP = 200000
const ITEM_TYPES = {
	"ore": {"name": "鉄鉱石", "weight": 2200, "volume": 900, "base": 6, "natural": true},
	"wood": {"name": "木材", "weight": 1800, "volume": 3800, "base": 4, "natural": true},
	"herb": {"name": "薬草", "weight": 200, "volume": 600, "base": 3, "natural": true},
	"sword": {"name": "鉄の剣", "weight": 3000, "volume": 4000, "base": 42, "natural": false},
	"medicine": {"name": "傷薬", "weight": 400, "volume": 500, "base": 12, "natural": false}
}
const RECIPES = {
	"sword": {"name": "鉄の剣", "inputs": {"ore": 3, "wood": 1}, "duration": 4.0, "station": "forge"},
	"medicine": {"name": "傷薬", "inputs": {"herb": 2, "wood": 1}, "duration": 2.0, "station": "apothecary"}
}
const STATIONS = {
	"market": Vector3(-8, 0, -8), "vault": Vector3(9, 0, -8),
	"forge": Vector3(-9, 0, 4), "apothecary": Vector3(9, 0, 4),
	"board": Vector3(0, 0, -10), "trainer": Vector3(-4, 0, 9),
	"wall": Vector3(0, 0, -22), "chest": Vector3(0, 0, -48)
}
const RESOURCES = {
	"ore": Vector3(-20, 0, -3), "wood": Vector3(20, 0, -2), "herb": Vector3(16, 0, 13)
}
const NAMES = ["エッダ", "トマス", "ミラ", "オスカー", "リーネ", "アルノ", "ベラ", "ノア", "イリス", "フーゴ", "エミル", "ハンナ", "フェリクス", "リーザ", "クララ", "レオン", "マルタ", "テオ", "エルザ", "ルーカス", "アデル", "ヨハン", "ローザ", "カール", "ニーナ", "ブルーノ", "ゼルマ", "ロルフ", "ソフィア", "オットー"]
const ROLES = ["鍛冶師", "薬師", "商人", "銀行員", "衛兵", "木こり", "採集者", "鉱夫", "村人", "農民"]

static func item_name(kind: String) -> String:
	return ITEM_TYPES.get(kind, {}).get("name", kind)

static func vec(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])

static func array_vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

static func load_tier(ratio: float) -> Dictionary:
	if ratio <= 0.5: return {"name": "軽量", "speed": 1.0, "stamina": 1.0}
	if ratio <= 0.75: return {"name": "標準", "speed": 1.0, "stamina": 1.2}
	if ratio <= 1.0: return {"name": "重量", "speed": 0.8, "stamina": 1.7}
	if ratio <= 1.25: return {"name": "過積載", "speed": 0.45, "stamina": 2.5}
	return {"name": "搬送不可", "speed": 0.0, "stamina": 3.0}
