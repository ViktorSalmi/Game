extends RefCounted

var id := 0
var pname := ""
var female := false
var born := 0.0
var lifespan := 0.0
var cell := Vector2.ZERO
var path: Array[Vector2i] = []
var state := "idle"          # idle, move, work, sleep
var job := {}                # {type, ...}
var work_t := 0.0
var hunger := 90.0
var energy := 90.0
var hp := 100.0
var carry_kind := ""
var carry_amt := 0
var home := -1               # byggnads-id
var town := 0
var role := ""               # senaste jobbtyp, för färg
var wait := 0.0
var face := 1.0
var moving := false
