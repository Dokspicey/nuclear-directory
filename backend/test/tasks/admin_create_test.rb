require "test_helper"
require "rake"

# bin/rails admin:create (#86): one admin account, asked for interactively.
class AdminCreateTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("admin:create")
    @task = Rake::Task["admin:create"]
  end

  # Runs the task with typed answers (email, handle, then the password).
  def run_task(*answers)
    input = StringIO.new(answers.first(2).map { "#{_1}\n" }.join)
    password = answers.last
    input.define_singleton_method(:getpass) { |_prompt| password }
    stdin, stdout = $stdin, $stdout
    $stdin, $stdout = input, StringIO.new
    @task.reenable
    @task.invoke
    $stdout.string
  ensure
    $stdin, $stdout = stdin, stdout
  end

  test "asks for the email and handle, and creates the account" do
    User.delete_all

    out = run_task("new@example.com", "sam", "a long enough password")

    assert_match "Created new@example.com. Decisions are recorded as human:sam.", out
    assert_equal [ [ "new@example.com", "sam" ] ], User.pluck(:email_address, :handle)
  end

  test "updates the one account (no second admin) and signs out its sessions" do
    admin = users(:admin)
    admin.sessions.create!

    out = run_task("changed@example.com", "tosin", "another long password")

    assert_match "Updated changed@example.com", out
    assert_match "Existing sessions were signed out", out
    assert_equal 1, User.count
    assert_equal "changed@example.com", admin.reload.email_address
    assert_empty admin.sessions
  end
end
