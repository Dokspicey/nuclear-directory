import { Controller } from "@hotwired/stimulus"

// The admin's nav on phones (#201): folded behind "Menu" at the top. Without
// JavaScript the button stays hidden and the nav stays open; on wider
// screens CSS shows the nav whatever the state.
export default class extends Controller {
  static targets = ["button"]

  connect() {
    this.buttonTarget.hidden = false
    this.set(false)
  }

  toggle() {
    this.set(this.element.dataset.menuState !== "open")
  }

  set(open) {
    this.element.dataset.menuState = open ? "open" : "closed"
    this.buttonTarget.setAttribute("aria-expanded", String(open))
  }
}
