class PromptsController < ApplicationController
  before_action :set_project
  before_action :set_prompt, only: %i[ show edit update destroy ]

  def show
    @versions = @prompt.prompt_versions.order(version_number: :desc)
  end

  def new
    @prompt = @project.prompts.build
    @prompt_version = @prompt.prompt_versions.build(version_number: 1)
  end

  def edit
    @prompt_version = @prompt.latest_version || @prompt.prompt_versions.build(version_number: 1)
  end

  def create
    @prompt = @project.prompts.build(prompt_params)

    # Wrap in transaction to ensure prompt and version are created together
    ActiveRecord::Base.transaction do
      if @prompt.save
        @prompt_version = @prompt.prompt_versions.build(
          version_number: 1,
          system_prompt: params[:system_prompt],
          user_prompt_template: params[:user_prompt_template],
          description: params[:version_description].presence || "Initial prompt version"
        )
        
        if @prompt_version.save
          redirect_to project_path(@project, tab: "prompts"), notice: "Prompt and V1 version were successfully created."
        else
          raise ActiveRecord::Rollback
        end
      end
    end

    if @prompt.new_record? || !@prompt_version.persisted?
      @prompt_version ||= @prompt.prompt_versions.build(version_number: 1)
      @prompt_version.system_prompt = params[:system_prompt]
      @prompt_version.user_prompt_template = params[:user_prompt_template]
      @prompt_version.description = params[:version_description]
      render :new, status: :unprocessable_entity
    end
  end

  def update
    # Wrap in transaction
    ActiveRecord::Base.transaction do
      # Update prompt metadata
      prompt_updated = @prompt.update(prompt_params)

      # Check if version content changed
      latest = @prompt.latest_version
      content_changed = latest.nil? || 
                        latest.system_prompt != params[:system_prompt] || 
                        latest.user_prompt_template != params[:user_prompt_template]

      if prompt_updated
        if content_changed
          next_version_num = (latest&.version_number || 0) + 1
          @prompt_version = @prompt.prompt_versions.build(
            version_number: next_version_num,
            system_prompt: params[:system_prompt],
            user_prompt_template: params[:user_prompt_template],
            description: params[:version_description].presence || "Updated prompt to V#{next_version_num}"
          )
          
          if @prompt_version.save
            redirect_to project_prompt_path(@project, @prompt), notice: "Prompt updated and new Version V#{@prompt_version.version_number} created."
          else
            raise ActiveRecord::Rollback
          end
        else
          redirect_to project_prompt_path(@project, @prompt), notice: "Prompt metadata was successfully updated."
        end
      else
        raise ActiveRecord::Rollback
      end
    end

  rescue ActiveRecord::RecordInvalid => e
    @prompt_version = @prompt.prompt_versions.build(
      system_prompt: params[:system_prompt],
      user_prompt_template: params[:user_prompt_template],
      description: params[:version_description]
    )
    render :edit, status: :unprocessable_entity
  end

  def destroy
    @prompt.destroy
    redirect_to project_path(@project, tab: "prompts"), notice: "Prompt was successfully destroyed."
  end

  private

  def set_project
    @project = Current.user.projects.find(params[:project_id])
  end

  def set_prompt
    @prompt = @project.prompts.find(params[:id])
  end

  def prompt_params
    params.require(:prompt).permit(:name, :description)
  end
end
