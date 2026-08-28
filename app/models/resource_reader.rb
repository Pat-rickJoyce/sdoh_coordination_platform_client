# A per-request identity map over FHIR reads.
#
# One dashboard load resolves, for every referral on the page, the focus
# ServiceRequest, the requester, the Patient, the Consent behind the
# ServiceRequest, and every reference in Task.input and Task.output. Those
# references overlap heavily: the same Patient, the same Consent and the same
# Organization belong to referral after referral, and resolving Task.input
# added a further read per attachment. Each one was its own sequential round
# trip, and a page of a dozen referrals read the same Consent a dozen times.
#
# A reference identifies a resource by "Type/id", so that is the key. The map is
# scoped to the request through Current, so accepting a referral and reloading
# still reads the new state rather than serving what the previous page saw.
#
# A read that returns nothing is remembered as nothing. A missing resource is
# missing for the whole of one page load, and retrying it once per referral is
# what made an unreachable reference cost the most.
class ResourceReader
  def self.read(fhir_client, fhir_class, resource_id)
    return if fhir_client.nil? || fhir_class.nil? || resource_id.blank?

    key = "#{fhir_class.name.split("::").last}/#{resource_id}"
    store = (Current.fhir_resources ||= {})
    return store[key] if store.key?(key)

    store[key] = fetch(fhir_client, fhir_class, resource_id)
  end

  def self.fetch(fhir_client, fhir_class, resource_id)
    Rails.logger.info("ResourceReader: fetching #{fhir_class.name.split("::").last}/#{resource_id}")
    fhir_resource = fhir_client.read(fhir_class, resource_id).resource
    # sometimes for some reason read returns FHIR::Bundle
    fhir_resource = fhir_resource&.entry&.first&.resource if fhir_resource.is_a?(FHIR::Bundle)
    fhir_resource
  end
  private_class_method :fetch
end
