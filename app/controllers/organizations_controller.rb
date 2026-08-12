class OrganizationsController < ApplicationController
  before_action :require_cp_client, except: [:check_capacity]

  CAPACITY_EXTENSION_URL = "http://hl7.org/fhir/us/sdoh-clinicalcare/StructureDefinition/SDOHCC-ExtensionHealthcareServiceCapacityStatus".freeze

  # SDOHCC-ExtensionHealthcareServiceCapacityStatus is a complex extension: the
  # code lives on a capacityStatus sub-extension (1..1) and a value on the outer
  # extension is prohibited (Extension.value[x] is 0..0).
  CAPACITY_STATUS_SUB_EXTENSION_URL = "capacityStatus".freeze

  # The four concepts bound to SDOHCC-ValueSetCapacityStatus, mapped to the
  # statuses the front end understands. These are the only capacity codes in
  # SDOHCC-CodeSystemTemporaryCodes; anything else deliberately falls through to
  # "unknown" so off-spec data is never silently read as available.
  CAPACITY_CODE_MAP = {
    "capacity" => "available",
    "no-capacity" => "at-capacity",
    "waitlist" => "has-waitlist",
    "additional-assessment-required" => "assessment-required",
  }.freeze

  # GET /organizations/:id/check_capacity(?category=food-insecurity)
  #
  # Direct Capacity Status Inquiry (SDOHCC IG, Capacity Status). The CP acts as
  # Intermediary here: it queries the CBO's HealthcareService and evaluates the
  # returned capacity status. The CP never writes capacity data.
  def check_capacity
    unless cp_client_connected?
      render json: { capacity: "unknown", error: "Session expired" }, status: 440 and return
    end

    org_id = params[:id]
    search_parameters = { organization: org_id }
    search_parameters["service-category"] = params[:category] if params[:category].present?

    bundle = get_cp_client.search(FHIR::HealthcareService, search: { parameters: search_parameters }).resource
    services = bundle&.entry&.map(&:resource)&.compact || []

    # Prefer the first service that actually carries a capacity extension.
    extension = services.filter_map { |s| s.extension&.find { |e| e.url == CAPACITY_EXTENSION_URL } }.first
    capacity_status = extension&.extension&.find { |e| e.url == CAPACITY_STATUS_SUB_EXTENSION_URL }
    code = capacity_status&.valueCodeableConcept&.coding&.first&.code
    capacity = CAPACITY_CODE_MAP[code] || "unknown"

    Rails.logger.info("[CHECK_CAPACITY] org=#{org_id} category=#{params[:category].inspect} " \
                      "services=#{services.size} raw_code=#{code.inspect} capacity=#{capacity}")

    render json: { capacity: capacity }
  rescue => e
    Rails.logger.error("[CHECK_CAPACITY] #{e.full_message}")

    render json: { capacity: "unknown", error: e.message }, status: 502
  end

  def create
    org = FHIR::Organization.new(
      active: true,
      name: params[:name],
      contact: org_contact,
      address: org_address,
      type: org_type
    )
    get_cp_client.create(org)
    flash[:success] = "successfully created organization #{org.name}"
    Rails.cache.delete(organizations_key)
  rescue => e
    Rails.logger.error(e.full_message)

    flash[:error] = "Unable to create organization"
  ensure
    redirect_to dashboard_path
  end

  private

  def org_contact
    [
      {
        telecom: [
          {
            system: "phone",
            value: params[:phone],
          },
          {
            system: "email",
            value: params[:email],
          },
          {
            system: "url",
            value: params[:url],
          },
        ],
      },
    ]
  end

  def org_address
    [
      {
        line: [params[:street]],
        city: params[:city],
        state: params[:state],
        postalCode: params[:postal_code],
      },
    ]
  end

  def org_type
    [
      {
          "coding": [
              {
                  "code": "cbo",
                  "display": "Community Based Organization",
                  "system": "http://hl7.org/gravity/CodeSystem/sdohcc-temporary-organization-type-codes"
              }
          ]
      }
    ]
  end
end
