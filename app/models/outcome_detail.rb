# What a referral source reads when a referral comes back.
#
# Task.output carries two different things under one element.
# output[PerformedActivityReference] and output[PerformedActivityCode] say what
# was actually done; output[AdditionalContent] carries the clinical content the
# referral target chose to return.
#
# The two slices are not interchangeable. Unlike the input slice, which is
# Reference(Resource) with no targetProfile, output[AdditionalContent] is closed
# to seven profiles - enrollment status, assessment, screening response, Goal,
# Condition, QuestionnaireResponse and CarePlan - and there is nothing on the
# input side that corresponds to the performed activity at all.
#
# The clinical content is grouped exactly as it is on the way in, through
# ClinicalContent. What this adds is the activity itself, which leads, because
# what was done is the first thing anyone reading a closed referral wants.
class OutcomeDetail
  include ClinicalContent

  attr_reader :task

  def initialize(task)
    @task = task
    @rows = build_rows
  end

  # A referral can close with an activity and no content, or with content and no
  # activity, and either is worth opening.
  def any?
    super || performed_activities.present?
  end

  # What was done. A reference resolves to a Procedure; a bare CodeableConcept is
  # the same statement with no resource behind it, and says so rather than being
  # dropped - both slices sit under the resulting-activity code and either one
  # answers the question.
  def performed_activities
    @performed_activities ||= Array(task.performed_activity_outputs).map do |entry|
      procedure = entry.resource if entry.resource.is_a?(Procedure)
      {
        entry: entry,
        resource: entry.resource,
        name: activity_name(entry, procedure),
        status: procedure&.status,
        date: date_of(procedure&.performed_date),
        coded_only: !entry.reference?,
      }
    end
  end

  private

  def activity_name(entry, procedure)
    procedure&.description.presence ||
      entry.resource_label.presence ||
      entry.value.presence ||
      entry.display_type
  end

  def content_entries
    Array(task.additional_content_outputs)
  end

  # The domain the referral was made for, so a returned finding about that
  # domain sorts above one about something else. Read from the referral, not the
  # outcome: it is the same question either way.
  def domain_codes
    Array(task.focus&.sdoh_category_codes)
  end
end
