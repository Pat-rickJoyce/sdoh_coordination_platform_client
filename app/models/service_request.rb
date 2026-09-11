class ServiceRequest
  include ModelHelper

  attr_reader :id, :status, :category, :description, :performer_name, :performer_reference, :priority, :fhir_resource

  def initialize(fhir_service_request)
    @id = fhir_service_request.id
    @fhir_resource = fhir_service_request
    remove_client_instances(@fhir_resource)
    @status = fhir_service_request.status
    @category = read_category(fhir_service_request.category)
    @description = read_codeable_concept(fhir_service_request.code)
    @performer_name = fhir_service_request.performer&.first&.display
    @performer_reference = fhir_service_request.performer&.first&.reference
    @priority = fhir_service_request.priority
  end

  # The SDOH domain code (e.g. food-insecurity, housing-instability) used to
  # scope a HealthcareService capacity query via the service-category search
  # parameter. Returns nil when the ServiceRequest carries no SDOHCC category,
  # in which case the capacity query falls back to all of the CBO's services.
  def sdoh_category_code
    codings = fhir_resource&.category&.flat_map { |c| c.coding || [] } || []
    coding = codings.find { |c| c.system.to_s.downcase.include?("sdoh") } ||
             codings.find { |c| SDOH_DOMAIN_CODES.include?(c.code) }
    coding&.code
  end

  private

  SDOH_DOMAIN_CODES = %w[
    food-insecurity
    housing-instability
    homelessness
    inadequate-housing
    transportation-insecurity
    financial-insecurity
    material-hardship
    educational-attainment
    employment-status
    veteran-status
    stress
    social-connection
    intimate-partner-violence
    elder-abuse
    health-insurance-coverage-status
    utility-insecurity
    sdoh-category-unspecified
  ].freeze

  def read_category(category)
    category&.map { |c| read_codeable_concept(c) }&.join(", ")
  end

  def read_codeable_concept(codeable_concept)
    c = codeable_concept&.coding&.first
    c&.display || c&.code&.gsub("-", " ")&.titleize
  end
end
