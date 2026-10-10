import { Controller } from "@hotwired/stimulus"

// Instant results under a search field (#41). Typing loads /search?q= into a
// Turbo Frame below the field; Enter still submits the form to the full
// results. Arrow keys move between results, Escape closes them, and a polite
// live region announces how many results there are.
export default class extends Controller {
  static targets = ["input", "results", "frame", "status"]
  static values = { url: String, minimum: { type: Number, default: 2 }, delay: { type: Number, default: 150 } }

  disconnect() {
    clearTimeout(this.timer)
  }

  search() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.load(), this.delayValue)
  }

  load() {
    const query = this.inputTarget.value.trim()
    if (query.length < this.minimumValue) return this.close()

    this.pending = true
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("q", query)
    this.frameTarget.src = url.toString()
  }

  // A load that finishes after the results were closed stays closed.
  loaded() {
    if (!this.pending) return
    this.pending = false

    const panel = this.frameTarget.querySelector("[data-instant-search-count]")
    if (!panel) return this.close()

    const count = Number(panel.dataset.instantSearchCount)
    this.statusTarget.textContent = count === 0 ? "No results" : `${count} ${count === 1 ? "result" : "results"}, use the down arrow to browse`
    this.open()
  }

  // Keys pressed in the field.
  keydown(event) {
    if (event.key === "ArrowDown" && this.isOpen) {
      event.preventDefault()
      this.links[0]?.focus()
    } else if (event.key === "Escape") {
      this.close()
    }
  }

  // Keys pressed while a result has focus.
  navigate(event) {
    const links = this.links
    const index = links.indexOf(document.activeElement)
    if (event.key === "ArrowDown") {
      event.preventDefault()
      links[Math.min(index + 1, links.length - 1)]?.focus()
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      index <= 0 ? this.inputTarget.focus() : links[index - 1].focus()
    } else if (event.key === "Escape") {
      this.close()
      this.inputTarget.focus()
    }
  }

  // A click anywhere outside the search box closes the results.
  outside(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  open() {
    this.resultsTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")
  }

  close() {
    clearTimeout(this.timer)
    this.pending = false
    this.resultsTarget.hidden = true
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.statusTarget.textContent = ""
  }

  get isOpen() {
    return !this.resultsTarget.hidden
  }

  get links() {
    return Array.from(this.frameTarget.querySelectorAll("a"))
  }
}
