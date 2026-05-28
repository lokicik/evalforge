class TestCasesController < ApplicationController
  before_action :set_project
  before_action :set_test_case, only: %i[ edit update destroy ]

  def new
    @test_case = @project.test_cases.build
  end

  def edit
  end

  def create
    @test_case = @project.test_cases.build(test_case_params)

    if @test_case.save
      redirect_to project_path(@project, tab: "test_cases"), notice: "Test case was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @test_case.update(test_case_params)
      redirect_to project_path(@project, tab: "test_cases"), notice: "Test case was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @test_case.destroy
    redirect_to project_path(@project, tab: "test_cases"), notice: "Test case was successfully destroyed."
  end

  private

  def set_project
    @project = Current.user.projects.find(params[:project_id])
  end

  def set_test_case
    @test_case = @project.test_cases.find(params[:id])
  end

  def test_case_params
    # Permit basic params
    p = params.require(:test_case).permit(:expected_behavior, :tags, :difficulty, :notes)
    
    # Process visual key-value variables
    keys = params[:input_keys] || []
    values = params[:input_values] || []
    
    # Zip together and convert to hash
    p[:input_variables] = keys.zip(values).reject { |k, v| k.blank? }.to_h
    p
  end
end
