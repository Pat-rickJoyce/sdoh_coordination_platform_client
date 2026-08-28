# What a referral target reads before deciding whether to accept a referral.
#
# A content-rich referral carries whatever the referral source chose to send in
# Task.input:AdditionalContent, and value[x] is Reference(Resource) with no
# targetProfile, so what arrives is arbitrary. This turns that into the sections
# a referral intake screen actually has: the problem list, the screening behind
# it, what a provider assessed, and what the patient is working towards.
#
# The grouping is ClinicalContent's, shared with OutcomeDetail. What belongs to
# this class is only what is particular to an incoming referral.
class ReferralDetail
  include ClinicalContent

  attr_reader :task

  def initialize(task)
    @task = task
    @rows = build_rows
  end

  # Consent is reported in the referral block as an attribute of the referral,
  # not as clinical content, so it is not listed again here.
  def supplemental
    super.reject { |row| row[:fhir].is_a?(FHIR::Consent) }
  end

  private

  def content_entries
    Array(task.additional_content_inputs)
  end

  def domain_codes
    Array(task.focus&.sdoh_category_codes)
  end
end
