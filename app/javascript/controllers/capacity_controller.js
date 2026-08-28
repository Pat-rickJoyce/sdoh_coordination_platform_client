// app/javascript/controllers/capacity_controller.js
//
// Capacity column on the CBO Organizations tab. One badge per CBO row, filled
// in on demand by the row's "Check Capacity" button.
import { Controller } from "@hotwired/stimulus";

// Fail closed: anything not explicitly recognized reads as Unknown, never as
// Available.
export const UNKNOWN = { text: "Unknown", cls: "bg-secondary" };

export const STATUSES = {
  "available": { text: "Available", cls: "bg-success" },
  "at-capacity": { text: "At Capacity", cls: "bg-danger" },
  "has-waitlist": { text: "Has Waitlist", cls: "bg-warning" },
  "assessment-required": { text: "Assessment Required", cls: "bg-info" },
  "unknown": UNKNOWN,
};

export const BADGE_CLASSES = [
  "bg-success",
  "bg-danger",
  "bg-warning",
  "bg-info",
  "bg-secondary",
];

export async function fetchCapacity(orgId, category) {
  const url = category
    ? `/organizations/${orgId}/check_capacity?category=${encodeURIComponent(category)}`
    : `/organizations/${orgId}/check_capacity`;

  try {
    const response = await fetch(url);
    if (!response.ok) return "unknown";
    const data = await response.json();
    return data.capacity || "unknown";
  } catch (err) {
    console.error("Capacity check failed", err);
    return "unknown";
  }
}

export default class extends Controller {
  static targets = ["badge"];

  async check(e) {
    const orgId = e.currentTarget.dataset.orgId;
    if (!orgId) return;

    const badge = this.badgeTargets.find((b) => b.dataset.orgId === orgId);
    if (!badge) return;

    badge.textContent = "Checking…";
    badge.classList.remove(...BADGE_CLASSES);

    const capacity = await fetchCapacity(orgId, e.currentTarget.dataset.category);
    const status = STATUSES[capacity] || UNKNOWN;

    badge.textContent = status.text;
    badge.classList.add(status.cls);
  }
}
