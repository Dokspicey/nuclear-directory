import { Controller } from "@hotwired/stimulus"

// Submits its form when a filter changes, so the list updates without an
// extra click. Without JavaScript the form's own button does the same.
export default class extends Controller {
  static targets = ["button"]

  connect() {
    this.buttonTargets.forEach((button) => button.hidden = true)
  }

  submit() {
    this.element.requestSubmit()
  }
}
