class_name CrewViewModal
extends ModalDialog

## Read-only CrewMemberView in a centered modal over a dimmed backdrop.
## One popup shared by every screen that shows a crew member: shop crew rows,
## hire candidates, and the assignment board callsign links.

const MODAL_WIDTH := 560


## Build, attach to `parent`, and show the modal for one entry
## (roster-entry shape; adapt crew dicts with CrewData.entry_from_crew).
static func open(parent: Node, entry: Dictionary) -> CrewViewModal:
	var modal: CrewViewModal = CrewViewModal.new()
	parent.add_child(modal)
	modal.setup(entry)
	return modal


func setup(entry: Dictionary) -> void:
	build_chrome(MODAL_WIDTH)
	var view := CrewMemberView.new()
	view.setup(entry, false)
	content.add_child(view)
	add_footer()
