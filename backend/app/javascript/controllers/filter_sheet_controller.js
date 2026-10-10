import { Controller } from "@hotwired/stimulus"

// The live count on the phone filter sheet (#90). The sheet itself is a
// native popover that the "Filters (N)" button opens and closes without
// JavaScript (popovertarget), so filtering never depends on this file. When
// it loads, it adds: the submit button counts what the choice would show
// ("Show 12 results"), a polite status line says the same, and the sheet
// closes if the screen grows past phone width.
export default class extends Controller {
  static targets = ["sheet", "form", "submit", "status"]
  static values = { countUrl: String }

  connect() {
    this.label = this.submitTarget.textContent
    this.phone = window.matchMedia("(max-width: 560px)")
    this.leftPhone = () => { if (!this.phone.matches && this.isOpen) this.sheetTarget.hidePopover() }
    this.phone.addEventListener("change", this.leftPhone)
    window.addEventListener("resize", this.leftPhone)
  }

  disconnect() {
    this.phone?.removeEventListener("change", this.leftPhone)
    window.removeEventListener("resize", this.leftPhone)
  }

  // The popover opened or closed.
  toggled(event) {
    if (event.newState === "open") {
      this.count()
    } else {
      this.request = null
      this.show(this.label, "")
    }
  }

  // Ask how many results the current choices give, and say so.
  async count() {
    if (!this.isOpen) return

    const request = (this.request = Symbol())
    const params = new URLSearchParams(new FormData(this.formTarget))
    let count = null
    try {
      const response = await fetch(`${this.countUrlValue}?${params}`, { headers: { Accept: "application/json" } })
      if (response.ok) count = (await response.json()).count
    } catch {
      count = null
    }
    if (request !== this.request) return // a newer choice is already being counted

    if (Number.isInteger(count)) {
      const words = `${count} ${count === 1 ? "result" : "results"}`
      this.show(`Show ${words}`, words)
    } else {
      this.show(this.label, "")
    }
  }

  show(label, status) {
    this.submitTarget.textContent = label
    this.statusTarget.textContent = status
  }

  get isOpen() {
    return this.sheetTarget.matches(":popover-open")
  }
}
