module TasksHelper
  include SessionsHelper

  # A server we are pointed at may be down, unreachable, slow, mis-configured for
  # TLS, or simply not a FHIR server at all. None of those are recoverable by us,
  # but none of them may take the dashboard down either: every one has to become
  # a flash message and an empty task list.
  SERVER_ERRORS = [
    Errno::ECONNREFUSED,
    Errno::ECONNRESET,
    Errno::EHOSTUNREACH,
    Errno::ENETUNREACH,
    Errno::ETIMEDOUT,
    SocketError,
    Timeout::Error, # covers Net::OpenTimeout and Net::ReadTimeout
    RestClient::Exceptions::Timeout, # ...which rest-client re-raises as its own
    RestClient::ServerBrokeConnection,
    OpenSSL::SSL::SSLError,
    JSON::ParserError,
  ].freeze

  # Error bodies get interpolated into a flash message. A server that answers
  # with an HTML error page would otherwise put the whole page in the toast.
  MAX_ERROR_BODY_LENGTH = 300

  def save_cp_tasks(tasks)
    Rails.cache.write(cp_tasks_key, tasks, expires_in: 1.day)
  end

  def save_ehr_tasks(tasks)
    Rails.cache.write(ehr_tasks_key, tasks, expires_in: 1.day)
  end

  def fetch_tasks
    client = get_cp_client
    return [false, "Not connected to a FHIR server. Please connect to a server and try again."] if client.nil?

    search_params = {
      parameters: {
        _profile: "http://hl7.org/fhir/us/sdoh-clinicalcare/StructureDefinition/SDOHCC-TaskForReferralManagement",
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
      code = response&.response&.[](:code)

      if code != 200
        Rails.logger.error("Failed to fetch referral tasks. Status: #{code} - #{error_body(response)}")

        return [false, "Failed to fetch referral tasks from #{cp_server_description}. Status: #{code} - #{error_body(response)}"]
      end

      bundle = response.resource
      if !bundle.is_a?(FHIR::Bundle)
        Rails.logger.error("#{cp_server_description} answered 200 but returned no FHIR Bundle: #{error_body(response)}")

        return [false, "#{cp_server_description} answered, but did not return a FHIR Bundle of Tasks. Check that the URL points at a FHIR endpoint, then log out and pick another server."]
      end

      entries = bundle.entry&.map(&:resource)
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
    rescue *SERVER_ERRORS => e
      Rails.logger.error(e.full_message)

      [false, "Could not reach #{cp_server_description}. Check that the URL is correct and the server is up, then log out and pick another server. #{e.class}: #{e.message}"]
    rescue StandardError => e
      Rails.logger.error(e.full_message)

      [false, "Something went wrong talking to #{cp_server_description}. #{e.message}"]
    end
  end

  private

  # The base URL the session actually holds. SessionsHelper defines this one;
  # an undefined helper here would turn a recoverable connection failure into an
  # unrescued NoMethodError.
  def cp_server_description
    get_cp_server_base_url.presence || "the selected FHIR server"
  end

  def error_body(response)
    body = response&.response&.[](:body)
    return "no response body" if body.blank?

    body = body.to_s
    body.length > MAX_ERROR_BODY_LENGTH ? "#{body[0, MAX_ERROR_BODY_LENGTH]}..." : body
  end

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
