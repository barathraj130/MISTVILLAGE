extends RefCounted
## Tiny per-system CPU profiler for --bench runs: Prof.add("name", start_usec) after each block.

static var totals := {}
static var frames := 0


static func add(name: String, start_usec: int) -> void:
	totals[name] = totals.get(name, 0) + (Time.get_ticks_usec() - start_usec)


static func report(frame_count: int) -> String:
	var parts := []
	for k in totals:
		parts.append("%s %.2fms" % [k, totals[k] / 1000.0 / maxi(frame_count, 1)])
	return "  ".join(parts)
