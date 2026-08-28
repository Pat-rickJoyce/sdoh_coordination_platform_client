# Per-request state, reset by the Rails executor at the end of every request.
#
# Only the FHIR identity map lives here. Nothing that outlives a page load
# belongs in it: a referral accepted on one request must be read fresh on the
# next.
class Current < ActiveSupport::CurrentAttributes
  attribute :fhir_resources
end
