class_name Calendar
extends RefCounted
## The calendar on Titamas follows the real one (the player's own clock): today's date,
## the real moon's phase and the holidays in data/world.json "holidays". Time of day in
## the game runs faster (WorldCycle), so one date sees several days and nights.
##
## Holidays: [{id, name, month, day, days}] (days = how long it lasts, from that day), or
## {id, name, month, weekday 0 = Sunday, nth 1..5 / -1 = last, days} for ones like
## Thanksgiving, or {id, name, easter: true, offset, days}.
## Names no autoloads (tests and @tool scripts can use it).

const SYNODIC := 29.530588853  # days from one new moon to the next
const NEW_MOON_UNIX := 947182440.0  # 6 Jan 2000, 18:14 UTC: a new moon
const PHASES := ["new", "waxing_crescent", "first_quarter", "waxing_gibbous", "full",
	"waning_gibbous", "last_quarter", "waning_crescent"]
const PHASE_NAMES := ["New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
	"Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent"]
const MONTHS := ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const WEEKDAYS := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

## For testing (Database → World → Sky "Moon phase"): ≥ 0 fixes the phase.
static var phase_override := -1.0
## For testing: a "YYYY-MM-DD" to use instead of today.
static var date_override := ""


## Today on the player's clock: {year, month, day, weekday}.
static func today() -> Dictionary:
	if date_override != "":
		var unix := Time.get_unix_time_from_datetime_string(date_override + "T12:00:00")
		return Time.get_date_dict_from_unix_time(unix)
	return Time.get_date_dict_from_system()


static func _now_unix() -> float:
	if date_override != "":
		return Time.get_unix_time_from_datetime_string(date_override + "T12:00:00")
	return Time.get_unix_time_from_system()


## 0 = new moon, 0.25 first quarter, 0.5 full, 0.75 last quarter.
static func moon_phase() -> float:
	if phase_override >= 0.0:
		return fposmod(phase_override, 1.0)
	var days := (_now_unix() - NEW_MOON_UNIX) / 86400.0
	return fposmod(days, SYNODIC) / SYNODIC


## Share of the moon's face that is lit (0..1).
static func moon_lit() -> float:
	return 0.5 * (1.0 - cos(moon_phase() * TAU))


## One of PHASES.
static func moon_phase_id() -> String:
	return PHASES[int(floor(moon_phase() * 8.0 + 0.5)) % 8]


static func moon_phase_name() -> String:
	return PHASE_NAMES[PHASES.find(moon_phase_id())]


## "Fri 13 Nov"
static func date_text() -> String:
	var d := today()
	return "%s %d %s" % [WEEKDAYS[int(d.weekday)], int(d.day), MONTHS[int(d.month)]]


static func _holiday_list() -> Array:
	var w = DataFiles.read(DataFiles.WORLD)
	var list = w.get("holidays", []) if w is Dictionary else []
	return list if list is Array else []


## The holidays on today's date (their entries).
static func holidays_today() -> Array:
	var out: Array = []
	var d := today()
	for h in _holiday_list():
		if h is Dictionary and is_holiday_on(h, d):
			out.append(h)
	return out


## Is the holiday with this id on today? "" = any holiday.
static func is_holiday(id: String) -> bool:
	for h: Dictionary in holidays_today():
		if id == "" or String(h.get("id", "")) == id:
			return true
	return false


static func is_holiday_on(h: Dictionary, d: Dictionary) -> bool:
	var year := int(d.year)
	var days := maxi(int(h.get("days", 1)), 1)
	var at := _day_number(year, int(d.month), int(d.day))
	for y: int in [year - 1, year]:  # one that started late last year can run into this one
		var s := _start_of(h, y)
		if at >= s and at < s + days:
			return true
	return false


## Days since 1970 for that date (local calendar, no times).
static func _day_number(year: int, month: int, day: int) -> int:
	return int(Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": day, "hour": 12}) / 86400)


static func _start_of(h: Dictionary, year: int) -> int:
	if bool(h.get("easter", false)):
		var e := easter(year)
		return _day_number(year, e.x, e.y) + int(h.get("offset", 0))
	var month := int(h.get("month", 1))
	if h.has("weekday"):
		var wd := int(h.get("weekday", 0))
		var nth := int(h.get("nth", 1))
		if nth > 0:
			var first := _day_number(year, month, 1)
			var first_wd := int(Time.get_date_dict_from_unix_time(first * 86400 + 43200).weekday)
			return first + (wd - first_wd + 7) % 7 + (nth - 1) * 7
		# Last one in the month.
		var next_month := _day_number(year + (1 if month == 12 else 0), 1 if month == 12 else month + 1, 1)
		var last := next_month - 1
		var last_wd := int(Time.get_date_dict_from_unix_time(last * 86400 + 43200).weekday)
		return last - (last_wd - wd + 7) % 7
	return _day_number(year, month, int(h.get("day", 1)))


## Easter Sunday (Gregorian): (month, day).
static func easter(year: int) -> Vector2i:
	var a := year % 19
	var b := year / 100
	var c := year % 100
	var d := b / 4
	var e := b % 4
	var f := (b + 8) / 25
	var g := (b - f + 1) / 3
	var h := (19 * a + b - d - g + 15) % 30
	var i := c / 4
	var k := c % 4
	var l := (32 + 2 * e + 2 * i - h - k) % 7
	var m := (a + 11 * h + 22 * l) / 451
	var month := (h + l - 7 * m + 114) / 31
	var day := (h + l - 7 * m + 114) % 31 + 1
	return Vector2i(month, day)


## Is today within from..to ("MM-DD", wrapping past New Year)?
static func in_dates(from: String, to: String) -> bool:
	var d := today()
	var now := int(d.month) * 100 + int(d.day)
	var a := _md(from)
	var b := _md(to if to != "" else from)
	return now >= a and now <= b if a <= b else (now >= a or now <= b)


static func _md(s: String) -> int:
	var p := s.split("-")
	if p.size() < 2:
		return 0
	return int(p[0]) * 100 + int(p[1])
