import { Controller } from "@hotwired/stimulus"

// The decision bar's Reject panel (#269): Cancel or Esc closes it, and the
// focus goes back to the button that opened it. It also closes before
// Turbo caches the page, so Back never shows it open.
export default class extends Controller {
  static targets = ["panel"]

  connect() {
    this.onKey = (event) => { if (event.key === "Escape") this.close() }
    this.onCache = () => this.close()
    document.addEventListener("keydown", this.onKey)
    document.addEventListener("turbo:before-cache", this.onCache)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKey)
    document.removeEventListener("turbo:before-cache", this.onCache)
  }

  close() {
    if (!this.hasPanelTarget || !this.panelTarget.open) return
    this.panelTarget.open = false
    this.panelTarget.querySelector("summary")?.focus()
  }
}
