class ServiceRequest
  include ModelHelper

  attr_reader :id, :status, :category, :sdoh_category_codes, :description,
              :performer_name, :performer_reference, :priority, :fhir_resource

  def initialize(fhir_service_request)
    @id = fhir_service_request.id
    @fhir_resource = fhir_service_request
    remove_client_instances(@fhir_resource)
    @status = fhir_service_request.status
    @category = read_category(fhir_service_request.category)
    @sdoh_category_codes = read_sdoh_category_codes(fhir_service_request.category)
    @description = read_codeable_concept(fhir_service_request.code)
    @performer_name = fhir_service_request.performer&.first&.display
    @performer_reference = fhir_service_request.performer&.first&.reference
    @priority = fhir_service_request.priority
  end

  private

  def read_category(category)
    category&.map { |c| read_codeable_concept(c) }&.join(", ")
  end

  # The SDOH domain(s) this referral was made for, as codes rather than display
  # text: category[SDOHCC] is bound to SDOHCC-ValueSetSDOHCategory, and the same
  # element on a Condition, Goal or Observation is what says whether a finding is
  # about the same domain.
  def read_sdoh_category_codes(category)
    Array(category).flat_map { |c| Array(c&.coding) }
      .select { |coding| coding&.system == FhirProfiles::TEMPORARY_CODE_SYSTEM }
      .map(&:code)
      .compact
      .uniq
  end

  def read_codeable_concept(codeable_concept)
    c = codeable_concept&.coding&.first
    c&.display || c&.code&.gsub("-", " ")&.titleize
  end
end
