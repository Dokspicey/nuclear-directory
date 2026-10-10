import { Controller } from "@hotwired/stimulus"

// "Select all" for the review queue's bulk approve (#86). The checkbox ticks
// or clears every item, and shows a mixed state when only some are ticked.
// The count next to the bulk button says how many are selected.
export default class extends Controller {
  static targets = ["all", "item", "count"]

  connect() {
    this.refresh()
  }

  toggle() {
    this.itemTargets.forEach((item) => { item.checked = this.allTarget.checked })
    this.refresh()
  }

  refresh() {
    const selected = this.itemTargets.filter((item) => item.checked).length
    this.allTarget.checked = selected > 0 && selected === this.itemTargets.length
    this.allTarget.indeterminate = selected > 0 && selected < this.itemTargets.length
    if (this.hasCountTarget) this.countTarget.textContent = `${selected} selected`
  }
}
