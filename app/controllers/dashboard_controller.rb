class DashboardController < ApplicationController
  before_action :require_cp_client, :set_tasks, :get_cbo_organizations

  private

  # Getting all resources associated with the given patient

  def set_tasks
    success, result = fetch_tasks
    if success
      @active_cp_tasks = result["cp_tasks"]&.dig("active") || []
      @completed_cp_tasks = result["cp_tasks"]&.dig("completed") || []
      @cancelled_cp_tasks = result["cp_tasks"]&.dig("cancelled") || []
      @active_ehr_tasks = result["ehr_tasks"]&.dig("active") || []
      @completed_ehr_tasks = result["ehr_tasks"]&.dig("completed") || []
      @cancelled_ehr_tasks = result["ehr_tasks"]&.dig("cancelled") || []
    else
      # The server we are pointed at could not be read. Render the dashboard
      # with empty tables and say why, so the user can log out and pick another
      # server instead of being stuck on an error page.
      @active_cp_tasks = []
      @completed_cp_tasks = []
      @cancelled_cp_tasks = []
      @active_ehr_tasks = []
      @completed_ehr_tasks = []
      @cancelled_ehr_tasks = []
      flash.now[:warning] = result
    end
  end
end
