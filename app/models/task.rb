class Task
  include ModelHelper

  attr_reader :id, :status, :focus, :owner_reference, :owner_name, :requester_name,
              :requester_resource, :patient_name, :patient_resource, :outputs, :inputs,
              :consent, :authored_on, :status_reason, :fhir_resource

  def initialize(fhir_task, cp_client)
    @id = fhir_task.id
    @fhir_resource = fhir_task
    @status = fhir_task.status
    sr_resource = get_fhir_resource(FHIR::ServiceRequest, fhir_task.focus, cp_client) if fhir_task.focus.present?
    @focus = ServiceRequest.new(sr_resource) if sr_resource.present?
    @owner_reference = fhir_task.owner&.reference
    @owner_name = fhir_task.owner&.display
    @requester_name = fhir_task.requester&.display
    @requester_resource =
      fhir_task.requester&.reference&.include?("Organization") ?
        get_fhir_resource(FHIR::Organization, fhir_task.requester, cp_client) :
        get_fhir_resource(FHIR::PractitionerRole, fhir_task.requester, cp_client)
    remove_client_instances(@requester_resource)
    @outputs = build_io_entries(fhir_task.output, cp_client)
    # Inputs are parsed but their references are deliberately not resolved: no
    # view renders Task.input yet, and resolving one would cost a server read
    # per entry on every dashboard refresh. Pass the client here when one does.
    @inputs = build_io_entries(fhir_task.input, nil)
    @consent = get_consent(@focus&.fhir_resource, cp_client)
    @authored_on = fhir_task.authoredOn&.to_date
    @status_reason = fhir_task.statusReason&.text
    @patient_name = fhir_task.for&.display
    @patient_resource = get_fhir_resource(FHIR::Patient, fhir_task.for, cp_client)
    remove_client_instances(@patient_resource)
  end

  # Task.output entries under the resulting-activity code: what was done.
  def performed_activity_outputs
    outputs.select(&:performed_activity?)
  end

  # Task.output entries under the additional-content code: enrollment status,
  # assessments, goals, conditions and the like.
  def additional_content_outputs
    outputs.select(&:additional_content?)
  end

  # Task.input entries under the additional-content code.
  def additional_content_inputs
    inputs.select(&:additional_content?)
  end

  # The Enrollment Status Observation the CBO closed the referral with, if there
  # is one.
  #
  # enrollment.html, referral-triggered workflow: the CBO points at the
  # Enrollment Status Observation from Task.output, and the coordination
  # platform is the Intermediary that carries it up to the EHR-facing Task. The
  # reference arrives in the AdditionalContent slice, which is shared with
  # assessments, goals and conditions, so the Observation's own category is what
  # identifies it.
  def enrollment_status
    additional_content_outputs
      .map(&:resource)
      .compact
      .find { |resource| resource.is_a?(Observation) && resource.program_enrollment? }
  end

  # The first resulting-activity output. Kept so callers written against the
  # single-outcome API keep working while they move to #outputs.
  def outcome
    performed_activity_outputs.first&.then { |entry| entry.resource || entry.value }
  end

  def outcome_type
    performed_activity_outputs.first&.type_display
  end

  private

  def build_io_entries(entries, cp_client)
    Array(entries).filter_map { |entry| TaskIoEntry.build(entry, cp_client) }
  end

  def get_consent(focus, cp_client)
    consent_ref = focus&.supportingInfo&.first
    fhir_consent = get_fhir_resource(FHIR::Consent, consent_ref, cp_client)
    Consent.new(fhir_consent) if fhir_consent
  end

  def get_fhir_resource(fhir_class, ref, cp_client)
    resource_id = ref&.reference_id
    return if resource_id.blank?

    fhir_resource = cp_client.read(fhir_class, resource_id).resource
    # sometimes for some reason read returns FHIR::Bundle
    fhir_resource = fhir_resource&.entry&.first&.resource if fhir_resource.is_a?(FHIR::Bundle)
    fhir_resource
  end
end
