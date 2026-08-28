# One candidate row in the completion modal's assessment-findings picker: a
# resource already on the FHIR server that the referral target can return in
# Task.output:AdditionalContent.
#
# rffa.html: "Task.output: When closing the loop, this element carries the
# results of the assessment ... This may include Observation Screening
# Responses, Questionnaire Response, Observation Assessments, Conditions,
# CarePlan, Goal, and Procedures."
#
# This is a picker row, not a clinical model. It answers three questions a
# person needs answered before ticking a box: what kind of thing is this, what
# does it say, and which SDOH domain is it about. The resources themselves are
# rendered by whoever receives them.
class Finding
  # The kinds the picker groups by. A bare "Observation" badge on both "Marital
  # status" and "Inadequate oral food intake" says nothing; what separates them
  # is the profile, so the profile is what this reads.
  KINDS = {
    instrument: { label: "Completed instruments", badge: "bg-info text-dark", badge_label: "Instrument" },
    answer: { label: "Individual answers", badge: "bg-light text-dark border", badge_label: "Answer" },
    assessment: { label: "Assessment results", badge: "bg-primary", badge_label: "Assessment" },
    condition: { label: "Health concerns", badge: "bg-danger", badge_label: "Condition" },
    goal: { label: "Goals", badge: "bg-success", badge_label: "Goal" },
    other: { label: "Other", badge: "bg-secondary", badge_label: "Other" },
  }.freeze

  attr_reader :resource_type, :id, :kind, :label, :detail, :domains, :recorded_on,
              :parent_reference, :duplicate_count

  def self.build(fhir_resource, questionnaire_titles: {})
    return if fhir_resource.blank? || fhir_resource.id.blank?

    new(fhir_resource, questionnaire_titles: questionnaire_titles)
  end

  def initialize(fhir_resource, questionnaire_titles: {})
    @resource_type = fhir_resource.resourceType
    @id = fhir_resource.id
    @profiles = Array(fhir_resource.meta&.profile).map(&:to_s)
    @kind = read_kind(fhir_resource)
    @label = read_label(fhir_resource, questionnaire_titles)
    @detail = read_detail(fhir_resource)
    @domains = read_domains(fhir_resource)
    @recorded_on = read_recorded_on(fhir_resource)
    @parent_reference = fhir_resource.is_a?(FHIR::Observation) ? Array(fhir_resource.derivedFrom).first&.reference : nil
    @duplicate_count = 1
  end

  # The literal reference that goes into Task.output.valueReference. The picker
  # has to carry the resource type as well as the id: TaskIoEntry resolves an
  # output by the type in its reference, and reading an Observation as a
  # Procedure silently drops it.
  def reference
    "#{resource_type}/#{id}"
  end

  def badge_class
    KINDS.fetch(kind, KINDS[:other])[:badge]
  end

  def badge_label
    KINDS.fetch(kind, KINDS[:other])[:badge_label]
  end

  # Two rows a reader could not tell apart. Identical Goals are written into
  # this demo data eight at a time, and offering six rows with the same text,
  # domain and date is a defect whichever one gets ticked.
  #
  # The value is part of the key, so two answers to the same question on the
  # same day stay separate when the answers differ. Collapsing those would drop
  # a real finding rather than a duplicate.
  def duplicate_key
    [resource_type, kind, label, detail, domains.sort, recorded_on].join("|")
  end

  def merge_duplicate
    @duplicate_count += 1
    self
  end

  def duplicated?
    duplicate_count > 1
  end

  # Does this finding belong to the domain the referral was made for? Compared
  # by exact category code: see AssessmentFindings for why nothing is filtered
  # out on the strength of it.
  def in_domains?(category_codes)
    codes = Array(category_codes)
    codes.present? && domains.any? { |domain| codes.include?(domain) }
  end

  private

  def read_kind(fhir_resource)
    case fhir_resource
    when FHIR::QuestionnaireResponse then :instrument
    when FHIR::Condition then :condition
    when FHIR::Goal then :goal
    when FHIR::Observation
      return :assessment if @profiles.include?(FhirProfiles::OBSERVATION_ASSESSMENT)
      return :answer if @profiles.include?(FhirProfiles::OBSERVATION_SCREENING_RESPONSE)

      :other
    else
      :other
    end
  end

  # Each of these resources says what it is in a different element.
  def read_label(fhir_resource, questionnaire_titles)
    text =
      case fhir_resource
      when FHIR::Goal then codeable_text(fhir_resource.description)
      when FHIR::CarePlan then fhir_resource.title.presence || codeable_text(fhir_resource.category&.first)
      when FHIR::QuestionnaireResponse then questionnaire_label(fhir_resource, questionnaire_titles)
      when FHIR::Consent then codeable_text(Array(fhir_resource.category).first)
      when FHIR::DocumentReference then fhir_resource.description.presence || codeable_text(fhir_resource.type)
      else
        # Task.input:AdditionalContent is Reference(Resource) with no
        # targetProfile, so this now sees types the output slice never carried -
        # and FHIR::Consent has category, scope and provision but no code.
        codeable_text(fhir_resource.code) if fhir_resource.respond_to?(:code)
      end

    text.presence || reference
  end

  # "QuestionnaireResponse (2025-09-25)" is not something anyone can choose by.
  # The Questionnaire's own title is, and it comes back in the same search as
  # the responses via _include, so this is a lookup rather than a read.
  def questionnaire_label(fhir_resource, questionnaire_titles)
    canonical = fhir_resource.questionnaire.to_s
    questionnaire_titles[canonical.split("|").first].presence ||
      canonical.split("/").reject(&:blank?).last.to_s.sub(/\ASDOHCC-Questionnaire/, "").presence ||
      canonical.split("/").reject(&:blank?).last
  end

  # What the row says beyond its name: how much of an instrument was answered,
  # what an observation's value was, whether a goal is still being pursued.
  def read_detail(fhir_resource)
    case fhir_resource
    when FHIR::QuestionnaireResponse
      answered = count_answers(fhir_resource.item)
      answered.positive? ? "#{answered} #{"answer".pluralize(answered)}" : fhir_resource.status
    when FHIR::Observation then observation_value(fhir_resource)
    when FHIR::Condition then codeable_text(fhir_resource.clinicalStatus)
    when FHIR::Goal then fhir_resource.lifecycleStatus.presence || codeable_text(fhir_resource.achievementStatus)
    end
  end

  # QuestionnaireResponse.item nests: PRAPARE puts all 27 of its items inside a
  # single group item, and answers to a question can carry items of their own.
  # Counting only the top level reports "1 answer" for a fully completed PRAPARE.
  def count_answers(items)
    Array(items).sum do |item|
      answers = Array(item.answer)
      answered = answers.any? { |answer| answer_value?(answer) } ? 1 : 0
      answered + answers.sum { |answer| count_answers(answer.item) } + count_answers(item.item)
    end
  end

  # QuestionnaireResponse.item.answer.value[x]. Tested with nil? rather than
  # present?, because valueBoolean false and valueInteger 0 are answers.
  ANSWER_VALUE_FIELDS = %w[
    valueBoolean valueDecimal valueInteger valueDate valueDateTime valueTime
    valueString valueUri valueAttachment valueCoding valueQuantity valueReference
  ].freeze

  def answer_value?(answer)
    return false if answer.nil?

    ANSWER_VALUE_FIELDS.any? { |field| answer.respond_to?(field) && !answer.send(field).nil? }
  end

  def observation_value(fhir_resource)
    codeable_text(fhir_resource.valueCodeableConcept).presence ||
      fhir_resource.valueString.presence ||
      quantity_text(fhir_resource.valueQuantity) ||
      boolean_text(fhir_resource.valueBoolean) ||
      codeable_text(fhir_resource.dataAbsentReason)
  end

  # "Inadequate oral food intake for physiological needs — true" is not how
  # anyone reads an assessment result.
  def boolean_text(value)
    return if value.nil?

    value ? "yes" : "no"
  end

  def quantity_text(quantity)
    return if quantity.blank?

    [quantity.value, quantity.unit.presence || quantity.code].compact.join(" ").presence
  end

  # The SDOH domains this resource is filed under, from the SDOHCC category
  # codes only: the same element the referral's own domain is written in.
  def read_domains(fhir_resource)
    return [] unless fhir_resource.respond_to?(:category)

    Array(fhir_resource.category).flat_map { |category| Array(category&.coding) }
      .select { |coding| coding&.system == FhirProfiles::TEMPORARY_CODE_SYSTEM }
      .map(&:code)
      .compact
      .uniq
  end

  # Clinically meaningful dates first, because that is what the reader is
  # choosing by; meta.lastUpdated only when the resource carries nothing else.
  def read_recorded_on(fhir_resource)
    candidates =
      case fhir_resource
      when FHIR::QuestionnaireResponse then [fhir_resource.authored]
      when FHIR::Observation then [fhir_resource.effectiveDateTime, fhir_resource.issued]
      when FHIR::Condition then [fhir_resource.recordedDate, fhir_resource.onsetDateTime]
      when FHIR::CarePlan then [fhir_resource.created]
      when FHIR::Goal then [fhir_resource.statusDate]
      else []
      end
    candidates += [fhir_resource.meta&.lastUpdated]

    candidates.compact.each do |value|
      parsed = parse_date(value)
      return parsed if parsed
    end
    nil
  end

  def parse_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def codeable_text(codeable_concept)
    return if codeable_concept.blank?

    coding = Array(codeable_concept.coding).first
    codeable_concept.text.presence || coding&.display.presence || coding&.code
  end
end
