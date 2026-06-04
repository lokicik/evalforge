class ProjectAnalytics
  attr_reader :project, :selected_prompt, :selected_model, :run_from, :run_to

  def initialize(project:, prompt_id: nil, run_model: nil, run_from: nil, run_to: nil)
    @project = project
    @selected_prompt = prompt_id.present? ? project.prompts.find_by(id: prompt_id) : nil
    @selected_model = run_model.to_s.strip.presence
    @run_from = run_from
    @run_to = run_to
  end

  def prompts
    @prompts ||= project.prompts.includes(:prompt_versions).order(created_at: :desc)
  end

  def available_models
    @available_models ||= project.evaluation_runs.distinct.order(:llm_model).pluck(:llm_model)
  end

  def filtered_runs
    @filtered_runs ||= begin
      scope = project.evaluation_runs.includes(prompt_version: :prompt).order(created_at: :asc)
      scope = scope.where(llm_model: selected_model) if selected_model.present?
      scope = scope.where(prompt_version_id: selected_prompt.prompt_versions.select(:id)) if selected_prompt.present?
      scope = scope.where("evaluation_runs.created_at >= ?", run_from.beginning_of_day) if run_from
      scope = scope.where("evaluation_runs.created_at <= ?", run_to.end_of_day) if run_to
      scope
    end
  end

  def filtered_run_ids
    @filtered_run_ids ||= filtered_runs.pluck(:id)
  end

  def summary_metrics
    {
      total_runs: filtered_runs.count,
      reviewed_responses: reviewed_responses.count,
      average_score: weighted_average_score(all_scores),
      average_pass_rate: pass_rate_for(reviewed_responses),
      total_tokens_used: all_responses.sum { |response| response.tokens_used.to_i },
      total_cost: all_responses.sum { |response| response.cost.to_d }.round(6)
    }
  end

  def trend_rows
    filtered_runs.map do |run|
      responses = responses_for_run(run.id)
      reviewed = reviewed_responses_for_run(run.id)

      {
        run: run,
        average_score: weighted_average_score(scores_for_run(run.id)),
        pass_rate: pass_rate_for(reviewed),
        total_cost: responses.sum { |response| response.cost.to_d }.round(6),
        total_tokens_used: responses.sum { |response| response.tokens_used.to_i },
        failures: reviewed.count { |response| response.review.status == "failed" },
        reviewed_cases: reviewed.count
      }
    end
  end

  def comparison_data
    return [] unless selected_prompt

    selected_prompt.prompt_versions.order(version_number: :desc).map do |version|
      run_ids = filtered_runs.select { |run| run.prompt_version_id == version.id }.map(&:id)
      reviewed = reviewed_responses.select { |response| run_ids.include?(response.evaluation_run_id) }

      {
        version: version,
        avg_score: weighted_average_score(scores_for_run_ids(run_ids)),
        pass_rate: pass_rate_for(reviewed),
        reviewed_cases: reviewed.count,
        failures: reviewed.count { |response| response.review.status == "failed" }
      }
    end
  end

  def criterion_failure_aggregates
    failed_scores = failed_reviewed_responses.flat_map do |response|
      response.scores.select { |score| score.value < 4 }
    end

    failed_scores.group_by(&:rubric_criterion).map do |criterion, scores|
      {
        criterion: criterion,
        failures: scores.count,
        average_score: (scores.sum(&:value).to_f / scores.count).round(2)
      }
    end.sort_by { |entry| [ -entry[:failures], entry[:average_score] ] }
  end

  def weakest_test_cases
    reviewed_responses.group_by(&:test_case_id).map do |test_case_id, responses|
      failed_count = responses.count { |response| response.review.status == "failed" }
      average_score = if responses.any?
        (responses.sum { |response| response.average_score_percentage.to_f } / responses.count).round(1)
      else
        0.0
      end

      {
        test_case: responses.first.test_case,
        reviewed_count: responses.count,
        failed_count: failed_count,
        failure_rate: ((failed_count.to_f / responses.count) * 100.0).round(1),
        average_score: average_score
      }
    end.sort_by { |entry| [ -entry[:failure_rate], entry[:average_score] ] }
  end

  private

  def all_responses
    @all_responses ||= begin
      ModelResponse.includes(:test_case, :review, scores: :rubric_criterion)
                   .where(evaluation_run_id: filtered_run_ids)
                   .to_a
    end
  end

  def reviewed_responses
    @reviewed_responses ||= all_responses.select(&:reviewed?)
  end

  def failed_reviewed_responses
    @failed_reviewed_responses ||= reviewed_responses.select { |response| response.review.status == "failed" }
  end

  def all_scores
    @all_scores ||= all_responses.flat_map(&:scores)
  end

  def responses_by_run
    @responses_by_run ||= all_responses.group_by(&:evaluation_run_id)
  end

  def reviewed_responses_by_run
    @reviewed_responses_by_run ||= reviewed_responses.group_by(&:evaluation_run_id)
  end

  def scores_by_run
    @scores_by_run ||= all_responses.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |response, hash|
      hash[response.evaluation_run_id].concat(response.scores)
    end
  end

  def responses_for_run(run_id)
    responses_by_run.fetch(run_id, [])
  end

  def reviewed_responses_for_run(run_id)
    reviewed_responses_by_run.fetch(run_id, [])
  end

  def scores_for_run(run_id)
    scores_by_run.fetch(run_id, [])
  end

  def scores_for_run_ids(run_ids)
    run_ids.flat_map { |run_id| scores_for_run(run_id) }
  end

  def weighted_average_score(scores)
    return 0.0 if scores.empty?

    total_points = 0.0
    total_weights = 0.0

    scores.each do |score|
      weight = score.rubric_criterion&.weight || 1
      total_points += (score.value.to_f / 5.0 * 100.0) * weight
      total_weights += weight
    end

    return 0.0 if total_weights.zero?

    (total_points / total_weights).round(1)
  end

  def pass_rate_for(reviewed_scope)
    return 0.0 if reviewed_scope.empty?

    passed_count = reviewed_scope.count { |response| response.review.status == "passed" }
    ((passed_count.to_f / reviewed_scope.count) * 100.0).round(1)
  end
end
