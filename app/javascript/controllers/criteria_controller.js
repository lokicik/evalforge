import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "template"]

  connect() {
    if (this.containerTarget.children.length === 0) {
      this.addRow()
    }
  }

  addRow(event) {
    if (event) event.preventDefault()

    const content = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, new Date().getTime())
    this.containerTarget.insertAdjacentHTML("beforeend", content)
  }

  removeRow(event) {
    event.preventDefault()
    
    const row = event.target.closest(".criterion-row")
    if (row) {
      row.remove()
    }
  }
}
