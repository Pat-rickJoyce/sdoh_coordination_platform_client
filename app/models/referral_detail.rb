# What a referral target reads before deciding whether to accept a referral.
#
# A content-rich referral carries whatever the referral source chose to send in
# Task.input:AdditionalContent, and value[x] is Reference(Resource) with no
# targetProfile, so what arrives is arbitrary. This turns that into the sections
# a referral intake screen actually has: the problem list, the screening behind
# it, what a provider assessed, and what the patient is working towards.
#
# Classification is Finding\'s rather than a new taxonomy - decided by profile
# rather than resource type, so a screening answer and an assessment result are
# never both just "Observation".
class ReferralDetail
  attr_reader :task

  def initialize(task)
    @task = task
    @rows = build_rows
  end

  def any?
    @rows.present?
  end

  def concerns
    of_kind(:condition).map do |row|
      resource = row[:fhir]
      {
        row: row,
        name: row[:finding].label,
        status: [clinical_status(resource), verification_status(resource)].compact_blank.join(", "),
        onset: date_of(onset_value(resource)),
        asserter: resource.asserter&.display,
        evidence: evidence_for(resource),
      }
    end
  end

  # Completed instruments carry their own answers; individual screening-response
  # Observations that arrived on their own are listed beside them.
  def screenings
    instruments = of_kind(:instrument).map do |row|
      { row: row, name: row[:finding].label, date: row[:finding].recorded_on,
        source: "patient-reported", answers: answers_of(row[:resource]) }
    end
    loose = of_kind(:answer)
    return instruments if loose.blank?

    instruments + [{ row: loose.first, name: "Individual screening responses", date: nil, source: nil,
                     answers: loose.map { |row| { text: row[:finding].label, value: row[:finding].detail } } }]
  end

  # Grouped by who assessed, which is the distinction between an assessment and
  # a screening answer in the first place.
  def assessments
    of_kind(:assessment).group_by { |row| row[:fhir].performer&.first&.display }.map do |performer, rows|
      { rows: rows, performer: performer.presence || "Assessed", date: rows.first[:finding].recorded_on,
        findings: rows.map { |row| { name: row[:finding].label, value: row[:finding].detail } } }
    end
  end

  def goals
    of_kind(:goal).map do |row|
      resource = row[:fhir]
      target = Array(resource.target).first
      {
        row: row,
        name: row[:finding].label,
        status: [resource.lifecycleStatus, codeable(resource.achievementStatus)].compact_blank.join(", "),
        due: date_of(target&.dueDate),
        updated: date_of(resource.statusDate),
        target: [codeable(target&.measure), codeable(target&.detailCodeableConcept)].compact_blank.join(": ").presence,
      }
    end
  end

  # Consent is reported in the referral block as an attribute of the referral,
  # not as clinical content, so it is not listed again here.
  def supplemental
    of_kind(:other).reject { |row| row[:fhir].is_a?(FHIR::Consent) }
  end

  # Everything that arrived, for the technical row at the foot of the drawer.
  def attachments
    @rows
  end

  def unresolved
    Array(task.additional_content_inputs).reject(&:resolved?)
  end

  private

  def of_kind(kind)
    @rows.select { |row| row[:finding].kind == kind }
  end

  def build_rows
    Array(task.additional_content_inputs).select(&:resolved?).filter_map do |entry|
      fhir_resource = entry.resource&.fhir_resource
      finding = Finding.build(fhir_resource)
      next if finding.nil?

      { entry: entry, finding: finding, resource: entry.resource, fhir: fhir_resource }
    end.sort_by.with_index { |row, index| [row[:finding].in_domains?(domain_codes) ? 0 : 1, index] }
  end

  def domain_codes
    Array(task.focus&.sdoh_category_codes)
  end

  # PRAPARE asks race, ethnicity and Hispanic origin. They are part of the
  # instrument, but they are not why anyone was referred, and leading a food
  # referral with a person\'s race is not something a reviewer should be shown by
  # default. Everything else the instrument asked is kept.
  DEMOGRAPHIC_ITEM = /\A\s*(race|ethnicity|hispanic or latino)\b/i.freeze

  def answers_of(resource)
    return [] unless resource.respond_to?(:sections)

    Array(resource.sections)
      .flat_map { |section| Array(section[:answers]) }
      .reject { |answer| answer[:text].to_s.match?(DEMOGRAPHIC_ITEM) }
  end

  # SDOHCC-Condition models a screening Observation as evidence for the concern.
  # Shown only when that Observation also came with the referral, so reading the
  # problem list costs no extra server round trips.
  def evidence_for(resource)
    references = Array(resource.evidence).flat_map { |evidence| Array(evidence.detail) }.map(&:reference).compact
    return if references.blank?

    @rows.find { |row| references.any? { |reference| reference.to_s.end_with?("/#{row[:finding].id}") } }
  end

  def clinical_status(resource)
    codeable(resource.clinicalStatus)&.titleize
  end

  def verification_status(resource)
    codeable(resource.verificationStatus)&.downcase
  end

  def onset_value(resource)
    resource.onsetDateTime.presence || resource.onsetPeriod&.start.presence || resource.recordedDate.presence
  end

  def codeable(codeable_concept)
    return if codeable_concept.blank?

    coding = Array(codeable_concept.coding).first
    codeable_concept.text.presence || coding&.display.presence || coding&.code
  end

  def date_of(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
