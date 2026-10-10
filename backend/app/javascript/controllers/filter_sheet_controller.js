import { Controller } from "@hotwired/stimulus"

// Directory filters on phones (#90): a "Filters (N)" button opens the filter
// form in a full-screen <dialog>, and its submit button counts what the
// choice would show ("Show 12 results") before you apply it; a polite
// status line says the same to screen readers.
//
// The form lives inline (its "home") and only moves into the dialog while
// the dialog is open, so it's never inside a closed dialog. CSS decides
// from first paint which shows on phones (no layout shift), and without
// JavaScript the form stays inline everywhere.
export default class extends Controller {
  static targets = ["dialog", "home", "slot", "form", "submit", "status"]
  static values = { countUrl: String }

  connect() {
    this.label = this.submitTarget.textContent
    // Rotating a phone or widening a window past phone width closes the
    // sheet. Both events are watched: some browsers skip the query's change.
    this.phone = window.matchMedia("(max-width: 560px)")
    this.leftPhone = () => { if (this.dialogTarget.open && !this.phone.matches) this.close() }
    this.phone.addEventListener("change", this.leftPhone)
    window.addEventListener("resize", this.leftPhone)
  }

  disconnect() {
    this.phone?.removeEventListener("change", this.leftPhone)
    window.removeEventListener("resize", this.leftPhone)
  }

  open() {
    this.slotTarget.append(this.formTarget)
    this.dialogTarget.showModal()
    this.count()
  }

  // Close button, Escape (the dialog's cancel event) or the screen getting
  // wider. The form goes back inline here rather than only on the dialog's
  // close event, which some browsers deliver late.
  close() {
    if (this.dialogTarget.open) this.dialogTarget.close()
    this.closed()
  }

  // Also bound to the dialog's close event; safe to run twice.
  closed() {
    if (this.homeTarget.contains(this.formTarget)) return

    this.homeTarget.append(this.formTarget)
    this.request = null
    this.show(this.label, "")
  }

  // Ask how many results the current choices give, and say so.
  async count() {
    if (!this.dialogTarget.open) return

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
}
