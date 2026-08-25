class Procedure
  include ModelHelper

  attr_reader :id, :status, :category, :description, :performed_date, :problem, :fhir_resource

  def initialize(fhir_procedure)
    @id = fhir_procedure.id
    @fhir_resource = fhir_procedure
    remove_client_instances(@fhir_resource)
    @status = fhir_procedure.status
    @category = read_codeable_concept(fhir_procedure.category)
    @description = read_codeable_concept(fhir_procedure.code)
    @performed_date = fhir_procedure.performedDateTime
    @problem = read_reference(fhir_procedure.reasonReference&.first)
  end

  private

  def read_codeable_concept(codeable_concept)
    display = codeable_concept&.coding&.map(&:display)&.join(", ")
    display || codeable_concept&.coding&.map(&:code)&.join(", ")&.gsub("-", " ")&.titleize
  end

  # Procedure.reasonReference is 0..*, and a referral made with no problem
  # recorded produces a Procedure with none. Reading .reference off nil raised,
  # TaskIoEntry's rescue turned that into an unresolved output, and the Outcomes
  # cell fell back to a bare "Resulting Activity" with nothing behind it.
  def read_reference(reference)
    reference&.reference
    # id = reference.reference.split("/").last
    # condition = FHIR::Condition.read(id)
    # # sometimes for some reason read returns FHIR::Bundle
    # condition = condition&.resource&.entry&.first&.resource if condition.is_a?(FHIR::Bundle)
    # Condition.new(condition) if condition
  end
end
