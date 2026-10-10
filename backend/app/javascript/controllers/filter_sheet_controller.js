import { Controller } from "@hotwired/stimulus"

// Directory filters on phones (#90): a "Filters (N)" button opens the same
// filter form in a full-screen <dialog>, and its submit button counts what
// the choice would show ("Show 12 results") before you apply it. On wider
// screens the form sits inline as before, and without JavaScript the form
// stays inline on phones too (the sheet only hides it once this connects).
export default class extends Controller {
  static targets = ["dialog", "form", "submit"]
  static values = { countUrl: String }

  connect() {
    this.element.dataset.enhanced = ""
    this.label = this.submitTarget.textContent
  }

  open() {
    this.dialogTarget.showModal()
    this.count()
  }

  close() {
    this.dialogTarget.close()
  }

  // Ask how many results the current choices give, and say so on the button.
  async count() {
    if (!this.dialogTarget.open) return

    const params = new URLSearchParams(new FormData(this.formTarget))
    const request = (this.request = Symbol())
    try {
      const response = await fetch(`${this.countUrlValue}?${params}`, { headers: { Accept: "application/json" } })
      if (!response.ok || request !== this.request) return
      const { count } = await response.json()
      this.submitTarget.textContent = `Show ${count} ${count === 1 ? "result" : "results"}`
    } catch {
      this.submitTarget.textContent = this.label
    }
  }
}
