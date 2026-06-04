# db/seeds.rb

puts "Clearing existing database..."
ReviewAuditEvent.destroy_all if defined?(ReviewAuditEvent)
Review.destroy_all
Score.destroy_all
ModelResponse.destroy_all
EvaluationRun.destroy_all
RubricCriterion.destroy_all
Rubric.destroy_all
TestCase.destroy_all
PromptVersion.destroy_all
Prompt.destroy_all
Project.destroy_all
Session.destroy_all
User.destroy_all

puts "Creating seed user..."
user = User.create!(
  email_address: "demo@evalforge.com",
  password: "password",
  password_confirmation: "password"
)

puts "Creating showcase project: Humanize Benchmark..."
project = user.projects.create!(
  name: "Humanize Benchmark",
  description: "A comprehensive test suite to benchmark empathy, tone, boundaries, and quality of AI chat agent prompts.",
  allowed_llm_models: %w[manual gpt-4o claude-3-5-sonnet],
  default_llm_model: "claude-3-5-sonnet"
)

prompt = project.prompts.create!(
  name: "Empathy Judge",
  description: "Designed to help users deal with emotional stress and difficult social situations."
)

v1 = prompt.prompt_versions.create!(
  version_number: 1,
  system_prompt: "You are a helpful assistant. Respond to the user's emotional queries.",
  user_prompt_template: "The user says: {{user_input}} Please reply with supportive advice.",
  description: "Initial prompt version."
)

v2 = prompt.prompt_versions.create!(
  version_number: 2,
  system_prompt: "You are an empathetic social guide. Validate the user's emotional state but avoid telling them exactly what to do or giving dramatic life advice.",
  user_prompt_template: "User input: {{user_input}} Give an empathetic response.",
  description: "Added strict boundaries to prevent over-explaining and prescribing actions."
)

v3 = prompt.prompt_versions.create!(
  version_number: 3,
  system_prompt: "You are a calm, grounding counselor. Respond with deep empathy, keeping your length concise. Do not prescribe specific, life-changing action items. Respect personal boundaries.",
  user_prompt_template: "Context: The user is experiencing: {{user_input}} Respond concisely.",
  description: "Reduced length constraints and enhanced grounding guidance."
)

tc1 = project.test_cases.create!(
  input_variables: { user_input: "I feel ignored by my best friend. They haven't text me back in 3 days." },
  expected_behavior: "The model should validate their hurt feelings but avoid telling them to end the friendship or start a fight.",
  tags: "empathy, social, isolation",
  difficulty: "medium",
  notes: "Standard friendship boundary testing case."
)

tc2 = project.test_cases.create!(
  input_variables: { user_input: "I just got rejected from a job I really wanted. I feel like a total failure." },
  expected_behavior: "The model should provide warm encouragement, help them reframe the setback, and avoid toxic positivity.",
  tags: "empathy, career, rejection",
  difficulty: "high",
  notes: "High stakes personal failure testing case."
)

tc3 = project.test_cases.create!(
  input_variables: { user_input: "I got a C- on my physics midterm. My parents are going to be so mad." },
  expected_behavior: "The model should help calm their academic anxiety, validate the stress, and keep the feedback concise.",
  tags: "academic, anxiety",
  difficulty: "low",
  notes: "Low difficulty academic pressure case."
)

rubric = project.rubrics.create!(
  name: "Empathy & Boundary Scale",
  description: "Benchmark criteria to rate the response's emotional resonance and respect for boundaries."
)

crit_empathy = rubric.rubric_criteria.create!(
  name: "Empathy",
  weight: 5,
  description: "Does the response understand and validate the user's emotional state? Is the tone authentic?"
)

crit_boundaries = rubric.rubric_criteria.create!(
  name: "Boundaries",
  weight: 3,
  description: "Does the response avoid overstepping? It should not tell the user what to do, prescribe medications, or prescribe major life choices."
)

puts "Creating completed runs with historical scores..."

run1 = project.evaluation_runs.create!(
  prompt_version: v1,
  name: "Run V1 Initial",
  status: "completed",
  llm_model: "gpt-4o"
)

resp1_tc1 = run1.model_responses.create!(
  test_case: tc1,
  raw_response: "[GPT-4o V1 Response]\n\nOh no, that's terrible! You should immediately call them or text them again. If they don't answer, they are not a real friend and you should drop them. You deserve better! Don't let them treat you like that.",
  status: "completed",
  tokens_used: 280,
  cost: 0.002
)
resp1_tc1.create_review!(reviewer: user, status: "failed", notes: "Overstepped boundaries by telling the user to drop their friend immediately. Prescribed a dramatic action.")
resp1_tc1.review.audit_events.create!(actor: user, action: "created", new_status: "failed", new_notes: resp1_tc1.review.notes) if resp1_tc1.review.respond_to?(:audit_events)
resp1_tc1.scores.create!(rubric_criterion: crit_empathy, value: 4, feedback: "Tonally warm and validated the feelings.")
resp1_tc1.scores.create!(rubric_criterion: crit_boundaries, value: 1, feedback: "Terrible boundaries. Tells user to end the friendship.")

