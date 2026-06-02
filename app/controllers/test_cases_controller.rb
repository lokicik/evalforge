require "csv"
require "json"

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

  def import
    file = params[:file]

    if file.blank?
      redirect_to project_path(@project, tab: "test_cases"), alert: "Choose a CSV file to import."
      return
    end

    result = import_test_cases(file)

    if result[:errors].any?
      redirect_to project_path(@project, tab: "test_cases"),
                  alert: "Imported #{result[:imported_count]} test case#{'s' unless result[:imported_count] == 1} with #{result[:errors].size} row error#{'s' unless result[:errors].size == 1}.",
                  flash: { import_errors: result[:errors], import_summary: result[:summary] }
    else
      redirect_to project_path(@project, tab: "test_cases"), notice: result[:summary]
    end
  end

  def template
    send_data TestCase.csv_template,
              filename: "evalforge-test-cases-template-#{Date.current}.csv",
              type: "text/csv; charset=utf-8; header=present"
  end

  def bulk_update
    test_cases = selected_test_cases
    difficulty = params[:bulk_difficulty].to_s.strip
    tags = params[:bulk_tags].to_s.strip

    if test_cases.empty?
      redirect_to project_path(@project, tab: "test_cases"), alert: "Select at least one test case first."
      return
    end

    if difficulty.blank? && tags.blank?
      redirect_to project_path(@project, tab: "test_cases"), alert: "Choose a difficulty or tags to apply."
      return
    end

    ActiveRecord::Base.transaction do
      test_cases.each do |test_case|
        attrs = {}
        attrs[:difficulty] = difficulty if difficulty.present?
        if tags.present?
          merged_tags = (test_case.tags_array + tags.split(",").map(&:strip)).reject(&:blank?).uniq
          attrs[:tags] = merged_tags.join(", ")
        end
        test_case.update!(attrs)
      end
    end

    redirect_to project_path(@project, tab: "test_cases"), notice: "Updated #{test_cases.size} test case#{'s' unless test_cases.size == 1}."
  end

  def bulk_destroy
    test_cases = selected_test_cases

    if test_cases.empty?
      redirect_to project_path(@project, tab: "test_cases"), alert: "Select at least one test case first."
      return
    end

    deleted_count = test_cases.size
    test_cases.destroy_all

    redirect_to project_path(@project, tab: "test_cases"), notice: "Deleted #{deleted_count} test case#{'s' unless deleted_count == 1}."
  end

  private

  def set_project
    @project = Current.user.projects.find(params[:project_id])
  end

  def set_test_case
    @test_case = @project.test_cases.find(params[:id])
  end

  def selected_test_cases
    ids = Array(params[:test_case_ids]).reject(&:blank?)
    @project.test_cases.where(id: ids)
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

  def import_test_cases(file)
    imported_count = 0
    errors = []

    CSV.foreach(file.path, headers: true).with_index(2) do |row, line_number|
      attributes = build_import_attributes(row.to_h, line_number)
      next if attributes.nil?

      test_case = @project.test_cases.build(attributes)

      if test_case.save
        imported_count += 1
      else
        errors << "Row #{line_number}: #{test_case.errors.full_messages.to_sentence}"
      end
    rescue JSON::ParserError => e
      errors << "Row #{line_number}: input_variables_json must be valid JSON object text."
    end

    summary = "Imported #{imported_count} test case#{'s' unless imported_count == 1}."
    { imported_count: imported_count, errors: errors, summary: summary }
  rescue CSV::MalformedCSVError => e
    { imported_count: 0, errors: [ "CSV parsing failed: #{e.message}" ], summary: "No test cases were imported." }
  end

  def build_import_attributes(row_hash, line_number)
    input_variables_json = row_hash["input_variables_json"].to_s
    input_variables = input_variables_json.present? ? JSON.parse(input_variables_json) : {}

    unless input_variables.is_a?(Hash)
      raise JSON::ParserError, "input_variables_json must decode to a JSON object"
    end

    {
      input_variables: input_variables.transform_keys(&:to_s),
      expected_behavior: row_hash["expected_behavior"].to_s.strip,
      tags: row_hash["tags"].to_s,
      difficulty: row_hash["difficulty"].to_s.strip.downcase,
      notes: row_hash["notes"].to_s.strip
    }
  rescue JSON::ParserError
    raise
  rescue StandardError => e
    raise e.class, "Row #{line_number}: #{e.message}"
  end
end
