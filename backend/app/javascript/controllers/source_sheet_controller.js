import { Controller } from "@hotwired/stimulus"

// Source chips on touch screens (#90): tapping a chip opens a sheet with the
// fact's quote, the source's title and link, and when it was checked, so
// nothing depends on hover or on scrolling down to the source list. On wide
// screens with a mouse, and without JavaScript, chips keep jumping to the
// numbered list. The sheet is a native <dialog>: Escape and the Close button
// close it, focus stays inside while open and returns to the chip after.
export default class extends Controller {
  static targets = ["dialog", "number", "body"]

  open(event) {
    const chip = event.target.closest?.("a.nd-src")
    if (!chip || !window.matchMedia("(max-width: 560px), (pointer: coarse)").matches) return

    const number = chip.getAttribute("href").replace("#source-", "")
    const entry = this.element.querySelector(`#source-${CSS.escape(number)}`)
    if (!entry) return

    event.preventDefault()
    this.chip = chip
    this.numberTarget.textContent = number
    this.bodyTarget.replaceChildren(...this.details(chip, entry))
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  // A tap on the dimmed backdrop (the dialog itself, outside its content) closes it.
  backdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  closed() {
    this.chip?.focus()
    this.chip = null
  }

  details(chip, entry) {
    const parts = []
    const quote = chip.closest(".nd-factrow")?.querySelector(".nd-quote")
    if (quote) parts.push(this.copy(quote))

    const source = entry.querySelector("span:last-child")
    if (source) {
      const copy = this.copy(source)
      copy.classList.add("nd-sheet__source")
      parts.push(copy)
    }

    const checked = chip.getAttribute("aria-label")?.match(/checked (\d{4}-\d{2}-\d{2})/)?.[1]
    if (checked) {
      const line = document.createElement("p")
      line.className = "type-data-sm text-ink-muted"
      line.textContent = `Checked ${checked}`
      parts.push(line)
    }
    return parts
  }

  copy(node) {
    const clone = node.cloneNode(true)
    clone.removeAttribute("id")
    return clone
  }
}
