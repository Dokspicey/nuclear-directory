import { Controller } from "@hotwired/stimulus"

// Live's filters (#201): open on wider screens; folded behind "Filters (N)"
// on phones, where the chips would push the list off the screen.
export default class extends Controller {
  connect() {
    if (window.matchMedia("(max-width: 560px)").matches) this.element.open = false
  }
}
