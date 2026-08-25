class TasksController < ApplicationController
  before_action :require_cp_client
  before_action :get_cbo_organizations, only: [:poll_tasks]

  # Server-assigned metadata on the source resource, which describes that
  # resource on that server and not the copy being created here.
  SERVER_ASSIGNED_META = %w[versionId lastUpdated].freeze

  def update_task
    cp_client = get_cp_client
    cached_cp_tasks = Rails.cache.read(cp_tasks_key)
    cached_ehr_tasks = Rails.cache.read(ehr_tasks_key)
    cached_tasks = [cached_cp_tasks, cached_ehr_tasks].flatten.compact
    part_of_id = ""
    begin
      task = cached_tasks.find { |t| t.id == params[:id] }&.fhir_resource
      sr_id = task.focus&.reference&.split("/")&.last
      service_request = cp_client.read(FHIR::ServiceRequest, sr_id).resource
      if task.present?
        status = params[:status] == "status" ? params[:task_status] : params[:status]
        part_of_id = task.partOf&.first&.reference&.split("/")&.last
        task.status = status
        if status == "accepted"
          task_result = cp_client.update(task, task.id).resource
          create_cp_task_service_request(task_result, service_request)
        elsif status == "in-progress"
          cp_client.update(task, task.id)
        elsif status == "rejected"
          task.statusReason = { text: params[:status_reason] }
          cp_client.update(task, task.id)
        elsif status == "completed"
          cp_task = cached_cp_tasks.map(&:fhir_resource).find { |t| t.partOf.first&.reference&.include?(task.id) }
          task.output = cp_task&.output
          cp_client.update(task, task.id)
        elsif status == "cancelled" && part_of_id.present?
          ehr_task = cached_tasks.find { |t| t.id == part_of_id }&.fhir_resource
          task.statusReason = ehr_task.statusReason
          cp_client.update(task, task.id)
        elsif status == "cancelled" && part_of_id.blank?
          cp_task = cached_cp_tasks.map(&:fhir_resource).find { |t| t.partOf.first&.reference&.include?(task.id) }
          task.statusReason = cp_task&.statusReason
          cp_client.update(task, task.id)
        end

        flash[:success] = "Task has been marked as #{status}."
      else
        Rails.logger.error("Unable to update task: task not found")

        flash[:error] = "Unable to update task: task not found"
      end
    rescue => e
      Rails.logger.error(e.full_message)

      flash[:error] = "Unable to update task: #{e.message}"
    end
    Rails.cache.delete(cp_tasks_key)
    Rails.cache.delete(ehr_tasks_key)
    tab = part_of_id.present? ? "our-tasks" : "service-requests"
    set_active_tab(tab)
    redirect_to dashboard_path
  end

  def poll_tasks
    if !cp_client_connected?
      render json: { error: "Session expired" }, status: 440 and return
    end
    cached_cp_tasks = Rails.cache.read(cp_tasks_key) || []
    cached_ehr_tasks = Rails.cache.read(ehr_tasks_key) || []
    cached_tasks = [cached_cp_tasks, cached_ehr_tasks].flatten
    Rails.cache.delete(cp_tasks_key)
    Rails.cache.delete(ehr_tasks_key)
    success, result = fetch_tasks

    if success
      @active_cp_tasks = result["cp_tasks"]&.dig("active") || []
      @completed_cp_tasks = result["cp_tasks"]&.dig("completed") || []
      @cancelled_cp_tasks = result["cp_tasks"]&.dig("cancelled") || []
      @active_ehr_tasks = result["ehr_tasks"]&.dig("active") || []
      @completed_ehr_tasks = result["ehr_tasks"]&.dig("completed") || []
      @cancelled_ehr_tasks = result["ehr_tasks"]&.dig("cancelled") || []
      new_cp_tasks = Rails.cache.read(cp_tasks_key) || []
      new_ehr_tasks = Rails.cache.read(ehr_tasks_key) || []
      new_taks_list = [new_cp_tasks, new_ehr_tasks].flatten
      # check if any active tasks have changed status
      updated_cp_tasks = []
      updated_ehr_tasks = []
      new_taks_list.each do |task|
        saved_task = cached_tasks.find { |t| t.id == task.id }
        if saved_task && saved_task.status != task.status
          if task.fhir_resource.partOf.present?
            updated_cp_tasks << task
          else
            updated_ehr_tasks << task
          end
        end
      end
      @cp_task_notifications = updated_cp_tasks.map do |t|
        msg = t.status == "requested" ? "new CP task requested" : "task #{t.focus&.description} was updated to #{t.status}"
        [msg, t.id]
      end
      @ehr_task_notifications = updated_ehr_tasks.map do |t|
        msg = t.status == "requested" ? "new referral source task requested" : "task #{t.focus&.description} was updated to #{t.status}"
        [msg, t.id]
      end
    else
      [false, "Failed to fetch referral tasks. Status: #{response.response[:code]} - #{response.response[:body]}"]
      Rails.logger.error("Unable to fetch tasks: #{result}")
    end
    ActionCable.server.broadcast "notifications", { cp_task_notifications: @cp_task_notifications.to_json, ehr_task_notifications: @ehr_task_notifications.to_json }
    render json: {
      active_cp_tasks: render_to_string(partial: "dashboard/cp_tasks_table", locals: { referrals: @active_cp_tasks, type: "active" }),
      completed_cp_tasks: render_to_string(partial: "dashboard/cp_tasks_table", locals: { referrals: @completed_cp_tasks, type: "completed" }),
      cancelled_cp_tasks: render_to_string(partial: "dashboard/cp_tasks_table", locals: { referrals: @cancelled_cp_tasks, type: "cancelled" }),
      active_ehr_tasks: render_to_string(partial: "dashboard/ehr_tasks_table", locals: { referrals: @active_ehr_tasks, type: "active" }),
      completed_ehr_tasks: render_to_string(partial: "dashboard/ehr_tasks_table", locals: { referrals: @completed_ehr_tasks, type: "completed" }),
      cancelled_ehr_tasks: render_to_string(partial: "dashboard/ehr_tasks_table", locals: { referrals: @cancelled_ehr_tasks, type: "cancelled" }),
    }
  end

  private

  # The coordination platform is the Intermediary of the indirect referral
  # patterns, so what it posts to the referral target is a *derived* request,
  # not the referral source's own. referral_workflow.md tags both patterns as
  # conformance requirements and asks for the same three things in each --
  # refer-1 (indirect, "Coordination Platform SHALL requirements handling
  # indirect referral tasks") and refer-2 (indirect referral light):
  #
  #   1. Create a local copy of, or proxy, all relevant referenced resources
  #      from the referral source
  #   2. Create ServiceRequest(s) with ServiceRequest.intent value
  #      "filler-order" and ServiceRequest.basedOn references the original
  #      referral source ServiceRequest(s)
  #   3. Create Task(s) ... that reference the referral source Task(s) via
  #      Task.partOf
  #
  # basedOn, partOf and the local copy were already here. The intent was not:
  # "original-order" says this platform originated the request, which is what
  # the referral source did.
  def create_cp_task_service_request(ehr_task, ehr_request)
    cp_client = get_cp_client
    # Creating CP request
    cp_request = derive(FHIR::ServiceRequest, ehr_request)
    cp_request.basedOn = [{ reference: "ServiceRequest/#{ehr_request.id}" }]
    cp_request.intent = "filler-order"
    result_cp_request = cp_client.create(cp_request).resource
    # Creating CP task
    cp_task = derive(FHIR::Task, ehr_task)
    cp_task.partOf = [{ reference: "Task/#{ehr_task.id}" }]
    cp_task.status = "requested"
    cp_task.authoredOn = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ")
    cp_task.requester = coordination_platform_reference
    cp_task.owner = {
      "reference": "Organization/#{params[:cbo_organization_id]}",
      "display": Rails.cache.read(organizations_key)&.find { |o| o.id == params[:cbo_organization_id] }&.name,
    }
    cp_task.focus = { reference: "ServiceRequest/#{result_cp_request.id}" }
    cp_client.create(cp_task).resource
  end

  # A derived resource is built from the source's data, never from the source
  # object.
  #
  # `cp_request = ehr_request` bound a second name to the same FHIR::Model, so
  # every assignment below it -- `intent`, `basedOn`, `id = nil` -- was made to
  # the resource the caller was still holding and passing on. The Task was
  # worse: `cp_task.requester = ehr_task.owner` read a field that
  # `cp_task.owner =` overwrote two lines later, so the requester was only ever
  # the platform's own Organization because the demo data happens to own the
  # referral source's Task to the platform.
  #
  # meta.profile is kept -- the copy claims the same SDOHCC profiles -- and the
  # source server's version and timestamp are dropped with the id.
  def derive(fhir_class, source)
    attributes = source.to_hash.except("id")
    meta = attributes["meta"].is_a?(Hash) ? attributes["meta"].except(*SERVER_ASSIGNED_META) : nil
    if meta.present?
      attributes["meta"] = meta
    else
      attributes.delete("meta")
    end

    fhir_class.new(attributes)
  end

  # The requester of the derived Task is this coordination platform: refer-1
  # makes the platform the party asking the referral target to do the work, and
  # SDOHCC-TaskForReferralManagement constrains requester (1..1) to
  # Reference(SDOHCC PractitionerRole | US Core Organization), so the
  # platform's own Organization is what goes there.
  def coordination_platform_reference
    org_id = current_user_id
    raise "This session has no coordination platform organization to author the derived Task" if org_id.blank?

    { reference: "Organization/#{org_id}", display: coordination_platform_name(org_id) }.compact
  end

  # Display only; a reference with no display is still conformant, so an
  # unreadable Organization must not stop the referral being passed on.
  def coordination_platform_name(org_id)
    Rails.cache.fetch("#{session_id}_cp_organization_name", expires_in: 1.day) do
      get_cp_client.read(FHIR::Organization, org_id).resource&.name
    end
  rescue => e
    Rails.logger.warn("Unable to read the coordination platform Organization #{org_id}: #{e.message}")
    nil
  end
end
