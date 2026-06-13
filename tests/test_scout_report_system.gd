extends GutTest

## Tests for ScoutReportSystem — behavior only, no specific data values.


func test_empty_fleet_returns_no_contacts_line():
	var lines := ScoutReportSystem.report_lines({})
	assert_eq(lines.size(), 1, "Empty fleet returns exactly one line")
	assert_true(lines[0].to_lower().contains("no contacts") or lines[0].to_lower().contains("long-range"),
		"Empty fleet line indicates no contacts")


func test_zero_count_fleet_returns_no_contacts_line():
	var lines := ScoutReportSystem.report_lines({"fighter": 0, "corvette": 0})
	assert_eq(lines.size(), 1, "All-zero fleet returns exactly one line")


func test_non_empty_fleet_returns_approximate_count_within_granularity():
	var fleet := {"fighter": 5, "corvette": 2}  # total = 7
	var total := 7
	var lines := ScoutReportSystem.report_lines(fleet)

	# Find the line that has a number in it (the count line)
	var count_line := ""
	for line in lines:
		if line.contains("~"):
			count_line = line
			break
	assert_ne(count_line, "", "Fleet report contains an approximate count line")

	# Extract the number from the count line
	var reported_count := _extract_number(count_line)
	var diff := abs(reported_count - total)
	assert_true(diff <= ScoutReportSystem.CONTACT_COUNT_GRANULARITY,
		"Reported count (%d) is within granularity of actual total (%d)" % [reported_count, total])


func test_names_largest_class_present():
	# corvette is larger than fighter in CLASS_SIZE_ORDER
	var fleet := {"fighter": 3, "corvette": 1}
	var lines := ScoutReportSystem.report_lines(fleet)

	var combined := " ".join(lines).to_lower()
	assert_true(combined.contains("corvette"),
		"Report names the largest class (corvette)")
	# fighter should not be named as largest
	assert_false(_has_class_as_largest(lines, "fighter"),
		"Report does not name fighter as largest class when corvette is present")


func test_does_not_name_absent_class_as_largest():
	# No capital ships present
	var fleet := {"fighter": 4}
	var lines := ScoutReportSystem.report_lines(fleet)
	var combined := " ".join(lines).to_lower()
	assert_false(combined.contains("capital"),
		"Report does not mention capital class when none are present")


func test_output_is_identical_across_calls():
	var fleet := {"torpedo_boat": 2, "heavy_fighter": 4}
	var first := ScoutReportSystem.report_lines(fleet)
	var second := ScoutReportSystem.report_lines(fleet)
	assert_eq(first, second, "Report is deterministic — identical on repeated calls")


func test_no_line_reveals_exact_per_type_count():
	var fleet := {"fighter": 3, "corvette": 2}
	var lines := ScoutReportSystem.report_lines(fleet)
	for line in lines:
		# Lines must not contain the exact substring "3" or "2" tied to a class name
		assert_false(line.to_lower().contains("3 fighter"),
			"No line reveals exact per-type count for fighters")
		assert_false(line.to_lower().contains("2 corvette"),
			"No line reveals exact per-type count for corvettes")


func test_minimum_reported_count_is_at_least_granularity():
	# Even with 1 ship, reported count must be >= CONTACT_COUNT_GRANULARITY
	var fleet := {"fighter": 1}
	var lines := ScoutReportSystem.report_lines(fleet)
	var count_line := ""
	for line in lines:
		if line.contains("~"):
			count_line = line
			break
	assert_ne(count_line, "", "Single-ship fleet has a count line")
	var reported := _extract_number(count_line)
	assert_gte(reported, ScoutReportSystem.CONTACT_COUNT_GRANULARITY,
		"Minimum reported count is at least CONTACT_COUNT_GRANULARITY")


# --- helpers ---

func _extract_number(line: String) -> int:
	## Pull first integer out of a string like "Contacts: ~6 signatures".
	var regex := RegEx.new()
	regex.compile("\\d+")
	var result := regex.search(line)
	if result:
		return int(result.get_string())
	return -1


func _has_class_as_largest(lines: Array, hull_class: String) -> bool:
	## Returns true if any "Largest contact" line names this class.
	for line in lines:
		if line.to_lower().contains("largest") and line.to_lower().contains(hull_class.to_lower()):
			return true
	return false