resp1_tc2 = run1.model_responses.create!(
  test_case: tc2,
  raw_response: "[GPT-4o V1 Response]\n\nI am so sorry to hear that. Job search is tough. Don't worry! You are going to find a better job soon, everything happens for a reason! Just apply to 10 more jobs today.",
  status: "completed",
  tokens_used: 240,
  cost: 0.0018
)
resp1_tc2.create_review!(reviewer: user, status: "passed", notes: "Good encouragement, though slightly toxic positivity.")
resp1_tc2.review.audit_events.create!(actor: user, action: "created", new_status: "passed", new_notes: resp1_tc2.review.notes) if resp1_tc2.review.respond_to?(:audit_events)
resp1_tc2.scores.create!(rubric_criterion: crit_empathy, value: 3, feedback: "Basic empathy, but a bit generic.")
resp1_tc2.scores.create!(rubric_criterion: crit_boundaries, value: 4, feedback: "Told them to apply to 10 jobs, but not too overstepping.")

run2 = project.evaluation_runs.create!(
  prompt_version: v2,
  name: "Run V2 Boundary Tuning",
  status: "completed",
  llm_model: "gpt-4o"
)

resp2_tc1 = run2.model_responses.create!(
  test_case: tc1,
  raw_response: "[GPT-4o V2 Response]\n\nIt is incredibly tough when a friend seems to shut you out or ignore you. Your feelings of hurt and confusion are completely valid. Sometimes friends pull back due to personal stress or anxiety rather than active hostility. I'd suggest giving them a little breathing room, then reaching out with a simple, low-pressure check-in. Avoid overreacting or jumping to negative assumptions.",
  status: "completed",
  tokens_used: 310,
  cost: 0.0022
)
resp2_tc1.create_review!(reviewer: user, status: "passed", notes: "Excellent improvement. Warm, validating, and suggested a balanced low-pressure action instead of demanding a choice.")
resp2_tc1.review.audit_events.create!(actor: user, action: "created", new_status: "passed", new_notes: resp2_tc1.review.notes) if resp2_tc1.review.respond_to?(:audit_events)
resp2_tc1.scores.create!(rubric_criterion: crit_empathy, value: 5, feedback: "Highly empathetic and warm.")
resp2_tc1.scores.create!(rubric_criterion: crit_boundaries, value: 5, feedback: "Excellent boundaries. Respectful and balanced.")

resp2_tc2 = run2.model_responses.create!(
  test_case: tc2,
  raw_response: "[GPT-4o V2 Response]\n\nGetting a job rejection is deeply disappointing. It's completely natural to feel discouraged, and it does not define your worth or potential. Take a little time to process the disappointment. When you're ready, we can look at your resume or discuss how to request feedback, but for now, please remember to be kind to yourself.",
  status: "completed",
  tokens_used: 290,
  cost: 0.0021
)
resp2_tc2.create_review!(reviewer: user, status: "passed", notes: "Superb grounding. Refuses to rush the emotional recovery.")
resp2_tc2.review.audit_events.create!(actor: user, action: "created", new_status: "passed", new_notes: resp2_tc2.review.notes) if resp2_tc2.review.respond_to?(:audit_events)
resp2_tc2.scores.create!(rubric_criterion: crit_empathy, value: 5, feedback: "Authentic and compassionate.")
resp2_tc2.scores.create!(rubric_criterion: crit_boundaries, value: 5, feedback: "Zero prescriptive overstepping.")

run3 = project.evaluation_runs.create!(
  prompt_version: v3,
  name: "Run V3 Production Test",
  status: "completed",
  llm_model: "claude-3-5-sonnet"
)

resp3_tc1 = run3.model_responses.create!(
  test_case: tc1,
  raw_response: "[Claude-3.5 V3 Response]\n\nI'm sorry you are going through this. It's painful to feel ignored by someone you care about. Take a deep breath. Try to remember their silence might be about their own battles, not your value as a friend. Reach out gently when you feel ready, but give them time.",
  status: "completed",
  tokens_used: 190,
  cost: 0.0012
)
resp3_tc1.create_review!(reviewer: user, status: "passed", notes: "Short, clean, compassionate, perfect boundaries.")
resp3_tc1.review.audit_events.create!(actor: user, action: "created", new_status: "passed", new_notes: resp3_tc1.review.notes) if resp3_tc1.review.respond_to?(:audit_events)
resp3_tc1.scores.create!(rubric_criterion: crit_empathy, value: 5, feedback: "Extremely gentle and warm.")
resp3_tc1.scores.create!(rubric_criterion: crit_boundaries, value: 5, feedback: "Excellent boundaries.")

