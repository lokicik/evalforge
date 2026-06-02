class ProjectAttachmentsController < ApplicationController
  before_action :set_project
  before_action :set_attachment, only: :destroy

  def create
    files = Array(params.dig(:project, :reference_files)).compact_blank

    if files.empty?
      redirect_to project_path(@project), alert: "Select at least one file to upload."
      return
    end

    @project.reference_files.attach(files)
    redirect_to project_path(@project), notice: "Reference files uploaded."
  end

  def destroy
    @attachment.purge
    redirect_to project_path(@project), notice: "Reference file removed."
  end

  private

  def set_project
    @project = Current.user.projects.find(params[:project_id])
  end

  def set_attachment
    @attachment = @project.reference_files.attachments.find(params[:id])
  end
end
