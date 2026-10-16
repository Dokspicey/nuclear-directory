import { Controller } from "@hotwired/stimulus"

// A domain's documents on a Sources page (#201 part 2b), folded under its
// row; the button opens and closes them. Without JavaScript every row
// shows. Rows that aren't the domain's own are its documents.
export default class extends Controller {
  static values = { open: Boolean }

  connect() {
    this.show(this.openValue)
  }

  toggle(event) {
    this.show(event.currentTarget.getAttribute("aria-expanded") !== "true")
  }

  show(open) {
    this.element.querySelector("[aria-expanded]")?.setAttribute("aria-expanded", String(open))
    this.element.querySelectorAll("tr:not(.nd-sources__group)").forEach((row) => { row.hidden = !open })
  }
}
