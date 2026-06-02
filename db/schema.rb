# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_05_29_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum", null: false
    t.datetime "created_at", precision: 6, null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "evaluation_runs", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.bigint "prompt_version_id", null: false
    t.string "name", null: false
    t.string "status", default: "pending", null: false
    t.string "llm_model", default: "manual", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "share_token"
    t.index ["project_id"], name: "index_evaluation_runs_on_project_id"
    t.index ["prompt_version_id"], name: "index_evaluation_runs_on_prompt_version_id"
    t.index ["share_token"], name: "index_evaluation_runs_on_share_token", unique: true
  end

  create_table "model_responses", force: :cascade do |t|
    t.bigint "evaluation_run_id", null: false
    t.bigint "test_case_id", null: false
    t.text "raw_response"
    t.integer "tokens_used"
    t.decimal "cost", precision: 10, scale: 6
    t.string "status", default: "pending", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["evaluation_run_id"], name: "index_model_responses_on_evaluation_run_id"
    t.index ["test_case_id"], name: "index_model_responses_on_test_case_id"
  end

  create_table "projects", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_projects_on_user_id"
  end

  create_table "prompt_versions", force: :cascade do |t|
    t.bigint "prompt_id", null: false
    t.integer "version_number", default: 1, null: false
    t.text "system_prompt"
    t.text "user_prompt_template"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["prompt_id"], name: "index_prompt_versions_on_prompt_id"
  end

  create_table "prompts", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.bigint "project_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_prompts_on_project_id"
  end

  create_table "reviews", force: :cascade do |t|
    t.bigint "model_response_id", null: false
    t.bigint "reviewer_id", null: false
    t.string "status", default: "passed", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["model_response_id"], name: "index_reviews_on_model_response_id"
    t.index ["reviewer_id"], name: "index_reviews_on_reviewer_id"
  end

  create_table "rubric_criteria", force: :cascade do |t|
    t.bigint "rubric_id", null: false
    t.string "name", null: false
    t.integer "weight", default: 1, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["rubric_id"], name: "index_rubric_criteria_on_rubric_id"
  end

  create_table "rubrics", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.string "name", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_rubrics_on_project_id"
  end

  create_table "scores", force: :cascade do |t|
    t.bigint "model_response_id", null: false
    t.bigint "rubric_criterion_id", null: false
    t.integer "value", null: false
    t.text "feedback"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["model_response_id"], name: "index_scores_on_model_response_id"
    t.index ["rubric_criterion_id"], name: "index_scores_on_rubric_criterion_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "test_cases", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.jsonb "input_variables", default: {}, null: false
    t.text "expected_behavior"
    t.string "tags"
    t.string "difficulty", default: "medium", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_test_cases_on_project_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "evaluation_runs", "projects"
  add_foreign_key "evaluation_runs", "prompt_versions"
  add_foreign_key "model_responses", "evaluation_runs"
  add_foreign_key "model_responses", "test_cases"
  add_foreign_key "projects", "users"
  add_foreign_key "prompt_versions", "prompts"
  add_foreign_key "prompts", "projects"
  add_foreign_key "reviews", "model_responses"
  add_foreign_key "reviews", "users", column: "reviewer_id"
  add_foreign_key "rubric_criteria", "rubrics"
  add_foreign_key "rubrics", "projects"
  add_foreign_key "scores", "model_responses"
  add_foreign_key "scores", "rubric_criteria", column: "rubric_criterion_id"
  add_foreign_key "sessions", "users"
  add_foreign_key "test_cases", "projects"
end
