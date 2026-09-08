module ApplicationHelper
  include SessionsHelper
  include TasksHelper

  # Returns the CBO organizations on the connected server, or nil when they
  # could not be fetched. Callers and views branch on nil, so a server that is
  # unreachable or is not a FHIR server must not raise out of here: on master
  # the else branch called #response on a resource that does not answer it, and
  # that NoMethodError was the 500 on /dashboard.
  def organizations
    cached = Rails.cache.read(organizations_key)
    return cached unless cached.nil?

    orgs = fetch_organizations
    # Only a successful lookup is cached, so picking a working server after a
    # failed one does not keep serving the failure for a day.
    Rails.cache.write(organizations_key, orgs, expires_in: 1.day) unless orgs.nil?
    orgs
  end

  def bootstrap_class_for(flash_type)
    case flash_type.to_sym
    when :success
      "success"
    when :error
      "danger"
    when :alert
      "warning"
    when :notice
      "info"
    else
      flash_type.to_s
    end
  end

  def colorize_json(json)
    output = ""
    tokens = {
      '{' => 'color: #ffc35f;',
      '}' => 'color: #ffc35f;',
      '[' => 'color: #ffc35f;',
      ']' => 'color: #ffc35f;',
      ',' => 'color: #ffc35f;',
      ':' => 'color: #0069ff;',
      'true' => 'color: green;',
      'false' => 'color: red;',
      'null' => 'color: #baa2cd;'
    }

    json.scan(/(".*?"|{|}|[|]|,|:|true|false|null|-?\d+(\.\d+)?([eE][+-]?\d+)?|\s+)/) do |token|
      color = tokens[token.first] || ('color: #3ea4dc;' if token.first.start_with?('"')) || nil
      if color
        output += "<span style='#{color}'>#{ERB::Util.html_escape(token.first)}</span>"
      else
        output += ERB::Util.html_escape(token.first)
      end
    end

    output.html_safe
  end

  private

  def fetch_organizations
    client = get_cp_client
    if client.nil?
      Rails.logger.error("Unable to fetch Organizations: not connected to a FHIR server")
      return nil
    end

    reply = client.search(FHIR::Organization, search: { parameters: { type: "cbo", _sort: "-_lastUpdated" } })
    bundle = reply.resource

    if bundle.is_a?(FHIR::Bundle)
      entries = bundle.entry&.map(&:resource)
      entries&.map { |entry| Organization.new(entry) } || []
    else
      Rails.logger.error("Unable to fetch Organizations: #{reply&.response&.[](:code)} - #{reply&.response&.[](:body)}")
      nil
    end
  rescue StandardError => e
    Rails.logger.error(e.full_message)
    nil
  end
end
