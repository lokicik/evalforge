class RubricsController < ApplicationController
  before_action :set_project
  before_action :set_rubric, only: %i[ edit update destroy ]

  def new
    @rubric = @project.rubrics.build
  end

  def edit
  end

  def create
    @rubric = @project.rubrics.build(rubric_params)

    ActiveRecord::Base.transaction do
      if @rubric.save
        save_rubric_criteria(@rubric)
        redirect_to project_path(@project, tab: "rubrics"), notice: "Rubric was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    render :new, status: :unprocessable_entity
  end

  def update
    ActiveRecord::Base.transaction do
      if @rubric.update(rubric_params)
        save_rubric_criteria(@rubric)
        redirect_to project_path(@project, tab: "rubrics"), notice: "Rubric was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    render :edit, status: :unprocessable_entity
  end

  def destroy
    @rubric.destroy
    redirect_to project_path(@project, tab: "rubrics"), notice: "Rubric was successfully destroyed."
  end

  private

  def set_project
    @project = Current.user.projects.find(params[:project_id])
  end

  def set_rubric
    @rubric = @project.rubrics.find(params[:id])
  end

  def rubric_params
    params.require(:rubric).permit(:name, :description)
  end

  def save_rubric_criteria(rubric)
    rubric.rubric_criteria.destroy_all
    
    criteria = params[:criteria] || []
    criteria.each do |crit|
      next if crit[:name].blank?
      rubric.rubric_criteria.create!(
        name: crit[:name],
        weight: crit[:weight].to_i.presence || 1,
        description: crit[:description]
      )
    end
  end
end
