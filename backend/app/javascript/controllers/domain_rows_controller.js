import { Controller } from "@hotwired/stimulus"

// A domain's documents on a Sources page (#201 part 2b), folded under its
// row; the button opens and closes them. Without JavaScript every row
// shows. Rows that aren't the domain's own are its documents. The state is
// kept in the open value, so Back to a cached page shows it as it was left.
export default class extends Controller {
  static values = { open: Boolean }

  openValueChanged(open) {
    this.show(open)
  }

  toggle() {
    this.openValue = !this.openValue
  }

  show(open) {
    this.element.querySelector("[aria-expanded]")?.setAttribute("aria-expanded", String(open))
    this.element.querySelectorAll("tr:not(.nd-sources__group)").forEach((row) => { row.hidden = !open })
  }
}
