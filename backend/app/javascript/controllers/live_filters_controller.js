import { Controller } from "@hotwired/stimulus"

// Live's filters (#201): open on wider screens; folded behind "Filters (N)"
// on phones, where the chips would push the list off the screen. Crossing
// the breakpoint (turning a tablet, widening a window) folds or opens them
// again, so they're never closed with their button hidden.
export default class extends Controller {
  connect() {
    this.phone = window.matchMedia("(max-width: 560px)")
    this.fit = () => { this.element.open = !this.phone.matches }
    this.phone.addEventListener("change", this.fit)
    this.fit()
  }

  disconnect() {
    this.phone.removeEventListener("change", this.fit)
  }
}
