// app/javascript/controllers/request_action_controller.js
//
// Drives the "Accept / Reject Task" modal on the CP dashboard.
//
// Replaces the previous inline <script> in _request_action_modal.html.erb. That
// script used document.querySelector, so with several modals rendered on the
// page it always toggled the FIRST matching container rather than the one in
// the open modal. Everything here is scoped to this.element.
//
// Capacity behaviour (CFRID-963, SDOHCC IG Direct Capacity Status Inquiry):
// when the coordinator sets Status = accepted we prefetch each CBO's capacity
// and label the dropdown options, so a CBO with capacity can be picked on the
// first try instead of by trial and error. Selecting a CBO then shows a badge
// and gates submission.
import { Controller } from "@hotwired/stimulus";
import { STATUSES, UNKNOWN, BADGE_CLASSES, fetchCapacity } from "./capacity_controller";

export default class extends Controller {
  static targets = [
    "statusSelect",
    "cboContainer",
    "cboSelect",
    "statusReasonContainer",
    "capacityBadge",
    "blockedAlert",
    "waitlistAlert",
    "submitButton",
  ];

  static values = { category: String };

  connect() {
    // orgId -> capacity string, populated by prefetchCapacities().
    this.capacities = {};
    this.capacitiesLoaded = false;
    this.resetCapacityUi();
  }

  // --- status dropdown -----------------------------------------------------

  statusChanged() {
    const status = this.statusSelectTarget.value;

    this.toggle(this.cboContainerTarget, status === "accepted");
    this.toggle(this.statusReasonContainerTarget, status === "rejected");

    if (status === "accepted") {
      this.prefetchCapacities();
    } else {
      // Leaving the accept path clears any capacity gating so a reject or a
      // plain status update is never blocked by a stale badge.
      this.resetCapacityUi();
      this.submitButtonTarget.disabled = false;
    }
  }

  // --- capacity ------------------------------------------------------------

  // One Direct Capacity Status Inquiry per CBO, issued once per modal. This is
  // the IG's repeated one-to-one query, not the out-of-scope bulk/broadcast
  // model: each CBO is queried individually and the coordinator still chooses.
  async prefetchCapacities() {
    if (this.capacitiesLoaded || !this.hasCboSelectTarget) return;
    this.capacitiesLoaded = true;

    const options = Array.from(this.cboSelectTarget.options).filter((o) => o.value);
    if (options.length === 0) return;

    // Never imply availability while a check is in flight.
    options.forEach((option) => {
      option.dataset.baseLabel = option.dataset.baseLabel || option.textContent;
      option.textContent = `${option.dataset.baseLabel} — Checking…`;
    });

    await Promise.all(
      options.map(async (option) => {
        const capacity = await fetchCapacity(option.value, this.categoryValue);
        this.capacities[option.value] = capacity;
        const status = STATUSES[capacity] || UNKNOWN;
        option.textContent = `${option.dataset.baseLabel} — ${status.text}`;
      })
    );

    // A CBO may already have been selected while the checks were running.
    this.cboChanged();
  }

  cboChanged() {
    const orgId = this.hasCboSelectTarget ? this.cboSelectTarget.value : "";

    this.resetCapacityUi();
    this.submitButtonTarget.disabled = false;
    if (!orgId) return;

    const capacity = this.capacities[orgId] || "unknown";
    const status = STATUSES[capacity] || UNKNOWN;

    this.capacityBadgeTarget.textContent = status.text;
    this.capacityBadgeTarget.classList.remove("d-none");
    this.capacityBadgeTarget.classList.add(status.cls);

    if (capacity === "at-capacity") {
      // IG: no capacity - do not forward the referral to this CBO.
      this.blockedAlertTarget.classList.remove("d-none");
      this.submitButtonTarget.disabled = true;
    } else if (capacity === "has-waitlist") {
      // IG: the CP "may forward the referral ... or repeat Steps 2 and 3 with
      // other CBOs" - a coordinator decision, so prompt rather than block.
      this.waitlistAlertTarget.classList.remove("d-none");
      this.submitButtonTarget.disabled = true;
    }
    // assessment-required and available are informational; unknown fails
    // closed to a grey badge but does not block, matching the EHR client.
  }

  proceedWaitlist() {
    this.waitlistAlertTarget.classList.add("d-none");
    this.submitButtonTarget.disabled = false;
  }

  cancelWaitlist() {
    this.waitlistAlertTarget.classList.add("d-none");
    if (this.hasCboSelectTarget) this.cboSelectTarget.value = "";
    this.resetCapacityUi();
    this.submitButtonTarget.disabled = false;
  }

  // --- helpers -------------------------------------------------------------

  resetCapacityUi() {
    if (this.hasCapacityBadgeTarget) {
      this.capacityBadgeTarget.textContent = "";
      this.capacityBadgeTarget.classList.add("d-none");
      this.capacityBadgeTarget.classList.remove(...BADGE_CLASSES);
    }
    if (this.hasBlockedAlertTarget) this.blockedAlertTarget.classList.add("d-none");
    if (this.hasWaitlistAlertTarget) this.waitlistAlertTarget.classList.add("d-none");
  }

  toggle(element, visible) {
    element.style.display = visible ? "block" : "none";
  }
}