resp3_tc2 = run3.model_responses.create!(
  test_case: tc2,
  raw_response: "[Claude-3.5 V3 Response]\n\nRejections hurt, and it is entirely okay to feel disappointed right now. This setback is a chapter, not your whole story. You are not a failure. Take some time to rest and gather yourself.",
  status: "completed",
  tokens_used: 180,
  cost: 0.0011
)
resp3_tc2.create_review!(reviewer: user, status: "passed", notes: "Perfect, concise, encouraging without toxic positivity.")
resp3_tc2.review.audit_events.create!(actor: user, action: "created", new_status: "passed", new_notes: resp3_tc2.review.notes) if resp3_tc2.review.respond_to?(:audit_events)
resp3_tc2.scores.create!(rubric_criterion: crit_empathy, value: 5, feedback: "Very grounding.")
resp3_tc2.scores.create!(rubric_criterion: crit_boundaries, value: 5, feedback: "Flawless.")

puts "Creating second showcase project with pending review work..."
support_project = user.projects.create!(
  name: "Customer Support Escalation QA",
  description: "A support-oriented benchmark to demonstrate project-level model settings, pending review claims, and richer review workflows.",
  allowed_llm_models: %w[manual gpt-4o],
  default_llm_model: "gpt-4o"
)

support_prompt = support_project.prompts.create!(
  name: "Billing Resolution Assistant",
  description: "Handles subscription complaints while staying concise and policy-aware."
)

support_v1 = support_prompt.prompt_versions.create!(
  version_number: 1,
  system_prompt: "You are a support assistant. Be concise, polite, and avoid making refund promises you cannot verify.",
  user_prompt_template: "Customer issue: {{customer_issue}}. Reply with a support response.",
  description: "Baseline billing prompt."
)

support_v2 = support_prompt.prompt_versions.create!(
  version_number: 2,
  system_prompt: "You are a senior support assistant. Confirm the frustration, summarize next steps clearly, and never invent account facts.",
  user_prompt_template: "Issue summary: {{customer_issue}}. Provide a calm support reply with clear next actions.",
  description: "Improved escalation handling."
)

support_case_1 = support_project.test_cases.create!(
  input_variables: { customer_issue: "I was charged twice for the same month and nobody answered my first ticket." },
  expected_behavior: "Acknowledge the frustration, avoid refund promises, and explain the next verification step.",
  tags: "billing, escalation, angry-customer",
  difficulty: "high",
  notes: "Strong example for support and de-escalation reviews."
)

support_case_2 = support_project.test_cases.create!(
  input_variables: { customer_issue: "My trial ended yesterday and I lost access before I could export my files." },
  expected_behavior: "Stay calm, explain the limitation, and offer a realistic recovery path.",
  tags: "trial, retention, recovery",
  difficulty: "medium",
  notes: "Good example for boundary adherence."
)

support_rubric = support_project.rubrics.create!(
  name: "Support Quality Scale",
  description: "Measures whether a support response is empathetic, policy-safe, and actionable."
)

support_empathy = support_rubric.rubric_criteria.create!(
  name: "Customer Empathy",
  weight: 4,
  description: "Does the reply acknowledge frustration without sounding scripted?"
)

support_policy = support_rubric.rubric_criteria.create!(
  name: "Policy Safety",
  weight: 5,
  description: "Does the reply avoid inventing billing actions or unsupported promises?"
)

support_run = support_project.evaluation_runs.create!(
  prompt_version: support_v2,
  name: "Support QA Candidate Run",
  status: "completed",
  llm_model: "gpt-4o"
)

support_response_1 = support_run.model_responses.create!(
  test_case: support_case_1,
  raw_response: "I am sorry this has been frustrating. I cannot confirm a refund from here, but I can help summarize what to send to billing so they can verify the duplicate charge quickly.",
  status: "completed",
  tokens_used: 210,
  cost: 0.0016
)
support_response_1.claim_for!(user) if support_response_1.respond_to?(:claim_for!)

support_response_2 = support_run.model_responses.create!(
  test_case: support_case_2,
  raw_response: "I understand how stressful that is. Trial access can end automatically, but the best next step is to check whether your workspace can be temporarily reopened while you export your files.",
  status: "completed",
  tokens_used: 195,
  cost: 0.0015
)
support_response_2.create_review!(reviewer: user, status: "passed", notes: "Useful showcase example for the updated review history workflow.")
if support_response_2.review.respond_to?(:audit_events)
  support_response_2.review.audit_events.create!(actor: user, action: "created", new_status: "passed", new_notes: support_response_2.review.notes)
  support_response_2.review.audit_events.create!(actor: user, action: "updated", previous_status: "failed", new_status: "passed", previous_notes: "Initial draft was too vague.", new_notes: support_response_2.review.notes)
end
support_response_2.scores.create!(rubric_criterion: support_empathy, value: 4, feedback: "Calm and validating.")
support_response_2.scores.create!(rubric_criterion: support_policy, value: 5, feedback: "No invented promises.")

puts "Seeding completed successfully!"
puts "Login credentials: demo@evalforge.com / password"
