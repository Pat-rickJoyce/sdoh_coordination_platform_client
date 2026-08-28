# One entry of Task.input or Task.output.
#
# SDOHCC-TaskForReferralManagement slices Task.output on both Task.output.type
# and the type of Task.output.value[x], and slices Task.input on
# Task.input.type. Both slicings are open and every slice is 0..*, so one
# completed referral can carry a Procedure reference, a procedure code and any
# number of additional-content references at the same time. Reading only the
# first entry, or assuming a reference points at a Procedure, loses data.
#
# This wraps a single entry: which slice it belongs to, the referenced resource
# or literal value it carries, and enough type information for a view to render
# it without going back to the server.
class TaskIoEntry
  attr_reader :slice, :type_code, :type_display, :value_kind, :reference,
              :resource_type, :resource_id, :resource, :value

  def self.build(fhir_entry, fhir_client = nil)
    return if fhir_entry.nil?

    new(fhir_entry, fhir_client)
  end

  # Splits "Procedure/123", an absolute URL or a versioned reference into its
  # resource type and id. Contained ("#p1") and urn: references have no type and
  # yield [nil, nil], as does anything that does not look like a resource type.
  def self.parse_reference(reference)
    return [nil, nil] if reference.blank?

    path = reference.to_s.split("?").first.to_s
    return [nil, nil] if path.start_with?("#", "urn:")

    segments = path.split("/").reject(&:blank?)
    history_at = segments.index("_history")
    segments = segments[0...history_at] if history_at
    type = segments[-2]
    id = segments[-1]
    return [nil, nil] unless type.to_s.match?(/\A[A-Z][A-Za-z]+\z/)

    [type, id]
  end

  def initialize(fhir_entry, fhir_client = nil)
    @type_code = read_type_code(fhir_entry.type)
    @type_display = read_type_display(fhir_entry.type)
    @value_kind = read_value_kind(fhir_entry)
    @reference = fhir_entry.valueReference&.reference
    @resource_type, @resource_id = self.class.parse_reference(@reference)
    @slice = read_slice
    @value = read_value(fhir_entry)
    @resource = resolve(fhir_client)
  end

  # PerformedActivityReference and PerformedActivityCode both sit under the
  # resulting-activity code; either one describes what was actually done.
  def performed_activity?
    slice == :performed_activity_reference || slice == :performed_activity_code
  end

  def additional_content?
    slice == :additional_content
  end

  def reference?
    value_kind == :reference
  end

  def resolved?
    resource.present?
  end

  # What a view labels this entry with: the referenced resource's type where
  # there is one, otherwise the slice's own display.
  def display_type
    case value_kind
    when :reference then resource_type.presence || type_display
    when :markdown then "markdown"
    else type_display
    end
  end

  def id
    resource&.id || resource_id
  end

  # What the referenced resource actually says, for a table cell that would
  # otherwise read "Additional Content (QuestionnaireResponse)". A completed
  # assessment comes back as several resources at once, and the reader needs to
  # tell a food insecurity Condition from a PRAPARE response without opening
  # each modal in turn.
  def resource_label
    fhir_resource = resource&.fhir_resource
    return if fhir_resource.nil?

    text =
      case fhir_resource
      when FHIR::Goal then codeable_display(fhir_resource.description)
      when FHIR::CarePlan then fhir_resource.title.presence || codeable_display(fhir_resource.category&.first)
      when FHIR::QuestionnaireResponse then questionnaire_display(fhir_resource)
      when FHIR::Consent then codeable_display(Array(fhir_resource.category).first)
      when FHIR::DocumentReference then fhir_resource.description.presence || codeable_display(fhir_resource.type)
      else
        # Task.input:AdditionalContent.value[x] is Reference(Resource) with no
        # targetProfile, so anything can arrive here and not every resource type
        # has a code element - FHIR::Consent has category, scope and provision
        # and no code at all. Label what can be labelled; the rest falls back to
        # the resource type in the caller.
        codeable_display(fhir_resource.code) if fhir_resource.respond_to?(:code)
      end

    text.presence
  end

  private

  def codeable_display(codeable_concept)
    return if codeable_concept.blank?

    coding = Array(codeable_concept.coding).first
    codeable_concept.text.presence || coding&.display.presence || coding&.code
  end

  # QuestionnaireResponse.questionnaire is a canonical URL. Resolving it would
  # be one more read per outcome on a table that already reads every referenced
  # resource, so the last segment is spaced out instead:
  # ".../SDOHCC-QuestionnairePRAPARE" reads as "Questionnaire PRAPARE".
  def questionnaire_display(fhir_resource)
    segment = fhir_resource.questionnaire.to_s.split("|").first.to_s.split("/").reject(&:blank?).last
    return if segment.blank?

    segment.sub(/\ASDOHCC-/, "").gsub(/([a-z])([A-Z])/, '\1 \2')
  end

  # The temporary-codes coding is the one the profile discriminates on; fall
  # back to the first coding so an off-spec entry still describes itself.
  def read_type_code(type)
    codings = Array(type&.coding)
    coding = codings.find { |c| c&.system == FhirProfiles::TEMPORARY_CODE_SYSTEM } || codings.first
    coding&.code
  end

  def read_type_display(type)
    return if type_code.blank?

    type_code.titleize
  end

  def read_value_kind(fhir_entry)
    return :reference if fhir_entry.valueReference&.reference.present?
    return :codeable_concept if fhir_entry.valueCodeableConcept.present?
    return :markdown if fhir_entry.valueMarkdown.present?
    return :string if fhir_entry.valueString.present?

    :other
  end

  def read_slice
    case type_code
    when FhirProfiles::RESULTING_ACTIVITY_CODE
      case value_kind
      when :reference then :performed_activity_reference
      when :codeable_concept then :performed_activity_code
      else :unknown
      end
    when FhirProfiles::ADDITIONAL_CONTENT_CODE
      :additional_content
    else
      :unknown
    end
  end

  # The value, not the name of the slice it arrived in.
  def read_value(fhir_entry)
    case value_kind
    when :codeable_concept
      coding = fhir_entry.valueCodeableConcept&.coding&.first
      coding&.display.presence || coding&.code&.titleize
    when :markdown
      fhir_entry.valueMarkdown
    when :string
      fhir_entry.valueString
    end
  end

  # Resolved by the resource type in the reference itself. Assuming Procedure
  # fetched an Observation as a Procedure and silently dropped it.
  def resolve(fhir_client)
    return if fhir_client.nil? || resource_type.blank? || resource_id.blank?

    fhir_resource = read_fhir_resource(fhir_client)
    return if fhir_resource.nil?

    wrap(fhir_resource)
  rescue => e
    Rails.logger.warn("Unable to resolve Task #{type_code} entry #{reference}: #{e.message}")
    nil
  end

  def read_fhir_resource(fhir_client)
    fhir_class = fhir_class_for(resource_type)
    if fhir_class.nil?
      Rails.logger.info("Task #{type_code} entry references unknown resource type #{resource_type}")
      return
    end

    Rails.logger.info("Task #{type_code} entry: reading #{resource_type}/#{resource_id}")
    fhir_resource = ResourceReader.read(fhir_client, fhir_class, resource_id)
    fhir_resource if fhir_resource.is_a?(fhir_class)
  end

  def fhir_class_for(type)
    return unless FHIR.const_defined?(type, false)

    fhir_class = FHIR.const_get(type, false)
    fhir_class if fhir_class.is_a?(Class) && fhir_class <= FHIR::Model
  end

  # This client models Procedure, Observation and QuestionnaireResponse, the
  # three resources its tables and the referral drawer render. Goal, Condition
  # and CarePlan additional content still resolve, as raw FHIR, rather than
  # being dropped.
  def wrap(fhir_resource)
    case resource_type
    when "Procedure" then Procedure.new(fhir_resource)
    when "Observation" then Observation.new(fhir_resource)
    when "QuestionnaireResponse" then QuestionnaireResponse.new(fhir_resource)
    else GenericResource.new(fhir_resource)
    end
  end

  # A referenced resource this client has no model for: enough for a view to
  # link to it and for shared/_fhir_resource_modal to render it.
  class GenericResource
    include ModelHelper

    attr_reader :id, :resource_type, :fhir_resource

    def initialize(fhir_resource)
      @fhir_resource = fhir_resource
      remove_client_instances(@fhir_resource)
      @id = fhir_resource.id
      @resource_type = fhir_resource.resourceType
    end

    def resourceType
      resource_type
    end
  end
end
