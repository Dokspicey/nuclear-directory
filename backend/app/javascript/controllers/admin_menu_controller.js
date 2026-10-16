import { Controller } from "@hotwired/stimulus"

// The admin's nav on phones (#201): folded behind "Menu" at the top. Without
// JavaScript the button stays hidden and the nav stays open; on wider
// screens CSS shows the nav whatever the state. It closes on every visit
// and before Turbo caches the page, so Back never shows it stuck open.
export default class extends Controller {
  static targets = ["button"]

  connect() {
    this.buttonTarget.hidden = false
    this.close = () => this.set(false)
    document.addEventListener("turbo:visit", this.close)
    document.addEventListener("turbo:before-cache", this.close)
    this.set(false)
  }

  disconnect() {
    document.removeEventListener("turbo:visit", this.close)
    document.removeEventListener("turbo:before-cache", this.close)
  }

  toggle() {
    this.set(this.element.dataset.menuState !== "open")
  }

  set(open) {
    this.element.dataset.menuState = open ? "open" : "closed"
    this.buttonTarget.setAttribute("aria-expanded", String(open))
  }
}
