class Observation
  include ModelHelper

  attr_reader :id, :code, :category, :value, :effective_date_time, :note, :fhir_resource

  def initialize(fhir_observation)
    @id = fhir_observation.id
    @fhir_resource = fhir_observation
    remove_client_instances(@fhir_resource)
    @code = get_code_string(fhir_observation.code)
    @category = get_category_display(fhir_observation.category)
    @category_codes = get_category_codes(fhir_observation.category)
    @value = get_code_string(fhir_observation.valueCodeableConcept) if fhir_observation.valueCodeableConcept.present?
    @value_coding = fhir_observation.valueCodeableConcept&.coding&.first
    @effective_date_time = fhir_observation.effectiveDateTime
    @note = fhir_observation.note&.map { |note| note&.text }&.compact&.join(" ").presence
  end

  # An SDOHCC Observation Program Enrollment Status: the profile fixes
  # category[enrollment] to program-enrollment, so that is what marks one out
  # from any other Observation a Task.output entry may reference.
  def program_enrollment?
    @category_codes.include?(FhirProfiles::PROGRAM_ENROLLMENT_CATEGORY_CODE)
  end

  # Observation.value[x] as a code from SDOHCC-ValueSetEnrollmentStatus:
  # enrolled, not-enrolled or not-enrolled-on-waitlist. The code, not the
  # display, is what a badge colour is chosen from.
  def enrollment_status_code
    @value_coding&.code
  end

  def enrollment_status_display
    @value_coding&.display.presence || @value_coding&.code&.tr("-", " ")&.titleize
  end

  private

  def get_category_codes(category)
    Array(category).flat_map { |c| Array(c&.coding) }.map { |coding| coding&.code }.compact
  end

  def get_code_string(code)
    c = code&.coding&.first
    c&.display ? "#{c.display} (#{c.code})" : c.code
  end

  def get_category_display(category)
    category&.map(&:coding)&.flatten&.map do |c|
      c&.display || c&.code&.gsub("-", " ")&.titleize
    end&.join("/ ")
  end
end
