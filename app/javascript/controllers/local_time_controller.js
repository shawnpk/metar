import { Controller } from "@hotwired/stimulus"

// Replaces the element's text with the UTC datetime formatted in the browser's local timezone.
export default class extends Controller {
  connect() {
    const utc = this.element.dateTime
    if (!utc) return

    const date = new Date(utc)
    if (isNaN(date)) return

    this.element.textContent = new Intl.DateTimeFormat(undefined, {
      hour: "numeric",
      minute: "2-digit",
      timeZoneName: "short",
      month: "short",
      day: "numeric",
    }).format(date)
  }
}
