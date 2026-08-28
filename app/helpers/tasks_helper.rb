module TasksHelper
  include SessionsHelper

  # Badge colours for SDOHCC-ValueSetEnrollmentStatus. Enrolled reads as done,
  # a waitlist as something still outstanding, not enrolled as neither.
  ENROLLMENT_STATUS_BADGE_CLASSES = {
    "enrolled" => "bg-success",
    "not-enrolled" => "bg-secondary",
    "not-enrolled-on-waitlist" => "bg-warning text-dark",
  }.freeze

  # The assessment procedures that make a referral a referral for further
  # assessment.
  #
  # rffa.html: "ServiceRequest.code: This field specifies that the object of
  # the request is an assessment procedure ... This CodeableConcept is what
  # differentiates a request to 'assess for food insecurity' from a request to
  # 'provide food'."
  #
  # SDOHCC-ServiceRequest binds code to US Core Procedure Codes (required) and
  # adds an extensible additional binding per SDOH category. The domain-specific
  # codes here are members of those VSAC value sets, version 20240604: Food
  # Insecurity Service Requests
  # (http://cts.nlm.nih.gov/fhir/ValueSet/2.16.840.1.113762.1.4.1247.11) and
  # Housing Instability Service Requests (...1.4.1247.45). The two general codes
  # are members of the food, housing and transportation value sets alike.
  #
  # This list decides how a referral is displayed and nothing else. It must not
  # be used to choose ServiceRequest.intent: filler-order follows from the
  # referral being indirect (refer-1, refer-2), not from an assessment being
  # what was asked for.
  ASSESSMENT_SERVICE_CODES = {
    "710824005" => "Assessment of health and social care needs",
    "1085651000000100" => "Assessment of social care needs",
    "1002224003" => "Assessment for food insecurity",
    "1148447008" => "Assessment for housing insecurity",
    # Not a member of the housing value set above, and no longer offered by the
    # referral source client for that reason. Recognised here because referrals
    # that use it already exist and still have to read as assessments.
    "225340009" => "Housing assessment",
  }.freeze

  # Badge colours for the resource types a completed referral can come back
  # with: Procedure under Task.output:PerformedActivityReference, and everything
  # SDOHCC-TaskForReferralManagement lets Task.output:AdditionalContent point at.
  OUTCOME_TYPE_BADGE_CLASSES = {
    "Procedure" => "bg-primary",
    "QuestionnaireResponse" => "bg-info text-dark",
    "Observation" => "bg-secondary",
    "Condition" => "bg-danger",
    "Goal" => "bg-success",
    "CarePlan" => "bg-dark",
  }.freeze

  # Is this the assessment kind of referral? Reads ServiceRequest.code, which is
  # the only thing that distinguishes it from a request for a service.
  def assessment_referral?(service_request)
    Array(service_request&.fhir_resource&.code&.coding).any? do |coding|
      coding.system == FhirProfiles::SNOMED_CT_SYSTEM && ASSESSMENT_SERVICE_CODES.key?(coding.code)
    end
  end

  def outcome_type_badge_class(resource_type)
    OUTCOME_TYPE_BADGE_CLASSES.fetch(resource_type, "bg-light text-dark border")
  end

  def enrollment_status_badge_class(code)
    ENROLLMENT_STATUS_BADGE_CLASSES.fetch(code, "bg-light text-dark border")
  end

  def save_cp_tasks(tasks)
    Rails.cache.write(cp_tasks_key, tasks, expires_in: 1.day)
  end

  def save_ehr_tasks(tasks)
    Rails.cache.write(ehr_tasks_key, tasks, expires_in: 1.day)
  end

  def fetch_tasks
    client = get_cp_client
    search_params = {
      parameters: {
        _profile: FhirProfiles::TASK_FOR_REFERRAL_MANAGEMENT,
        _sort: "-_lastUpdated",
      # _include: "Task:focus",
      # _include: "Task:requester",
      # _include: "Task:patient",
      # _include: "Task:ServiceRequest:supporting-info"
      },
    }
    # TODO: We are Not getting the include resources in the response
    begin
      response = client.search(FHIR::Task, search: search_params)
      if response.response[:code] == 200
        entries = response.resource.entry&.map(&:resource)
        task_entries = entries&.select { |entry| entry&.resourceType == "Task" }
        # sr_entries = entries.select { |entry| entry.resourceType == "ServiceRequest" }
        # consent_entries = entries.select { |entry| entry.resourceType == "Consent" }
        # requester_entries = entries.select { |entry| entry.resourceType == "Organization" || entry.resourceType == "PractitionerRole" }
        # patient_entries = entries.select { |entry| entry.resourceType == "Patient" }
        # if consent_entries.size == 0
        #   consent_entries = client.read_feed(FHIR::Consent).resource&.entry&.map(&:resource) || []
        # end
        cp_tasks = []
        ehr_tasks = []
        task_entries&.each do |task|
          # focus_id = task&.focus&.reference_id
          # focus = sr_entries.find { |sr| sr.id == focus_id }
          # # byebug
          # consent_id = focus&.supportingInfo&.reference_id
          # consent = consent_entries.find { |consent| consent.id == consent_id }
          # patient_id = task&.for&.reference_id
          # patient = patient_entries.find { |patient| patient.id == patient_id }
          # requester_id = task&.requester&.reference_id
          # requester = requester_entries.find { |requester| requester.id == requester_id }

          if task.partOf.present?
            cp_tasks << Task.new(task, client)
          else
            ehr_tasks << Task.new(task, client)
          end
        end

        # Group tasks by status and org requesting
        grp = { "cp_tasks" => group_tasks(cp_tasks), "ehr_tasks" => group_tasks(ehr_tasks) }
        save_cp_tasks(cp_tasks)
        save_ehr_tasks(ehr_tasks)
        [true, grp]
      else
        Rails.logger.error("Failed to fetch referral tasks. Status: #{response.response[:code]} - #{response.response[:body]}")

        [false, "Failed to fetch referral tasks. Status: #{response.response[:code]} - #{response.response[:body]}"]
      end
    rescue Errno::ECONNREFUSED => e
      Rails.logger.error(e.full_message)

      [false, "Connection refused. Please check FHIR server's URL #{get_ehr_base_url} is up and try again. #{e.message}"]
    rescue StandardError => e
      Rails.logger.error(e.full_message)

      [false, "Something went wrong. #{e.message}"]
    end
  end

  # The referral drawer's patient banner puts age beside the date of birth, the
  # way every EMR does, rather than making the reader do the arithmetic.
  def parse_birth_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def age_in_years(birth_date)
    today = Date.current
    age = today.year - birth_date.year
    age -= 1 if ([today.month, today.day] <=> [birth_date.month, birth_date.day]) == -1
    age
  end

  private

  def group_tasks(tasks)
    grp = { "active" => [], "completed" => [], "cancelled" => [] }
    tasks&.each do |task|
      grp["active"] << task if task.status != "completed" && task.status != "cancelled" && task.status != "rejected"
      grp["completed"] << task if task.status == "completed"
      grp["cancelled"] << task if task.status == "cancelled" || task.status == "rejected"
    end
    grp
  end
end
