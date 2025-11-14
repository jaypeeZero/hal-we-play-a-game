# Crew AI Performance Fix - The Right Way

## Current Problem (Polling Every Frame)

```gdscript
func _process(delta):
    # WRONG: Process ALL crew EVERY frame
    update_all_crew_memory()      # 20 crew × 60fps = 1200/sec
    update_all_crew_awareness()   # 20 crew × 60fps = 1200/sec
    process_command_chain()       # 20 crew × 60fps = 1200/sec
    update_all_crew_decisions()   # filtered, but still checks all
```

Even with event-driven decisions, we're still checking everyone constantly.

## Solution: True Event-Driven (Wake on Events Only)

Crew should be **completely passive** until woken by specific events:

### Events That Wake Crew

1. **Sensor Contact** - Enemy enters awareness range
2. **Order Received** - Superior issues command
3. **Ship Damaged** - Alert condition
4. **Timer Expired** - Scheduled re-evaluation
5. **Target Lost** - Need new target

### Architecture

```gdscript
# Event queue (processed once per frame)
var _crew_events: Array = []

# Only crew with pending events are processed
func _process(delta):
    process_crew_events(_crew_events)
    _crew_events.clear()

# Emit events when things happen
func _on_enemy_enters_sensor_range(crew_id, enemy_id):
    _crew_events.append({
        "type": "sensor_contact",
        "crew_id": crew_id,
        "data": {"enemy_id": enemy_id}
    })

# Crew only "think" when they have events
func process_crew_events(events):
    for event in events:
        var crew = find_crew(event.crew_id)
        handle_crew_event(crew, event)
```

## Implementation Plan

### 1. Replace Awareness System (No More Polling)

**CURRENT (Bad):**
```gdscript
# Every frame for every crew
for crew in all_crew:
    check_all_ships_in_range()  # O(N×M) every frame!
```

**NEW (Event-Driven):**
```gdscript
# Ship emits event when entering range
signal enemy_detected(crew_id, enemy_data)

# Only process when signal fires
func _on_enemy_detected(crew_id, enemy_data):
    queue_crew_event(crew_id, "threat_detected", enemy_data)
```

### 2. Replace Command Chain (No More Polling)

**CURRENT (Bad):**
```gdscript
# Every frame
distribute_orders_down_chain()  # Check all crew
share_information_up_chain()    # Check all crew
```

**NEW (Event-Driven):**
```gdscript
# Only when order is issued
func issue_order(from_crew_id, to_crew_id, order):
    queue_crew_event(to_crew_id, "order_received", order)

# Only when report is generated
func send_report(from_crew_id, to_crew_id, report):
    queue_crew_event(to_crew_id, "report_received", report)
```

### 3. Replace Memory System (No More Polling)

**CURRENT (Bad):**
```gdscript
# Every frame
update_all_crew_memory(recent_events)  # Process all crew
```

**NEW (Event-Driven):**
```gdscript
# Only when significant event occurs
func _on_battle_event(event):
    # Find affected crew (spatial query, not all crew)
    var nearby_crew = get_crew_in_range(event.position, 1000)
    for crew_id in nearby_crew:
        queue_crew_event(crew_id, "witnessed_event", event)
```

## Performance Comparison

### Current (Polling)
- 20 crew × 60 FPS × 3 systems = **3,600 operations/sec**
- Scales linearly with crew count: O(N × FPS)
- 1000 crew = 180,000 operations/sec = death

### Event-Driven
- ~5 events/sec per crew (average) × 20 crew = **100 operations/sec**
- Scales with activity, not crew count: O(events)
- 1000 crew at peace = ~100 events/sec = fine
- 1000 crew in battle = ~5000 events/sec = still fine

## Code Changes Required

1. **Add event queue to SpaceBattleGame**
2. **Remove polling from _update_crew_ai_systems**
3. **Add spatial triggers for awareness**
4. **Convert command chain to message passing**
5. **Convert memory to event handlers**

This is the CORRECT architecture for simulation.
